import Foundation

/// Decides whether content looks like a password or a credential, with the patterns the core serves
/// (`shared_rules.secret_like`). A match on any pattern counts. Only the first `max_length_checked`
/// characters of the trimmed content are looked at.
public struct SecretMatcher: @unchecked Sendable {
    private let patterns: [(name: String, regex: NSRegularExpression)]
    public let maxLengthChecked: Int

    public init(rules: SharedRules) {
        maxLengthChecked = rules.secretMaxLengthChecked
        patterns = rules.secretPatterns.compactMap { p in
            (try? NSRegularExpression(pattern: p.regex)).map { (p.name, $0) }
        }
    }

    public var patternCount: Int { patterns.count }

    /// The name of the first pattern that matches, or nil.
    public func match(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let head = String(trimmed.prefix(maxLengthChecked))
        let range = NSRange(head.startIndex..., in: head)
        for p in patterns where p.regex.firstMatch(in: head, range: range) != nil {
            return p.name
        }
        return nil
    }

    public func looksSecret(_ content: String?) -> Bool {
        guard let content else { return false }
        return match(content) != nil
    }
}
