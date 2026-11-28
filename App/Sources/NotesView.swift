import SwiftUI
import UniformTypeIdentifiers
import KeepCore

/// Notes: quick find on top (notes only), the deep-dive queue, the notes newest first, and this
/// month's calendar at the bottom.
struct NotesView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var notes: [NoteSummary] = []
    @State private var queue: [QueueEntry] = []
    @State private var month: CalendarMonth?
    @State private var loaded = false
    @State private var report: QueueEntry?
    @State private var diving: DeepDiveTarget?
    @State private var pasting: QueueEntry?
    @State private var showCalendar = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: L("tab.notes"))
                KEField(title: L("notes.find"), text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("notes.find")
                if query.isEmpty && !queue.isEmpty {
                    SectionLabel(L("term.queue"))
                    ForEach(queue) { e in queueCard(e) }
                }
                if query.isEmpty { SectionLabel(L("tab.notes")) }
                if loaded && notes.isEmpty {
                    Sentence(query.isEmpty ? L("notes.none") : L("notes.find.none"))
                }
                ForEach(notes) { n in
                    NavigationLink(value: n.id) { noteRow(n) }.buttonStyle(.plain)
                }
                if query.isEmpty, let month {
                    Button { showCalendar = true } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(KeepDates.monthTitle(month.month)).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text3)
                            CalendarDots(month: month, cell: 16, gap: 10)
                            CalendarCounts(counts: month.counts)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .accessibilityIdentifier("notes.calendar")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await load() }
        .scrollDismissesKeyboard(.interactively)
        .padding(.top, 1)   // keeps scrolled content from running under the clock
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { NoteView(noteId: $0) }
        .sheet(item: $report) { DeepReadSheet(entry: $0) }
        .sheet(item: $diving, onDismiss: { Task { await load() } }) { DeepDiveSheet(itemId: $0.itemId).environmentObject(model) }
        .sheet(item: $pasting) { e in PasteSheet(entry: e, onSaved: { Task { await load() } }).environmentObject(model) }
        .sheet(isPresented: $showCalendar) { CalendarSheet(start: month).environmentObject(model) }
        .task { await load() }
        .task(id: query) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { await find() }
        }
    }

    private func noteRow(_ n: NoteSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Dot(kind: .gold).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(n.title).font(Theme.item).multilineTextAlignment(.leading)
                if let e = n.excerpt, !e.isEmpty {
                    Text(e).font(Theme.secondary).foregroundStyle(Theme.text2).lineLimit(2).multilineTextAlignment(.leading)
                }
                Text(KeepDates.time(n.createdAt)).font(Theme.caption).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func queueCard(_ e: QueueEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(e.title).font(Theme.item)
            deepReadState(e)
            if let went = e.wentAt {
                Text(L("queue.went", KeepDates.ago(went))).font(Theme.caption).foregroundStyle(Theme.text3)
            }
            FlowButtons {
                if e.report != nil {
                    Button(L("queue.see_deep_read")) { report = e }.buttonStyle(QuietButton(small: true))
                }
                Button(L("action.start_deep_dive")) { diving = DeepDiveTarget(itemId: e.itemId) }.buttonStyle(SolidButton(small: true))
                if e.wentAt != nil {
                    Button(L("queue.paste_back")) { pasting = e }.buttonStyle(QuietButton(small: true))
                }
                Button(L("queue.remove")) { Task { await remove(e) } }.buttonStyle(QuietButton(small: true))
            }
        }
        .card()
        .accessibilityElement(children: .contain)
                .accessibilityIdentifier("queue.card")
    }

    @ViewBuilder private func deepReadState(_ e: QueueEntry) -> some View {
        switch e.deepRead {
        case "waiting": DotLabel(kind: .greyRing, text: L("queue.waiting"))
        case "reading": DotLabel(kind: .ring, text: L("queue.reading"))
        case "ready": DotLabel(kind: .solid, text: L("queue.ready"), color: Theme.text)
        default: DotLabel(kind: .greyRing, text: L("queue.no_assistant"))
        }
    }

    private func load() async {
        if let q = await model.run({ try await model.client.listQueue() }) { queue = q }
        await find()
        if let m = await model.run(quiet: true, { try await model.client.getCalendar() }) { month = m }
        loaded = true
        await model.refreshStatus()
    }

    private func find() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        if let page = await model.run({ try await model.client.listNotes(q: q) }) { notes = page.notes }
    }

    private func remove(_ e: QueueEntry) async {
        if await model.run({ try await model.client.removeFromQueue(itemId: e.itemId) }) != nil { await load() }
    }
}

