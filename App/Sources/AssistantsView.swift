import SwiftUI
import UIKit
import KeepCore

/// Assistants: the assistants and who does which step, connecting one, the rules, the devices, my
/// calendar, notifications and the account. Only a manage-tier device has this entry.
struct AssistantsView: View {
    @EnvironmentObject var model: AppModel

    enum Section: String, Hashable, CaseIterable {
        case assistants, connect, rules, devices, calendar, notifications, account
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: L("tab.assistants"))
                VStack(spacing: 0) {
                    ForEach(Array(Section.allCases.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        NavigationLink(value: s) {
                            HStack {
                                Text(title(s)).font(Theme.body)
                                Spacer()
                                Text("›").font(Theme.body).foregroundStyle(Theme.text3)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("assistants.\(s.rawValue)")
                    }
                }
                .card(padding: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Section.self) { s in
            Group {
                switch s {
                case .assistants: AssistantListPage()
                case .connect: ConnectPage()
                case .rules: RulesPage()
                case .devices: DeviceListPage()
                case .calendar: MyCalendarPage()
                case .notifications: NotificationsPage()
                case .account: AccountPage()
                }
            }
            .navigationTitle(title(s))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.refreshStatus() }
    }

    private func title(_ s: Section) -> String {
        switch s {
        case .assistants: return L("term.assistant")
        case .connect: return L("assistants.connect")
        case .rules: return L("assistants.rules")
        case .devices: return L("assistants.devices")
        case .calendar: return L("assistants.my_calendar")
        case .notifications: return L("assistants.notifications")
        case .account: return L("assistants.account")
        }
    }
}

/// A page inside Assistants: a scrolling column on the page background.
struct SubPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .page()
    }
}

struct KVRow<V: View>: View {
    let label: String
    @ViewBuilder let value: () -> V
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.body).foregroundStyle(Theme.text2)
            Spacer()
            value().font(Theme.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

func stepName(_ s: Step) -> String {
    switch s {
    case .triage: return L("step.triage")
    case .analysis: return L("term.analysis")
    case .digest: return L("tab.digest")
    case .deepRead: return L("term.deep_read")
    case .deepDive: return L("term.deep_dive")
    }
}

func tierName(_ t: Tier) -> String {
    switch t {
    case .save: return L("tier.save")
    case .read: return L("tier.read")
    case .manage: return L("tier.manage")
    }
}

// MARK: assistants and roles

struct AssistantListPage: View {
    @EnvironmentObject var model: AppModel
    @State private var assistants: [Assistant] = []
    @State private var settings: UserSettings?
    @State private var loaded = false

    var body: some View {
        SubPage {
            if loaded && assistants.isEmpty { Sentence(L("assistants.none")) }
            ForEach(assistants) { a in
                NavigationLink { AssistantPage(assistant: a, onChange: { Task { await load() } }) } label: { row(a) }
                    .buttonStyle(.plain)
            }
            if let s = settings {
                SectionLabel(L("roles.title"))
                VStack(spacing: 0) {
                    role(L("roles.analysis"), "analysis", s.roles.analysis, step: .analysis, scheduledOnly: true)
                    Divider1()
                    role(L("roles.digest"), "digest", s.roles.digest, step: .digest, scheduledOnly: true)
                    Divider1()
                    role(L("roles.deep_read"), "deep_read", s.roles.deepRead, step: .deepRead, scheduledOnly: true)
                    Divider1()
                    role(L("roles.deep_dive"), "deep_dive", s.roles.deepDive, step: .deepDive, scheduledOnly: false)
                }
                .card(padding: 0)
            }
        }
        .task { await load() }
    }

    private func row(_ a: Assistant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(a.name).font(Theme.item)
                Spacer()
                Text(a.builtIn ? L("assistant.built_in") : (a.kind == "chat" ? L("assistant.chat") : L("assistant.scheduled")))
                    .font(Theme.secondary).foregroundStyle(Theme.text2)
            }
            Text(a.steps.map(stepName).joined(separator: " · ")).font(Theme.secondary).foregroundStyle(Theme.text2)
            DotLabel(kind: a.lastSeenAt == nil ? .greyRing : .solid,
                     text: a.lastSeenAt.map { L("status.state.came", KeepDates.ago($0)) } ?? L("status.state.never"), font: Theme.caption, color: Theme.text3)
        }
        .card()
    }

    private func role(_ label: String, _ key: String, _ current: String?, step: Step, scheduledOnly: Bool) -> some View {
        let options = assistants.filter { $0.steps.contains(step) && (!scheduledOnly || $0.kind != "chat") }
        return KVRow(label: label) {
            Menu {
                ForEach(options) { a in Button(a.name) { Task { await setRole(key, a.id) } } }
                Button(L("roles.nobody")) { Task { await setRole(key, nil) } }
            } label: {
                Text(assistants.first { $0.id == current }?.name ?? L("roles.nobody")).underline()
            }
        }
    }

    private func load() async {
        if let page = await model.run({ try await model.client.listAssistants() }) { assistants = page.assistants }
        if let s = await model.run({ try await model.client.getSettings() }) { settings = s }
        loaded = true
    }

    private func setRole(_ key: String, _ id: String?) async {
        if let s = await model.run({ try await model.client.updateSettings(SettingsChange(roles: [key: id])) }) { settings = s }
    }
}

