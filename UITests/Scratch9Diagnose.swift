import XCTest

/// TEMPORARY (ios#9): reads the real Safari page menu and share sheet on the CI simulator and attaches the
/// accessibility hierarchy at each stage. It asserts nothing, so it cannot make a run green or red by itself.
/// Removed in the next commit, before the PR is ready.
final class Scratch9Diagnose: XCTestCase {
    private let server = "http://127.0.0.1:8795"

    private func dump(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "hierarchy " + name
        a.lifetime = .keepAlways
        add(a)
        let image = XCUIScreen.main.screenshot()
        let s = XCTAttachment(screenshot: image)
        s.name = "screen " + name
        s.lifetime = .keepAlways
        add(s)
    }

    private func note(_ text: String) {
        let a = XCTAttachment(string: text)
        a.name = "note"
        a.lifetime = .keepAlways
        add(a)
        XCTContext.runActivity(named: text) { _ in }
    }

    func testAAADiagnoseSafariShare() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-KEServer", server, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        _ = app.buttons["tab.today"].waitForExistence(timeout: 8)

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
        note("page loaded: \(safari.staticTexts["A page made for the share test"].waitForExistence(timeout: 15))")
        dump(safari, "a-after-page-load")

        let tip = safari.popovers.firstMatch
        if tip.waitForExistence(timeout: 5) {
            dump(safari, "b-tip-up")
            let close = tip.buttons.matching(NSPredicate(format: "identifier == 'xmark.circle.fill' OR label IN {'Close','关闭'}")).firstMatch
            note("tip close button exists: \(close.exists) hittable: \(close.isHittable)")
            if close.exists { close.tap() }
            note("tip gone: \(tip.waitForNonExistence(timeout: 5))")
            dump(safari, "c-tip-closed")
        } else {
            note("no first-run tip")
        }

        let more = safari.buttons["MoreMenuButton"]
        note("MoreMenuButton exists: \(more.waitForExistence(timeout: 5)) hittable: \(more.isHittable) frame: \(more.frame)")
        guard more.exists else { return }
        more.tap()
        sleep(3)
        dump(safari, "d-menu-open")

        let shareLabels = ["Share", "Share…", "Share...", "共享", "分享"]
        let candidates = safari.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", shareLabels))
        note("elements with an exact Share label: \(candidates.count)")
        for i in 0..<min(candidates.count, 6) {
            let e = candidates.element(boundBy: i)
            note("Share candidate \(i): type \(e.elementType.rawValue) id '\(e.identifier)' label '\(e.label)' frame \(e.frame) hittable \(e.isHittable)")
        }
        let item = candidates.matching(NSPredicate(format: "elementType IN %@", [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue])).firstMatch
        note("button/menuItem Share exists: \(item.exists)")
        guard item.exists else { return }
        item.tap()
        sleep(4)
        dump(safari, "e-after-share-tap")

        let ours = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'KeepEssence'"))
        note("elements labelled KeepEssence: \(ours.count)")
        for i in 0..<min(ours.count, 6) {
            let e = ours.element(boundBy: i)
            note("KeepEssence candidate \(i): type \(e.elementType.rawValue) id '\(e.identifier)' frame \(e.frame) hittable \(e.isHittable)")
        }
        guard ours.firstMatch.exists else { return }
        ours.firstMatch.tap()
        sleep(2)
        dump(safari, "f-after-keepessence-tap")
        sleep(3)
        dump(safari, "g-later")
        note("safari state: \(safari.state.rawValue) app state: \(app.state.rawValue)")
    }
}
