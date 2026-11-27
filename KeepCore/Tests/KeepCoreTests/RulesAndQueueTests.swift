import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import KeepCore

final class SecretMatcherTests: XCTestCase {
    /// The patterns come from the contract (x-shared-rules), through the generated copy.
    private let matcher = SecretMatcher(rules: Meta.bundled.sharedRules)
    private let secretLine = ["pass", "word = hunter", "2222"].joined()

    func testEveryPatternOfTheContractCompiles() {
        XCTAssertEqual(Meta.bundled.sharedRules.secretPatterns.count, 5)
        XCTAssertEqual(matcher.patternCount, 5, "a pattern of the contract does not compile on this platform")
        XCTAssertEqual(matcher.maxLengthChecked, 200)
    }

    // Invented examples of what the patterns are for. None is a real credential.
    func testEachPatternMatchesWhatItIsFor() {
        XCTAssertEqual(matcher.match("-----BEGIN RSA PRIVATE KEY-----\nMIIEow..."), "private_key_block") // gitleaks:allow
        XCTAssertEqual(matcher.match("-----BEGIN PRIVATE KEY-----"), "private_key_block") // gitleaks:allow
        XCTAssertEqual(matcher.match("my key is sk-abcdefghijklmnop1234"), "known_credential_prefix") // gitleaks:allow
        XCTAssertEqual(matcher.match("ghp_" + String(repeating: "a1B2", count: 9)), "known_credential_prefix") // gitleaks:allow
        XCTAssertEqual(matcher.match("AKIAIOSFODNN7EXAMPLE"), "known_credential_prefix") // gitleaks:allow
        XCTAssertEqual(matcher.match("xoxb-1234567890-abcdefghij"), "known_credential_prefix") // gitleaks:allow
        XCTAssertEqual(matcher.match("Authorization: Bearer abcdefghijklmnop1234"), "bearer_or_basic_header") // gitleaks:allow
        XCTAssertEqual(matcher.match("password = hunter2222"), "assignment_of_secret") // gitleaks:allow
        XCTAssertEqual(matcher.match("API_KEY: 123456abcdef"), "assignment_of_secret") // gitleaks:allow
        XCTAssertEqual(matcher.match("https://x.example/?api_key=abcdef123456"), "assignment_of_secret") // gitleaks:allow
        XCTAssertEqual(matcher.match("Tr0ub4dor&3xY!"), "single_dense_string") // gitleaks:allow
        XCTAssertEqual(matcher.match("  Tr0ub4dor&3xY!\n"), "single_dense_string", "surrounding white space is trimmed") // gitleaks:allow
    }

    func testOrdinaryContentIsNotAsked() {
        XCTAssertNil(matcher.match("把定时任务做成幂等的七种写法"))
        XCTAssertNil(matcher.match("The password policy of the company was discussed at length."))
        XCTAssertNil(matcher.match("https://blog.example.dev/Idempotent-Jobs_2026?page=2#Top"), "a URL is not a dense string")
        XCTAssertNil(matcher.match("hello world"))
        XCTAssertNil(matcher.match("Tr0ub4dor&3 two words"))
        XCTAssertNil(matcher.match(""))
        XCTAssertFalse(matcher.looksSecret(nil))
    }

    func testLongTextNeverCountsExceptForAnyLengthPatterns() {
        let filler = String(repeating: "正文。", count: 100)
        XCTAssertNil(matcher.match(secretLine + " " + filler), "text longer than max_length_checked is not checked")
        XCTAssertNil(matcher.match(filler + " " + secretLine))
        let fill = 200 - secretLine.count - 1
        XCTAssertEqual(matcher.match(String(repeating: "正", count: fill) + " " + secretLine), "assignment_of_secret", "exactly 200 characters: checked")
        XCTAssertNil(matcher.match(String(repeating: "正", count: fill + 1) + " " + secretLine), "201 characters: not checked")
        // A private key block is marked any_length: found in text of any length.
        XCTAssertEqual(matcher.match(filler + "\n-----BEGIN OPENSSH PRIVATE KEY-----\n" + filler), "private_key_block") // gitleaks:allow
    }

    func testFlagsAndInlineFlagsBothWork() {
        let rules = SharedRules(json: .object(["secret_like": .object(["max_length_checked": .number(50), "patterns": .array([
            .object(["name": .string("with_flag"), "regex": .string("alpha"), "flags": .string("i")]),
            .object(["name": .string("inline"), "regex": .string("(?i)beta")]),
            .object(["name": .string("exact"), "regex": .string("gamma")]),
        ])])]))
        let m = SecretMatcher(rules: rules)
        XCTAssertEqual(m.maxLengthChecked, 50)
        XCTAssertEqual(m.match("ALPHA"), "with_flag")
        XCTAssertEqual(m.match("BeTa"), "inline")
        XCTAssertNil(m.match("GAMMA"))
        XCTAssertEqual(m.match("gamma"), "exact")
    }

