import Foundation

// Types of the contract (contract/openapi.yaml). Field names follow the contract; the decoder
// converts snake_case keys.

public enum Tier: String, Codable, CaseIterable, Sendable {
    case save, read, manage

    public var rank: Int {
        switch self {
        case .save: return 0
        case .read: return 1
        case .manage: return 2
        }
    }

    /// The tiers an approver may grant for a request: the requested one and lower ones.
    public static func grantable(requested: Tier) -> [Tier] {
        allCases.filter { $0.rank <= requested.rank }
    }
}

public enum Step: String, Codable, CaseIterable, Sendable {
    case triage, analysis, digest
    case deepRead = "deep_read"
    case deepDive = "deep_dive"
}

public enum Verdict: String, Codable, Sendable {
    case worthDeepDive = "worth_deep_dive"
    case goodToKnow = "good_to_know"
    case skippable
}

public enum Signal: String, Codable, Sendable {
    case notInterested = "not_interested"
    case seen
}

public struct User: Codable, Equatable, Sendable {
    public var id: String
    public var timezone: String
    public var lang: String?
}

public struct Device: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var client: String?
    public var tier: Tier?
    public var steps: [Step]?
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var notifications: Bool?
    public var thisDevice: Bool?
}

public struct DeviceGrant: Codable, Sendable {
    public var credential: String
    public var device: Device
    public var user: User
}

public struct ThisDevice: Codable, Equatable, Sendable {
    public var device: Device
    public var user: User

    public init(device: Device, user: User) {
        self.device = device
        self.user = user
    }
}

public struct DevicesPage: Codable, Sendable { public var devices: [Device] }

public struct DeviceCodeRequest: Codable, Equatable, Sendable {
    public var deviceName: String
    public var client: String
    public var requestedTier: Tier
    public var expiresAt: Date
}

public struct SaveRequest: Codable, Equatable, Sendable {
    public var kind: String
    public var url: String?
    public var title: String?
    public var text: String?
    public var assetId: String?
    public var entry: String?

    public init(kind: String, url: String? = nil, title: String? = nil, text: String? = nil, assetId: String? = nil, entry: String? = nil) {
        self.kind = kind
        self.url = url
        self.title = title
        self.text = text
        self.assetId = assetId
        self.entry = entry
    }
}

public struct SaveResult: Codable, Equatable, Sendable {
    public var status: String
    public var itemId: String?
    public var messageKey: String
    public var message: String
    public var imageStored: Bool?
}

public struct Signature: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var submittedByUser: Bool?
}

public struct Analysis: Codable, Equatable, Sendable {
    public var unavailable: Bool
    public var summary: String?
    public var keyFact: String?
    public var points: [String]?
    public var verdict: Verdict?
    public var relatedHint: String?
    public var assistant: Signature
    public var createdAt: Date?
}

public struct NamedRef: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String?
}

/// `Item` and `ItemDetail` of the contract. The detail fields are nil in lists.
public struct Item: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var site: String?
    public var url: String?
    public var createdAt: Date
    public var stage: String
    public var contentUnavailable: Bool?
    public var dispatchTo: NamedRef?
    public var daysLeft: Int?
    public var pinned: Bool?
    public var signal: Signal?
    public var inQueue: Bool?
    public var analysis: Analysis?
    public var body: String?
    public var assetId: String?
    public var tags: [String]?
    public var expiryDays: Int?

    /// Not interested, seen, or in the deep-dive queue: it leaves the main list.
    public var handled: Bool { signal != nil || inQueue == true }
}

public struct ItemsPage: Codable, Sendable {
    public var items: [Item]
    public var nextCursor: String?
}

public struct DigestSummary: Codable, Equatable, Sendable {
    public var day: String
    public var read: Bool
}

public struct DigestsPage: Codable, Sendable {
    public var digests: [DigestSummary]
    public var nextCursor: String?
}

public struct DailyDigest: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var saved: Int?
        public var worth: Int?
    }
    public struct Worth: Codable, Equatable, Identifiable, Sendable {
        public var itemId: String
        public var title: String?
        public var line: String
        public var verdict: Verdict?
        public var available: Bool?
        public var inQueue: Bool?
        public var id: String { itemId }
    }
    public struct Rest: Codable, Equatable, Identifiable, Sendable {
        public var itemId: String
        public var title: String
        public var signal: String?
        public var inQueue: Bool?
        public var available: Bool?
        public var canRestore: Bool?
        public var id: String { itemId }
    }
    public var day: String
    public var read: Bool
    public var counts: Counts?
    public var summary: String
    public var worth: [Worth]
    public var rest: [Rest]
    public var question: String
    public var assistant: Signature
    public var previousDay: String?
    public var nextDay: String?
}

public struct DeepReadReport: Codable, Equatable, Sendable {
    public var read: String
    public var found: String
    public var questions: [String]
    public var assistant: Signature?
}

public struct QueueEntry: Codable, Equatable, Identifiable, Sendable {
    public var itemId: String
    public var title: String
    public var addedAt: Date
    public var deepRead: String
    public var report: DeepReadReport?
    public var wentAt: Date?
    public var fetchedAt: Date?
    public var entry: String?
    public var id: String { itemId }
}

