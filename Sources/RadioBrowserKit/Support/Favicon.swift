import Foundation

/// Turns the free-text favicon field of a station into a URL you can load.
///
/// The field is entered by people: it can be empty, `"null"`, protocol-relative (`//cdn…`),
/// relative to the homepage (`/logo.png`), plain http, or point at a page instead of an image.
/// Only the first few can be fixed here; whether the URL really returns an image is up to the
/// server, so always have a fallback such as ``StationMonogram``.
public enum Favicon {
    /// An http or https URL for `field`, resolving a relative path against `homepage`.
    public static func url(from field: String, homepage: URL? = nil) -> URL? {
        let text = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.lowercased() != "null" else { return nil }
        if let absolute = URL.lenient(text) {
            return absolute
        }
        // A path on the station's own site.
        guard text.hasPrefix("/"), !text.hasPrefix("//"), let homepage,
              let resolved = URL(string: text.replacingOccurrences(of: " ", with: "%20"), relativeTo: homepage)?.absoluteURL
        else { return nil }
        return URL.lenient(resolved.absoluteString)
    }

    /// The same URL on https.
    public static func upgradingToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url ?? url
    }
}

/// Initials and a color for a generated station logo, the same every time for the same name.
///
/// ```swift
/// let monogram = station.monogram        // "Radio Paradise" → "RP"
/// Color(hue: monogram.hue, saturation: 0.55, brightness: 0.55)
/// ```
public struct StationMonogram: Hashable, Sendable {
    /// One or two characters, uppercased.
    public let initials: String
    /// A hue from 0 up to 1, from a stable hash of the name.
    public let hue: Double

    /// Words that say nothing about a station, skipped when there are others.
    static let fillerWords: Set<String> = ["radio", "the", "fm", "am", "de", "del", "la", "le", "el", "web", "online", "stream"]

    public init(name: String) {
        let words = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let meaningful = words.filter { !Self.fillerWords.contains($0.lowercased()) }
        // "The Jazz Groove" → "JG", but "Radio Paradise" → "RP" rather than "PA".
        let chosen = meaningful.count >= 2 ? meaningful : words
        let initials: String
        switch chosen.count {
        case 0:
            initials = "♪"
        case 1:
            initials = String(chosen[0].prefix(2))
        default:
            initials = String(chosen[0].prefix(1)) + String(chosen[1].prefix(1))
        }
        self.initials = initials.uppercased()

        // FNV-1a over the lowercased name: stable between launches, unlike `hashValue`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        hue = Double(hash % 360) / 360
    }
}
