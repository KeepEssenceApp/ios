import SwiftUI
import KeepCore

// MARK: surfaces

extension View {
    /// A card: only things that can be pressed or that hold content get a fill and a border.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(Theme.shape(.card))
            .overlay(Theme.shape(.card).stroke(Theme.line, lineWidth: 1))
    }

    func quietBox(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quiet)
            .clipShape(Theme.shape(.quietBox))
    }

    func page() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .tint(Theme.text)
    }
}

/// A small heading above a group.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.secondary.weight(.semibold))
            .foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// The one sentence a page shows when it has nothing to list. No illustration.
struct Sentence: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }
}

// MARK: buttons

struct SolidButton: ButtonStyle {
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? Theme.secondary.weight(.semibold) : Theme.bodyStrong)
            .foregroundStyle(Theme.onSolid)
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 8 : 12)
            .background(Theme.solid)
            .clipShape(Theme.shape(.solidButton))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct QuietButton: ButtonStyle {
    var small = false
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? Theme.secondary.weight(.semibold) : Theme.bodyStrong)
            .foregroundStyle(danger ? Theme.danger : Theme.text)
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 8 : 12)
            .background(Theme.card)
            .clipShape(Theme.shape(.quietButton))
            .overlay(Theme.shape(.quietButton).stroke(danger ? Theme.danger : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Words that can be pressed, underlined, without a fill.
struct TextLink: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.secondary)
            .foregroundStyle(Theme.text2)
            .underline()
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct KEField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        TextField(title, text: $text)
            .font(Theme.body)
            .padding(12)
            .background(Theme.card)
            .clipShape(Theme.shape(.field))
            .overlay(Theme.shape(.field).stroke(Theme.line, lineWidth: 1))
    }
}

// MARK: dots. A state is a dot plus words, never a chip.

enum DotKind { case solid, ring, greyRing, gold, goldRing, danger, tiny }

