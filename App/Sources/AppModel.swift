import SwiftUI
import KeepCore

enum AppTab: String, CaseIterable {
    case today, digest, notes, assistants
}

/// The state every page shares: who is signed in, the status bar, the dot on the digest entry.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case launching, signedOut, signedIn }

    @Published var phase: Phase = .launching
    @Published var device: Device?
    @Published var user: User?
    @Published var status: Status?
    @Published var digestUnread = false
    @Published var tab: AppTab = .today
    /// The day the digest page should show; nil is the latest.
    @Published var digestDay: String?
    /// One sentence shown for a moment above the bottom bar.
    @Published var notice: String?
    /// Sentences of queued saves the core refused, shown on Today until dismissed.
    @Published var saveFailures: [String] = []
    @Published var queuedCount = 0
    @Published var statusExpanded = false

    let store = KeepStore.shared
    private(set) var client: APIClient
    private var noticeTask: Task<Void, Never>?

    init() {
        let args = UserDefaults.standard
        if let server = args.string(forKey: "KEServer"), let url = KeepStore.parseServer(server) { store.serverURL = url }
        if args.bool(forKey: "KEReset") {
            store.credential = nil
            store.cachedDevice = nil
        }
        client = store.makeClient()
    }

    var tier: Tier { device?.tier ?? .read }
    var isManager: Bool { tier == .manage }
    var tabs: [AppTab] { isManager ? AppTab.allCases : [.today, .digest, .notes] }

    // MARK: session

    func bootstrap() async {
        guard store.credential != nil else {
            phase = .signedOut
            return
        }
        client = store.makeClient()
        do {
            let me = try await client.getThisDevice()
            adopt(me)
        } catch let e as APIError where e.isUnauthorized {
            signOutLocally()
            return
        } catch {
            // No connection: open with what this device last knew.
            if let cached = store.cachedDevice {
                device = cached.device
                user = cached.user
                phase = .signedIn
            } else {
                phase = .signedOut
                return
            }
        }
        await refreshAfterForeground()
    }

    private func adopt(_ me: ThisDevice) {
        device = me.device
        user = me.user
        store.cachedDevice = me
        phase = .signedIn
        if !tabs.contains(tab) { tab = .today }
    }

    func signedIn(_ grant: DeviceGrant) async {
        store.credential = grant.credential
        client = store.makeClient()
        adopt(ThisDevice(device: grant.device, user: grant.user))
        await refreshAfterForeground()
    }

    func signOut() async -> Bool {
        do {
            try await client.signOutThisDevice()
        } catch let e as APIError where e.isUnauthorized {
            // Already revoked elsewhere.
        } catch {
            say(message(for: error))
            return false
        }
        signOutLocally()
        return true
    }

    func signOutLocally() {
        store.credential = nil
        store.cachedDevice = nil
        client = store.makeClient()
        device = nil
        user = nil
        status = nil
        digestUnread = false
        tab = .today
        phase = .signedOut
    }

    // MARK: calls

    func message(for error: Error) -> String {
        if let e = error as? APIError { return e.message }
        if error is URLError { return L("error.unreachable") }
        return error.localizedDescription
    }

    /// Runs a call. A refused credential signs this device out; any other failure is said in one sentence.
    @discardableResult
    func run<T>(quiet: Bool = false, _ op: () async throws -> T) async -> T? {
        do {
            return try await op()
        } catch let e as APIError where e.isUnauthorized {
            signOutLocally()
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            if !quiet { say(message(for: error)) }
        }
        return nil
    }

    func say(_ sentence: String) {
        notice = sentence
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    // MARK: what every page shows

    func refreshStatus() async {
        guard tier != .save else { return }
        if let s = await run(quiet: true, { try await client.getStatus() }) { status = s }
    }

    func refreshDigestDot() async {
        guard tier != .save else { return }
        do {
            digestUnread = !(try await client.getDigest().read)
        } catch let e as APIError where e.status == 404 {
            digestUnread = false
        } catch let e as APIError where e.isUnauthorized {
            signOutLocally()
        } catch {}
    }

    func refreshAfterForeground() async {
        guard phase == .signedIn else { return }
        if let (_, data) = try? await client.getMeta() { store.cacheMeta(data) }
        await flushQueue()
        await refreshStatus()
        await refreshDigestDot()
    }

    /// Sends what the share extension queued while there was no connection.
    func flushQueue() async {
        let service = SaveService(client: client, queue: store.queue, rules: store.meta.sharedRules, quotaReason: L("save.quota"))
        let outcomes = await service.flush()
        saveFailures += outcomes.filter { $0.kind == .failed }.map(\.sentence)
        queuedCount = store.queue.count
    }

    func openDigest(day: String?) {
        digestDay = day
        tab = .digest
    }
}
