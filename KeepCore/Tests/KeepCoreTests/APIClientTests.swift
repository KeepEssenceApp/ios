import XCTest
@testable import KeepCore

/// Every operation of the contract the app uses: what is sent, and that the answer decodes.
final class APIClientTests: XCTestCase {
    private let device = #"{"id":"d1","name":"iPhone","category":"client","client":"phone","tier":"manage","created_at":"2026-11-24T12:00:00Z","last_used_at":null,"notifications":false,"this_device":true}"#
    private let user = #"{"id":"u1","timezone":"Asia/Shanghai","lang":"zh"}"#
    private let analysis = #"{"unavailable":false,"summary":"One sentence.","key_fact":"Author · 8 min","points":["a","b"],"verdict":"worth_deep_dive","related_hint":null,"assistant":{"id":"a1","name":"Reader"},"created_at":"2026-11-24T12:01:02.345Z"}"#
    private var item: String {
        #"{"id":"i1","kind":"link","title":"T","site":"blog.example.dev","url":"https://blog.example.dev/x","created_at":"2026-11-24T12:00:00Z","stage":"analysed","content_unavailable":false,"dispatch_to":{"id":"a1","name":"Reader"},"days_left":29,"pinned":false,"signal":null,"in_queue":false,"analysis":\#(analysis)}"#
    }
    private let settings = #"{"rules":"r","preference":null,"expiry_options":[7,30,90,365],"notify":true,"timezone":"Asia/Shanghai","lang":"zh","roles":{"analysis":"a1","digest":"a1","deep_read":null,"deep_dive":null},"calendar_image":{"enabled":true,"url":"https://core.example/c/abc.svg"}}"#
    private let note = #"{"id":"n1","title":"N","body":"B","created_at":"2026-11-24T12:00:00Z","assistant":{"id":"a2","name":"Deep","submitted_by_user":true},"origin":{"item_id":"i1","item_title":"T","item_url":null,"digest_day":"2026-11-23"},"sources":[{"title":"S","url":"https://s.example"}],"asset_ids":[]}"#

    private let firstKey = "save-1-0000001"
    private let secondKey = "save-2-0000002"
    private let pasteKey = "paste-1-000001"

    private func stub(_ answer: StubProtocol.Answer) -> APIClient {
        StubProtocol.reset { _ in answer }
        return StubProtocol.client()
    }

    private var last: StubProtocol.Recorded { StubProtocol.requests.last! }

    private func expect(_ method: String, _ path: String, query: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(last.method, method, file: file, line: line)
        XCTAssertEqual(last.path, path, file: file, line: line)
        XCTAssertEqual(last.query, query, file: file, line: line)
    }

