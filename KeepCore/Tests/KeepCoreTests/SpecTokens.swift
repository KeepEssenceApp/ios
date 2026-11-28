import Foundation
@testable import KeepCore

/// The root of this repository (the folder with `KeepCore/`, `App/` and `ShareExtension/`).
enum RepoPaths {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// The spec's `design/tokens.css`, which the Swift theme mirrors, and the comparison of the two.
///
/// The spec repository is not part of this one: it is checked out next to it (`../spec`). CI pins it to
/// the commit named in `SPEC_REF` and sets `KE_REQUIRE_SPEC=1`, so a missing spec fails there instead of
/// skipping the comparison. A developer without the spec still skips it.
enum SpecTokens {
    static let requireFlag = "KE_REQUIRE_SPEC"

    enum Lookup: Equatable {
        /// The text of tokens.css.
        case css(String)
        /// The spec is not there and nothing demands it.
        case skip(String)
        /// The spec is not there and `KE_REQUIRE_SPEC=1` demands it.
        case fail(String)
    }

    /// Finds `spec/design/tokens.css` next to the repository at `repo`.
    static func lookup(nextTo repo: URL, environment: [String: String]) -> Lookup {
        let file = repo.deletingLastPathComponent().appendingPathComponent("spec/design/tokens.css")
        if let text = try? String(contentsOf: file, encoding: .utf8) { return .css(text) }
        let message = "spec/design/tokens.css is not next to this repository (looked at \(file.path))"
        if environment[requireFlag] == "1" {
            return .fail("\(requireFlag)=1, so a missing spec is a failure and not a skip: \(message)")
        }
        return .skip(message)
    }

    /// The three blocks of tokens.css that hold colours, each told apart by its media condition and its
    /// selector. The two dark ones are separate on purpose: the system's dark mode and the app's manual dark
    /// setting are two blocks that say the same thing, and a change of one of them has to be seen.
    enum Block: String, CaseIterable {
        case light
        case systemDark
        case manualDark

        static let systemMedia = "@media (prefers-color-scheme: dark)"
        static let systemSelector = ":root:not([data-theme=\"light\"])"
        static let manualSelector = ":root[data-theme=\"dark\"]"

        /// How a message names the block.
        var name: String {
            switch self {
            case .light: return "light block (:root)"
            case .systemDark: return "system dark block (\(Block.systemMedia) { \(Block.systemSelector) })"
            case .manualDark: return "manual dark block (\(Block.manualSelector))"
            }
        }

        static func of(media: String?, selector: String) -> Block? {
            switch (media, selector) {
            case (nil, ":root"): return .light
            case (systemMedia?, systemSelector): return .systemDark
            case (nil, manualSelector): return .manualDark
            default: return nil
            }
        }
    }

    struct Parsed {
        var light: [String: UInt32] = [:]
        /// The block of `@media (prefers-color-scheme: dark)`: the system is dark and the app is not told otherwise.
        var systemDark: [String: UInt32] = [:]
        /// The block of `:root[data-theme="dark"]`: the user chose dark.
        var manualDark: [String: UInt32] = [:]
        /// `--ke-radius*` in points; `0` has no unit in the css.
        var radii: [String: Double] = [:]
    }

    private struct Rule {
        var media: String?
        var selector: String
        var body: String
    }

    private static func squeeze(_ s: Substring) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The rules of a stylesheet with comments already dropped. A rule inside `@media` carries the condition.
    private static func rules(_ text: Substring, media: String?, problems: inout [String]) -> [Rule] {
        var out: [Rule] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard let open = text[i...].firstIndex(of: "{") else {
                let rest = squeeze(text[i...])
                if !rest.isEmpty { problems.append("tokens.css has text outside any block: \(rest)") }
                break
            }
            var depth = 1
            var j = text.index(after: open)
            while j < text.endIndex, depth > 0 {
                if text[j] == "{" { depth += 1 } else if text[j] == "}" { depth -= 1 }
                j = text.index(after: j)
            }
            guard depth == 0 else { problems.append("tokens.css has a block that is not closed: \(squeeze(text[i..<open]))"); break }
            let prelude = squeeze(text[i..<open])
            let body = text[text.index(after: open)..<text.index(before: j)]
            if prelude.hasPrefix("@media") {
                out += rules(body, media: prelude, problems: &problems)
            } else {
                out.append(Rule(media: media, selector: prelude, body: String(body)))
            }
            i = j
        }
        return out
    }

