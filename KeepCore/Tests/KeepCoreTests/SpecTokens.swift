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

    struct Parsed {
        var light: [String: UInt32] = [:]
        var dark: [String: UInt32] = [:]
        /// `--ke-radius*` in points; `0` has no unit in the css.
        var radii: [String: Double] = [:]
    }

    /// Reads the colours (light, and the dark block) and the radii of tokens.css. Comments are dropped first,
    /// so a token named in a comment is not a token.
    static func parse(_ css: String) -> (parsed: Parsed, problems: [String]) {
        let text = css.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        let parts = text.components(separatedBy: "@media (prefers-color-scheme: dark)")
        var problems: [String] = []
        if parts.count != 2 { problems.append("tokens.css has \(parts.count - 1) dark blocks, expected 1") }
        var out = Parsed()
        func colours(_ s: String) -> [String: UInt32] {
            var found: [String: UInt32] = [:]
            let re = try! NSRegularExpression(pattern: "--ke-([a-z0-9-]+):\\s*#([0-9A-Fa-f]{6})")
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                found[String(s[Range(m.range(at: 1), in: s)!])] = UInt32(s[Range(m.range(at: 2), in: s)!], radix: 16)
            }
            return found
        }
        out.light = colours(parts[0])
        out.dark = parts.count > 1 ? colours(parts[1]) : [:]
        let re = try! NSRegularExpression(pattern: "--ke-(radius[a-z-]*):\\s*([0-9]+)(?:px)?\\s*;")
        for m in re.matches(in: parts[0], range: NSRange(parts[0].startIndex..., in: parts[0])) {
            out.radii[String(parts[0][Range(m.range(at: 1), in: parts[0])!])] = Double(parts[0][Range(m.range(at: 2), in: parts[0])!])
        }
        return (out, problems)
    }

    /// Every way the Swift theme differs from tokens.css: a colour (light or dark) or a radius whose value
    /// differs, and a token that only one side has. Empty when the theme mirrors the css.
    static func differences(_ css: String) -> [String] {
        let (spec, parseProblems) = parse(css)
        var out = parseProblems
        func hex(_ v: UInt32?) -> String { v.map { String(format: "#%06X", $0) } ?? "missing" }
        func keys(_ what: String, spec: Set<String>, theme: Set<String>) {
            for name in theme.subtracting(spec).sorted() { out.append("\(what) --ke-\(name) is in Theme and not in tokens.css") }
            for name in spec.subtracting(theme).sorted() { out.append("\(what) --ke-\(name) is in tokens.css and not in Theme") }
        }
        keys("colour", spec: Set(spec.light.keys), theme: Set(Theme.tokens.keys))
        for (name, token) in Theme.tokens.sorted(by: { $0.key < $1.key }) {
            guard let light = spec.light[name] else { continue }
            if token.light != light { out.append("--ke-\(name) light: Theme \(hex(token.light)), tokens.css \(hex(light))") }
            let dark = spec.dark[name] ?? light
            if token.dark != dark { out.append("--ke-\(name) dark: Theme \(hex(token.dark)), tokens.css \(hex(dark))") }
        }
        keys("radius", spec: Set(spec.radii.keys), theme: Set(Theme.Radius.tokens.keys))
        for (name, value) in Theme.Radius.tokens.sorted(by: { $0.key < $1.key }) {
            guard let want = spec.radii[name] else { continue }
            if Double(value) != want { out.append("--ke-\(name): Theme \(value), tokens.css \(want)") }
        }
        return out
    }

    /// A tokens.css written out from the Swift theme, for checking that the comparison can fail. It is not the spec.
    static func renderTheme() -> String {
        func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }
        var css = "/* --ke-not-a-token: #123456; --ke-radius-not-a-token: 99px; the header comment is not read */\n:root {\n"
        for (name, t) in Theme.tokens.sorted(by: { $0.key < $1.key }) { css += "  --ke-\(name): \(hex(t.light));\n" }
        for (name, v) in Theme.Radius.tokens.sorted(by: { $0.key < $1.key }) {
            css += "  --ke-\(name): \(Int(v))\(v == 0 ? "" : "px");\n"
        }
        css += "}\n\n@media (prefers-color-scheme: dark) {\n  :root:not([data-theme=\"light\"]) {\n"
        for (name, t) in Theme.tokens.sorted(by: { $0.key < $1.key }) where t.dark != t.light { css += "    --ke-\(name): \(hex(t.dark));\n" }
        css += "  }\n}\n"
        return css
    }
}
