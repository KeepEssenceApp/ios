import Foundation

/// Free-form JSON, for the parts of `GET /v1/meta` the contract leaves open.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var int: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

/// `Meta` of the contract: its version, the limits and the one copy of the shared rules.
public struct Meta: Equatable, Sendable {
    public let contractVersion: String
    public let limits: JSONValue
    public let sharedRules: SharedRules

    public init(data: Data) throws {
        // Plain decoder: the key conversion would also rename the keys inside the free-form objects.
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let version = root["contract_version"]?.string, let limits = root["limits"], let rules = root["shared_rules"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "meta is missing a required field"))
        }
        contractVersion = version
        self.limits = limits
        sharedRules = SharedRules(json: rules)
    }

    public func limit(_ name: String) -> Int? { limits[name]?.int }

    /// The copy generated from `contract/openapi.yaml` by `scripts/gen-shared-rules.rb`. Used only until the
    /// first answer of `GET /v1/meta` is cached.
    public static let bundled: Meta = {
        guard let url = Bundle.module.url(forResource: "shared-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url), let meta = try? Meta(data: data) else {
            fatalError("shared-rules.json is missing from the package; run scripts/gen-shared-rules.rb")
        }
        return meta
    }()
}

public struct SecretPattern: Equatable, Sendable {
    public let name: String
    public let regex: String
    /// `i` means match without regard to case.
    public let flags: String?
    /// Checked on text of any length, not only up to `max_length_checked`.
    public let anyLength: Bool

    public init(name: String, regex: String, flags: String? = nil, anyLength: Bool = false) {
        self.name = name
        self.regex = regex
        self.flags = flags
        self.anyLength = anyLength
    }
}

/// `x-shared-rules` of the contract, as served by `GET /v1/meta`.
public struct SharedRules: Equatable, Sendable {
    public let json: JSONValue

    public init(json: JSONValue) { self.json = json }

    public var secretPatterns: [SecretPattern] {
        (json["secret_like"]?["patterns"]?.array ?? []).compactMap { p in
            guard let name = p["name"]?.string, let regex = p["regex"]?.string else { return nil }
            return SecretPattern(name: name, regex: regex, flags: p["flags"]?.string, anyLength: p["any_length"]?.bool ?? false)
        }
    }

    public var secretMaxLengthChecked: Int { json["secret_like"]?["max_length_checked"]?.int ?? 200 }

    /// One of `save_messages`, in `zh` or `en`. `{reason}` is filled in when given.
    public func saveMessage(_ key: String, lang: String, reason: String? = nil) -> String? {
        guard let entry = json["save_messages"]?[key], let text = entry[lang]?.string ?? entry["en"]?.string else { return nil }
        return reason.map { text.replacingOccurrences(of: "{reason}", with: $0) } ?? text
    }
}
