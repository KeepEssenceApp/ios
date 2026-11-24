import XCTest

/// The app against a deployed core, nothing faked. Skipped unless asked for:
///
///   TEST_RUNNER_KE_ONLINE_SERVER=https://keepessence.app \
///   TEST_RUNNER_KE_ONLINE_EMAIL=<an invited test account that already has analysed items> \
///   TEST_RUNNER_KE_ONLINE_ADMIN_SECRET=<the core's ADMIN_SECRET> \
///   xcodebuild test ... -only-testing:KeepEssenceUITests/OnlineUITests
///
/// The admin secret is used once, to fetch the sign-in code the operator would pass on when the
/// core has no mail provider. Use a test account and made-up content.
final class OnlineUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = env["KE_SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func loginCode(server: String, email: String, secret: String) throws -> String {
        var request = URLRequest(url: URL(string: server + "/admin/login-codes")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        var code: String?
        let done = expectation(description: "sign-in code")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                code = object["code"] as? String
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        return try XCTUnwrap(code, "the core returned a sign-in code")
    }

    /// I1, I2 online: sign in, the four entries, Today with real analyses, a swipe, an action, Notes, Assistants.
    func testSignInAndReadAgainstTheDeployedCore() throws {
        guard let server = env["KE_ONLINE_SERVER"], let email = env["KE_ONLINE_EMAIL"], let secret = env["KE_ONLINE_ADMIN_SECRET"],
              !server.isEmpty, !email.isEmpty, !secret.isEmpty else {
            throw XCTSkip("set KE_ONLINE_SERVER, KE_ONLINE_EMAIL and KE_ONLINE_ADMIN_SECRET to run against a deployed core")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-KEServer", server, "-KEReset", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20))
        emailField.tap()
        emailField.typeText(email)
        app.buttons["signin.send"].tap()
        let codeField = app.textFields["signin.code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 20))
        // The app's own request made a fresh code; the operator fetches it after that.
        let code = try loginCode(server: server, email: email, secret: secret)
        codeField.tap()
        codeField.typeText(code)
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 30), "signed in and on the main page")

        let tabs = ["tab.today", "tab.digest", "tab.notes", "tab.assistants"].map { app.buttons[$0] }
        for tab in tabs { XCTAssertTrue(tab.exists) }
        let xs = tabs.map { $0.frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "today, digest, notes, assistants from left to right")

        // Real analyses written by the built-in assistant.
        XCTAssertTrue(app.buttons["action.seen"].firstMatch.waitForExistence(timeout: 30), "an analysis with its actions")
        for label in ["Summary", "Key fact", "Key points", "Verdict"] {
            XCTAssertTrue(app.staticTexts[label].firstMatch.exists, "\(label) is shown")
        }
        XCTAssertTrue(app.descendants(matching: .any)["status.line"].exists, "the status bar is on Today")
        shot("online-1-today")

        let cards = app.descendants(matching: .any).matching(identifier: "today.card")
        cards.firstMatch.swipeRight()
        XCTAssertTrue(app.staticTexts["Added to the deep-dive queue"].waitForExistence(timeout: 20))
        let seen = app.buttons.matching(identifier: "action.seen")
        if seen.count > 0 {
            seen.firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["today.rest"].waitForExistence(timeout: 20))
        }
        shot("online-2-today-after-actions")

        app.buttons["tab.digest"].tap()
        sleep(2)
        shot("online-3-digest")

        app.buttons["tab.notes"].tap()
        XCTAssertTrue(app.textFields["notes.find"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "queue.card").firstMatch.waitForExistence(timeout: 20), "the swiped item is in the queue")
        shot("online-4-notes")

        app.buttons["tab.assistants"].tap()
        XCTAssertTrue(app.buttons["assistants.devices"].waitForExistence(timeout: 20))
        shot("online-5-assistants")
    }
}