/// Buttons that wrap onto further lines when they do not fit on one.
struct FlowButtons<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        FlowLayout(spacing: 8) { content() }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in place(subviews, width: bounds.width).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}

/// The deep read an assistant wrote for a queued item: what it says, what else was looked up, what to ask next.
struct DeepReadSheet: View {
    let entry: QueueEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("term.deep_read")).font(Theme.caption).foregroundStyle(Theme.text3)
                Text(entry.title).font(Theme.subtitle)
                if let r = entry.report {
                    if let a = r.assistant { Text(a.name).font(Theme.caption).foregroundStyle(Theme.text3) }
                    SectionLabel(L("deepread.read"))
                    Text(r.read).font(Theme.body).lineSpacing(4).textSelection(.enabled)
                    if !r.found.isEmpty {
                        SectionLabel(L("deepread.found"))
                        Text(r.found).font(Theme.body).lineSpacing(4).textSelection(.enabled)
                    }
                    if !r.questions.isEmpty {
                        SectionLabel(L("deepread.questions"))
                        ForEach(Array(r.questions.enumerated()), id: \.offset) { _, q in
                            Text(q).font(Theme.body).quietBox(padding: 10)
                        }
                    }
                }
            }
            .padding(20)
        }
        .page()
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}

/// Paste back what came out of a deep dive, as a note. Only for when the assistant cannot save it itself.
struct PasteSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: QueueEntry
    let onSaved: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var busy = false
    @State private var key = UUID().uuidString.lowercased()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("queue.paste_back")).font(Theme.subtitle)
                Text(entry.title).font(Theme.secondary).foregroundStyle(Theme.text2)
                KEField(title: L("paste.title"), text: $title).accessibilityIdentifier("paste.title")
                TextEditor(text: $text)
                    .font(Theme.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Theme.card)
                    .clipShape(Theme.shape(.textEditor))
                    .overlay(Theme.shape(.textEditor).stroke(Theme.line, lineWidth: 1))
                    .accessibilityIdentifier("paste.body")
                HStack(spacing: 8) {
                    Button(L("action.paste")) { if let s = UIPasteboard.general.string { text = s } }.buttonStyle(QuietButton())
                    Button(L("action.save")) { Task { await save() } }
                        .buttonStyle(SolidButton())
                        .disabled(busy || title.isEmpty || text.isEmpty)
                        .opacity(title.isEmpty || text.isEmpty ? 0.5 : 1)
                        .accessibilityIdentifier("paste.save")
                }
            }
            .padding(20)
        }
        .page()
        .presentationCornerRadius(Theme.Radius.sheet)
        .onAppear { if title.isEmpty { title = entry.title } }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let request = PasteNoteRequest(title: title, body: text, itemId: entry.itemId, assistantId: entry.wentTo?.id)
        if await model.run({ try await model.client.pasteNote(request, idempotencyKey: key) }) != nil {
            model.say(L("said.saved"))
            onSaved()
            dismiss()
        }
    }
}