struct Dot: View {
    let kind: DotKind
    var size: CGFloat = 8
    var body: some View {
        Group {
            switch kind {
            case .solid: Circle().fill(Theme.text)
            case .ring: Circle().strokeBorder(Theme.text, lineWidth: 1.5)
            case .greyRing: Circle().strokeBorder(Theme.text3, lineWidth: 1.5)
            case .gold: Circle().fill(Theme.gold)
            case .goldRing: Circle().strokeBorder(Theme.gold, lineWidth: 2)
            case .danger: Circle().fill(Theme.danger)
            case .tiny: Circle().fill(Theme.text3).padding(size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DotLabel: View {
    let kind: DotKind
    let text: String
    var font: Font = Theme.secondary
    var color: Color = Theme.text2
    var body: some View {
        HStack(spacing: 6) {
            Dot(kind: kind)
            Text(text).font(font).foregroundStyle(color)
        }
    }
}

struct VerdictLabel: View {
    let verdict: Verdict
    var body: some View {
        switch verdict {
        case .worthDeepDive: DotLabel(kind: .goldRing, text: L("verdict.worth"), font: Theme.secondary.weight(.semibold), color: Theme.text)
        case .goodToKnow: DotLabel(kind: .solid, text: L("verdict.good"), color: Theme.text)
        case .skippable: DotLabel(kind: .greyRing, text: L("verdict.skip"))
        }
    }
}

/// The three shapes of the logo: what came in and is not processed yet. Hollow while it waits to be
/// dispatched, solid while it waits to be analysed.
struct IncomingShapes: View {
    let filled: Bool
    var body: some View {
        HStack(spacing: 2) {
            shape(Triangle())
            shape(Rectangle())
            shape(Circle())
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func shape<S: Shape>(_ s: S) -> some View {
        if filled { s.fill(Theme.text3).frame(width: 7, height: 7) }
        else { s.stroke(Theme.text3, lineWidth: 1).frame(width: 7, height: 7) }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: calendar

/// One month as dots, seven to a row by date. `faint` is the background version on Today.
struct CalendarDots: View {
    let month: CalendarMonth
    var cell: CGFloat = 16
    var gap: CGFloat = 8
    var numbers = false
    var onDay: ((CalendarCell) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(CalendarLayout.rows(month).enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    ForEach(row) { c in
                        dayView(c)
                    }
                }
            }
        }
        .accessibilityElement(children: onDay == nil ? .ignore : .contain)
        .accessibilityLabel(L("calendar"))
    }

    @ViewBuilder private func dayView(_ c: CalendarCell) -> some View {
        let dot = VStack(spacing: 3) {
            dayDot(c.dot)
                .frame(width: cell, height: cell)
                .overlay {
                    if c.isToday { Rectangle().stroke(Theme.text, lineWidth: 1).frame(width: cell + 6, height: cell + 6) }
                }
            if numbers {
                Text("\(c.number)").font(Theme.caption).foregroundStyle(c.opensDigest ? Theme.text : Theme.text3)
            }
        }
        .frame(width: cell + 6)
        if let onDay, c.opensDigest {
            Button { onDay(c) } label: { dot }
                .buttonStyle(.plain)
                .accessibilityLabel(KeepDates.dayTitle(c.day))
        } else {
            dot
        }
    }

    @ViewBuilder private func dayDot(_ d: DayDot) -> some View {
        switch d {
        case .empty: Circle().fill(Theme.text3).frame(width: cell * 0.25, height: cell * 0.25)
        case .saved: Circle().strokeBorder(Theme.text3, lineWidth: 1.5).padding(cell * 0.12)
        case .digestUnread: Circle().strokeBorder(Theme.text, lineWidth: 1.5).padding(cell * 0.12)
        case .digestRead: Circle().fill(Theme.text).padding(cell * 0.12)
        case .note: Circle().fill(Theme.gold).padding(cell * 0.12)
        }
    }
}

struct CalendarCounts: View {
    let counts: CalendarMonth.Counts
    var body: some View {
        Text(L("calendar.counts", counts.saved, counts.digests, counts.read, counts.notes))
            .font(Theme.secondary)
            .foregroundStyle(Theme.text2)
    }
}

// MARK: swipe. Right adds to the deep-dive queue, left marks not interested. "Seen" has no swipe.

struct SwipeRow<Content: View>: View {
    let onRight: () -> Void
    let onLeft: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 96

    var body: some View {
        ZStack {
            HStack {
                Text(L("action.queue")).font(Theme.secondary.weight(.semibold)).opacity(offset > 12 ? 1 : 0)
                Spacer()
                Text(L("action.not_interested")).font(Theme.secondary.weight(.semibold)).opacity(offset < -12 ? 1 : 0)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.quiet)
            .clipShape(Theme.shape(.swipeBackground))
            .accessibilityHidden(true)

            content().offset(x: offset)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { g in
                    guard abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                    offset = g.translation.width
                }
                .onEnded { g in
                    let dx = g.translation.width
                    let horizontal = abs(dx) > abs(g.translation.height) * 1.5
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    guard horizontal else { return }
                    if dx > threshold { onRight() } else if dx < -threshold { onLeft() }
                }
        )
    }
}

// MARK: the status bar

extension Status {
    /// Assistants that hold a claim now or came within a day.
    var activeCount: Int { assistants.filter { $0.state == "working" || $0.state == "recent" }.count }

    var dot: DotKind {
        if activeCount > 0 { return .solid }
        return waiting > 0 ? .danger : .greyRing
    }

    var lastSeen: (name: String, at: Date)? {
        assistants.compactMap { a in a.lastSeenAt.map { (a.name, $0) } }.max { $0.1 < $1.1 }
    }

    var headline: String {
        activeCount > 0 ? L("status.working", activeCount) : L("status.none_working")
    }

    var countsLine: String { L("status.counts", savedToday, waiting) }
}

/// The narrow layout: one line of words in the header. Used on Today.
struct StatusLine: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let s = model.status {
            Button { model.statusExpanded = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Dot(kind: s.dot)
                    Text(line(s))
                        .font(Theme.secondary)
                        .foregroundStyle(s.dot == .danger ? Theme.danger : Theme.text2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("status.line")
        }
    }

    private func line(_ s: Status) -> String {
        var parts = [s.headline]
        if let last = s.lastSeen { parts.append(L("status.last_seen", last.name, KeepDates.ago(last.at))) }
        parts.append(s.countsLine)
        return parts.joined(separator: " · ")
    }
}

/// The narrowest layout: the number of assistants and a state dot. Pressing it opens the full status.
struct StatusMark: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let s = model.status {
            Button { model.statusExpanded = true } label: {
                HStack(spacing: 5) {
                    Text("\(s.assistants.count)").font(Theme.secondary.weight(.semibold)).monospacedDigit()
                    Dot(kind: s.dot)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Theme.shape(.statusMark).stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.headline)
            .accessibilityIdentifier("status.mark")
        }
    }
}

/// The status in full: one row per assistant, the counts, and why there is no digest today.
struct StatusSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = model.status {
                    Text(s.headline).font(Theme.subtitle)
                    ForEach(s.assistants) { a in
                        HStack(alignment: .firstTextBaseline) {
                            Dot(kind: a.state == "working" || a.state == "recent" ? .solid : .greyRing)
                            Text(a.name).font(Theme.bodyStrong)
                            Spacer()
                            Text(stateText(a)).font(Theme.secondary).foregroundStyle(Theme.text2)
                        }
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text(s.countsLine).font(Theme.body)
                    if s.waiting > 0, let day = s.oldestWaitingDeletedOn {
                        Text(L("status.oldest_deleted", KeepDates.dayTitle(day)))
                            .font(Theme.secondary)
                            .foregroundStyle(s.activeCount == 0 ? Theme.danger : Theme.text2)
                    }
                    if let reason = s.noDigestReason, let text = reasonText(reason) {
                        Text(text).font(Theme.secondary).foregroundStyle(Theme.text2)
                    }
                    if model.isManager {
                        Button(L("tab.assistants")) {
                            dismiss()
                            model.tab = .assistants
                        }
                        .buttonStyle(QuietButton(small: true))
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
        }
        .page()
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task { await model.refreshStatus() }
    }

    private func stateText(_ a: Status.AssistantState) -> String {
        switch a.state {
        case "working": return L("status.state.working")
        case "never": return L("status.state.never")
        default: return a.lastSeenAt.map { L("status.state.came", KeepDates.ago($0)) } ?? L("status.state.never")
        }
    }

    private func reasonText(_ r: String) -> String? {
        switch r {
        case "not_yet_time": return L("status.no_digest.not_yet_time")
        case "nothing_analysed": return L("status.no_digest.nothing_analysed")
        case "no_assistant": return L("status.no_digest.no_assistant")
        case "waiting_for_assistant": return L("status.no_digest.waiting")
        default: return nil
        }
    }
}

// MARK: page header

/// The title of a main page with the status bar: the narrow line under the title on Today, the
/// narrowest mark beside it elsewhere.
struct PageHeader: View {
    let title: String
    var narrow = false
    /// Today only: the month, faint, top right, where it covers no words.
    var month: CalendarMonth?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title).font(Theme.title).accessibilityAddTraits(.isHeader)
                Spacer()
                if !narrow { StatusMark() }
                if let month {
                    CalendarDots(month: month, cell: 6, gap: 4).opacity(0.45).frame(height: 44).allowsHitTesting(false)
                }
            }
            if narrow { StatusLine() }
        }
    }
}

// MARK: deep dive

/// What "deep dive" on an analysis or a digest line asks: queue it for a deep read first, or go now.
struct DeepDiveChoice: ViewModifier {
    @Binding var itemId: String?
    let onQueue: (String) -> Void
    let onStart: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(L("term.deep_dive"), isPresented: Binding(get: { itemId != nil }, set: { if !$0 { itemId = nil } }), titleVisibility: .visible) {
            Button(L("action.queue")) { if let id = itemId { onQueue(id) } }
            Button(L("action.start_deep_dive")) { if let id = itemId { onStart(id) } }
        }
    }
}

struct DeepDiveTarget: Identifiable {
    let itemId: String
    var id: String { itemId }
}

/// How to get to the assistant: the opening line to copy, and a way to open the assistant when there is one.
struct DeepDiveSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    let itemId: String
    @State private var entry: DeepDiveEntry?
    @State private var assistants: [Assistant] = []
    @State private var failed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("action.start_deep_dive")).font(Theme.subtitle)
                if let entry {
                    HStack {
                        Text(L("term.assistant")).font(Theme.secondary).foregroundStyle(Theme.text3)
                        Spacer()
                        if assistants.count > 1 {
                            Menu {
                                ForEach(assistants) { a in
                                    Button(a.name) { Task { await load(a.id) } }
                                }
                            } label: {
                                Text(entry.assistant.name).font(Theme.bodyStrong).underline()
                            }
                        } else {
                            Text(entry.assistant.name).font(Theme.bodyStrong)
                        }
                    }
                    Text(entry.openingLine)
                        .font(Theme.body)
                        .textSelection(.enabled)
                        .quietBox()
                        .accessibilityIdentifier("deepdive.opening")
                    if let text = entry.entry, URL(string: text)?.scheme == nil {
                        Text(text).font(Theme.secondary).foregroundStyle(Theme.text2).textSelection(.enabled)
                    }
                    HStack(spacing: 8) {
                        Button(L("action.copy")) {
                            UIPasteboard.general.string = entry.openingLine
                            model.say(L("said.copied"))
                        }
                        .buttonStyle(SolidButton())
                        if let url = target(entry) {
                            Button(L("action.open")) { openURL(url) }.buttonStyle(QuietButton())
                        }
                    }
                    Text(L("deepdive.note")).font(Theme.caption).foregroundStyle(Theme.text3)
                } else if let failed {
                    Text(failed).font(Theme.body).foregroundStyle(Theme.text2)
                } else {
                    ProgressView()
                }
            }
            .padding(20)
        }
        .page()
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task {
            await load(nil)
            if let page = await model.run(quiet: true, { try await model.client.listAssistants() }) {
                assistants = page.assistants.filter { $0.steps.contains(.deepDive) }
            }
        }
    }

    private func target(_ e: DeepDiveEntry) -> URL? {
        for s in [e.openUrl, e.entry] {
            if let s, let u = URL(string: s), let scheme = u.scheme, ["https", "http"].contains(scheme) { return u }
        }
        return nil
    }

    private func load(_ assistantId: String?) async {
        do {
            entry = try await model.client.startDeepDive(itemId: itemId, assistantId: assistantId)
            failed = nil
        } catch {
            if entry == nil { failed = model.message(for: error) } else { model.say(model.message(for: error)) }
        }
    }
}

// MARK: the notice

struct NoticeBar: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.secondary.weight(.semibold))
            .foregroundStyle(Theme.onSolid)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.solid)
            .clipShape(Theme.shape(.notice))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("notice")
    }
}

/// The brand's mark, from its own files: white on dark, black on light, one gold dot. `size` is its
/// height. Under 28 points the brand asks for the small variant, which this app does not carry.
struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme
    var forceDark = false
    var size: CGFloat = 48
    var body: some View {
        Image(forceDark || scheme == .dark ? "MarkOnDark" : "MarkOnLight")
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .accessibilityHidden(true)
    }
}

/// The name beside the mark is always text: weight 700, letter-spacing 0.04em. English with a
/// space, and the Chinese name beneath.
struct BrandName: View {
    var size: CGFloat = Theme.Size.display
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Keep Essence").font(.system(size: size, weight: .bold)).tracking(size * 0.04)
                .foregroundStyle(Theme.white)
            Text(verbatim: "精华").font(.system(size: Theme.Size.body, weight: .bold)).tracking(Theme.Size.body * 0.04)
                .foregroundStyle(Theme.paper.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keep Essence")
    }
}