struct AssistantPage: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var assistant: Assistant
    let onChange: () -> Void
    @State private var name = ""
    @State private var confirmRevoke = false

    private var possibleSteps: [Step] { assistant.kind == "chat" ? [.deepDive] : [.analysis, .digest, .deepRead, .deepDive] }

    var body: some View {
        SubPage {
            Text(assistant.builtIn ? L("assistant.built_in") : (assistant.kind == "chat" ? L("assistant.chat") : L("assistant.scheduled")))
                .font(Theme.secondary).foregroundStyle(Theme.text2)
            if let at = assistant.runsAt {
                Text(L("assistant.runs_at", at)).font(Theme.secondary).foregroundStyle(Theme.text2)
            }
            if !assistant.builtIn {
                SectionLabel(L("action.rename"))
                HStack(spacing: 8) {
                    KEField(title: L("action.rename"), text: $name)
                    Button(L("action.rename")) { Task { await update(name: name) } }
                        .buttonStyle(QuietButton())
                        .disabled(name.isEmpty || name == assistant.name)
                }
                SectionLabel(L("assistant.steps"))
                VStack(spacing: 0) {
                    ForEach(Array(possibleSteps.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider1() }
                        Toggle(stepName(s), isOn: Binding(get: { assistant.steps.contains(s) }, set: { on in
                            var steps = assistant.steps.filter { $0 != s }
                            if on { steps.append(s) }
                            Task { await update(steps: steps) }
                        }))
                        .font(Theme.body)
                        .tint(Theme.solid)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .card(padding: 0)
                Button(L("action.revoke")) { confirmRevoke = true }
                    .buttonStyle(QuietButton(small: true, danger: true))
                    .padding(.top, 8)
            } else {
                Text(assistant.steps.map(stepName).joined(separator: " · ")).font(Theme.body)
            }
        }
        .navigationTitle(assistant.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("assistant.revoke.confirm", assistant.name), isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(L("action.revoke"), role: .destructive) { Task { await revoke() } }
        }
        .onAppear { name = assistant.name }
    }

    private func update(name: String? = nil, steps: [Step]? = nil) async {
        if let a = await model.run({ try await model.client.updateAssistant(id: assistant.id, name: name, steps: steps) }) {
            assistant = a
            onChange()
        }
    }

    private func revoke() async {
        if await model.run({ try await model.client.revokeAssistant(id: assistant.id) }) != nil {
            onChange()
            dismiss()
        }
    }
}

// MARK: connect an assistant

struct ConnectPage: View {
    @EnvironmentObject var model: AppModel
    @State private var address: String?
    @State private var product = "claude"

    private let products: [(id: String, name: String, steps: Int)] = [
        ("claude", "Claude", 4), ("chatgpt", "ChatGPT", 4), ("gemini", "Gemini", 4), ("own", "", 3), ("muse", "Muse", 0),
    ]

    var body: some View {
        SubPage {
            Text(L("connect.intro")).font(Theme.body).foregroundStyle(Theme.text2)
            SectionLabel(L("connect.address"))
            HStack {
                Text(address ?? "…").font(.system(size: Theme.Size.secondary, design: .monospaced)).textSelection(.enabled)
                    .accessibilityIdentifier("connect.address")
                Spacer()
                Button(L("action.copy")) {
                    UIPasteboard.general.string = address
                    model.say(L("said.copied"))
                }
                .buttonStyle(QuietButton(small: true))
                .disabled(address == nil)
            }
            .card(padding: 12)
            Text(L("connect.not_credential")).font(Theme.caption).foregroundStyle(Theme.text3)
            // Rule D10: say where the content goes.
            Text(L("connect.content_goes")).font(Theme.secondary).foregroundStyle(Theme.text2).quietBox()

            SectionLabel(L("connect.pick"))
            FlowLayout(spacing: 8) {
                ForEach(products, id: \.id) { p in
                    Button(p.id == "own" ? L("connect.own") : p.name) { product = p.id }
                        .buttonStyle(ProductButton(on: product == p.id))
                }
            }
            steps
        }
        .task {
            if let page = await model.run({ try await model.client.listAssistants() }) { address = page.connectUrl }
        }
    }

    @ViewBuilder private var steps: some View {
        let p = products.first { $0.id == product } ?? products[0]
        VStack(alignment: .leading, spacing: 10) {
            Text(L("connect.\(p.id).kind")).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text2)
            if p.steps == 0 {
                // Rule D13: no steps are written for a product that was not checked.
                DotLabel(kind: .greyRing, text: L("connect.unverified"), font: Theme.body)
            } else {
                ForEach(1...p.steps, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i)").font(Theme.bodyStrong).monospacedDigit()
                        Text(L("connect.\(p.id).\(i)")).font(Theme.body)
                    }
                }
                Text(L("connect.\(p.id).note")).font(Theme.secondary).foregroundStyle(Theme.text2)
            }
        }
        .card()
    }
}

