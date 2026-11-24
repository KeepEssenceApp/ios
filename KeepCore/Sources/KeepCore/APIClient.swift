import Foundation

/// An error answered by the core: `{ "error": { "code", "message" } }`. `message` is written for the
/// user in the language of `Accept-Language`.
public struct APIError: Error, Equatable, LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public let message: String

    public init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
    public var isUnauthorized: Bool { status == 401 }
}

public enum KeepJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// The client of the contract. One method per operation this app uses, named after its `operationId`.
public final class APIClient: @unchecked Sendable {
    public let baseURL: URL
    public let credential: String?
    public let lang: String
    private let session: URLSession

    public init(baseURL: URL, credential: String?, lang: String = KeepLang.current, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credential = credential
        self.lang = lang
        self.session = session
    }

    // MARK: plumbing

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { let code: String; let message: String }
        let error: Inner
    }

    private struct Empty: Encodable {}

    public static func segment(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil,
                     idempotencyKey: String? = nil, auth: Bool = true, accept: String = "application/json",
                     timeout: TimeInterval = 20) throws -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var parts = URLComponents(string: base + path) else { throw URLError(.badURL) }
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        if !items.isEmpty { parts.queryItems = items }
        guard let url = parts.url else { throw URLError(.badURL) }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue(lang, forHTTPHeaderField: "Accept-Language")
        if auth, let credential { r.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { r.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError(status: http.statusCode, code: e.error.code, message: e.error.message)
            }
            throw APIError(status: http.statusCode, code: "server_error", message: "HTTP \(http.statusCode)")
        }
        return (data, http)
    }

    private func body<B: Encodable>(_ value: B) throws -> Data { try KeepJSON.encoder().encode(value) }

    private func get<T: Decodable>(_ path: String, query: [String: String?] = [:], auth: Bool = true) async throws -> T {
        let (data, _) = try await perform(makeRequest("GET", path, query: query, auth: auth))
        return try KeepJSON.decoder().decode(T.self, from: data)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil, idempotencyKey: String? = nil,
                                    auth: Bool = true, timeout: TimeInterval = 20) async throws -> T {
        let (data, _) = try await perform(makeRequest(method, path, body: body, idempotencyKey: idempotencyKey, auth: auth, timeout: timeout))
        return try KeepJSON.decoder().decode(T.self, from: data)
    }

    private func sendEmpty(_ method: String, _ path: String, body: Data? = nil, auth: Bool = true) async throws {
        _ = try await perform(makeRequest(method, path, body: body, auth: auth))
    }

    // MARK: meta, sign-in

    /// getMeta. Returns the raw body too, so it can be cached as it came.
    public func getMeta() async throws -> (Meta, Data) {
        let (data, _) = try await perform(makeRequest("GET", "/v1/meta", auth: false))
        return (try Meta(data: data), data)
    }

    public func requestLoginCode(email: String) async throws {
        try await sendEmpty("POST", "/v1/auth/email-codes", body: body(["email": email, "lang": lang]), auth: false)
    }

    public func signIn(email: String, code: String, deviceName: String, timezone: String) async throws -> DeviceGrant {
        let b = ["email": email, "code": code, "device_name": deviceName, "client": "phone", "timezone": timezone]
        return try await send("POST", "/v1/auth/sessions", body: body(b), auth: false)
    }

    // MARK: devices

    public func getThisDevice() async throws -> ThisDevice { try await get("/v1/devices/me") }
    public func signOutThisDevice() async throws { try await sendEmpty("DELETE", "/v1/devices/me") }
    public func listDevices() async throws -> [Device] { (try await get("/v1/devices") as DevicesPage).devices }

    public func updateDevice(id: String, name: String? = nil, tier: Tier? = nil) async throws -> Device {
        var b: [String: String] = [:]
        if let name { b["name"] = name }
        if let tier { b["tier"] = tier.rawValue }
        return try await send("PATCH", "/v1/devices/\(Self.segment(id))", body: body(b))
    }

    public func revokeDevice(id: String) async throws { try await sendEmpty("DELETE", "/v1/devices/\(Self.segment(id))") }

    public func getDeviceCodeRequest(code: String) async throws -> DeviceCodeRequest {
        try await get("/v1/device-codes/\(Self.segment(code))/request")
    }

    public func approveDeviceCode(code: String, tier: Tier) async throws -> Device {
        try await send("POST", "/v1/device-codes/\(Self.segment(code))/approve", body: body(["tier": tier.rawValue]))
    }

    public func denyDeviceCode(code: String) async throws {
        try await sendEmpty("POST", "/v1/device-codes/\(Self.segment(code))/deny")
    }

    // MARK: save

    public func saveItem(_ request: SaveRequest, idempotencyKey: String, timeout: TimeInterval = 20) async throws -> SaveResult {
        try await send("POST", "/v1/items", body: body(request), idempotencyKey: idempotencyKey, timeout: timeout)
    }

    public func requestUpload(sha256: String, bytes: Int, contentType: String) async throws -> UploadTicket {
        struct B: Encodable { let sha256: String; let bytes: Int; let contentType: String }
        return try await send("POST", "/v1/assets", body: body(B(sha256: sha256, bytes: bytes, contentType: contentType)))
    }

    /// PUT the bytes to the address the core gave. The address carries its own signature, so no credential is sent.
    public func upload(to address: String, data: Data, contentType: String) async throws {
        guard let url = URL(string: address, relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
        var r = URLRequest(url: url, timeoutInterval: 60)
        r.httpMethod = "PUT"
        r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        r.setValue(lang, forHTTPHeaderField: "Accept-Language")
        r.httpBody = data
        _ = try await perform(r)
    }

    public func completeUpload(assetId: String) async throws {
        try await sendEmpty("POST", "/v1/assets/\(Self.segment(assetId))/complete")
    }

    public func getAsset(id: String) async throws -> AssetLocation { try await get("/v1/assets/\(Self.segment(id))") }

    // MARK: items

    public func listItems(state: String, cursor: String? = nil, limit: Int = 100) async throws -> ItemsPage {
        try await get("/v1/items", query: ["state": state, "cursor": cursor, "limit": String(limit)])
    }

    public func getItem(id: String) async throws -> Item { try await get("/v1/items/\(Self.segment(id))") }

    public func updateItem(id: String, expiryDays: Int? = nil, dispatchTo: String? = nil) async throws -> Item {
        struct B: Encodable { let expiryDays: Int?; let dispatchTo: String? }
        return try await send("PATCH", "/v1/items/\(Self.segment(id))", body: body(B(expiryDays: expiryDays, dispatchTo: dispatchTo)))
    }

    public func deleteItem(id: String) async throws { try await sendEmpty("DELETE", "/v1/items/\(Self.segment(id))") }
    public func pinItem(id: String) async throws { try await sendEmpty("PUT", "/v1/items/\(Self.segment(id))/pin") }
    public func unpinItem(id: String) async throws { try await sendEmpty("DELETE", "/v1/items/\(Self.segment(id))/pin") }

    public func setSignal(id: String, signal: Signal) async throws {
        try await sendEmpty("PUT", "/v1/items/\(Self.segment(id))/signal", body: body(["signal": signal.rawValue]))
    }

    public func clearSignal(id: String) async throws { try await sendEmpty("DELETE", "/v1/items/\(Self.segment(id))/signal") }

    // MARK: digests

    public func listDigests(cursor: String? = nil, limit: Int = 20) async throws -> DigestsPage {
        try await get("/v1/digests", query: ["cursor": cursor, "limit": String(limit)])
    }

    /// `day` is `YYYY-MM-DD` or `latest`.
    public func getDigest(day: String = "latest") async throws -> DailyDigest { try await get("/v1/digests/\(Self.segment(day))") }
    public func markDigestRead(day: String) async throws { try await sendEmpty("POST", "/v1/digests/\(Self.segment(day))/read") }

    // MARK: deep-dive queue

    public func listQueue() async throws -> [QueueEntry] { (try await get("/v1/deep-read-queue") as QueuePage).entries }
    public func addToQueue(itemId: String) async throws -> QueueEntry { try await send("PUT", "/v1/deep-read-queue/\(Self.segment(itemId))") }
    public func removeFromQueue(itemId: String) async throws { try await sendEmpty("DELETE", "/v1/deep-read-queue/\(Self.segment(itemId))") }

    public func startDeepDive(itemId: String, assistantId: String? = nil) async throws -> DeepDiveEntry {
        struct B: Encodable { let itemId: String; let assistantId: String? }
        return try await send("POST", "/v1/deep-dive-requests", body: body(B(itemId: itemId, assistantId: assistantId)))
    }

    // MARK: notes

    public func listNotes(q: String? = nil, cursor: String? = nil, limit: Int = 50) async throws -> NotesPage {
        let query = (q?.isEmpty == false) ? q : nil
        return try await get("/v1/notes", query: ["q": query, "cursor": cursor, "limit": String(limit)])
    }

    public func getNote(id: String) async throws -> Note { try await get("/v1/notes/\(Self.segment(id))") }

    public func getNoteMarkdown(id: String) async throws -> String {
        let (data, _) = try await perform(makeRequest("GET", "/v1/notes/\(Self.segment(id))", accept: "text/markdown"))
        return String(decoding: data, as: UTF8.self)
    }

    public func pasteNote(_ request: PasteNoteRequest, idempotencyKey: String) async throws -> Note {
        try await send("POST", "/v1/notes", body: body(request), idempotencyKey: idempotencyKey)
    }

    // MARK: status, calendar

    public func getStatus() async throws -> Status { try await get("/v1/status") }
    public func getCalendar(month: String? = nil) async throws -> CalendarMonth { try await get("/v1/calendar", query: ["month": month]) }

    // MARK: settings, assistants

    public func getSettings() async throws -> UserSettings { try await get("/v1/settings") }
    public func updateSettings(_ change: SettingsChange) async throws -> UserSettings { try await send("PATCH", "/v1/settings", body: body(change)) }
    public func rotateCalendarImage() async throws -> UserSettings { try await send("POST", "/v1/settings/calendar-image/rotate") }
    public func listAssistants() async throws -> AssistantsPage { try await get("/v1/assistants") }

    public func updateAssistant(id: String, name: String? = nil, steps: [Step]? = nil) async throws -> Assistant {
        struct B: Encodable { let name: String?; let steps: [Step]? }
        return try await send("PATCH", "/v1/assistants/\(Self.segment(id))", body: body(B(name: name, steps: steps)))
    }

    public func revokeAssistant(id: String) async throws { try await sendEmpty("DELETE", "/v1/assistants/\(Self.segment(id))") }
}

public enum KeepLang {
    /// `zh` or `en`, following the system language.
    public static var current: String {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
    }
}
