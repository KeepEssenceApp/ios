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
/// puts one gold dot on its entry; the selected entry has a short gold line above its icon. There
/// are no numbers anywhere.
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
        // Selected: the main text colour, a bolder label and one short gold line above the icon.
        return VStack(spacing: 4) {
            Capsule().fill(on ? Theme.gold : Color.clear).frame(width: 18, height: 3)
                .accessibilityHidden(true)
            ZStack(alignment: .topTrailing) {
                TabGlyph(tab: tab).frame(width: 24, height: 24)
                if tab == .digest && model.digestUnread {
                    Circle().fill(Theme.gold).frame(width: 8, height: 8).offset(x: 5, y: -2)
                        .accessibilityIdentifier("tab.digest.dot")
                        .accessibilityLabel(L("digest.unread"))
                }
            }
            Text(title(tab)).font(.system(size: 11, weight: on ? .semibold : .regular))
        }
        .foregroundStyle(on ? Theme.text : Theme.text3)
        .frame(maxWidth: .infinity)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}

/// The brand's four tab icons (24×24, stroke 1.8), template-rendered so they take the label's colour.
struct TabGlyph: View {
    let tab: AppTab

    var body: some View {
        Image(name).renderingMode(.template).resizable().scaledToFit()
    }

    private var name: String {
        switch tab {
        case .today: return "TabToday"
        case .digest: return "TabDigest"
        case .notes: return "TabNotes"
        case .assistants: return "TabAssistants"
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
