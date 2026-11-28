import XCTest
@testable import KeepCore

final class CalendarLayoutTests: XCTestCase {
    private func month(_ marks: [String], today: String? = "2026-11-05", digests: Set<Int> = []) -> CalendarMonth {
        let days = marks.enumerated().map { i, m in
            CalendarMonth.Day(day: String(format: "2026-11-%02d", i + 1), mark: m, hasDigest: digests.isEmpty ? nil : digests.contains(i + 1))
        }
        return CalendarMonth(month: "2026-11", today: today, days: days, counts: .init(saved: 0, digests: 0, read: 0, notes: 0), previousMonth: "2026-10", nextMonth: nil)
    }

    func testTheFiveMarks() {
        XCTAssertEqual(CalendarLayout.dot(forMark: "empty"), .empty)
        XCTAssertEqual(CalendarLayout.dot(forMark: "saved"), .saved)
        XCTAssertEqual(CalendarLayout.dot(forMark: "digest_unread"), .digestUnread)
        XCTAssertEqual(CalendarLayout.dot(forMark: "digest_read"), .digestRead)
        XCTAssertEqual(CalendarLayout.dot(forMark: "note"), .note)
    }

    func testFutureDaysAndUnknownMarksAreNotDrawn() {
        XCTAssertNil(CalendarLayout.dot(forMark: "future"))
        XCTAssertNil(CalendarLayout.dot(forMark: "something_new"))
        let cells = CalendarLayout.cells(month(["empty", "saved", "digest_unread", "digest_read", "note", "future", "future"]))
        XCTAssertEqual(cells.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(cells.map(\.dot), [.empty, .saved, .digestUnread, .digestRead, .note])
    }

    func testTodayIsMarkedAndOnlyDaysWithADigestOpen() {
        let cells = CalendarLayout.cells(month(["empty", "saved", "digest_unread", "digest_read", "note"], digests: [3, 4, 5]))
        XCTAssertEqual(cells.filter(\.isToday).map(\.number), [5])
        XCTAssertEqual(cells.filter(\.opensDigest).map(\.number), [3, 4, 5])
        // Without `has_digest` only the digest marks open: a note day may have no digest.
        let guessed = CalendarLayout.cells(month(["saved", "digest_unread", "digest_read", "note"]))
        XCTAssertEqual(guessed.filter(\.opensDigest).map(\.number), [2, 3])
    }

    func testSevenToARowByDate() {
        let rows = CalendarLayout.rows(month(Array(repeating: "empty", count: 30), today: "2026-11-30"))
        XCTAssertEqual(rows.map(\.count), [7, 7, 7, 7, 2])
        XCTAssertEqual(rows[1].first?.number, 8)
        XCTAssertEqual(rows.last?.last?.number, 30)
    }

    func testDaysAreSortedByDate() {
        var m = month(["empty", "saved", "note"])
        m.days.reverse()
        XCTAssertEqual(CalendarLayout.cells(m).map(\.number), [1, 2, 3])
    }

    func testDayTitles() {
        XCTAssertEqual(KeepDates.dayTitle("2026-11-24", locale: Locale(identifier: "en_US")), "Nov 24")
        XCTAssertEqual(KeepDates.dayTitle("2026-11-24", locale: Locale(identifier: "zh_Hans_CN")), "11月24日")
        XCTAssertEqual(KeepDates.monthTitle("2026-11", locale: Locale(identifier: "en_US")), "November 2026")
        XCTAssertEqual(KeepDates.dayTitle("latest"), "latest")
        XCTAssertNotNil(KeepJSON.parseDate("2026-11-24T12:00:00Z"))
        XCTAssertNotNil(KeepJSON.parseDate("2026-11-24T12:00:00.123Z"))
        XCTAssertNotNil(KeepJSON.parseDate("2026-11-24T20:00:00+08:00"))
        XCTAssertNil(KeepJSON.parseDate("yesterday"))
    }
}

final class ThemeAndStringsTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The Swift theme mirrors design/tokens.css of the spec, value for value: every colour (light and
    /// dark, `gold-ink` included) and every radius, read from the css. Without the spec repository next to
    /// this one it is skipped, unless KE_REQUIRE_SPEC=1, which CI sets: then it fails.
    func testThemeMirrorsTheTokens() throws {
        switch SpecTokens.lookup(nextTo: repo, environment: ProcessInfo.processInfo.environment) {
        case .skip(let why): throw XCTSkip(why)
        case .fail(let why): XCTFail(why)
        case .css(let css):
            let differences = SpecTokens.differences(css)
            XCTAssertTrue(differences.isEmpty, "Theme differs from tokens.css:\n" + differences.joined(separator: "\n"))
            // The sizes are the phone ones of tokens.css (body 16, secondary 14, caption 13).
            XCTAssertEqual([Theme.Size.display, Theme.Size.title, Theme.Size.subtitle, Theme.Size.item, Theme.Size.body, Theme.Size.secondary, Theme.Size.caption],
                           [32, 26, 20, 17, 16, 14, 13])
        }
    }

    /// The bundled copy of the shared rules is the contract's, not a second wording.
    func testBundledRulesAreTheContracts() throws {
        let yaml = try String(contentsOf: repo.appendingPathComponent("contract/openapi.yaml"), encoding: .utf8)
        for key in ["saved", "duplicate", "queued_offline", "secret_like_question"] {
            for lang in ["zh", "en"] {
                let sentence = try XCTUnwrap(Meta.bundled.sharedRules.saveMessage(key, lang: lang))
                XCTAssertTrue(yaml.contains(sentence), "\(key).\(lang) is not in the contract")
            }
        }
        XCTAssertTrue(yaml.contains("version: \(Meta.bundled.contractVersion)"))
    }

    /// The String Catalog has every key in zh and en.
    func testCatalogHasBothLanguages() throws {
        let url = repo.appendingPathComponent("KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        XCTAssertGreaterThan(strings.count, 150)
        for (key, value) in strings {
            let l = value["localizations"] as? [String: Any]
            XCTAssertNotNil(l?["en"], "\(key) has no en")
            XCTAssertNotNil(l?["zh-Hans"], "\(key) has no zh-Hans")
        }
        func text(_ key: String, _ lang: String) -> String? {
            (((strings[key]?["localizations"] as? [String: Any])?[lang] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        XCTAssertEqual(["tab.today", "tab.digest", "tab.notes", "tab.assistants"].map { text($0, "zh-Hans") }, ["今天", "每日摘要", "笔记", "助手设置"])
        XCTAssertEqual(["tab.today", "tab.digest", "tab.notes", "tab.assistants"].map { text($0, "en") }, ["Today", "Daily digest", "Notes", "Assistants"])
        XCTAssertEqual(text("digest.read", "zh-Hans"), "读了，晚安")
        XCTAssertEqual(text("digest.read", "en"), "Read. Good night")
    }
}
