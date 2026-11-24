import Foundation

/// One save that could not reach the core. Its `id` is the `Idempotency-Key`, so sending it twice adds nothing.
public struct QueuedSave: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var request: SaveRequest
    /// For an image: the file next to the entry holding the encoded bytes, and what the upload needs.
    public var blobName: String?
    public var contentType: String?
    public var sha256: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString.lowercased(), request: SaveRequest, blobName: String? = nil,
                contentType: String? = nil, sha256: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.request = request
        self.blobName = blobName
        self.contentType = contentType
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

/// Saves waiting on the device, one file per entry, in the app group container so that the share
/// extension writes them and the app sends them.
public struct OfflineQueue: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fm: FileManager { .default }
    private func entryURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }

    public func enqueue(_ entry: QueuedSave, blob: Data? = nil) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var e = entry
        if let blob {
            let name = "\(entry.id).bin"
            try blob.write(to: directory.appendingPathComponent(name), options: .atomic)
            e.blobName = name
        }
        try KeepJSON.encoder().encode(e).write(to: entryURL(e.id), options: .atomic)
    }

    /// Oldest first.
    public func entries() -> [QueuedSave] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? KeepJSON.decoder().decode(QueuedSave.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public var count: Int { entries().count }

    public func blob(for entry: QueuedSave) -> Data? {
        entry.blobName.flatMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    public func remove(_ entry: QueuedSave) {
        try? fm.removeItem(at: entryURL(entry.id))
        if let b = entry.blobName { try? fm.removeItem(at: directory.appendingPathComponent(b)) }
    }
}