public struct QueuePage: Codable, Sendable { public var entries: [QueueEntry] }

public struct DeepDiveEntry: Codable, Equatable, Sendable {
    public var assistant: Signature
    public var openingLine: String
    public var openUrl: String?
    public var entry: String?
}

public struct NoteSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var excerpt: String?
    public var createdAt: Date
}

public struct NotesPage: Codable, Sendable {
    public var notes: [NoteSummary]
    public var nextCursor: String?
}

public struct Note: Codable, Equatable, Identifiable, Sendable {
    public struct Origin: Codable, Equatable, Sendable {
        public var itemId: String?
        public var itemTitle: String?
        public var itemUrl: String?
        public var digestDay: String?
    }
    public struct Source: Codable, Equatable, Sendable {
        public var title: String?
        public var url: String?
    }
    public var id: String
    public var title: String
    public var body: String
    public var createdAt: Date
    public var assistant: Signature
    public var origin: Origin?
    public var sources: [Source]?
    public var assetIds: [String]?
}

public struct PasteNoteRequest: Codable, Sendable {
    public var title: String
    public var body: String
    public var itemId: String?
    public var assistantId: String?

    public init(title: String, body: String, itemId: String? = nil, assistantId: String? = nil) {
        self.title = title
        self.body = body
        self.itemId = itemId
        self.assistantId = assistantId
    }
}

public struct UploadTicket: Codable, Equatable, Sendable {
    public var assetId: String
    public var status: String
    public var uploadUrl: String?
    public var expiresAt: Date?
}

public struct AssetLocation: Codable, Equatable, Sendable {
    public var downloadUrl: String
    public var expiresAt: Date
    public var contentType: String
    public var bytes: Int
}

public struct Status: Codable, Equatable, Sendable {
    public struct AssistantState: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var state: String
        public var lastSeenAt: Date?
    }
    public var assistants: [AssistantState]
    public var savedToday: Int
    public var waiting: Int
    public var oldestWaitingDeletedOn: String?
    public var noDigestReason: String?
}

public struct CalendarMonth: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Identifiable, Sendable {
        public var day: String
        public var mark: String
        public var hasDigest: Bool?
        public var id: String { day }
    }
    public struct Counts: Codable, Equatable, Sendable {
        public var saved: Int
        public var digests: Int
        public var read: Int
        public var notes: Int
    }
    public var month: String
    public var today: String?
    public var days: [Day]
    public var counts: Counts
    public var previousMonth: String?
    public var nextMonth: String?
}

public struct Assistant: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var steps: [Step]
    public var builtIn: Bool
    public var connectedAt: Date?
    public var lastSeenAt: Date?
    public var runsAt: String?
}

public struct AssistantsPage: Codable, Sendable {
    public var assistants: [Assistant]
    public var connectUrl: String
}

public struct UserSettings: Codable, Equatable, Sendable {
    public struct Roles: Codable, Equatable, Sendable {
        public var analysis: String?
        public var digest: String?
        public var deepRead: String?
        public var deepDive: String?
    }
    public struct CalendarImage: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var url: String?
    }
    public var rules: String
    public var preference: String?
    public var expiryOptions: [Int]
    public var notify: Bool
    public var timezone: String
    public var lang: String
    public var roles: Roles
    public var calendarImage: CalendarImage
}

/// `SettingsChange`. Only the fields that are set are sent. A role set to `.some(nil)` is sent as null.
public struct SettingsChange: Encodable, Sendable {
    public var rules: String?
    public var expiryOptions: [Int]?
    public var notify: Bool?
    public var timezone: String?
    public var lang: String?
    public var roles: [String: String?]?
    public var calendarImageEnabled: Bool?

    public init(rules: String? = nil, expiryOptions: [Int]? = nil, notify: Bool? = nil, timezone: String? = nil,
                lang: String? = nil, roles: [String: String?]? = nil, calendarImageEnabled: Bool? = nil) {
        self.rules = rules
        self.expiryOptions = expiryOptions
        self.notify = notify
        self.timezone = timezone
        self.lang = lang
        self.roles = roles
        self.calendarImageEnabled = calendarImageEnabled
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encodeIfPresent(rules, forKey: Key("rules"))
        try c.encodeIfPresent(expiryOptions, forKey: Key("expiry_options"))
        try c.encodeIfPresent(notify, forKey: Key("notify"))
        try c.encodeIfPresent(timezone, forKey: Key("timezone"))
        try c.encodeIfPresent(lang, forKey: Key("lang"))
        try c.encodeIfPresent(calendarImageEnabled, forKey: Key("calendar_image_enabled"))
        if let roles {
            var r = c.nestedContainer(keyedBy: Key.self, forKey: Key("roles"))
            for (name, value) in roles.sorted(by: { $0.key < $1.key }) {
                if let value { try r.encode(value, forKey: Key(name)) } else { try r.encodeNil(forKey: Key(name)) }
            }
        }
    }
}
