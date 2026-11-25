import SwiftUI
import KeepCore

/// Today: what was saved and is not in a daily digest yet. Analyses newest first, each with its three
/// actions; handled ones in one line each; items not analysed yet after, lighter.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var month: CalendarMonth?
    @State private var choosing: String?
    @State private var diving: DeepDiveTarget?
    @State private var restOpen = false

    private var analysed: [Item] {
        items.filter { $0.analysis != nil }.sorted { ($0.analysis?.createdAt ?? $0.createdAt) > ($1.analysis?.createdAt ?? $1.createdAt) }
    }
    private var open: [Item] { analysed.filter { !$0.handled } }
    private var handled: [Item] { analysed.filter(\.handled) }
    private var waiting: [Item] { items.filter { $0.analysis == nil }.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: L("tab.today"), narrow: true, month: month)
                    .padding(.bottom, 4)
                queueLines
                if loaded && open.isEmpty && waiting.isEmpty {
                    Sentence(L("today.all_handled")).accessibilityIdentifier("today.done")
                }
                ForEach(open) { item in
                    SwipeRow(onRight: { Task { await queue(item.id) } }, onLeft: { Task { await signal(item.id, .notInterested) } }) {
                        AnalysisCard(item: item, onDeepDive: { choosing = item.id },
                                     onSignal: { s in Task { await signal(item.id, s) } })
                    }
                    .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.card")
                }
                if !handled.isEmpty { rest }
                if !waiting.isEmpty {
                    SectionLabel(L("today.waiting", waiting.count))
                    ForEach(waiting) { item in
                        NavigationLink(value: item.id) { WaitingRow(item: item) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await load() }
        .padding(.top, 1)   // keeps scrolled content from running under the clock
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { id in ItemDetailView(itemId: id, onChange: { Task { await load() } }) }
        .modifier(DeepDiveChoice(itemId: $choosing, onQueue: { id in Task { await queue(id) } }, onStart: { diving = DeepDiveTarget(itemId: $0) }))
        .sheet(item: $diving) { DeepDiveSheet(itemId: $0.itemId).environmentObject(model) }
        .task { await load() }
    }

    @ViewBuilder private var queueLines: some View {
        if model.queuedCount > 0 {
            DotLabel(kind: .greyRing, text: L("today.queued", model.queuedCount))
        }
        ForEach(Array(model.saveFailures.enumerated()), id: \.offset) { i, sentence in
            HStack(alignment: .firstTextBaseline) {
                DotLabel(kind: .danger, text: sentence, color: Theme.danger)
                Spacer()
                Button(L("action.dismiss")) { model.saveFailures.remove(at: i) }.buttonStyle(TextLink())
            }
        }
    }

    private var rest: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { restOpen.toggle() } label: {
                HStack {
                    Text(L("today.rest", handled.count)).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text3)
                    Spacer()
                    Text(restOpen ? "−" : "+").font(Theme.body).foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.rest")
            if restOpen {
                ForEach(handled) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(Theme.secondary).foregroundStyle(Theme.text2).lineLimit(1)
                            Text(handledWord(item)).font(Theme.caption).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                        Button(L("action.restore")) { Task { await restore(item) } }.buttonStyle(TextLink())
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func handledWord(_ item: Item) -> String {
        if item.inQueue == true { return L("term.queue") }
        return item.signal == .notInterested ? L("action.not_interested") : L("action.seen")
    }

    private func load() async {
        if let page = await model.run({ try await model.client.listItems(state: "today") }) { items = page.items }
        if let m = await model.run(quiet: true, { try await model.client.getCalendar() }) { month = m }
        loaded = true
        await model.refreshStatus()
        await model.refreshDigestDot()
        model.queuedCount = model.store.queue.count
    }

    private func signal(_ id: String, _ s: Signal) async {
        guard await model.run({ try await model.client.setSignal(id: id, signal: s) }) != nil else { return }
        model.say(s == .notInterested ? L("said.not_interested") : L("said.seen"))
        await load()
    }

    private func queue(_ id: String) async {
        guard await model.run({ try await model.client.addToQueue(itemId: id) }) != nil else { return }
        model.say(L("said.queued"))
        await load()
    }

    private func restore(_ item: Item) async {
        let ok: Void? = await model.run {
            if item.inQueue == true { try await model.client.removeFromQueue(itemId: item.id) }
            if item.signal != nil { try await model.client.clearSignal(id: item.id) }
        }
        if ok != nil { await load() }
    }
}

/// One analysis: the four fixed fields in their order, the related hint when there is one, the three
/// actions, and the original link in the corner.
struct AnalysisCard: View {
    @Environment(\.openURL) private var openURL
    let item: Item
    let onDeepDive: () -> Void
    let onSignal: (Signal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ItemMeta.line(item)).font(Theme.caption).foregroundStyle(Theme.text3).lineLimit(1)
                Spacer()
                if let s = item.url, let url = URL(string: s) {
                    Button(L("term.original")) { openURL(url) }.buttonStyle(TextLink())
                }
            }
            NavigationLink(value: item.id) {
                Text(item.title).font(Theme.item).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if let a = item.analysis {
                AnalysisFields(analysis: a)
                if !a.unavailable {
                    HStack(spacing: 8) {
                        Button(L("term.deep_dive"), action: onDeepDive).buttonStyle(SolidButton(small: true))
                            .accessibilityIdentifier("action.deepdive")
                        Button(L("action.not_interested")) { onSignal(.notInterested) }.buttonStyle(QuietButton(small: true))
                            .accessibilityIdentifier("action.not_interested")
                        Button(L("action.seen")) { onSignal(.seen) }.buttonStyle(QuietButton(small: true))
                            .accessibilityIdentifier("action.seen")
                    }
                    .padding(.top, 2)
                } else {
                    Button(L("action.seen")) { onSignal(.seen) }.buttonStyle(QuietButton(small: true))
                        .accessibilityIdentifier("action.seen")
                }
                Text(a.assistant.name).font(Theme.caption).foregroundStyle(Theme.text3)
            }
        }
        .card()
    }
}