/// The large month: dots with their day numbers, the month's counts, and paging. A day with a
/// digest opens that digest; a day without one cannot be pressed.
struct CalendarSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: CalendarMonth?
    @State private var month: CalendarMonth?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let m = month ?? start {
                    HStack {
                        Text(KeepDates.monthTitle(m.month)).font(Theme.subtitle)
                        Spacer()
                        if let p = m.previousMonth {
                            Button("‹") { Task { await load(p) } }.buttonStyle(QuietButton(small: true))
                                .accessibilityLabel(KeepDates.monthTitle(p))
                                .accessibilityIdentifier("calendar.previous")
                        }
                        if let n = m.nextMonth {
                            Button("›") { Task { await load(n) } }.buttonStyle(QuietButton(small: true))
                                .accessibilityLabel(KeepDates.monthTitle(n))
                                .accessibilityIdentifier("calendar.next")
                        }
                    }
                    CalendarDots(month: m, cell: 26, gap: 14, numbers: true) { c in
                        dismiss()
                        model.openDigest(day: c.day)
                    }
                    .frame(maxWidth: .infinity)
                    CalendarCounts(counts: m.counts)
                }
            }
            .padding(20)
        }
        .page()
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private func load(_ m: String) async {
        if let c = await model.run({ try await model.client.getCalendar(month: m) }) { month = c }
    }
}

/// One note: what was kept. It can be shared and downloaded as Markdown.
struct NoteView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    let noteId: String
    @State private var note: Note?
    @State private var markdown: String?
    @State private var exporting = false

    var body: some View {
        ScrollView {
            if let n = note {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Dot(kind: .gold)
                        Text(signature(n)).font(Theme.caption).foregroundStyle(Theme.text3)
                    }
                    Text(n.title).font(Theme.title)
                    MarkdownText(text: n.body)
                    if let o = n.origin, o.itemTitle != nil || o.digestDay != nil {
                        SectionLabel(L("note.origin"))
                        VStack(alignment: .leading, spacing: 4) {
                            if let t = o.itemTitle {
                                if let s = o.itemUrl, let u = URL(string: s) {
                                    Button(t) { openURL(u) }.buttonStyle(TextLink())
                                } else {
                                    Text(t).font(Theme.secondary).foregroundStyle(Theme.text2)
                                }
                            }
                            if let d = o.digestDay {
                                Button(L("tab.digest") + " · " + KeepDates.dayTitle(d)) { model.openDigest(day: d) }.buttonStyle(TextLink())
                            }
                        }
                    }
                    if let sources = n.sources, !sources.isEmpty {
                        SectionLabel(L("note.sources"))
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, s in
                            if let u = s.url.flatMap(URL.init(string:)) {
                                Button(s.title ?? u.host ?? "") { openURL(u) }.buttonStyle(TextLink())
                            } else if let t = s.title {
                                Text(t).font(Theme.secondary).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().padding(40)
            }
        }
        .page()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let n = note, let markdown {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: markdown, subject: Text(n.title)) { Text(L("action.share")) }
                        .accessibilityIdentifier("note.share")
                    Button(L("action.download")) { exporting = true }.accessibilityIdentifier("note.download")
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: MarkdownFile(text: markdown ?? ""), contentType: MarkdownFile.type,
                      defaultFilename: fileName) { _ in }
        .task { await load() }
    }

    private var fileName: String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return (note?.title ?? "note").components(separatedBy: bad).joined(separator: " ")
    }

    private func signature(_ n: Note) -> String {
        var parts = [n.assistant.name, KeepDates.time(n.createdAt)]
        if n.assistant.submittedByUser == true { parts.append(L("note.pasted")) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let n = await model.run({ try await model.client.getNote(id: noteId) }) else { return }
        note = n
        markdown = await model.run(quiet: true) { try await model.client.getNoteMarkdown(id: noteId) } ?? "# \(n.title)\n\n\(n.body)\n"
    }
}

struct MarkdownFile: FileDocument {
    static let type = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [type, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Markdown, block by block: headings, list lines and paragraphs, with inline emphasis and links.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b.kind {
                case .heading(let level):
                    Text(inline(b.text)).font(level <= 1 ? Theme.subtitle : Theme.item).padding(.top, 4)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle().fill(Theme.text3).frame(width: 4, height: 4).offset(y: -3)
                        Text(inline(b.text)).font(Theme.body).lineSpacing(4)
                    }
                case .paragraph:
                    Text(inline(b.text)).font(Theme.body).lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Kind { case heading(Int), bullet, paragraph }
    private struct Block { let kind: Kind; let text: String }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(Block(kind: .paragraph, text: paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                out.append(Block(kind: .heading(level), text: String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                out.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return out
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
