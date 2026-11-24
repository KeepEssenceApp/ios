import Foundation
import Security

public enum KeepEnvironment {
    public static let appGroup = "group.app.keepessence.ios"
    public static let defaultServer = URL(string: "https://keepessence.app")!
    /// The keychain access group both targets share, with the team prefix, from the target's Info.plist.
    public static var keychainGroup: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "KEKeychainGroup") as? String, !g.isEmpty, !g.hasPrefix(".") else { return nil }
        return g
    }
}

public protocol CredentialStoring: AnyObject {
    func read() -> String?
    func write(_ credential: String?)
}

/// The device credential in the keychain, in the access group the app and the share extension share.
/// It is never shown and never leaves the device.
public final class KeychainCredentialStore: CredentialStoring {
    private let service = "app.keepessence.ios.credential"
    private let account = "device"
    private let group: String?
    /// The last status the keychain answered, for the diagnostics in docs/pitfalls.md.
    public private(set) var lastStatus: OSStatus = errSecSuccess

    public init(group: String? = KeepEnvironment.keychainGroup) { self.group = group }

    private func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    public func read() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        lastStatus = SecItemCopyMatching(q as CFDictionary, &out)
        guard lastStatus == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ credential: String?) {
        lastStatus = SecItemDelete(query() as CFDictionary)
        guard let credential else { return }
        var q = query()
        q[kSecValueData as String] = Data(credential.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        lastStatus = SecItemAdd(q as CFDictionary, nil)
    }

    @discardableResult
    public func tryWrite(_ credential: String) -> Bool {
        write(credential)
        return lastStatus == errSecSuccess
    }
}

/// Fallback for builds whose signing does not carry the shared keychain group: the credential in a
/// file of the app group container, readable only by this app and its extension, excluded from backups.
public final class FileCredentialStore: CredentialStoring {
    private let url: URL

    public init(directory: URL) { url = directory.appendingPathComponent("credential") }

    public func read() -> String? {
        guard let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    public func write(_ credential: String?) {
        try? FileManager.default.removeItem(at: url)
        guard let credential else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? Data(credential.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? Data(credential.utf8).write(to: url, options: [.atomic])
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try? u.setResourceValues(values)
    }
}

/// What the app and the share extension share on the device: the server address, the credential,
/// the cached shared rules and the offline queue.
public final class KeepStore: @unchecked Sendable {
    public static let shared = KeepStore()

    public let container: URL
    private let defaults: UserDefaults
    private let keychain: KeychainCredentialStore
    private let file: FileCredentialStore

    public init(appGroup: String = KeepEnvironment.appGroup) {
        let fm = FileManager.default
        if let c = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            container = c
            defaults = UserDefaults(suiteName: appGroup) ?? .standard
        } else {
            container = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
                .appendingPathComponent("KeepEssence")
            defaults = .standard
        }
        try? fm.createDirectory(at: container, withIntermediateDirectories: true)
        keychain = KeychainCredentialStore()
        file = FileCredentialStore(directory: container)
    }

    // MARK: server address

    public var serverURL: URL {
        get { defaults.string(forKey: "server").flatMap(URL.init(string:)) ?? KeepEnvironment.defaultServer }
        set { defaults.set(newValue.absoluteString, forKey: "server") }
    }

    /// Accepts `https://host` and, for a self-hosted or local core, `http://host:port`.
    public static func parseServer(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host?.isEmpty == false else { return nil }
        return url
    }

    // MARK: credential

    /// Where the credential is kept on this build: `keychain`, or `file` when the keychain refused the shared group.
    public var credentialPlace: String { defaults.string(forKey: "credentialPlace") ?? "keychain" }

    public var credential: String? {
        get { keychain.read() ?? file.read() }
        set {
            guard let newValue else {
                keychain.write(nil)
                file.write(nil)
                return
            }
            if keychain.tryWrite(newValue) {
                file.write(nil)
                defaults.set("keychain", forKey: "credentialPlace")
            } else {
                file.write(newValue)
                defaults.set("file (keychain status \(keychain.lastStatus))", forKey: "credentialPlace")
            }
        }
    }

    // MARK: this device, cached so the app opens without a connection

    public var cachedDevice: ThisDevice? {
        get { defaults.data(forKey: "thisDevice").flatMap { try? KeepJSON.decoder().decode(ThisDevice.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? KeepJSON.encoder().encode($0) }, forKey: "thisDevice") }
    }

    // MARK: shared rules

    private var metaURL: URL { container.appendingPathComponent("meta.json") }

    /// The shared rules as the core last served them, else the copy generated from the contract.
    public var meta: Meta {
        if let data = try? Data(contentsOf: metaURL), let m = try? Meta(data: data) { return m }
        return .bundled
    }

    public func cacheMeta(_ data: Data) { try? data.write(to: metaURL, options: .atomic) }

    // MARK: offline queue

    public var queue: OfflineQueue { OfflineQueue(directory: container.appendingPathComponent("queue")) }

    public func makeClient(session: URLSession = .shared) -> APIClient {
        APIClient(baseURL: serverURL, credential: credential, session: session)
    }
}
