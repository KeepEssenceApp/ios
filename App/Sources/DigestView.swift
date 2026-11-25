import SwiftUI
import KeepCore

/// The daily digest: the latest one first. A counts line, then four parts in a fixed order: the
/// summary, what is worth a deep dive, the rest (collapsed), and a question to sleep on.
struct DigestView: View {
    @EnvironmentObject var model: AppModel
    @State private var digest: DailyDigest?
    @State private var missing = false
    @State private var restOpen = false
    @State private var choosing: String?
    @State private var diving: DeepDiveTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: L("tab.digest"))
                if let d = digest {
                    content(d)
                } else if missing {
                    Sentence(noDigestSentence).accessibilityIdentifier("digest.none")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
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
        .task(id: model.digestDay) { await load() }
    }

    private var noDigestSentence: String {
        // One digest a day, after 21:00 in the user's time zone, when the day has an analysis. The
        // sentence says which of these is missing; nothing is written on request.
        let reason = model.status?.noDigestReason
        let key = DigestEmpty.key(reason: reason)
        return DigestEmpty.namesTime(reason: reason) ? L(key, model.user?.timezone ?? TimeZone.current.identifier) : L(key)
    }

    @ViewBuilder private func content(_ d: DailyDigest) -> some View {
        // Paging to other days.
        HStack {
            if let p = d.previousDay {
                Button("‹ " + KeepDates.dayTitle(p)) { model.digestDay = p }.accessibilityIdentifier("digest.previous")
            }
            Spacer()
            if let n = d.nextDay {
                Button(KeepDates.dayTitle(n) + " ›") { model.digestDay = n }.accessibilityIdentifier("digest.next")
            }
        }
        .buttonStyle(TextLink())

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(KeepDates.dayTitle(d.day)).font(Theme.display)
                if !d.read { Dot(kind: .gold, size: 10).accessibilityLabel(L("digest.unread")) }
            }
            // The head line is a number: how many came in, how many are worth a deep dive.
            Text(L("digest.counts", d.counts?.saved ?? (d.worth.count + d.rest.count), d.counts?.worth ?? d.worth.count))
                .font(Theme.bodyStrong)
            Text(d.assistant.name).font(Theme.caption).foregroundStyle(Theme.text3)
        }

        SectionLabel(L("digest.summary"))
        Text(d.summary).font(Theme.body).foregroundStyle(Theme.text2).lineSpacing(4)

        if !d.worth.isEmpty {
            SectionLabel(L("digest.worth"))
            ForEach(d.worth) { w in
                SwipeRow(onRight: { Task { await queue(w.itemId) } }, onLeft: { Task { await signal(w.itemId, .notInterested) } }) {
                    worthCard(w)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("digest.card")
            }
        }

        if !d.rest.isEmpty { rest(d) }

        SectionLabel(L("digest.question"))
        Text(d.question).font(Theme.subtitle).padding(.bottom, 8)

        if d.read {
            DotLabel(kind: .solid, text: L("digest.read_done")).accessibilityIdentifier("digest.read.done")
        } else {
            Button { Task { await markRead(d) } } label: {
                Text(L("digest.read")).frame(maxWidth: .infinity)
            }
            .buttonStyle(SolidButton())
            .accessibilityIdentifier("digest.read")
        }
    }

    private func worthCard(_ w: DailyDigest.Worth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = w.title, w.available != false {
                NavigationLink(value: w.itemId) {
                    Text(title).font(Theme.item).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else if let title = w.title {
                Text(title).font(Theme.item)
            }
            Text(w.line).font(Theme.body).foregroundStyle(Theme.text2)
            VerdictLabel(verdict: w.verdict ?? .worthDeepDive)
            if w.available != false {
                HStack(spacing: 8) {
                    Button(L("term.deep_dive")) { choosing = w.itemId }.buttonStyle(SolidButton(small: true))
                    Button(L("action.not_interested")) { Task { await signal(w.itemId, .notInterested) } }.buttonStyle(QuietButton(small: true))
                    Button(L("action.seen")) { Task { await signal(w.itemId, .seen) } }.buttonStyle(QuietButton(small: true))
                }
            }
        }
        .card()
    }

    private func rest(_ d: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { restOpen.toggle() } label: {
                HStack {
                    Text(L("digest.rest", d.rest.count)).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text3)
                    Spacer()
                    Text(restOpen ? "−" : "+").font(Theme.body).foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("digest.rest")
            if restOpen {
                ForEach(d.rest) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.title).font(Theme.secondary).foregroundStyle(Theme.text2).lineLimit(1)
                        Spacer()
                        if r.canRestore == true {
                            Button(L("action.restore")) { Task { await restore(r) } }.buttonStyle(TextLink())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func load() async {
        do {
            let d = try await model.client.getDigest(day: model.digestDay ?? "latest")
            digest = d
            missing = false
        } catch let e as APIError where e.status == 404 {
            digest = nil
            missing = true
        } catch {
            _ = await model.run { throw error }
        }
        await model.refreshStatus()
        await model.refreshDigestDot()
    }

    private func markRead(_ d: DailyDigest) async {
        guard await model.run({ try await model.client.markDigestRead(day: d.day) }) != nil else { return }
        await load()
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

    private func restore(_ r: DailyDigest.Rest) async {
        let ok: Void? = await model.run {
            if r.inQueue == true { try await model.client.removeFromQueue(itemId: r.itemId) }
            if r.signal != nil { try await model.client.clearSignal(id: r.itemId) }
        }
        if ok != nil { await load() }
    }
}