/// The four fields. When the content could not be fetched there is only the first, saying so.
struct AnalysisFields: View {
    let analysis: Analysis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if analysis.unavailable {
                DotLabel(kind: .greyRing, text: L("term.unavailable"), font: Theme.body)
            } else {
                if let s = analysis.summary { field(L("field.summary")) { Text(s).font(Theme.body) } }
                if let k = analysis.keyFact, !k.isEmpty { field(L("field.key_fact")) { Text(k).font(Theme.body).foregroundStyle(Theme.text2) } }
                if let points = analysis.points, !points.isEmpty {
                    field(L("field.points")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Rectangle().fill(Theme.text3).frame(width: 4, height: 4).offset(y: -3)
                                    Text(p).font(Theme.body)
                                }
                            }
                        }
                    }
                }
                if let v = analysis.verdict { field(L("field.verdict")) { VerdictLabel(verdict: v) } }
                if let hint = analysis.relatedHint, !hint.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("field.related")).font(Theme.caption).foregroundStyle(Theme.text3)
                        Text(hint).font(Theme.secondary).foregroundStyle(Theme.text2)
                    }
                    .quietBox(padding: 10)
                }
            }
        }
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.text3)
            value()
        }
    }
}

enum ItemMeta {
    /// The source site's name and when it was saved. Never the address.
    static func line(_ item: Item) -> String {
        [item.site, KeepDates.time(item.createdAt)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// An item no assistant has analysed yet: lighter than a card.
struct WaitingRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IncomingShapes(filled: item.stage == "triaged").padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Theme.body).foregroundStyle(Theme.text2).lineLimit(2).multilineTextAlignment(.leading)
                Text(ItemMeta.line(item)).font(Theme.caption).foregroundStyle(Theme.text3)
                if item.contentUnavailable == true {
                    Text(L("term.unavailable")).font(Theme.caption).foregroundStyle(Theme.text3)
                }
                if item.stage == "triaged", let second = triaged {
                    Text(second).font(Theme.caption).foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var triaged: String? {
        let parts = [item.dispatchTo?.name, item.pinned == true ? L("item.never_deleted") : Retention.daysLeft(of: item).map { L("item.days_left", $0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One item: the original, the analysis, the tags; who analyses it and how long it is kept; keep and delete.
struct ItemDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let itemId: String
    var onChange: () -> Void = {}
    @State private var item: Item?
    @State private var assistants: [Assistant] = []
    @State private var expiryOptions: [Int] = []
    @State private var imageURL: URL?
    @State private var confirmDelete = false
    /// What this page itself has chosen since it was opened. The core does not say who set a
    /// value, so this is all the page knows for certain about an item that is sorted (QA #32).
    @State private var choseRetention = false
    @State private var choseAssistant = false

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ItemMeta.line(item)).font(Theme.caption).foregroundStyle(Theme.text3)
                    Text(item.title).font(Theme.subtitle)
                    original(item)
                    if let a = item.analysis {
                        SectionLabel(L("term.analysis") + " · " + a.assistant.name)
                        AnalysisFields(analysis: a).card()
                    }
                    handling(item)
                    if let note = handlingNote(item) {
                        Text(note).font(Theme.caption).foregroundStyle(Theme.text3).accessibilityIdentifier("item.handling_note")
                    }
                    // A kept item shows no `expiry:N` tag: header, control and tags agree.
                    if case let tags = Retention.visibleTags(of: item), !tags.isEmpty {
                        Text(tags.joined(separator: "  ")).font(.system(size: Theme.Size.caption, design: .monospaced)).foregroundStyle(Theme.text3)
                    }
                    if model.isManager {
                        Button(L("action.delete")) { confirmDelete = true }
                            .buttonStyle(QuietButton(small: true, danger: true))
                            .padding(.top, 8)
                            .accessibilityIdentifier("item.delete")
                    }
                }
                .padding(16)
            } else {
                ProgressView().padding(40)
            }
        }
        .page()
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("item.delete.confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("action.delete"), role: .destructive) { Task { await delete() } }
        }
        .task { await load() }
    }

    @ViewBuilder private func original(_ item: Item) -> some View {
        SectionLabel(L("term.original"))
        VStack(alignment: .leading, spacing: 10) {
            if let s = item.url, let url = URL(string: s) {
                Button(item.site ?? url.host ?? L("term.original")) { openURL(url) }.buttonStyle(TextLink())
            }
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag))
                } placeholder: {
                    Rectangle().fill(Theme.quiet).frame(height: 120)
                }
            }
            if item.contentUnavailable == true {
                DotLabel(kind: .greyRing, text: L("term.unavailable"))
            } else if let body = item.body, !body.isEmpty {
                Text(body).font(Theme.body).foregroundStyle(Theme.text2).lineLimit(40).textSelection(.enabled)
            }
        }
        .card()
    }

    @ViewBuilder private func handling(_ item: Item) -> some View {
        VStack(spacing: 0) {
            row(L("item.analysed_by")) {
                // An item always has an assistant once it is dispatched: there is no "nobody" to pick.
                let current = item.dispatchTo?.name ?? item.analysis?.assistant.name ?? L("item.not_assigned")
                let list = Analysers.candidates(assistants, current: item.dispatchTo)
                if model.isManager && !list.isEmpty {
                    Menu {
                        ForEach(list, id: \.id) { a in
                            Button(a.name ?? "") { Task { if let id = a.id { await update(dispatchTo: id) } } }
                        }
                    } label: { Text(current).underline() }
                    .accessibilityIdentifier("item.analysed_by")
                } else {
                    Text(current)
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            // One control for how long it is kept: the user's options, then "Never delete" last.
            row(L("item.kept_for")) {
                if model.isManager && !expiryOptions.isEmpty {
                    Menu {
                        ForEach(Array(Retention.choices(options: expiryOptions).enumerated()), id: \.offset) { _, choice in
                            Button(choiceText(choice)) { Task { await choose(choice) } }
                        }
                    } label: { Text(keptText(item)).underline() }
                    .accessibilityIdentifier("item.kept_for")
                } else {
                    Text(keptText(item))
                }
            }
            if !(model.isManager && !expiryOptions.isEmpty) {
                // Without the options (not a manager), the one change left is named for what it does.
                Rectangle().fill(Theme.line).frame(height: 1)
                row("") {
                    Button(item.pinned == true ? L("item.end_date") : L("item.never_delete")) {
                        Task { await item.pinned == true ? endDate() : choose(.never) }
                    }
                    .buttonStyle(QuietButton(small: true))
                    .accessibilityIdentifier("item.never_delete")
                }
            }
        }
        .font(Theme.body)
        .card(padding: 0)
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.text2)
            Spacer()
            value()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func choiceText(_ choice: Retention) -> String {
        switch choice {
        case .days(let d): return L("item.days", d)
        case .never: return L("item.never_delete")
        }
    }

    /// Under the two controls (QA #32): before sorting, that nothing is decided yet; after it,
    /// who set the values the user has not chosen here.
    private func handlingNote(_ item: Item) -> String? {
        if !Retention.decided(item) { return L("item.undecided_hint", Retention.placeholderDays) }
        guard item.stage != "saved" else { return nil }
        let retention = item.pinned != true && !choseRetention
        let assistant = item.dispatchTo != nil && !choseAssistant
        return retention || assistant ? L("item.set_by_sorting") : nil
    }

    private func keptText(_ item: Item) -> String {
        if item.pinned == true { return L("item.never_deleted") }
        // Not sorted yet and not chosen: a state, not a number of days.
        if !Retention.decided(item) { return L("item.decided_when_sorted") }
        if let left = item.daysLeft { return L("item.days_left", left) }
        if let days = item.expiryDays { return L("item.days", days) }
        return "—"
    }

    private func load() async {
        guard let it = await model.run({ try await model.client.getItem(id: itemId) }) else { return }
        item = it
        if let page = await model.run(quiet: true, { try await model.client.listAssistants() }) { assistants = page.assistants }
        if let s = await model.run(quiet: true, { try await model.client.getSettings() }) { expiryOptions = s.expiryOptions }
        if let asset = it.assetId, it.kind == "image",
           let loc = await model.run(quiet: true, { try await model.client.getAsset(id: asset) }) {
            imageURL = URL(string: loc.downloadUrl, relativeTo: model.client.baseURL)?.absoluteURL
        }
    }

    private func update(dispatchTo: String) async {
        if await model.run({ try await model.client.updateItem(id: itemId, dispatchTo: dispatchTo) }) != nil {
            choseAssistant = true
            await reload()
            model.say(L("item.said.changed"))
        }
    }

    /// Days give the item an end date (the core takes a kept item out of "never deleted" itself; an
    /// older core needs the unpin first). "Never delete" keeps it without one.
    private func choose(_ choice: Retention) async {
        let wasPinned = item?.pinned == true
        let ok: Void? = await model.run {
            switch choice {
            case .never:
                try await model.client.pinItem(id: itemId)
            case .days(let d):
                let after = try await model.client.updateItem(id: itemId, expiryDays: d)
                if wasPinned && after.pinned == true {
                    try await model.client.unpinItem(id: itemId)
                    _ = try await model.client.updateItem(id: itemId, expiryDays: d)
                }
            }
        }
        if ok != nil {
            choseRetention = true
            await reload(sayRetention: true)
        }
    }

    private func endDate() async {
        if await model.run({ try await model.client.unpinItem(id: itemId) }) != nil {
            choseRetention = true
            await reload(sayRetention: true)
        }
    }

    /// After a change everything shown comes from the core again, and one sentence says what is now true.
    private func reload(sayRetention: Bool = false) async {
        if let it = await model.run({ try await model.client.getItem(id: itemId) }) {
            item = it
            if sayRetention {
                let s = Retention.sentence(for: it)
                if let days = s.days, let date = s.date { model.say(L(s.key, days, date)) } else { model.say(L(s.key)) }
            }
        }
        onChange()
    }

    private func delete() async {
        if await model.run({ try await model.client.deleteItem(id: itemId) }) != nil {
            onChange()
            dismiss()
        }
    }
}
