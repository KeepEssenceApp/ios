import SwiftUI
import XCTest
@testable import KeepCore

/// The spec comparison itself: that it can fail, and what it does when the spec is missing.
final class SpecComparisonTests: XCTestCase {
    /// A comparison that cannot fail proves nothing. Written out from the theme it passes; one changed
    /// value, one missing token or one extra token each make it report.
    func testTheComparisonReportsEveryKindOfDrift() {
        let css = SpecTokens.renderTheme()
        XCTAssertEqual(SpecTokens.differences(css), [], "the theme written out as css must match itself")

        func drift(_ from: String, _ to: String) -> [String] {
            XCTAssertTrue(css.contains(from), "the fixture has no \(from)")
            return SpecTokens.differences(css.replacingOccurrences(of: from, with: to))
        }
        XCTAssertEqual(drift("--ke-radius-card: 20px;", "--ke-radius-card: 6px;").count, 1)
        XCTAssertEqual(drift("--ke-radius-tag: 8px;", "--ke-radius-tag: 4px;").count, 1)
        XCTAssertEqual(drift("--ke-radius-sheet: 28px;", "--ke-radius-sheet: 10px;").count, 1)
        XCTAssertEqual(drift("--ke-radius: 14px;", "--ke-radius: 6px;").count, 1)
        XCTAssertEqual(drift("--ke-radius-control: 999px;", "--ke-radius-control: 12px;").count, 1)
        XCTAssertEqual(drift("--ke-card: #FFFDFC;", "--ke-card: #FFFFFF;").count, 1)
        XCTAssertEqual(drift("--ke-gold-ink: #795600;", "--ke-gold-ink: #795601;").count, 1, "a light value")
        // A dark value is in two blocks (the system's and the manual one). Changed in one of them it is one
        // difference, changed in both it is two: neither hides the other.
        for block in [SpecTokens.Block.systemDark, .manualDark] {
            for (from, to) in [("--ke-gold-ink: #F2D27D;", "--ke-gold-ink: #F2D27E;"), ("--ke-bg: #191817;", "--ke-bg: #0B0B0B;")] {
                XCTAssertEqual(SpecTokens.differences(changed(css, in: block, from: from, to: to)).count, 1, "a dark value of the \(block.name)")
            }
        }
        XCTAssertEqual(drift("--ke-gold-ink: #F2D27D;", "--ke-gold-ink: #F2D27E;").count, 2, "a dark value in both dark blocks")
        XCTAssertEqual(drift("--ke-bg: #191817;", "--ke-bg: #0B0B0B;").count, 2, "a dark value in both dark blocks")
        // A token only the css has, and one only the theme has.
        XCTAssertEqual(drift("  --ke-gold-ink: #795600;\n", "").count, 1)
        XCTAssertEqual(drift("  --ke-gold-ink: #795600;\n", "  --ke-gold-ink: #795600;\n  --ke-gold-ink-2: #795600;\n").count, 1)
        XCTAssertEqual(drift("  --ke-radius-card: 20px;\n", "").count, 1)
        XCTAssertEqual(drift("  --ke-radius-card: 20px;\n", "  --ke-radius-card: 20px;\n  --ke-radius-pill: 40px;\n").count, 1)
    }

    // MARK: the two dark blocks

    /// `css` with `from` replaced by `to` inside one block only. The block runs from its marker (the media
    /// condition of the system's dark block, the selector of the manual one) to the next marker or the end;
    /// the light block is what comes before both. `from` must be in the block exactly once, or the copy would
    /// not differ from the original and the test would prove nothing.
    private func region(of block: SpecTokens.Block, in css: String) -> Range<String.Index> {
        var starts: [(SpecTokens.Block, String.Index)] = [(.light, css.startIndex)]
        for (b, marker) in [(SpecTokens.Block.systemDark, SpecTokens.Block.systemMedia), (.manualDark, SpecTokens.Block.manualSelector)] {
            XCTAssertEqual(css.components(separatedBy: marker).count - 1, 1, "the fixture must have one \(b.name)")
            if let r = css.range(of: marker) { starts.append((b, r.lowerBound)) }
        }
        starts.sort { $0.1 < $1.1 }
        let i = starts.firstIndex { $0.0 == block } ?? 0
        return starts[i].1..<(i + 1 < starts.count ? starts[i + 1].1 : css.endIndex)
    }

