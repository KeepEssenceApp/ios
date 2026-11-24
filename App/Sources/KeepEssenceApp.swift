import SwiftUI
import KeepCore

@main
struct KeepEssenceApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refreshAfterForeground() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.phase {
        case .launching:
            ZStack {
                Theme.black.ignoresSafeArea()
                BrandMark(forceDark: true, size: 72)
            }
        case .signedOut:
            SignInView()
        case .signedIn:
            if model.tier == .save { SaveOnlyView() } else { MainView() }
        }
    }
}

/// Four entries in a fixed order. A read-tier device does not get the last one. An unread digest
/// puts one dot on its entry; there are no numbers anywhere.
struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Group {
                    switch model.tab {
                    case .today: NavigationStack { TodayView() }
                    case .digest: NavigationStack { DigestView() }
                    case .notes: NavigationStack { NotesView() }
                    case .assistants: NavigationStack { AssistantsView() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let notice = model.notice {
                    NoticeBar(text: notice).transition(.opacity)
                }
            }
            TabBar()
        }
        .page()
        .animation(.easeOut(duration: 0.15), value: model.notice)
        .sheet(isPresented: $model.statusExpanded) { StatusSheet().environmentObject(model) }
    }
}

struct TabBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.tabs, id: \.self) { tab in
                Button { model.tab = tab } label: { label(tab) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func title(_ tab: AppTab) -> String {
        switch tab {
        case .today: return L("tab.today")
        case .digest: return L("tab.digest")
        case .notes: return L("tab.notes")
        case .assistants: return L("tab.assistants")
        }
    }

    private func label(_ tab: AppTab) -> some View {
        let on = model.tab == tab
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                TabGlyph(tab: tab, on: on).frame(width: 20, height: 20)
                if tab == .digest && model.digestUnread {
                    Circle().fill(Theme.gold).frame(width: 8, height: 8).offset(x: 7, y: -4)
                        .accessibilityIdentifier("tab.digest.dot")
                        .accessibilityLabel(L("digest.unread"))
                }
            }
            Text(title(tab)).font(.system(size: 11, weight: on ? .semibold : .regular))
        }
        .foregroundStyle(on ? Theme.text : Theme.text3)
        .frame(maxWidth: .infinity)
        .padding(.top, 9)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}

/// Glyphs drawn from the shapes of the logo, with square line ends: a square for today, lines that
/// get shorter for the digest, a circle for what was kept, a triangle for the assistants.
struct TabGlyph: View {
    let tab: AppTab
    let on: Bool

    var body: some View {
        let style = StrokeStyle(lineWidth: on ? 2.2 : 1.6, lineCap: .butt, lineJoin: .miter)
        switch tab {
        case .today:
            Rectangle().stroke(style: style).padding(2)
        case .digest:
            GeometryReader { g in
                Path { p in
                    let w = g.size.width, h = g.size.height
                    for (i, len) in [1.0, 0.72, 0.44].enumerated() {
                        let y = h * (0.2 + 0.3 * Double(i))
                        p.move(to: CGPoint(x: 1, y: y))
                        p.addLine(to: CGPoint(x: 1 + (w - 2) * len, y: y))
                    }
                }
                .stroke(style: style)
            }
        case .notes:
            Circle().stroke(style: style).padding(2)
        case .assistants:
            Triangle().stroke(style: style).padding(2)
        }
    }
}

/// A device lowered to the save tier sees no content: only that it can save, and the way out.
struct SaveOnlyView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandMark(size: 48)
            Text(L("saveonly.sentence")).font(Theme.body).foregroundStyle(Theme.text2)
            Button(L("account.sign_out")) { Task { _ = await model.signOut() } }.buttonStyle(QuietButton())
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .page()
    }
}
