import Foundation

/// A country and how many stations it has (`/json/countries`).
public struct Country: Identifiable, Hashable, Sendable, Decodable {
    /// The English name, such as `"Germany"`.
    public let name: String
    /// ISO 3166-1 alpha-2, such as `"DE"`. Empty for stations without a country.
    public let code: String
    public let stationCount: Int

    public var id: String { code.isEmpty ? name : code }

    public init(name: String, code: String, stationCount: Int) {
        self.name = name
        self.code = code.uppercased()
        self.stationCount = stationCount
    }

    enum CodingKeys: String, CodingKey {
        case name
        case code = "iso_3166_1"
        case stationcount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(.name).trimmingCharacters(in: .whitespaces)
        code = container.lenientString(.code).trimmingCharacters(in: .whitespaces).uppercased()
        stationCount = container.lenientInt(.stationcount)
    }

    /// The flag emoji, such as 🇩🇪.
    public var flag: String? {
        Self.flag(for: code)
    }

    /// The flag emoji for an ISO 3166-1 alpha-2 code, or `nil` for anything else.
    public static func flag(for code: String) -> String? {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        var flag = ""
        for letter in letters {
            guard let scalar = Unicode.Scalar(0x1F1E6 + letter.value - 65) else { return nil }
            flag.unicodeScalars.append(scalar)
        }
        return flag
    }
}

/// A tag and how many stations use it (`/json/tags`). Named `StationTag` so it doesn't clash
/// with Swift Testing's `Tag`.
public struct StationTag: Identifiable, Hashable, Sendable, Decodable {
    public let name: String
    public let stationCount: Int

    public var id: String { name }

    public init(name: String, stationCount: Int) {
        self.name = name
        self.stationCount = stationCount
    }

    enum CodingKeys: String, CodingKey {
        case name, stationcount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(.name).trimmingCharacters(in: .whitespacesAndNewlines)
        stationCount = container.lenientInt(.stationcount)
    }
}

/// A language and how many stations broadcast in it (`/json/languages`).
public struct StationLanguage: Identifiable, Hashable, Sendable, Decodable {
    /// The name as stored, usually lowercase English: `"german"`.
    public let name: String
    /// ISO 639 code when known, such as `"de"`.
    public let code: String?
    public let stationCount: Int

    public var id: String { name }

    public init(name: String, code: String?, stationCount: Int) {
        self.name = name
        self.code = code
        self.stationCount = stationCount
    }

    enum CodingKeys: String, CodingKey {
        case name
        case code = "iso_639"
        case stationcount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(.name).trimmingCharacters(in: .whitespacesAndNewlines)
        code = container.lenientOptionalString(.code)
        stationCount = container.lenientInt(.stationcount)
    }

    /// `"German"`.
    public var displayName: String {
        name.capitalized
    }
}

/// A Radio Browser API server (`/json/servers`).
public struct ServerMirror: Hashable, Sendable, Decodable {
    /// The host name, such as `de1.api.radio-browser.info`.
    public let name: String
    public let ip: String?

    public init(name: String, ip: String? = nil) {
        self.name = name
        self.ip = ip
    }

    enum CodingKeys: String, CodingKey {
        case name, ip
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(.name).trimmingCharacters(in: .whitespaces).lowercased()
        ip = container.lenientOptionalString(.ip)
    }
}

/// The answer to a click (`/json/url/{stationuuid}`).
public struct ClickResult: Hashable, Sendable, Decodable {
    /// `false` when the click was not counted, for example a second click from the same IP
    /// within a day.
    public let ok: Bool
    public let message: String
    public let stationID: String?
    public let name: String?
    /// The stream URL to play.
    public let url: URL?

    public init(ok: Bool, message: String, stationID: String?, name: String?, url: URL?) {
        self.ok = ok
        self.message = message
        self.stationID = stationID
        self.name = name
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case ok, message, stationuuid, name, url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = container.lenientBool(.ok)
        message = container.lenientString(.message)
        stationID = container.lenientOptionalString(.stationuuid)
        name = container.lenientOptionalString(.name)
        url = container.lenientURL(.url)
    }
}