    private func changed(_ css: String, in block: SpecTokens.Block, from: String, to: String) -> String {
        let range = region(of: block, in: css)
        let part = String(css[range])
        XCTAssertEqual(part.components(separatedBy: from).count - 1, 1, "\(from) must be in the \(block.name) once")
        return css.replacingCharacters(in: range, with: part.replacingOccurrences(of: from, with: to))
    }

    /// What happens when the two dark blocks of `css`, a tokens.css that matches the theme, are told apart:
    /// each is compared with the theme on its own, and a copy changed in one block reports that block only.
    private func checkEachDarkBlockOnItsOwn(_ css: String, _ label: String) {
        let system = SpecTokens.Block.systemDark, manual = SpecTokens.Block.manualDark
        let was = "--ke-card: #292725;", white = "--ke-card: #FFFFFF;"
        XCTAssertEqual(SpecTokens.differences(css), [], "\(label): the unchanged copy has no difference")

        // Two tables, not one: the value of one block does not overwrite the other's.
        let systemOnly = changed(css, in: system, from: was, to: white)
        let manualOnly = changed(css, in: manual, from: was, to: white)
        let a = SpecTokens.parse(systemOnly).parsed, b = SpecTokens.parse(manualOnly).parsed
        XCTAssertEqual(a.systemDark["card"], 0xFFFFFF, label); XCTAssertEqual(a.manualDark["card"], 0x292725, label)
        XCTAssertEqual(b.systemDark["card"], 0x292725, label); XCTAssertEqual(b.manualDark["card"], 0xFFFFFF, label)

        // Only the system's block changed, only the manual one changed, both changed.
        let onlySystem = SpecTokens.differences(systemOnly)
        XCTAssertEqual(onlySystem.count, 1, "\(label): only the system dark block changed: \(onlySystem)")
        XCTAssertTrue(onlySystem.first?.contains(system.name) == true && onlySystem.first?.contains(manual.name) == false, "\(label): \(onlySystem)")
        let onlyManual = SpecTokens.differences(manualOnly)
        XCTAssertEqual(onlyManual.count, 1, "\(label): only the manual dark block changed: \(onlyManual)")
        XCTAssertTrue(onlyManual.first?.contains(manual.name) == true && onlyManual.first?.contains(system.name) == false, "\(label): \(onlyManual)")
        let both = SpecTokens.differences(changed(systemOnly, in: manual, from: was, to: white))
        XCTAssertEqual(both.count, 2, "\(label): both dark blocks changed: \(both)")
        XCTAssertTrue(both.contains { $0.contains(system.name) } && both.contains { $0.contains(manual.name) }, "\(label): \(both)")

        // A token one dark block does not declare (it would be the light value there) is that block's difference.
        for (block, other) in [(system, manual), (manual, system)] {
            let d = SpecTokens.differences(changed(css, in: block, from: was, to: ""))
            XCTAssertEqual(d.count, 1, "\(label): --ke-card left out of the \(block.name): \(d)")
            XCTAssertTrue(d.first?.contains(block.name) == true && d.first?.contains(other.name) == false && d.first?.contains("not declared") == true, "\(label): \(d)")
            // A token only one dark block has, and the theme does not: that block's difference.
            let extra = SpecTokens.differences(changed(css, in: block, from: was, to: "\(was) --ke-extra-one: #123456;"))
            XCTAssertEqual(extra.count, 1, "\(label): an extra token in the \(block.name): \(extra)")
            XCTAssertTrue(extra.first?.contains("--ke-extra-one") == true && extra.first?.contains(block.name) == true && extra.first?.contains(other.name) == false, "\(label): \(extra)")
            // The same token twice in one block: the later one would hide the earlier one.
            let twice = SpecTokens.differences(changed(css, in: block, from: was, to: "\(was) \(white)"))
            XCTAssertTrue(twice.contains { $0.contains("--ke-card is declared twice in the \(block.name)") }, "\(label): \(twice)")
        }

        // A dark block that is not there, and one that is there twice: neither is taken for no difference.
        for (block, other) in [(system, manual), (manual, system)] {
            let range = region(of: block, in: css)
            let missing = SpecTokens.differences(css.replacingCharacters(in: range, with: ""))
            XCTAssertTrue(missing.contains { $0.contains("tokens.css has no \(block.name)") }, "\(label): \(missing)")
            XCTAssertFalse(missing.contains { $0.contains(other.name) }, "\(label): the other block is not blamed: \(missing)")
            let doubled = SpecTokens.differences(css + "\n" + String(css[range]))
            XCTAssertEqual(doubled.count, 1, "\(label): \(block.name) twice: \(doubled)")
            XCTAssertTrue(doubled.first?.contains("2 copies of the \(block.name)") == true, "\(label): \(doubled)")
        }

        // Colours in a block the theme does not mirror are a problem. A block with no colours (sizes) is not.
        let sepia = SpecTokens.differences(css + "\n:root[data-theme=\"sepia\"] { --ke-bg: #000000; }\n")
        XCTAssertEqual(sepia.count, 1, "\(label): \(sepia)")
        XCTAssertTrue(sepia.first?.contains("[data-theme=\"sepia\"]") == true, "\(label): \(sepia)")
        XCTAssertEqual(SpecTokens.differences(css + "\n@media (max-width: 400px) { :root { --ke-size-body: 18px; } }\n"), [], label)
    }