    func testSaveMessagesComeFromTheContract() {
        let r = Meta.bundled.sharedRules
        XCTAssertEqual(r.saveMessage("saved", lang: "zh"), "已存入。")
        XCTAssertEqual(r.saveMessage("queued_offline", lang: "en"), "Not saved yet. Queued, and it will be saved when you are back online.")
        XCTAssertEqual(r.saveMessage("failed", lang: "zh", reason: "原因"), "没存入：原因")
        XCTAssertEqual(r.saveMessage("queued_not_connected", lang: "zh"), "还没存入，排着队，接入后自动存入。")
        XCTAssertEqual(r.saveMessage("declined", lang: "en"), "Not saved.")
        XCTAssertEqual(r.saveMessage("secret_like_question", lang: "zh"), "这段内容看起来像密码或凭据，还要存入吗？")
        XCTAssertNil(r.saveMessage("no_such_key", lang: "en"))
        XCTAssertEqual(Meta.bundled.limit("image_long_edge_px"), 1600)
        XCTAssertEqual(Meta.bundled.limit("asset_max_bytes"), 3_145_728)
    }
}

final class OfflineQueueTests: XCTestCase {
    private var dir: URL!
    private var queue: OfflineQueue!

    override func setUp() {
        dir = temporaryDirectory()
        queue = OfflineQueue(directory: dir.appendingPathComponent("queue"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func service(lang: String = "en") -> SaveService {
        SaveService(client: StubProtocol.client(lang: lang), queue: queue, rules: Meta.bundled.sharedRules, lang: lang)
    }

    private let savedBody = #"{"status":"saved","item_id":"i9","message_key":"saved","message":"Saved."}"#

    func testEntriesAreKeptOldestFirstWithTheirBlobs() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try queue.enqueue(QueuedSave(id: "b", request: SaveRequest(kind: "text", text: "second"), createdAt: t.addingTimeInterval(60)))
        try queue.enqueue(QueuedSave(id: "a", request: SaveRequest(kind: "image"), contentType: "image/jpeg", sha256: "00", createdAt: t), blob: Data([9, 8, 7]))
        let all = queue.entries()
        XCTAssertEqual(all.map(\.id), ["a", "b"])
        XCTAssertEqual(queue.blob(for: all[0]), Data([9, 8, 7]))
        XCTAssertNil(queue.blob(for: all[1]))
        queue.remove(all[0])
        XCTAssertEqual(queue.entries().map(\.id), ["b"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: queue.directory.path).count, 1, "the blob goes with its entry")
    }

    func testSavedIsSaidOnlyWhenTheCoreAnswered() async {
        StubProtocol.reset { _ in .json(201, self.savedBody) }
        let o = await service().save(SaveDraft(id: "key-00000001", request: SaveRequest(kind: "link", url: "https://x.example", entry: "share")))
        XCTAssertEqual(o, SaveOutcome(kind: .saved, sentence: "Saved."))
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(StubProtocol.requests.last?.headers["Idempotency-Key"], "key-00000001")
    }

    func testDuplicateIsSaidAsTheCoreSaidIt() async {
        StubProtocol.reset { _ in .json(200, #"{"status":"duplicate","item_id":"i1","message_key":"duplicate","message":"之前存过了，没有重复存。"}"#) }
        let o = await service(lang: "zh").save(SaveDraft(request: SaveRequest(kind: "link", url: "https://x.example")))
        XCTAssertEqual(o, SaveOutcome(kind: .duplicate, sentence: "之前存过了，没有重复存。"))
    }

    func testOfflineIsQueuedAndSaidSo() async {
        StubProtocol.reset { _ in .offline }
        let o = await service(lang: "zh").save(SaveDraft(id: "key-00000002", request: SaveRequest(kind: "text", text: "一段摘抄", entry: "share")))
        XCTAssertEqual(o.kind, .queued)
        XCTAssertEqual(o.sentence, "还没存入，排着队，联网后自动存入。")
        XCTAssertEqual(queue.entries().map(\.id), ["key-00000002"])
        XCTAssertEqual(queue.entries().first?.request.text, "一段摘抄")
    }

    func testARefusalIsSaidWithTheCoresReasonAndNotQueued() async {
        StubProtocol.reset { _ in .json(403, #"{"error":{"code":"forbidden","message":"This device was revoked."}}"#) }
        let o = await service().save(SaveDraft(request: SaveRequest(kind: "text", text: "x")))
        XCTAssertEqual(o, SaveOutcome(kind: .failed, sentence: "Not saved: This device was revoked."))
        XCTAssertEqual(queue.count, 0)
    }

    func testFlushSendsWithTheSameKeyAndEmptiesTheQueue() async throws {
        StubProtocol.reset { _ in .offline }
        _ = await service().save(SaveDraft(id: "key-00000003", request: SaveRequest(kind: "link", url: "https://x.example/1", entry: "share")))
        _ = await service().save(SaveDraft(id: "key-00000004", request: SaveRequest(kind: "text", text: "t", entry: "share")))
        XCTAssertEqual(queue.count, 2)

        // Still offline: nothing is lost, nothing is said.
        let none = await service().flush()
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(queue.count, 2)

        StubProtocol.reset { _ in .json(201, self.savedBody) }
        let outcomes = await service().flush()
        XCTAssertEqual(outcomes.map(\.kind), [.saved, .saved])
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(Set(StubProtocol.requests.compactMap { $0.headers["Idempotency-Key"] }), ["key-00000003", "key-00000004"])
    }

    func testFlushReportsWhatTheCoreRefusesAndKeepsWhatItCouldNotSend() async throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try queue.enqueue(QueuedSave(id: "key-bad00001", request: SaveRequest(kind: "link", url: "https://bad.example"), createdAt: t))
        try queue.enqueue(QueuedSave(id: "key-good0001", request: SaveRequest(kind: "text", text: "ok"), createdAt: t.addingTimeInterval(1)))
        try queue.enqueue(QueuedSave(id: "key-later001", request: SaveRequest(kind: "text", text: "later"), createdAt: t.addingTimeInterval(2)))
        StubProtocol.reset { r in
            switch r.headers["Idempotency-Key"] {
            case "key-bad00001": return .json(400, #"{"error":{"code":"bad_request","message":"The address is not valid."}}"#)
            case "key-good0001": return .json(201, self.savedBody)
            default: return .offline
            }
        }
        let outcomes = await service().flush()
        XCTAssertEqual(outcomes.map(\.kind), [.failed, .saved])
        XCTAssertEqual(outcomes.first?.sentence, "Not saved: The address is not valid.")
        XCTAssertEqual(queue.entries().map(\.id), ["key-later001"])
    }

    func testFlushKeepsEverythingWhenTheCredentialIsRefused() async throws {
        try queue.enqueue(QueuedSave(id: "key-00000009", request: SaveRequest(kind: "text", text: "x")))
        StubProtocol.reset { _ in .json(401, #"{"error":{"code":"unauthorized","message":"no"}}"#) }
        let outcomes = await service().flush()
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertEqual(queue.count, 1)
    }

    func testImageGoesThroughTheAssetFlow() async throws {
        let image = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 300, height: 200)))
        StubProtocol.reset { r in
            switch (r.method, r.path) {
            case ("POST", "/v1/assets"): return .json(200, #"{"asset_id":"as1","status":"upload","upload_url":"https://core.example/up/as1?sig=s"}"#)
            case ("PUT", "/up/as1"): return .empty()
            case ("POST", "/v1/assets/as1/complete"): return .empty()
            default: return .json(201, self.savedBody)
            }
        }
        let o = await service().save(SaveDraft(request: SaveRequest(kind: "image", entry: "share"), image: image))
        XCTAssertEqual(o.kind, .saved)
        XCTAssertEqual(StubProtocol.requests.map { "\($0.method) \($0.path)" },
                       ["POST /v1/assets", "PUT /up/as1", "POST /v1/assets/as1/complete", "POST /v1/items"])
        let ask = StubProtocol.requests[0].json
        XCTAssertEqual(ask["sha256"] as? String, image.sha256)
        XCTAssertEqual(ask["bytes"] as? Int, image.data.count)
        XCTAssertEqual(ask["content_type"] as? String, image.contentType)
        XCTAssertEqual(StubProtocol.requests[1].body, image.data)
        XCTAssertEqual(StubProtocol.requests[3].json["asset_id"] as? String, "as1")
    }

    func testAlreadyStoredBytesAreNotUploadedAgain() async throws {
        let image = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 64, height: 64)))
        StubProtocol.reset { r in
            r.path == "/v1/assets" ? .json(200, #"{"asset_id":"as7","status":"stored"}"#) : .json(201, self.savedBody)
        }
        _ = await service().save(SaveDraft(request: SaveRequest(kind: "image"), image: image))
        XCTAssertEqual(StubProtocol.requests.map(\.path), ["/v1/assets", "/v1/items"])
    }

    func testOverQuotaStillSavesAndTheCoreSaysTheImageWasNotStored() async throws {
        let image = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 64, height: 64)))
        StubProtocol.reset { r in
            r.path == "/v1/assets" ? .json(200, #"{"asset_id":"as8","status":"over_quota"}"#)
                : .json(201, #"{"status":"saved","item_id":"i9","message_key":"saved_image_skipped_quota","message":"Saved. The image was not stored: storage quota exceeded.","image_stored":false}"#)
        }
        let o = await service().save(SaveDraft(request: SaveRequest(kind: "image", url: "https://x.example/p"), image: image))
        // Still `.saved` (the item is in), but the outcome carries that the picture is not: a sentence about the picture
        // (the one-frame line of an animation) is only said for `imageStored == true`.
        XCTAssertEqual(o, SaveOutcome(kind: .saved, sentence: "Saved. The image was not stored: storage quota exceeded.", imageStored: false))
        XCTAssertEqual(ImageNote(after: "Only one frame of the animation was kept.").apply(to: o), o, "an over-quota animation is not said to have kept a frame")
        XCTAssertEqual(StubProtocol.requests.map(\.path), ["/v1/assets", "/v1/items"], "nothing is uploaded")
        XCTAssertEqual(StubProtocol.requests.last?.json["asset_id"] as? String, "as8")
        XCTAssertEqual(StubProtocol.requests.last?.json["kind"] as? String, "image")
    }

    func testNotSignedInIsHeldAndSaidSo() async throws {
        StubProtocol.reset { _ in .empty(500) }
        let o = service(lang: "en").hold(SaveDraft(id: "hold-0000001", request: SaveRequest(kind: "link", url: "https://x.example", entry: "share")))
        XCTAssertEqual(o, SaveOutcome(kind: .queued, sentence: "Not saved yet. Queued, and it will be saved once this device is connected."))
        XCTAssertEqual(queue.entries().map(\.id), ["hold-0000001"])
        XCTAssertTrue(StubProtocol.requests.isEmpty, "nothing is sent")
        XCTAssertEqual(service(lang: "zh").declinedSentence, "没存入。")
    }

    func testOfflineImageIsQueuedWithItsBytes() async throws {
        let image = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 64, height: 64)))
        StubProtocol.reset { _ in .offline }
        let o = await service().save(SaveDraft(id: "key-img00001", request: SaveRequest(kind: "image", entry: "share"), image: image))
        XCTAssertEqual(o.kind, .queued)
        let entry = try XCTUnwrap(queue.entries().first)
        XCTAssertEqual(queue.blob(for: entry), image.data)
        XCTAssertEqual(entry.sha256, image.sha256)
    }
}