struct ProductButton: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.secondary.weight(.semibold))
            .foregroundStyle(on ? Theme.onSolid : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(on ? Theme.solid : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.base))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.base).stroke(on ? Theme.solid : Theme.line, lineWidth: 1))
    }
}

// MARK: rules and expiry options

struct RulesPage: View {
    @EnvironmentObject var model: AppModel
    @State private var rules = ""
    @State private var options = ""
    @State private var loaded: UserSettings?

    var body: some View {
        SubPage {
            Text(L("rules.intro")).font(Theme.secondary).foregroundStyle(Theme.text2)
            TextEditor(text: $rules)
                .font(Theme.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(8)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.base))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.base).stroke(Theme.line, lineWidth: 1))
                .accessibilityIdentifier("rules.text")
            SectionLabel(L("rules.expiry"))
            Text(L("rules.expiry.intro")).font(Theme.secondary).foregroundStyle(Theme.text2)
            KEField(title: "7, 30, 90, 365", text: $options).keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("rules.expiry")
            Button(L("action.save")) { Task { await save() } }
                .buttonStyle(SolidButton())
                .disabled(loaded == nil)
                .accessibilityIdentifier("rules.save")
        }
        .task {
            if let s = await model.run({ try await model.client.getSettings() }) { show(s) }
        }
    }

    private func show(_ s: UserSettings) {
        loaded = s
        rules = s.rules
        options = s.expiryOptions.map(String.init).joined(separator: ", ")
    }

    private func save() async {
        let days = options.split { !$0.isNumber }.compactMap { Int($0) }
        guard !days.isEmpty, days.count <= 6, days.allSatisfy({ (1...365).contains($0) }) else {
            model.say(L("rules.expiry.bad"))
            return
        }
        let change = SettingsChange(rules: String(rules.prefix(4000)), expiryOptions: days)
        if let s = await model.run({ try await model.client.updateSettings(change) }) {
            show(s)
            model.say(L("said.saved"))
        }
    }
}

// MARK: devices

struct DeviceListPage: View {
    @EnvironmentObject var model: AppModel
    @State private var devices: [Device] = []
    @State private var code = ""
    @State private var asking: PendingCode?

    struct PendingCode: Identifiable {
        let code: String
        let request: DeviceCodeRequest
        var id: String { code }
    }

    var body: some View {
        SubPage {
            // Approve a short code: type it, see who asks and for which tier.
            SectionLabel(L("devices.approve"))
            Text(L("devices.approve.intro")).font(Theme.secondary).foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                KEField(title: "K7M-2QX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("devices.code")
                Button(L("devices.check")) { Task { await check() } }
                    .buttonStyle(SolidButton())
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("devices.check")
            }
            SectionLabel(L("assistants.devices"))
            ForEach(devices) { d in
                NavigationLink { DevicePage(device: d, onChange: { Task { await load() } }) } label: { row(d) }
                    .buttonStyle(.plain)
            }
        }
        .sheet(item: $asking) { p in
            ApproveSheet(pending: p, onDone: { Task { await load() } }).environmentObject(model)
        }
        .task { await load() }
    }