    /// The same check on the theme written out as css: it needs no spec, so it always runs.
    func testEachDarkBlockOfTheThemeCssIsComparedOnItsOwn() {
        let css = SpecTokens.renderTheme()
        XCTAssertEqual(css.components(separatedBy: SpecTokens.Block.systemMedia).count - 1, 1, "renderTheme writes the system dark block")
        XCTAssertEqual(css.components(separatedBy: SpecTokens.Block.manualSelector).count - 1, 1, "renderTheme writes the manual dark block")
        let parsed = SpecTokens.parse(css)
        XCTAssertEqual(parsed.problems, [])
        XCTAssertFalse(parsed.parsed.systemDark.isEmpty)
        XCTAssertEqual(parsed.parsed.systemDark, parsed.parsed.manualDark, "both dark blocks hold the theme's dark values")
        let darkOnes = Theme.tokens.filter { $0.value.dark != $0.value.light }
        XCTAssertEqual(Set(parsed.parsed.systemDark.keys), Set(darkOnes.keys))
        XCTAssertEqual(Set(parsed.parsed.manualDark.keys), Set(darkOnes.keys))
        checkEachDarkBlockOnItsOwn(css, "the theme written out as css")
    }

    /// The same check on a copy of the pinned spec's tokens.css. The copy is a string in memory: the spec is
    /// never written to. Without the spec it is skipped, and under KE_REQUIRE_SPEC=1 it fails.
    func testEachDarkBlockOfTheSpecIsComparedOnItsOwn() throws {
        switch SpecTokens.lookup(nextTo: RepoPaths.root, environment: ProcessInfo.processInfo.environment) {
        case .skip(let why): throw XCTSkip(why)
        case .fail(let why): XCTFail(why)
        case .css(let css): checkEachDarkBlockOnItsOwn(css, "a copy of the spec's tokens.css")
        }
    }

    /// Where the spec is not next to the repository: a skip, unless KE_REQUIRE_SPEC=1 asks for it, which is a failure.
    func testAMissingSpecFailsOnlyWhenItIsRequired() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ke-spec-lookup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = folder.appendingPathComponent("ios")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        guard case .skip = SpecTokens.lookup(nextTo: repo, environment: [:]) else { return XCTFail("no spec and no flag must skip") }
        guard case .skip = SpecTokens.lookup(nextTo: repo, environment: ["KE_REQUIRE_SPEC": "0"]) else { return XCTFail("flag 0 must skip") }
        guard case .skip = SpecTokens.lookup(nextTo: repo, environment: ["KE_REQUIRE_SPEC": ""]) else { return XCTFail("an empty flag must skip") }
        guard case .fail(let why) = SpecTokens.lookup(nextTo: repo, environment: ["KE_REQUIRE_SPEC": "1"]) else {
            return XCTFail("no spec and KE_REQUIRE_SPEC=1 must fail")
        }
        XCTAssertTrue(why.contains("KE_REQUIRE_SPEC=1"), why)
        XCTAssertTrue(why.contains("spec/design/tokens.css"), why)

