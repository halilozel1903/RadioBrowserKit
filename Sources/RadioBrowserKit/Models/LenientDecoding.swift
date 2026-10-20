import Foundation

/// The Radio Browser database is community-edited and has been served by several server versions,
/// so the same field can arrive as a number, a string, a boolean or `null`. These helpers decode
/// what is there and fall back to a default instead of failing the whole response.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return ""
    }

    func lenientOptionalString(_ key: Key) -> String? {
        let value = lenientString(key).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.lowercased() == "null" ? nil : value
    }

    func lenientInt(_ key: Key) -> Int {
        lenientOptionalInt(key) ?? 0
    }

    func lenientOptionalInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespaces))
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// An ISO 8601 timestamp such as `2026-10-17T08:15:30Z`, or `nil`.
    func lenientDate(_ key: Key) -> Date? {
        guard let string = lenientOptionalString(key) else { return nil }
        return RadioBrowserDate.parse(string)
    }

    /// A comma-separated list such as `"jazz,smooth jazz, lounge"`, trimmed, without empty items.
    func commaSeparated(_ key: Key) -> [String] {
        RadioBrowserList.split(lenientString(key))
    }

    func lenientURL(_ key: Key) -> URL? {
        lenientOptionalString(key).flatMap(URL.lenient)
    }
}

enum RadioBrowserList {
    static func split(_ string: String) -> [String] {
        string
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum RadioBrowserDate {
    /// Parses `2026-10-17T08:15:30Z`, with or without fractional seconds, and the older
    /// `2026-10-17 08:15:30` form (UTC).
    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) {
            return date
        }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(string) {
            return date
        }
        let spaced = string.replacingOccurrences(of: " ", with: "T") + (string.hasSuffix("Z") ? "" : "Z")
        return try? Date(spaced, strategy: .iso8601)
    }
}

extension URL {
    /// A URL from user-entered text: trimmed, with spaces escaped, and only for http and https
    /// with a host. `nil` for anything else, such as `""`, `"null"` or `"data:…"`.
    static func lenient(_ string: String) -> URL? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.lowercased() != "null" else { return nil }
        if text.hasPrefix("//") {
            text = "https:" + text
        }
        text = text.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
