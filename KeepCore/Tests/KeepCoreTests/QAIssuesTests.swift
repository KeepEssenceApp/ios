import XCTest
@testable import KeepCore

/// One test per decision taken on the internal QA issues. XCTest names cannot hold "#", so each
/// test is named `testQA<number>_…` and carries the issue's sentence above it.
final class QAIssuesTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func item(_ json: String) throws -> Item {
        try KeepJSON.decoder().decode(Item.self, from: Data(json.utf8))
    }

    private func text(_ key: String, _ lang: String) throws -> String {
        let url = repo.appendingPathComponent("KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        let unit = ((strings[key]?["localizations"] as? [String: Any])?[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
        return try XCTUnwrap(unit?["value"] as? String, "\(key) has no \(lang)")
    }

    private let base = #""id":"i1","kind":"text","title":"A note","created_at":"2026-11-25T01:00:00Z","stage":"analysed""#

    /// QA #7: one retention control: the user's options, then "Never delete" as the last one.
    func testQA7_oneRetentionControlWithNeverDeleteLast() {
        XCTAssertEqual(Retention.choices(options: [7, 30, 90, 365]), [.days(7), .days(30), .days(90), .days(365), .never])
        XCTAssertEqual(Retention.choices(options: []), [.never])
        XCTAssertEqual(Retention.choices(options: [30, 30, 0]), [.days(30), .never])
    }

    /// QA #7: a kept item shows no `expiry:N` tag; an item with an end date shows its own.
    func testQA7_aKeptItemShowsNoExpiryTag() throws {
        let kept = try item("{\(base),\"pinned\":true,\"days_left\":null,\"expiry_days\":null,\"tags\":[\"assistant:Built-in assistant\",\"expiry:90\",\"source:web\"]}")
        XCTAssertEqual(Retention.current(of: kept), .never)
        XCTAssertEqual(Retention.visibleTags(of: kept), ["assistant:Built-in assistant", "source:web"])
        XCTAssertNil(Retention.until(kept))
        XCTAssertEqual(Retention.sentence(for: kept).key, "item.said.never")

        let dated = try item("{\(base),\"pinned\":false,\"days_left\":90,\"expiry_days\":90,\"tags\":[\"expiry:90\",\"source:web\"]}")
        XCTAssertEqual(Retention.current(of: dated), .days(90))
        XCTAssertEqual(Retention.visibleTags(of: dated), ["expiry:90", "source:web"])
    }

    /// QA #32: how long an item is kept is decided when it is sorted. Until then no days are shown
    /// and no expiry tag; a value the user chose before that is a decision and is shown.
    func testQA32_noDaysLeftBeforeTheItemIsSorted() throws {
        let fresh = #""id":"i2","kind":"text","title":"A note","created_at":"2026-11-25T07:00:00Z""#
        // Freshly saved: the core stores 30 as a placeholder. In a list (no tags) and on its page.
        let row = try item("{\(fresh),\"stage\":\"saved\",\"pinned\":false,\"days_left\":30}")
        XCTAssertFalse(Retention.decided(row))
        XCTAssertNil(Retention.daysLeft(of: row))
        let page = try item("{\(fresh),\"stage\":\"saved\",\"pinned\":false,\"days_left\":30,\"expiry_days\":30,\"tags\":[\"source:web\"]}")
        XCTAssertFalse(Retention.decided(page))
        XCTAssertNil(Retention.daysLeft(of: page))
        XCTAssertNil(Retention.current(of: page))
        XCTAssertEqual(Retention.visibleTags(of: page), ["source:web"])

        // The user chose before sorting: the core lists the tag, and it is shown as decided.
        let chosen = try item("{\(fresh),\"stage\":\"saved\",\"pinned\":false,\"days_left\":90,\"expiry_days\":90,\"tags\":[\"expiry:90\",\"source:web\"]}")
        XCTAssertTrue(Retention.decided(chosen))
        XCTAssertEqual(Retention.daysLeft(of: chosen), 90)
        XCTAssertEqual(Retention.current(of: chosen), .days(90))
        XCTAssertEqual(Retention.visibleTags(of: chosen), ["expiry:90", "source:web"])
        let kept = try item("{\(fresh),\"stage\":\"saved\",\"pinned\":true,\"days_left\":null,\"expiry_days\":null,\"tags\":[\"source:web\"]}")
        XCTAssertTrue(Retention.decided(kept))
        XCTAssertEqual(Retention.current(of: kept), .never)
        XCTAssertNil(Retention.daysLeft(of: kept))

        // Sorted: the days are the dispatch step's decision and are shown, in a list too.
        for stage in ["triaged", "analysed"] {
            let sorted = try item("{\(fresh),\"stage\":\"\(stage)\",\"pinned\":false,\"days_left\":7,\"expiry_days\":7,\"tags\":[\"expiry:7\",\"source:web\"]}")
            XCTAssertTrue(Retention.decided(sorted))
            XCTAssertEqual(Retention.daysLeft(of: sorted), 7)
            XCTAssertEqual(Retention.current(of: sorted), .days(7))
            XCTAssertEqual(Retention.visibleTags(of: sorted), ["expiry:7", "source:web"])
            XCTAssertEqual(Retention.daysLeft(of: try item("{\(fresh),\"stage\":\"\(stage)\",\"days_left\":7}")), 7)
        }

        XCTAssertEqual(Retention.placeholderDays, 30)
        XCTAssertEqual(try text("item.decided_when_sorted", "en"), "Decided when it is sorted")
        XCTAssertEqual(try text("item.decided_when_sorted", "zh-Hans"), "初筛时定")
        XCTAssertEqual(try text("item.undecided_hint", "en"), "Unless you choose, how long this is kept is decided when the item is sorted: %lld days, or what your rules say.")
        XCTAssertEqual(try text("item.set_by_sorting", "en"), "Set when the item was sorted. Choose another to change it.")
    }

    /// QA #7: every retention change is said in one sentence that is exactly true: the days and the day it ends.
    func testQA7_theSentenceNamesTheDaysAndTheEndDate() throws {
        // The core's own moment wins when it gives one.
        let exact = try item("{\(base),\"pinned\":false,\"days_left\":90,\"expiry_days\":90,\"expires_at\":\"2027-02-23T01:00:00Z\"}")
        XCTAssertEqual(Retention.until(exact), KeepJSON.parseDate("2027-02-23T01:00:00Z"))
        let said = Retention.sentence(for: exact, locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(said.key, "item.said.days")
        XCTAssertEqual(said.days, 90)
        XCTAssertTrue(try XCTUnwrap(said.date).contains("2027"), said.date ?? "")
        // A core that does not give it: counted from the days that are left.
        let now = try XCTUnwrap(KeepJSON.parseDate("2026-11-25T02:00:00Z"))
        let older = try item("{\(base),\"pinned\":false,\"days_left\":7,\"expiry_days\":7}")
        XCTAssertEqual(Retention.until(older, now: now), now.addingTimeInterval(7 * 86400))

        XCTAssertEqual(try text("item.said.days", "en"), "Kept for %1$lld days, until %2$@.")
        XCTAssertEqual(try text("item.said.never", "en"), "Never deleted.")
        XCTAssertEqual(try text("item.said.days", "zh-Hans"), "保留 %1$lld 天，到 %2$@ 删除。")
    }

    /// QA #7: no action is labelled with a bare "Keep" / 「收藏」; the labels say what happens.
    func testQA7_noBareKeepLabel() throws {
        XCTAssertEqual(try text("item.never_delete", "en"), "Never delete")
        XCTAssertEqual(try text("item.end_date", "en"), "Give it an end date")
        XCTAssertEqual(try text("item.never_delete", "zh-Hans"), "收藏（不过期）")
        XCTAssertEqual(try text("item.end_date", "zh-Hans"), "改回有期限")
        let url = repo.appendingPathComponent("KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in strings.keys {
            XCTAssertNotEqual(try text(key, "en"), "Keep", key)
            XCTAssertNotEqual(try text(key, "zh-Hans"), "收藏", key)
        }
    }

    /// QA #9: "Analysed by" never offers nobody; it lists every assistant that can analyse, and the current one.
    func testQA9_analysedByListsEveryAnalyserAndTheCurrentOne() {
        func a(_ id: String, _ kind: String, _ steps: [Step]) -> Assistant {
            Assistant(id: id, name: id.uppercased(), kind: kind, steps: steps, builtIn: id == "w", connectedAt: nil, lastSeenAt: nil, runsAt: nil)
        }
        let all = [a("w", "scheduled", [.analysis, .digest]), a("s", "scheduled", [.analysis, .deepRead]), a("c", "chat", [.deepDive]), a("d", "scheduled", [.digest])]
        XCTAssertEqual(Analysers.candidates(all, current: NamedRef(id: "w", name: "W")).map(\.id), ["w", "s"])
        // The one it is with now stays in the list even when it no longer analyses.
        XCTAssertEqual(Analysers.candidates(all, current: NamedRef(id: "d", name: "D")).map(\.id), ["w", "s", "d"])
        // Not dispatched yet: no made-up entry.
        XCTAssertEqual(Analysers.candidates(all, current: nil).map(\.id), ["w", "s"])
        XCTAssertEqual(try text("item.not_assigned", "en"), "Not assigned yet")
    }

    /// QA #14: a product that was not verified gets no tab; it is named in one line.
    func testQA14_unverifiedProductsGetNoTab() throws {
        XCTAssertEqual(ConnectProducts.verified.map(\.id), ["claude", "chatgpt", "gemini", "own"])
        XCTAssertTrue(ConnectProducts.verified.allSatisfy { $0.steps > 0 })
        XCTAssertEqual(ConnectProducts.unverified, ["Muse"])
        // Every tab has its steps written, in both languages; nothing is written for Muse.
        for p in ConnectProducts.verified {
            for i in 1...p.steps { for lang in ["en", "zh-Hans"] { XCTAssertFalse(try text("connect.\(p.id).\(i)", lang).isEmpty) } }
        }
        let catalog = try String(contentsOf: repo.appendingPathComponent("KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings"), encoding: .utf8)
        XCTAssertFalse(catalog.contains("connect.muse."))
        XCTAssertEqual(String(format: try text("connect.unverified_list", "en"), "Muse"), "Not verified yet: Muse.")
        XCTAssertEqual(String(format: try text("connect.unverified_list", "zh-Hans"), "Muse"), "待验证：Muse。")
    }

    /// QA #16: with no daily digest the page says when it comes, what it needs and where today's analyses are.
    func testQA16_theEmptyDigestPageSaysWhenAndWhy() throws {
        XCTAssertEqual(DigestEmpty.key(reason: "not_yet_time"), "digest.none.not_yet_time")
        XCTAssertEqual(DigestEmpty.key(reason: "nothing_analysed"), "digest.none.nothing_analysed")
        XCTAssertEqual(DigestEmpty.key(reason: "no_assistant"), "digest.none.no_assistant")
        XCTAssertEqual(DigestEmpty.key(reason: "waiting_for_assistant"), "digest.none.waiting")
        XCTAssertEqual(DigestEmpty.key(reason: nil), "digest.none")
        for reason in ["not_yet_time", "nothing_analysed", "no_assistant", "waiting_for_assistant", nil] as [String?] {
            let key = DigestEmpty.key(reason: reason)
            for lang in ["en", "zh-Hans"] {
                let s = try text(key, lang)
                // The hour and the time zone are named exactly where the sentence is about time.
                XCTAssertEqual(s.contains("%@"), DigestEmpty.namesTime(reason: reason), "\(key) \(lang)")
                XCTAssertEqual(s.contains("21:00"), DigestEmpty.namesTime(reason: reason), "\(key) \(lang)")
            }
        }
        let en = String(format: try text("digest.none.not_yet_time", "en"), "Australia/Sydney")
        XCTAssertTrue(en.contains("after 21:00 (Australia/Sydney)"))
        XCTAssertTrue(en.contains("at least one analysed item"))
        XCTAssertTrue(en.contains("in Today"))
        // Nothing offers to write one on request.
        for key in ["digest.none", "digest.none.not_yet_time", "digest.none.nothing_analysed", "digest.none.no_assistant", "digest.none.waiting"] {
            XCTAssertFalse(try text(key, "en").lowercased().contains("now"), key)
        }
    }
}