        // With the spec there, both cases read it.
        let design = folder.appendingPathComponent("spec/design")
        try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)
        try ":root { --ke-bg: #F9F6F4; }".write(to: design.appendingPathComponent("tokens.css"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SpecTokens.lookup(nextTo: repo, environment: [:]), .css(":root { --ke-bg: #F9F6F4; }"))
        XCTAssertEqual(SpecTokens.lookup(nextTo: repo, environment: ["KE_REQUIRE_SPEC": "1"]), .css(":root { --ke-bg: #F9F6F4; }"))
    }
}

/// Which component takes which rounding. `Theme.Surface` is the table; these tests hold it to tokens.css
/// and hold the views to the table.
final class SurfaceTests: XCTestCase {
    private var repo: URL { RepoPaths.root }

    /// Component to token, written out here on purpose: a change of a component's rounding is a change of this table.
    private static let expected: [Theme.Surface: String] = [
        .card: "radius-card", .swipeBackground: "radius-card", .notice: "radius-card", .shareCard: "radius-card",
        .quietBox: "radius", .field: "radius", .textEditor: "radius", .darkField: "radius", .originalImage: "radius",
        .solidButton: "radius-control", .quietButton: "radius-control", .choiceChip: "radius-control",
        .statusMark: "radius-control", .shareButton: "radius-control",
    ]

    /// Where each component is drawn, so a view cannot take another component's rounding unnoticed.
    private static let components: [(file: String, anchor: String, surface: Theme.Surface)] = [
        ("App/Sources/Components.swift", "func card(padding", .card),
        ("App/Sources/Components.swift", "func quietBox(padding", .quietBox),
        ("App/Sources/Components.swift", "struct SolidButton: ButtonStyle", .solidButton),
        ("App/Sources/Components.swift", "struct QuietButton: ButtonStyle", .quietButton),
        ("App/Sources/Components.swift", "struct KEField: View", .field),
        ("App/Sources/Components.swift", "struct SwipeRow<Content: View>", .swipeBackground),
        ("App/Sources/Components.swift", "struct StatusMark: View", .statusMark),
        ("App/Sources/Components.swift", "struct NoticeBar: View", .notice),
        ("App/Sources/AssistantsView.swift", "struct ProductButton: ButtonStyle", .choiceChip),
        ("App/Sources/AssistantsView.swift", "struct RulesPage: View", .textEditor),
        ("App/Sources/NotesView.swift", "struct PasteSheet: View", .textEditor),
        ("App/Sources/SignInView.swift", "private struct DarkField: ViewModifier", .darkField),
        ("App/Sources/TodayView.swift", "private func original(_ item: Item)", .originalImage),
        ("ShareExtension/ShareViewController.swift", "struct ShareSheetView: View", .shareCard),
        ("ShareExtension/ShareViewController.swift", "private struct ShareButton: ButtonStyle", .shareButton),
    ]

    func testTheTableNamesTheTokenOfEveryComponent() {
        XCTAssertEqual(Set(Theme.Surface.allCases), Set(Self.expected.keys), "a new component needs a line in this table")
        for surface in Theme.Surface.allCases {
            XCTAssertEqual(surface.token, Self.expected[surface], "\(surface)")
            XCTAssertNotNil(Theme.Radius.tokens[surface.token], "\(surface) names \(surface.token), which Theme.Radius does not have")
        }
    }

