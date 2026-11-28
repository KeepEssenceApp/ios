import XCTest

/// Runs against the fake core (`node fake/server.mjs`, port 8795). Reset it before each run:
/// `curl -X POST http://127.0.0.1:8795/__reset`.
///
/// Environment (pass with the `TEST_RUNNER_` prefix to xcodebuild):
///   KE_LANG            `zh-Hans` (default) or `en`
///   KE_SCREENSHOT_DIR  a folder on the Mac to write screenshots into
final class KeepEssenceUITests: XCTestCase {
    private let server = "http://127.0.0.1:8795"
    private var lang: String { ProcessInfo.processInfo.environment["KE_LANG"] ?? "zh-Hans" }
    private var zh: Bool { lang.hasPrefix("zh") }

    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KE_SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KEServer", server, "-AppleLanguages", "(\(lang))", "-AppleLocale", zh ? "zh_CN" : "en_US"]
        if reset { app.launchArguments += ["-KEReset", "YES"] }
        app.launch()
        return app
    }

    /// Exists and can be tapped now: an element under an overlay exists but is not hittable.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        shot("0-sign-in")
        email.tap()
        email.typeText("reader@example.com")
        app.buttons["signin.send"].tap()
        let code = app.textFields["signin.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap()
        code.typeText("123456")
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15), "signed in and on the main page")
    }

    /// I1, I2: sign in, the four entries in order, Today with an analysis, one action, the digest and "Read. Good night".
    func testSignInTodayActionDigestRead() {
        let app = launch(reset: true)
        signIn(app)

        // Four entries, fixed order, no others.
        let tabs = ["tab.today", "tab.digest", "tab.notes", "tab.assistants"].map { app.buttons[$0] }
        for t in tabs { XCTAssertTrue(t.exists) }
        let xs = tabs.map { $0.frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "today, digest, notes, assistants from left to right")
        for (tab, word) in zip(tabs, zh ? ["今天", "每日摘要", "笔记", "助手设置"] : ["Today", "Daily digest", "Notes", "Assistants"]) {
            XCTAssertTrue(tab.label.contains(word), "\(tab.label) should say \(word)")
        }

        // Today shows analyses with the four fields and three actions.
        let cards = app.descendants(matching: .any).matching(identifier: "today.card")
        XCTAssertTrue(app.buttons["action.seen"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[zh ? "内容概述" : "Summary"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts[zh ? "关键事实" : "Key fact"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts[zh ? "要点" : "Key points"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts[zh ? "判定" : "Verdict"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts[zh ? "值得深挖" : "Worth a deep dive"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["status.line"].exists, "the status bar is on Today")
        shot("1-today")

        // One action: seen. The analysis leaves the list and moves to the rest.
        let seenButtons = app.buttons.matching(identifier: "action.seen")
        let before = seenButtons.count
        seenButtons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["today.rest"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "action.seen").count, before - 1)

        // Swipe right adds to the deep-dive queue; swipe left marks not interested.
        XCTAssertTrue(cards.firstMatch.exists)
        cards.firstMatch.swipeRight()
        XCTAssertTrue(app.staticTexts[zh ? "已加入深挖队列" : "Added to the deep-dive queue"].waitForExistence(timeout: 10))
        sleep(1)
        cards.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts[zh ? "已标为不感兴趣" : "Marked as not interested"].waitForExistence(timeout: 10))
        shot("2-today-after-actions")

        // The digest entry carries one dot while the latest digest is not read.
        XCTAssertTrue(app.descendants(matching: .any)["tab.digest.dot"].exists)
        app.buttons["tab.digest"].tap()
        XCTAssertTrue(app.staticTexts[zh ? "值得深挖的" : "Worth a deep dive"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[zh ? "总结" : "Summary"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["status.mark"].exists, "the narrowest status bar is on the other pages")
        shot("3-digest")
        let read = app.buttons["digest.read"]
        for _ in 0..<6 where !(read.exists && read.isHittable) { app.swipeUp() }
        XCTAssertTrue(app.staticTexts[zh ? "睡前一问" : "A question to sleep on"].exists)
        shot("4-digest-end")
        read.tap()
        XCTAssertTrue(app.descendants(matching: .any)["digest.read.done"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["tab.digest.dot"].exists, "read: the dot is gone")

        // Notes: quick find, the deep-dive queue with the item swiped in, notes, the calendar.
        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.textFields["notes.find"].waitForExistence(timeout: 10))
        let queue = app.descendants(matching: .any).matching(identifier: "queue.card")
        XCTAssertTrue(queue.firstMatch.waitForExistence(timeout: 10))
        shot("5-notes")
        app.swipeUp()
        app.swipeUp()
        shot("6-notes-calendar")

        // Assistants.
        app.buttons["tab.assistants"].tap()
        XCTAssertTrue(app.buttons["assistants.devices"].waitForExistence(timeout: 10))
        shot("7-assistants")
        app.buttons["assistants.notifications"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notify.not_here"].waitForExistence(timeout: 10))
        shot("8-notifications")
    }

    /// Approving a short code: who asks, the tier lowered, allow.
    func testApproveShortCode() {
        let app = launch(reset: true)
        signIn(app)
        app.buttons["tab.assistants"].tap()
        app.buttons["assistants.devices"].tap()
        let field = app.textFields["devices.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("K7M-2QX")
        app.buttons["devices.check"].tap()
        XCTAssertTrue(app.staticTexts["approve.code"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["approve.tier.manage"].exists, "the tier cannot be raised above what was asked")
        app.buttons["approve.tier.save"].tap()
        shot("9-approve")
        app.buttons["approve.allow"].tap()
        XCTAssertTrue(app.staticTexts["Edge 扩展"].waitForExistence(timeout: 10), "the new device is in the list")
    }

    /// I3: share from Safari, pick KeepEssence, one sentence, no jump to the app.
    func testShareFromSafari() throws {
        // Signed in first, so that the extension has the credential.
        let app = launch(reset: false)
        if !app.buttons["tab.today"].waitForExistence(timeout: 8) { signIn(app) }

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let page = "\(server)/__page/\(Int(Date().timeIntervalSince1970))"
        var address = safari.textFields.firstMatch
        if !address.waitForExistence(timeout: 10) {
            safari.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'address' OR identifier CONTAINS[c] 'URL'")).firstMatch.tap()
            address = safari.textFields.firstMatch
        }
        address.tap()
        safari.typeText(page + "\n")
        XCTAssertTrue(safari.staticTexts["A page made for the share test"].waitForExistence(timeout: 15))
        shot("10-safari-1-page")

        // iOS 26 Safari has no Share button in its toolbar: Share is the first item of the page menu behind
        // `More`. Every element below was read from the CI simulator's own accessibility hierarchy (ios#9),
        // and each step is named so that the log and the screenshots show them in this order.

        // Step 0 (only the first time Safari runs on a fresh simulator): its tip about the new menu covers
        // the screen with a full-screen dismiss region, which swallows a tap on `More`. Close it by its own
        // button and wait for it to go; when there is no tip, there is nothing to do.
        XCTContext.runActivity(named: "I3 step 0: Safari's first-run tip, if it is up, is closed") { _ in
            let tip = safari.otherElements["TipView"]
            if tip.waitForExistence(timeout: 5) {
                let close = tip.buttons["xmark.circle.fill"]
                XCTAssertTrue(close.waitForExistence(timeout: 5), "the tip has its Close button")
                close.tap()
                XCTAssertTrue(tip.waitForNonExistence(timeout: 5), "the tip is gone")
            }
            shot("10-safari-2-tip-closed")
        }

        // Step 1: the page menu opens.
        let more = safari.buttons["MoreMenuButton"]
        let menu = safari.otherElements["TabBarMoreMenu"]
        XCTContext.runActivity(named: "I3 step 1: the Safari page menu opens") { _ in
            XCTAssertTrue(more.waitForExistence(timeout: 10), "Safari's More button is there")
            XCTAssertTrue(waitUntilHittable(more, timeout: 10), "More is not under an overlay")
            more.tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "the page menu is open")
            shot("10-safari-3-page-menu")
        }

        // Step 2: the tap lands on the menu's own Share item: a button inside the menu, found by its
        // identifier, so the page's own title ("Share test …") can never match it.
        let item = menu.buttons["ShareButton"]
        XCTContext.runActivity(named: "I3 step 2: the tap lands on Share in the page menu") { _ in
            XCTAssertTrue(item.waitForExistence(timeout: 5), "the page menu has its Share item")
            XCTAssertTrue(["Share", "共享", "分享"].contains(item.label), "that item is Share: \(item.label)")
            XCTAssertTrue(waitUntilHittable(item, timeout: 5), "the Share item can be tapped")
            item.tap()
        }

        // Step 3: the system share sheet first, then KeepEssence in it, as two separate waits.
        let sheet = safari.otherElements["ActivityListView"]
        let ours = sheet.cells.matching(NSPredicate(format: "identifier == 'shareCell' AND label == 'KeepEssence'")).firstMatch
        XCTContext.runActivity(named: "I3 step 3: the system share sheet is up and KeepEssence is in it") { _ in
            XCTAssertTrue(sheet.waitForExistence(timeout: 15), "the system share sheet is open")
            XCTAssertTrue(ours.waitForExistence(timeout: 15), "KeepEssence is in the system share sheet")
            shot("10-share-sheet")
        }

        // Step 4: picking KeepEssence saves the page, and the core's one sentence says so.
        let sentence = safari.staticTexts["share.sentence"]
        XCTContext.runActivity(named: "I3 step 4: KeepEssence is picked and says the page is saved") { _ in
            ours.tap()
            XCTAssertTrue(sentence.waitForExistence(timeout: 15), "the core's one sentence is shown")
            // The extension follows the system language, not the launch arguments of the app.
            XCTAssertTrue(["已存入。", "Saved."].contains(sentence.label), sentence.label)
            shot("11-share-saved")
        }

        // Step 5: it closes itself and Safari stays in front.
        XCTContext.runActivity(named: "I3 step 5: the sheet closes itself and Safari is still in front") { _ in
            XCTAssertTrue(sentence.waitForNonExistence(timeout: 8))
            XCTAssertEqual(safari.state, .runningForeground)
            XCTAssertNotEqual(app.state, .runningForeground, "the app was not opened")
        }
    }
}