    /// `--ke-name: #RRGGBB` of one block's body. A name declared twice in one block is a problem: the later
    /// value would hide the earlier one.
    private static func colours(_ body: String, in block: String, problems: inout [String]) -> [String: UInt32] {
        var found: [String: UInt32] = [:]
        let re = try! NSRegularExpression(pattern: "--ke-([a-z0-9-]+):\\s*#([0-9A-Fa-f]{6})")
        for m in re.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            let name = String(body[Range(m.range(at: 1), in: body)!])
            if found[name] != nil { problems.append("--ke-\(name) is declared twice in the \(block)") }
            found[name] = UInt32(body[Range(m.range(at: 2), in: body)!], radix: 16)
        }
        return found
    }

    /// Reads the colours of each of the three blocks (light, system dark, manual dark) into its own table, and
    /// the radii of the light block. Comments are dropped first, so a token named in a comment is not a token.
    /// Each block must be there once; a block that is missing, one that is there twice, and colours in any
    /// other block are problems, not silently nothing.
    static func parse(_ css: String) -> (parsed: Parsed, problems: [String]) {
        let text = css.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        var problems: [String] = []
        let all = rules(Substring(text), media: nil, problems: &problems)
        var out = Parsed()
        for block in Block.allCases {
            let mine = all.filter { Block.of(media: $0.media, selector: $0.selector) == block }
            if mine.isEmpty { problems.append("tokens.css has no \(block.name)") }
            if mine.count > 1 { problems.append("tokens.css has \(mine.count) copies of the \(block.name), expected 1") }
            guard let rule = mine.first else { continue }
            let found = colours(rule.body, in: block.name, problems: &problems)
            switch block {
            case .light: out.light = found
            case .systemDark: out.systemDark = found
            case .manualDark: out.manualDark = found
            }
            if block == .light {
                let re = try! NSRegularExpression(pattern: "--ke-(radius[a-z-]*):\\s*([0-9]+)(?:px)?\\s*;")
                for m in re.matches(in: rule.body, range: NSRange(rule.body.startIndex..., in: rule.body)) {
                    out.radii[String(rule.body[Range(m.range(at: 1), in: rule.body)!])] = Double(rule.body[Range(m.range(at: 2), in: rule.body)!])
                }
            }
        }
        for rule in all where Block.of(media: rule.media, selector: rule.selector) == nil {
            var unused: [String] = []
            if !colours(rule.body, in: "", problems: &unused).isEmpty {
                problems.append("tokens.css has colours in a block the theme does not mirror: \(rule.media.map { $0 + " " } ?? "")\(rule.selector)")
            }
        }
        return (out, problems)
    }

    /// Every way the Swift theme differs from tokens.css: a colour (light, system dark or manual dark) or a
    /// radius whose value differs, a token that only one side has, and a block that is missing, doubled or
    /// not expected. Each message names the block it is about. Empty when the theme mirrors the css.
    static func differences(_ css: String) -> [String] {
        let (spec, parseProblems) = parse(css)
        var out = parseProblems
        func hex(_ v: UInt32?) -> String { v.map { String(format: "#%06X", $0) } ?? "missing" }
        func keys(_ what: String, spec: Set<String>, theme: Set<String>) {
            for name in theme.subtracting(spec).sorted() { out.append("\(what) --ke-\(name) is in Theme and not in tokens.css") }
            for name in spec.subtracting(theme).sorted() { out.append("\(what) --ke-\(name) is in tokens.css and not in Theme") }
        }
        keys("colour (\(Block.light.name))", spec: Set(spec.light.keys), theme: Set(Theme.tokens.keys))
        // A dark block lists what changes; a token it does not list is the light one there. What it lists
        // has to be a token of the theme.
        for (block, table) in [(Block.systemDark, spec.systemDark), (Block.manualDark, spec.manualDark)] {
            for name in Set(table.keys).subtracting(Theme.tokens.keys).sorted() {
                out.append("colour --ke-\(name) is in tokens.css (\(block.name)) and not in Theme")
            }
        }
        for (name, token) in Theme.tokens.sorted(by: { $0.key < $1.key }) {
            guard let light = spec.light[name] else { continue }
            if token.light != light { out.append("--ke-\(name) light (\(Block.light.name)): Theme \(hex(token.light)), tokens.css \(hex(light))") }
            for (block, table) in [(Block.systemDark, spec.systemDark), (Block.manualDark, spec.manualDark)] {
                let dark = table[name] ?? light
                if token.dark != dark {
                    out.append("--ke-\(name) dark (\(block.name)): Theme \(hex(token.dark)), tokens.css \(hex(dark))\(table[name] == nil ? " (not declared in this block, so the light value)" : "")")
                }
            }
        }
        keys("radius (\(Block.light.name))", spec: Set(spec.radii.keys), theme: Set(Theme.Radius.tokens.keys))
        for (name, value) in Theme.Radius.tokens.sorted(by: { $0.key < $1.key }) {
            guard let want = spec.radii[name] else { continue }
            if Double(value) != want { out.append("--ke-\(name): Theme \(value), tokens.css \(want)") }
        }
        return out
    }

    /// A tokens.css written out from the Swift theme, for checking that the comparison can fail. It is not the
    /// spec, but it has the spec's three colour blocks: `:root`, the system's dark block and the manual one.
    static func renderTheme() -> String {
        func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }
        let sorted = Theme.tokens.sorted(by: { $0.key < $1.key })
        func dark(_ indent: String) -> String {
            sorted.filter { $0.value.dark != $0.value.light }.map { "\(indent)--ke-\($0.key): \(hex($0.value.dark));\n" }.joined()
        }
        var css = "/* --ke-not-a-token: #123456; --ke-radius-not-a-token: 99px; the header comment is not read */\n:root {\n"
        for (name, t) in sorted { css += "  --ke-\(name): \(hex(t.light));\n" }
        for (name, v) in Theme.Radius.tokens.sorted(by: { $0.key < $1.key }) {
            css += "  --ke-\(name): \(Int(v))\(v == 0 ? "" : "px");\n"
        }
        css += "}\n\n\(Block.systemMedia) {\n  \(Block.systemSelector) {\n" + dark("    ") + "  }\n}\n"
        css += "\n\(Block.manualSelector) {\n" + dark("  ") + "}\n"
        return css
    }
}