    private func row(_ d: Device) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(d.name).font(Theme.item)
                if d.thisDevice == true { Text(L("devices.this")).font(Theme.caption).foregroundStyle(Theme.text3) }
                Spacer()
                Text(d.category == "assistant" ? L("term.assistant") : (d.tier.map(tierName) ?? "")).font(Theme.secondary).foregroundStyle(Theme.text2)
            }
            Text(d.lastUsedAt.map { L("devices.last_used", KeepDates.ago($0)) } ?? L("devices.never_used"))
                .font(Theme.caption).foregroundStyle(Theme.text3)
        }
        .card()
    }

    private func load() async {
        if let d = await model.run({ try await model.client.listDevices() }) { devices = d }
    }

    private func check() async {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        if let r = await model.run({ try await model.client.getDeviceCodeRequest(code: c) }) {
            asking = PendingCode(code: c, request: r)
        }
    }
}

/// Who asks to connect, and the tier. The tier can be lowered, never raised above what was asked.
struct ApproveSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let pending: DeviceListPage.PendingCode
    let onDone: () -> Void
    @State private var tier: Tier = .save

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("devices.asks", pending.request.deviceName)).font(Theme.subtitle)
                Text(pending.code).font(.system(size: Theme.Size.title, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier("approve.code")
                Text(L("devices.compare")).font(Theme.secondary).foregroundStyle(Theme.text2)
                SectionLabel(L("devices.tier"))
                HStack(spacing: 8) {
                    ForEach(Tier.grantable(requested: pending.request.requestedTier), id: \.self) { t in
                        Button(tierName(t)) { tier = t }.buttonStyle(ProductButton(on: tier == t))
                            .accessibilityIdentifier("approve.tier.\(t.rawValue)")
                    }
                }
                Text(tierNote(tier)).font(Theme.secondary).foregroundStyle(Theme.text2)
                HStack(spacing: 8) {
                    Button(L("action.allow")) { Task { await allow() } }.buttonStyle(SolidButton())
                        .accessibilityIdentifier("approve.allow")
                    Button(L("action.refuse")) { Task { await refuse() } }.buttonStyle(QuietButton())
                        .accessibilityIdentifier("approve.refuse")
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .page()
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .onAppear { tier = pending.request.requestedTier }
    }

    private func tierNote(_ t: Tier) -> String {
        switch t {
        case .save: return L("tier.save.note")
        case .read: return L("tier.read.note")
        case .manage: return L("tier.manage.note")
        }
    }

    private func allow() async {
        if await model.run({ try await model.client.approveDeviceCode(code: pending.code, tier: tier) }) != nil {
            onDone()
            dismiss()
        }
    }

    private func refuse() async {
        if await model.run({ try await model.client.denyDeviceCode(code: pending.code) }) != nil {
            onDone()
            dismiss()
        }
    }
}

struct DevicePage: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var device: Device
    let onChange: () -> Void
    @State private var name = ""
    @State private var confirmRevoke = false

    var body: some View {
        SubPage {
            SectionLabel(L("action.rename"))
            HStack(spacing: 8) {
                KEField(title: L("action.rename"), text: $name).accessibilityIdentifier("device.name")
                Button(L("action.rename")) { Task { await update(name: name) } }
                    .buttonStyle(QuietButton())
                    .disabled(name.isEmpty || name == device.name)
                    .accessibilityIdentifier("device.rename")
            }
            if device.category != "assistant", let current = device.tier {
                SectionLabel(L("devices.tier"))
                HStack(spacing: 8) {
                    ForEach(Tier.allCases, id: \.self) { t in
                        Button(tierName(t)) { Task { await update(tier: t) } }.buttonStyle(ProductButton(on: current == t))
                    }
                }
            }
            Button(L("action.revoke")) { confirmRevoke = true }
                .buttonStyle(QuietButton(small: true, danger: true))
                .padding(.top, 12)
                .accessibilityIdentifier("device.revoke")
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("devices.revoke.confirm", device.name), isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(L("action.revoke"), role: .destructive) { Task { await revoke() } }
        }
        .onAppear { name = device.name }
    }

    private func update(name: String? = nil, tier: Tier? = nil) async {
        if let d = await model.run({ try await model.client.updateDevice(id: device.id, name: name, tier: tier) }) {
            device = d
            onChange()
            if d.thisDevice == true { await model.bootstrap() }
        }
    }

    private func revoke() async {
        if await model.run({ try await model.client.revokeDevice(id: device.id) }) != nil {
            if device.thisDevice == true {
                model.signOutLocally()
            } else {
                onChange()
                dismiss()
            }
        }
    }
}

// MARK: my calendar

struct MyCalendarPage: View {
    @EnvironmentObject var model: AppModel
    @State private var settings: UserSettings?
    @State private var month: CalendarMonth?
    @State private var confirmRotate = false

