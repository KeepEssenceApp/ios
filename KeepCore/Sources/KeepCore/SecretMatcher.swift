import Foundation

/// Decides whether content looks like a password or a credential, with the patterns the core serves
/// (`shared_rules.secret_like`). A match on any pattern counts. Only content of at most
/// `max_length_checked` characters after trimming is checked; longer content never counts, except
/// for a pattern marked `any_length`.
public struct SecretMatcher: @unchecked Sendable {
    private let patterns: [(name: String, regex: NSRegularExpression, anyLength: Bool)]
    public let maxLengthChecked: Int

    public init(rules: SharedRules) {
        maxLengthChecked = rules.secretMaxLengthChecked
        patterns = rules.secretPatterns.compactMap { p in
            let options: NSRegularExpression.Options = (p.flags ?? "").contains("i") ? [.caseInsensitive] : []
            return (try? NSRegularExpression(pattern: p.regex, options: options)).map { (p.name, $0, p.anyLength) }
        }
    }

    public var patternCount: Int { patterns.count }

    /// The name of the first pattern that matches, or nil.
    public func match(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let long = trimmed.count > maxLengthChecked
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for p in patterns where (!long || p.anyLength) && p.regex.firstMatch(in: trimmed, range: range) != nil {
            return p.name
        }
        return nil
    }

    public func looksSecret(_ content: String?) -> Bool {
        guard let content else { return false }
        return match(content) != nil
    }
}