enum TestImage {
    static func png(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.77, green: 0.64, blue: 0.16, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    static func size(of data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (image.width, image.height)
    }
}

final class ImagePrepTests: XCTestCase {
    func testLargeImageIsResizedToTheLongEdge() throws {
        let p = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 3200, height: 1800), longEdge: 1600))
        XCTAssertEqual(p.width, 1600)
        XCTAssertEqual(p.height, 900)
        let decoded = try XCTUnwrap(TestImage.size(of: p.data))
        XCTAssertEqual(decoded.0, 1600)
        XCTAssertEqual(decoded.1, 900)
        XCTAssertLessThanOrEqual(p.data.count, 3_145_728)
    }

    func testSmallImageIsNotEnlarged() throws {
        let p = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 400, height: 300), longEdge: 1600))
        XCTAssertEqual(p.width, 400)
        XCTAssertEqual(p.height, 300)
    }

    func testEncodingAndHash() throws {
        let p = try XCTUnwrap(ImagePrep.prepare(TestImage.png(width: 800, height: 600)))
        XCTAssertEqual(p.contentType, ImagePrep.canEncodeWebP ? "image/webp" : "image/jpeg")
        if p.contentType == "image/jpeg" { XCTAssertEqual(Array(p.data.prefix(3)), [0xFF, 0xD8, 0xFF]) }
        XCTAssertNotNil(p.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        XCTAssertEqual(p.sha256, ImagePrep.sha256Hex(p.data))
        XCTAssertEqual(ImagePrep.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNotAnImage() {
        XCTAssertNil(ImagePrep.prepare(Data("not an image".utf8)))
    }
}