    var body: some View {
        SubPage {
            if let month {
                VStack(alignment: .leading, spacing: 12) {
                    CalendarDots(month: month, cell: 16, gap: 10)
                    CalendarCounts(counts: month.counts)
                }
                .card()
            }
            Text(L("mycalendar.intro")).font(Theme.secondary).foregroundStyle(Theme.text2)
            if let s = settings {
                Toggle(L("mycalendar.public"), isOn: Binding(get: { s.calendarImage.enabled }, set: { on in
                    Task { await change(SettingsChange(calendarImageEnabled: on)) }
                }))
                .font(Theme.body)
                .tint(Theme.solid)
                .card(padding: 12)
                .accessibilityIdentifier("mycalendar.toggle")
                if s.calendarImage.enabled, let url = s.calendarImage.url {
                    Text(url).font(.system(size: Theme.Size.caption, design: .monospaced)).textSelection(.enabled).quietBox()
                        .accessibilityIdentifier("mycalendar.url")
                    HStack(spacing: 8) {
                        Button(L("action.copy")) {
                            UIPasteboard.general.string = url
                            model.say(L("said.copied"))
                        }
                        .buttonStyle(SolidButton(small: true))
                        Button(L("mycalendar.rotate")) { confirmRotate = true }.buttonStyle(QuietButton(small: true))
                            .accessibilityIdentifier("mycalendar.rotate")
                    }
                    Text(L("connect.not_credential")).font(Theme.caption).foregroundStyle(Theme.text3)
                }
            }
        }
        .confirmationDialog(L("mycalendar.rotate.confirm"), isPresented: $confirmRotate, titleVisibility: .visible) {
            Button(L("mycalendar.rotate"), role: .destructive) {
                Task { if let s = await model.run({ try await model.client.rotateCalendarImage() }) { settings = s } }
            }
        }
        .task {
            if let s = await model.run({ try await model.client.getSettings() }) { settings = s }
            if let m = await model.run(quiet: true, { try await model.client.getCalendar() }) { month = m }
        }
    }

    private func change(_ c: SettingsChange) async {
        if let s = await model.run({ try await model.client.updateSettings(c) }) { settings = s }
    }
}

// MARK: notifications

struct NotificationsPage: View {
    @EnvironmentObject var model: AppModel
    @State private var settings: UserSettings?

    var body: some View {
        SubPage {
            Text(L("notify.what")).font(Theme.secondary).foregroundStyle(Theme.text2)
            if let s = settings {
                Toggle(L("notify.me"), isOn: Binding(get: { s.notify }, set: { on in
                    Task { if let n = await model.run({ try await model.client.updateSettings(SettingsChange(notify: on)) }) { settings = n } }
                }))
                .font(Theme.body)
                .tint(Theme.solid)
                .card(padding: 12)
                .accessibilityIdentifier("notify.toggle")
            }
            // Said as it is: this version does not use system notifications.
            DotLabel(kind: .greyRing, text: L("notify.not_here"), font: Theme.body, color: Theme.text)
                .accessibilityIdentifier("notify.not_here")
        }
        .task {
            if let s = await model.run({ try await model.client.getSettings() }) { settings = s }
        }
    }
}

// MARK: account

struct AccountPage: View {
    @EnvironmentObject var model: AppModel
    @State private var settings: UserSettings?
    @State private var confirmSignOut = false

    var body: some View {
        SubPage {
            VStack(spacing: 0) {
                KVRow(label: L("account.language")) { Text(L("account.language.system")) }
                Divider1()
                KVRow(label: L("account.timezone")) { Text(settings?.timezone ?? model.user?.timezone ?? "") }
            }
            .card(padding: 0)
            if let s = settings, s.timezone != TimeZone.current.identifier {
                Button(L("account.timezone.use", TimeZone.current.identifier)) {
                    Task { await change(SettingsChange(timezone: TimeZone.current.identifier)) }
                }
                .buttonStyle(QuietButton(small: true))
                .accessibilityIdentifier("account.timezone.use")
            }
            Text(L("account.server", model.store.serverURL.host ?? "")).font(Theme.caption).foregroundStyle(Theme.text3)
            Button(L("account.sign_out")) { confirmSignOut = true }
                .buttonStyle(QuietButton())
                .padding(.top, 12)
                .accessibilityIdentifier("account.sign_out")
        }
        .confirmationDialog(L("account.sign_out.confirm"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(L("account.sign_out"), role: .destructive) { Task { _ = await model.signOut() } }
        }
        .task {
            if let s = await model.run({ try await model.client.getSettings() }) { settings = s }
        }
    }

    private func change(_ c: SettingsChange) async {
        if let s = await model.run({ try await model.client.updateSettings(c) }) { settings = s }
    }
}
