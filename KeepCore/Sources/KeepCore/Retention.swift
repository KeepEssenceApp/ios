import Foundation

/// How long one item is kept. There is one control for it: the user's expiry options, then
/// "Never delete" as the last choice. The header, the control and the tags are all read from here,
/// so they cannot disagree.
public enum Retention: Equatable, Sendable {
    case days(Int)
    case never

    /// The choices of the control, in order: the user's options, "Never delete" last.
    public static func choices(options: [Int]) -> [Retention] {
        var seen = Set<Int>()
        return options.filter { $0 >= 1 && seen.insert($0).inserted }.map { Retention.days($0) } + [.never]
    }

    /// What is true of the item now. Nil when the core has not said how long it is kept.
    public static func current(of item: Item) -> Retention? {
        if item.pinned == true { return .never }
        return item.expiryDays.map { .days($0) }
    }

    /// The day the item is deleted: the core's own moment when it gives one, else counted from the
    /// days that are left. Nil for an item that is never deleted.
    public static func until(_ item: Item, now: Date = Date()) -> Date? {
        if item.pinned == true { return nil }
        if let at = item.expiresAt { return at }
        return item.daysLeft.map { now.addingTimeInterval(TimeInterval($0) * 86400) }
    }

    /// The tags to show. A kept item has no end date, so an `expiry:N` tag is not shown as if it applied.
    public static func visibleTags(of item: Item) -> [String] {
        let tags = item.tags ?? []
        return item.pinned == true ? tags.filter { !$0.hasPrefix("expiry:") } : tags
    }

    /// The one sentence after a change: the key of the string and what fills it.
    public static func sentence(for item: Item, now: Date = Date(), locale: Locale = .current) -> (key: String, days: Int?, date: String?) {
        guard item.pinned != true, let days = item.expiryDays, let end = until(item, now: now) else {
            return (item.pinned == true ? "item.said.never" : "item.said.changed", nil, nil)
        }
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return ("item.said.days", days, f.string(from: end))
    }
}

public enum Analysers {
    /// Every assistant that can analyse (chat assistants only deep dive), plus the one the item is
    /// with now when it is no longer among them. There is no "nobody": an item always has one.
    public static func candidates(_ assistants: [Assistant], current: NamedRef?) -> [NamedRef] {
        var out = assistants.filter { $0.steps.contains(.analysis) && $0.kind != "chat" }.map { NamedRef(id: $0.id, name: $0.name) }
        if let current, let id = current.id, !out.contains(where: { $0.id == id }) { out.append(current) }
        return out
    }
}

/// The products of "Connect an assistant". Only a product whose steps were checked gets a tab
/// (rule D13); the others are named in one line under the tabs.
public enum ConnectProducts {
    public struct Product: Equatable, Sendable {
        public let id: String
        public let name: String
        public let steps: Int
    }

    public static let verified: [Product] = [
        Product(id: "claude", name: "Claude", steps: 4),
        Product(id: "chatgpt", name: "ChatGPT", steps: 4),
        Product(id: "gemini", name: "Gemini", steps: 4),
        Product(id: "own", name: "", steps: 3),
    ]
    public static let unverified: [String] = ["Muse"]
}

public enum DigestEmpty {
    /// The sentence for the page with no daily digest, by the reason the core gives.
    public static func key(reason: String?) -> String {
        switch reason {
        case "not_yet_time": return "digest.none.not_yet_time"
        case "nothing_analysed": return "digest.none.nothing_analysed"
        case "no_assistant": return "digest.none.no_assistant"
        case "waiting_for_assistant": return "digest.none.waiting"
        default: return "digest.none"
        }
    }

    /// Whether the sentence names the hour and the time zone.
    public static func namesTime(reason: String?) -> Bool {
        reason != "no_assistant" && reason != "waiting_for_assistant"
    }
}