    func testHeadersCarryCredentialAndLanguage() async throws {
        let c = stub(.json(200, #"{"device":\#(device),"user":\#(user)}"#))
        let me = try await c.getThisDevice()
        expect("GET", "/v1/devices/me")
        XCTAssertEqual(last.headers["Authorization"], "Bearer cred-1")
        XCTAssertEqual(last.headers["Accept-Language"], "en")
        XCTAssertEqual(me.device.tier, .manage)
        XCTAssertEqual(me.device.thisDevice, true)
        XCTAssertEqual(me.user.timezone, "Asia/Shanghai")
    }

    func testErrorBodyBecomesAPIError() async {
        let c = stub(.json(409, #"{"error":{"code":"last_manager","message":"The last device with the manage tier cannot be lowered or revoked."}}"#))
        do {
            try await c.signOutThisDevice()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.status, 409)
            XCTAssertEqual(e.code, "last_manager")
            XCTAssertTrue(e.message.hasPrefix("The last device"))
        } catch { XCTFail("\(error)") }
        expect("DELETE", "/v1/devices/me")
    }

    func testUnauthorized() async {
        let c = stub(.json(401, #"{"error":{"code":"unauthorized","message":"no"}}"#))
        do { _ = try await c.getStatus(); XCTFail() } catch let e as APIError { XCTAssertTrue(e.isUnauthorized) } catch { XCTFail() }
    }

    func testGetMeta() async throws {
        let c = stub(.json(200, #"{"contract_version":"1.0.0","limits":{"image_long_edge_px":1600},"shared_rules":{"secret_like":{"max_length_checked":200,"patterns":[{"name":"p","regex":"abc"}]},"save_messages":{"saved":{"zh":"已存入。","en":"Saved."}}}}"#))
        let (meta, data) = try await c.getMeta()
        expect("GET", "/v1/meta")
        XCTAssertNil(last.headers["Authorization"])
        XCTAssertEqual(meta.contractVersion, "1.0.0")
        XCTAssertEqual(meta.limit("image_long_edge_px"), 1600)
        XCTAssertEqual(meta.sharedRules.secretPatterns, [SecretPattern(name: "p", regex: "abc")])
        XCTAssertEqual(meta.sharedRules.saveMessage("saved", lang: "zh"), "已存入。")
        XCTAssertFalse(data.isEmpty)
    }

    func testRequestLoginCodeAndSignIn() async throws {
        var c = stub(.empty(202))
        try await c.requestLoginCode(email: "a@example.com")
        expect("POST", "/v1/auth/email-codes")
        XCTAssertEqual(last.json["email"] as? String, "a@example.com")
        XCTAssertEqual(last.json["lang"] as? String, "en")
        XCTAssertNil(last.headers["Authorization"])

        c = stub(.json(201, #"{"credential":"secret-value","device":\#(device),"user":\#(user)}"#))
        let grant = try await c.signIn(email: "a@example.com", code: "123456", deviceName: "iPhone", timezone: "Asia/Shanghai")
        expect("POST", "/v1/auth/sessions")
        XCTAssertEqual(last.json["client"] as? String, "phone")
        XCTAssertEqual(last.json["code"] as? String, "123456")
        XCTAssertEqual(last.json["device_name"] as? String, "iPhone")
        XCTAssertEqual(last.json["timezone"] as? String, "Asia/Shanghai")
        XCTAssertEqual(grant.credential, "secret-value")
        XCTAssertEqual(grant.device.tier, .manage)
    }

    func testDevices() async throws {
        var c = stub(.json(200, #"{"devices":[\#(device),{"id":"a1","name":"Reader","category":"assistant","steps":["analysis","deep_read"],"created_at":"2026-11-20T08:00:00Z"}]}"#))
        let list = try await c.listDevices()
        expect("GET", "/v1/devices")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[1].steps, [.analysis, .deepRead])
        XCTAssertNil(list[1].tier)

        c = stub(.json(200, device))
        _ = try await c.updateDevice(id: "d 1", name: "New", tier: .read)
        expect("PATCH", "/v1/devices/d%201".removingPercentEncoding!)
        XCTAssertEqual(last.json["name"] as? String, "New")
        XCTAssertEqual(last.json["tier"] as? String, "read")

        c = stub(.empty())
        try await c.revokeDevice(id: "d1")
        expect("DELETE", "/v1/devices/d1")
    }

    func testDeviceCodes() async throws {
        var c = stub(.json(200, #"{"device_name":"Edge","client":"extension","requested_tier":"read","expires_at":"2026-11-24T12:10:00Z"}"#))
        let r = try await c.getDeviceCodeRequest(code: "K7M-2QX")
        expect("GET", "/v1/device-codes/K7M-2QX/request")
        XCTAssertEqual(r.requestedTier, .read)
        XCTAssertEqual(r.deviceName, "Edge")

        c = stub(.json(200, device))
        _ = try await c.approveDeviceCode(code: "K7M-2QX", tier: .save)
        expect("POST", "/v1/device-codes/K7M-2QX/approve")
        XCTAssertEqual(last.json["tier"] as? String, "save")

        c = stub(.empty())
        try await c.denyDeviceCode(code: "K7M-2QX")
        expect("POST", "/v1/device-codes/K7M-2QX/deny")
    }

    func testSaveItem() async throws {
        let c = stub(.json(201, #"{"status":"saved","item_id":"i9","message_key":"saved","message":"Saved.","image_stored":true}"#))
        let r = try await c.saveItem(SaveRequest(kind: "link", url: "https://x.example/a", title: "A", entry: "share"), idempotencyKey: firstKey)
        expect("POST", "/v1/items")
        XCTAssertEqual(last.headers["Idempotency-Key"], "save-1-0000001")
        // No tags and no triage information, and nothing that is not set (rule B7).
        XCTAssertEqual(Set(last.json.keys), ["kind", "url", "title", "entry"])
        XCTAssertEqual(r.status, "saved")
        XCTAssertEqual(r.messageKey, "saved")
        XCTAssertEqual(r.imageStored, true)

        let d = stub(.json(200, #"{"status":"duplicate","item_id":"i1","message_key":"duplicate","message":"Already saved. Nothing was added."}"#))
        let dup = try await d.saveItem(SaveRequest(kind: "link", url: "https://x.example/a"), idempotencyKey: secondKey)
        XCTAssertEqual(dup.status, "duplicate")
    }

    func testAssetFlow() async throws {
        var c = stub(.json(200, #"{"asset_id":"as1","status":"upload","upload_url":"/v1/uploads/as1?sig=abc","expires_at":"2026-11-24T12:10:00Z"}"#))
        let sha = String(repeating: "ab", count: 32)
        let t = try await c.requestUpload(sha256: sha, bytes: 3, contentType: "image/jpeg")
        expect("POST", "/v1/assets")
        XCTAssertEqual(last.json["sha256"] as? String, sha)
        XCTAssertEqual(last.json["bytes"] as? Int, 3)
        XCTAssertEqual(last.json["content_type"] as? String, "image/jpeg")
        XCTAssertEqual(t.status, "upload")

        c = stub(.empty())
        try await c.upload(to: t.uploadUrl!, data: Data([1, 2, 3]), contentType: "image/jpeg")
        expect("PUT", "/v1/uploads/as1", query: "sig=abc")
        XCTAssertEqual(last.headers["Content-Type"], "image/jpeg")
        XCTAssertEqual(last.body, Data([1, 2, 3]))
        XCTAssertNil(last.headers["Authorization"], "the upload address carries its own signature")

        try await c.completeUpload(assetId: "as1")
        expect("POST", "/v1/assets/as1/complete")

        c = stub(.json(200, #"{"download_url":"https://core.example/d/as1","expires_at":"2026-11-24T12:05:00Z","content_type":"image/jpeg","bytes":3}"#))
        let loc = try await c.getAsset(id: "as1")
        expect("GET", "/v1/assets/as1")
        XCTAssertEqual(loc.bytes, 3)
    }

    func testItems() async throws {
        var c = stub(.json(200, #"{"items":[\#(item),{"id":"i2","kind":"image","title":"Shot","created_at":"2026-11-24T12:00:00Z","stage":"saved"}],"next_cursor":null}"#))
        let page = try await c.listItems(state: "today")
        expect("GET", "/v1/items", query: "limit=100&state=today")
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items[0].analysis?.verdict, .worthDeepDive)
        XCTAssertEqual(page.items[0].analysis?.points?.count, 2)
        XCTAssertNotNil(page.items[0].analysis?.createdAt, "fractional seconds are accepted")
        XCTAssertNil(page.items[1].analysis)
        XCTAssertFalse(page.items[0].handled)

        c = stub(.json(200, String(item.dropLast()) + #","body":"text","asset_id":null,"tags":["assistant:Reader","expiry:30"],"expiry_days":30}"#))
        let detail = try await c.getItem(id: "i1")
        expect("GET", "/v1/items/i1")
        XCTAssertEqual(detail.tags, ["assistant:Reader", "expiry:30"])
        XCTAssertEqual(detail.expiryDays, 30)

        _ = try await c.updateItem(id: "i1", expiryDays: 90)
        expect("PATCH", "/v1/items/i1")
        XCTAssertEqual(last.json["expiry_days"] as? Int, 90)
        XCTAssertNil(last.json["dispatch_to"])
        _ = try await c.updateItem(id: "i1", dispatchTo: "a2")
        XCTAssertEqual(last.json["dispatch_to"] as? String, "a2")

        c = stub(.empty())
        try await c.deleteItem(id: "i1"); expect("DELETE", "/v1/items/i1")
        try await c.pinItem(id: "i1"); expect("PUT", "/v1/items/i1/pin")
        try await c.unpinItem(id: "i1"); expect("DELETE", "/v1/items/i1/pin")
        try await c.setSignal(id: "i1", signal: .notInterested); expect("PUT", "/v1/items/i1/signal")
        XCTAssertEqual(last.json["signal"] as? String, "not_interested")
        try await c.setSignal(id: "i1", signal: .seen)
        XCTAssertEqual(last.json["signal"] as? String, "seen")
        try await c.clearSignal(id: "i1"); expect("DELETE", "/v1/items/i1/signal")
    }

    func testDigests() async throws {
        var c = stub(.json(200, #"{"digests":[{"day":"2026-11-23","read":false},{"day":"2026-11-22","read":true}],"next_cursor":null}"#))
        let list = try await c.listDigests()
        expect("GET", "/v1/digests", query: "limit=20")
        XCTAssertEqual(list.digests.map(\.read), [false, true])

        c = stub(.json(200, #"{"day":"2026-11-23","read":false,"counts":{"saved":9,"worth":2},"summary":"S","worth":[{"item_id":"i1","title":"T","line":"L","verdict":"worth_deep_dive","available":true,"in_queue":false}],"rest":[{"item_id":"i2","title":"R","signal":"seen","in_queue":false,"available":true,"can_restore":true}],"question":"Q?","assistant":{"id":"a1","name":"Reader"},"previous_day":"2026-11-22","next_day":null}"#))
        let d = try await c.getDigest()
        expect("GET", "/v1/digests/latest")
        XCTAssertEqual(d.counts?.saved, 9)
        XCTAssertEqual(d.worth.first?.line, "L")
        XCTAssertEqual(d.rest.first?.canRestore, true)
        XCTAssertEqual(d.previousDay, "2026-11-22")
        XCTAssertNil(d.nextDay)
        _ = try await c.getDigest(day: "2026-11-22")
        expect("GET", "/v1/digests/2026-11-22")

        c = stub(.empty())
        try await c.markDigestRead(day: "2026-11-23")
        expect("POST", "/v1/digests/2026-11-23/read")
    }

    func testQueueAndDeepDive() async throws {
        let entry = #"{"item_id":"i1","title":"T","added_at":"2026-11-24T12:00:00Z","deep_read":"ready","report":{"read":"R","found":"F","questions":["q1"],"assistant":{"id":"a1","name":"Reader"}},"went_at":null,"fetched_at":null,"entry":"https://a.example/start"}"#
        var c = stub(.json(200, #"{"entries":[\#(entry)]}"#))
        let q = try await c.listQueue()
        expect("GET", "/v1/deep-read-queue")
        XCTAssertEqual(q.first?.deepRead, "ready")
        XCTAssertEqual(q.first?.report?.questions, ["q1"])

        c = stub(.json(200, entry))
        _ = try await c.addToQueue(itemId: "i1")
        expect("PUT", "/v1/deep-read-queue/i1")

        c = stub(.empty())
        try await c.removeFromQueue(itemId: "i1")
        expect("DELETE", "/v1/deep-read-queue/i1")

        c = stub(.json(201, #"{"assistant":{"id":"a2","name":"Deep"},"opening_line":"Deep dive into this item: T","open_url":"https://chat.example/new","entry":null}"#))
        let e = try await c.startDeepDive(itemId: "i1")
        expect("POST", "/v1/deep-dive-requests")
        XCTAssertEqual(last.json["item_id"] as? String, "i1")
        XCTAssertNil(last.json["assistant_id"])
        XCTAssertEqual(e.openingLine, "Deep dive into this item: T")
        _ = try await c.startDeepDive(itemId: "i1", assistantId: "a2")
        XCTAssertEqual(last.json["assistant_id"] as? String, "a2")
    }

    func testNotes() async throws {
        var c = stub(.json(200, #"{"notes":[{"id":"n1","title":"N","excerpt":"e","created_at":"2026-11-24T12:00:00Z"}],"next_cursor":null}"#))
        _ = try await c.listNotes()
        expect("GET", "/v1/notes", query: "limit=50")
        let found = try await c.listNotes(q: "租约")
        XCTAssertEqual(last.path, "/v1/notes")
        XCTAssertTrue(last.query?.contains("q=") == true)
        XCTAssertEqual(found.notes.first?.title, "N")

        c = stub(.json(200, note))
        let n = try await c.getNote(id: "n1")
        expect("GET", "/v1/notes/n1")
        XCTAssertEqual(last.headers["Accept"], "application/json")
        XCTAssertEqual(n.assistant.submittedByUser, true)
        XCTAssertEqual(n.origin?.digestDay, "2026-11-23")
        XCTAssertEqual(n.sources?.first?.url, "https://s.example")

        c = stub(.json(200, "# N\n\nB\n"))
        let md = try await c.getNoteMarkdown(id: "n1")
        XCTAssertEqual(last.headers["Accept"], "text/markdown")
        XCTAssertEqual(md, "# N\n\nB\n")

        c = stub(.json(201, note))
        _ = try await c.pasteNote(PasteNoteRequest(title: "N", body: "B", itemId: "i1"), idempotencyKey: pasteKey)
        expect("POST", "/v1/notes")
        XCTAssertEqual(last.headers["Idempotency-Key"], "paste-1-000001")
        XCTAssertEqual(last.json["item_id"] as? String, "i1")
        XCTAssertNil(last.json["assistant_id"])
    }

    func testStatusAndCalendar() async throws {
        var c = stub(.json(200, #"{"assistants":[{"id":"a1","name":"Reader","state":"recent","last_seen_at":"2026-11-24T11:56:00Z"},{"id":"a2","name":"Deep","state":"never","last_seen_at":null}],"saved_today":9,"waiting":2,"oldest_waiting_deleted_on":"2026-12-24","no_digest_reason":"not_yet_time"}"#))
        let s = try await c.getStatus()
        expect("GET", "/v1/status")
        XCTAssertEqual(s.savedToday, 9)
        XCTAssertEqual(s.assistants.map(\.state), ["recent", "never"])
        XCTAssertEqual(s.noDigestReason, "not_yet_time")

        c = stub(.json(200, #"{"month":"2026-11","today":"2026-11-24","days":[{"day":"2026-11-01","mark":"empty","has_digest":false},{"day":"2026-11-02","mark":"note","has_digest":true}],"counts":{"saved":40,"digests":12,"read":9,"notes":3},"previous_month":"2026-10","next_month":null}"#))
        let m = try await c.getCalendar()
        expect("GET", "/v1/calendar")
        XCTAssertEqual(m.counts.notes, 3)
        _ = try await c.getCalendar(month: "2026-10")
        expect("GET", "/v1/calendar", query: "month=2026-10")
    }

    func testSettings() async throws {
        let c = stub(.json(200, settings))
        let s = try await c.getSettings()
        expect("GET", "/v1/settings")
        XCTAssertEqual(s.expiryOptions, [7, 30, 90, 365])
        XCTAssertEqual(s.roles.analysis, "a1")
        XCTAssertNil(s.roles.deepRead)
        XCTAssertEqual(s.calendarImage.url, "https://core.example/c/abc.svg")

        _ = try await c.updateSettings(SettingsChange(rules: "new", calendarImageEnabled: false))
        expect("PATCH", "/v1/settings")
        XCTAssertEqual(Set(last.json.keys), ["rules", "calendar_image_enabled"], "only what changed is sent")
        XCTAssertEqual(last.json["calendar_image_enabled"] as? Bool, false)

        // A role can be set to nobody: an explicit null.
        _ = try await c.updateSettings(SettingsChange(roles: ["deep_read": nil, "digest": "a1"]))
        let roles = last.json["roles"] as? [String: Any]
        XCTAssertTrue(roles?["deep_read"] is NSNull)
        XCTAssertEqual(roles?["digest"] as? String, "a1")

        _ = try await c.rotateCalendarImage()
        expect("POST", "/v1/settings/calendar-image/rotate")
    }

    func testAssistants() async throws {
        let a = #"{"id":"a1","name":"Reader","kind":"scheduled","steps":["analysis","digest","deep_read","deep_dive"],"built_in":false,"connected_at":"2026-11-20T08:00:00Z","last_seen_at":null,"runs_at":"agent.example.net"}"#
        var c = stub(.json(200, #"{"assistants":[\#(a)],"connect_url":"https://core.example/mcp"}"#))
        let page = try await c.listAssistants()
        expect("GET", "/v1/assistants")
        XCTAssertEqual(page.connectUrl, "https://core.example/mcp")
        XCTAssertEqual(page.assistants.first?.steps.count, 4)
        XCTAssertEqual(page.assistants.first?.builtIn, false)

        c = stub(.json(200, a))
        _ = try await c.updateAssistant(id: "a1", steps: [.deepDive])
        expect("PATCH", "/v1/assistants/a1")
        XCTAssertEqual(last.json["steps"] as? [String], ["deep_dive"])
        XCTAssertNil(last.json["name"])

        c = stub(.empty())
        try await c.revokeAssistant(id: "a1")
        expect("DELETE", "/v1/assistants/a1")
    }

    func testServerAddressParsing() {
        XCTAssertEqual(KeepStore.parseServer("keepessence.app")?.absoluteString, "https://keepessence.app")
        XCTAssertEqual(KeepStore.parseServer(" http://127.0.0.1:8791/ ")?.absoluteString, "http://127.0.0.1:8791")
        XCTAssertNil(KeepStore.parseServer(""))
        XCTAssertNil(KeepStore.parseServer("ftp://x.example"))
    }

    func testTierCanBeLoweredNeverRaised() {
        XCTAssertEqual(Tier.grantable(requested: .read), [.save, .read])
        XCTAssertEqual(Tier.grantable(requested: .save), [.save])
        XCTAssertEqual(Tier.grantable(requested: .manage), [.save, .read, .manage])
    }
}