    /// The text of the declaration that starts at the first line holding `anchor`, up to its closing brace.
    private func block(_ file: String, _ anchor: String) throws -> String {
        let text = try String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.contains(anchor) }, "\(file) has no line with \(anchor)")
        let indent = String(repeating: " ", count: lines[start].prefix { $0 == " " }.count)
        let end = try XCTUnwrap(lines[(start + 1)...].firstIndex { $0 == indent + "}" }, "\(anchor) in \(file) has no closing brace")
        return lines[start...end].joined(separator: "\n")
    }

    private func swiftFiles(_ folders: [String]) throws -> [(path: String, lines: [String])] {
        var out: [(String, [String])] = []
        for folder in folders {
            let root = repo.appendingPathComponent(folder)
            let walker = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil), "no \(folder) folder")
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                out.append((folder + "/" + url.lastPathComponent, text.components(separatedBy: "\n")))
            }
        }
        XCTAssertFalse(out.isEmpty, "no Swift sources read")
        return out
    }

    /// Each component's own declaration asks for its own entry of the table, and for no other rounding.
    func testEachComponentTakesItsOwnToken() throws {
        XCTAssertEqual(Set(Self.components.map(\.surface)), Set(Theme.Surface.allCases), "every entry of the table is drawn by a listed component")
        for c in Self.components {
            let code = try block(c.file, c.anchor)
            let re = try NSRegularExpression(pattern: "Theme\\.shape\\(\\.(\\w+)\\)")
            let asked = Set(re.matches(in: code, range: NSRange(code.startIndex..., in: code)).map { String(code[Range($0.range(at: 1), in: code)!]) })
            XCTAssertEqual(asked, [c.surface.rawValue], "\(c.anchor) in \(c.file) must take .\(c.surface.rawValue) (\(c.surface.token))")
            // (A sheet's own corners, `Theme.Radius.sheet`, may sit in the same declaration: they are not a surface.)
            let own = ["RoundedRectangle(", "Capsule(", "Theme.Radius.mark", "Theme.Radius.tag", "Theme.Radius.base", "Theme.Radius.card", "Theme.Radius.control"]
            XCTAssertEqual(own.filter(code.contains), [], "\(c.anchor) in \(c.file) names a rounding itself")
        }
    }

    /// No view builds a rounded shape or names a radius of its own. The one exception is the short gold
    /// line above the selected tab, which is no component. Sheets (the top corners of a bottom sheet) take `Theme.Radius.sheet`.
    func testNoViewNamesARadiusOutsideTheTable() throws {
        var sheets = 0
        for file in try swiftFiles(["App/Sources", "ShareExtension"]) {
            for (i, line) in file.lines.enumerated() {
                let where_ = "\(file.path):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))"
                if line.contains("RoundedRectangle(") || line.contains("Capsule(") || line.contains(".cornerRadius(") || line.contains("UnevenRoundedRectangle") {
                    let gold = file.path.hasSuffix("KeepEssenceApp.swift") && line.contains("Capsule().fill(on ? Theme.gold")
                    XCTAssertTrue(gold, "a shape outside Theme.shape: \(where_)")
                }
                for step in ["mark", "tag", "base", "card", "control"] where line.contains("Theme.Radius.\(step)") {
                    XCTFail("a radius named outside the table: \(where_)")
                }
                if line.contains("presentationCornerRadius(") {
                    sheets += 1
                    XCTAssertTrue(line.contains("presentationCornerRadius(Theme.Radius.sheet)"), "a sheet that is not the sheet radius: \(where_)")
                }
                if line.contains("preferredCornerRadius") {
                    sheets += 1
                    XCTAssertTrue(line.contains("preferredCornerRadius = Theme.Radius.sheet"), "a sheet that is not the sheet radius: \(where_)")
                }
            }
        }
        XCTAssertGreaterThan(sheets, 0, "no sheet found: the scan reads nothing")
    }

    // MARK: against the spec

    /// The shape each component draws has the radius tokens.css gives its token: 20 for cards, 14 for
    /// fields and small blocks, a capsule for the pills.
    func testTheShapesFollowTheRadiiOfTheSpec() throws {
        let css: String
        switch SpecTokens.lookup(nextTo: repo, environment: ProcessInfo.processInfo.environment) {
        case .skip(let why): throw XCTSkip(why)
        case .fail(let why): return XCTFail(why)
        case .css(let text): css = text
        }
        let radii = SpecTokens.parse(css).parsed.radii
        let rect = CGRect(x: 0, y: 0, width: 200, height: 44)
        for surface in Theme.Surface.allCases {
            let value = try XCTUnwrap(radii[surface.token], "tokens.css has no --ke-\(surface.token)")
            let want: Path = surface.token == "radius-control"
                ? Capsule().path(in: rect)
                : RoundedRectangle(cornerRadius: CGFloat(value)).path(in: rect)
            XCTAssertTrue(Theme.shape(surface).path(in: rect) == want, "\(surface) is not drawn with --ke-\(surface.token): \(value)")
        }
        // The sheets are not a `Surface` (they take the corner radius of the system's sheet), so check theirs.
        XCTAssertEqual(radii["radius-sheet"], Double(Theme.Radius.sheet), "--ke-radius-sheet")
    }
}
