import Foundation

/// What a share is, before it is sent.
public struct SaveDraft: Sendable {
    public var id: String
    public var request: SaveRequest
    public var image: PreparedImage?

    public init(id: String = UUID().uuidString.lowercased(), request: SaveRequest, image: PreparedImage? = nil) {
        self.id = id
        self.request = request
        self.image = image
    }
}

/// What happened to a save, and the one sentence to show for it.
public struct SaveOutcome: Equatable, Sendable {
    public enum Kind: String, Sendable { case saved, duplicate, queued, failed }
    public let kind: Kind
    public let sentence: String
}

/// Saving, shared by the share extension (one save, now) and the app (sending the offline queue).
/// It says no more than what is true: saved only when the core answered so, queued when the core
/// could not be reached, and the core's own reason when it refused.
public struct SaveService: Sendable {
    public let client: APIClient
    public let queue: OfflineQueue
    public let rules: SharedRules
    public let lang: String
    /// Said when the storage quota refuses an image that has nothing else to save with it.
    public let quotaReason: String

    public init(client: APIClient, queue: OfflineQueue, rules: SharedRules, lang: String = KeepLang.current, quotaReason: String) {
        self.client = client
        self.queue = queue
        self.rules = rules
        self.lang = lang
        self.quotaReason = quotaReason
    }

    private enum Refused: Error { case overQuota }

    private func sentence(_ key: String, reason: String? = nil) -> String {
        rules.saveMessage(key, lang: lang, reason: reason) ?? Meta.bundled.sharedRules.saveMessage(key, lang: lang, reason: reason) ?? key
    }

    private func failed(_ reason: String) -> SaveOutcome { SaveOutcome(kind: .failed, sentence: sentence("failed", reason: reason)) }

    /// The asset flow: ask, upload when asked to, confirm. Returns the asset id, or nil when the quota refused it.
    private func store(_ data: Data, contentType: String, sha256: String) async throws -> String? {
        let ticket = try await client.requestUpload(sha256: sha256, bytes: data.count, contentType: contentType)
        switch ticket.status {
        case "stored":
            return ticket.assetId
        case "over_quota":
            return nil
        default:
            guard let address = ticket.uploadUrl else { throw URLError(.badServerResponse) }
            try await client.upload(to: address, data: data, contentType: contentType)
            try await client.completeUpload(assetId: ticket.assetId)
            return ticket.assetId
        }
    }

    private func send(id: String, request: SaveRequest, blob: Data?, contentType: String?, sha256: String?, timeout: TimeInterval) async throws -> SaveOutcome {
        var request = request
        var quotaSkipped = false
        if let blob, let contentType, let sha256 {
            if let assetId = try await store(blob, contentType: contentType, sha256: sha256) {
                request.assetId = assetId
            } else if request.url != nil {
                // The image is refused; what came with it is still saved, and the sentence says so.
                request.kind = "link"
                quotaSkipped = true
            } else if let text = request.text, !text.isEmpty {
                request.kind = "text"
                quotaSkipped = true
            } else {
                throw Refused.overQuota
            }
        }
        let result = try await client.saveItem(request, idempotencyKey: id, timeout: timeout)
        if quotaSkipped && result.status == "saved" && result.messageKey == "saved" {
            return SaveOutcome(kind: .saved, sentence: sentence("saved_image_skipped_quota"))
        }
        return SaveOutcome(kind: result.status == "duplicate" ? .duplicate : .saved, sentence: result.message)
    }

    /// One save, now. When the core cannot be reached the save is written to the queue.
    public func save(_ draft: SaveDraft, timeout: TimeInterval = 12) async -> SaveOutcome {
        do {
            return try await send(id: draft.id, request: draft.request, blob: draft.image?.data,
                                  contentType: draft.image?.contentType, sha256: draft.image?.sha256, timeout: timeout)
        } catch let e as APIError {
            return failed(e.message)
        } catch Refused.overQuota {
            return failed(quotaReason)
        } catch is URLError {
            let entry = QueuedSave(id: draft.id, request: draft.request, contentType: draft.image?.contentType, sha256: draft.image?.sha256)
            do {
                try queue.enqueue(entry, blob: draft.image?.data)
                return SaveOutcome(kind: .queued, sentence: sentence("queued_offline"))
            } catch {
                return failed(error.localizedDescription)
            }
        } catch {
            return failed(error.localizedDescription)
        }
    }

    /// Sends what is waiting, oldest first. Stops at the first entry that cannot reach the core, or
    /// whose credential is refused, and leaves it and the rest in the queue. An entry the core
    /// refuses for another reason is removed and reported.
    public func flush() async -> [SaveOutcome] {
        var outcomes: [SaveOutcome] = []
        for entry in queue.entries() {
            do {
                let o = try await send(id: entry.id, request: entry.request, blob: queue.blob(for: entry),
                                       contentType: entry.contentType, sha256: entry.sha256, timeout: 20)
                queue.remove(entry)
                outcomes.append(o)
            } catch let e as APIError {
                if e.isUnauthorized { break }
                queue.remove(entry)
                outcomes.append(failed(e.message))
            } catch Refused.overQuota {
                queue.remove(entry)
                outcomes.append(failed(quotaReason))
            } catch {
                break
            }
        }
        return outcomes
    }
}
