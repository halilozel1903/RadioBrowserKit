import Foundation

/// How a stream is delivered.
public enum StreamKind: String, Sendable, Hashable {
    /// HTTP Live Streaming (`.m3u8`): AVPlayer plays it directly.
    case hls
    /// A playlist file (`.pls`, `.m3u`, `.asx`, `.xspf`) that lists the real stream URLs.
    case playlist
    /// A plain audio stream (Icecast, Shoutcast, MP3, AAC…).
    case direct

    public init(url: URL, isHLS: Bool = false) {
        let pathExtension = url.pathExtension.lowercased()
        if isHLS || pathExtension == "m3u8" {
            self = .hls
        } else if ["pls", "m3u", "asx", "xspf"].contains(pathExtension) {
            self = .playlist
        } else {
            self = .direct
        }
    }
}

/// Reads the stream URLs out of `.pls`, `.m3u`, `.asx` and `.xspf` playlists.
public enum StreamPlaylist {
    /// The http and https URLs in the playlist, in order.
    public static func urls(in text: String) -> [URL] {
        var urls: [URL] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.lowercased().hasPrefix("file"), let equals = line.firstIndex(of: "=") {
                // PLS: File1=http://…
                if let url = URL.lenient(String(line[line.index(after: equals)...])) { urls.append(url) }
            } else if line.contains("<") {
                // ASX <ref href="…"/> and XSPF <location>…</location>.
                urls.append(contentsOf: xmlURLs(in: line))
            } else if let url = URL.lenient(line) {
                // M3U: one URL per line.
                urls.append(url)
            }
        }
        return urls
    }

    /// The first URL of the playlist in `data`.
    public static func firstURL(in data: Data) -> URL? {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return urls(in: text).first
    }

    private static func xmlURLs(in line: String) -> [URL] {
        var urls: [URL] = []
        var rest = Substring(line)
        while let start = rest.range(of: "http", options: .caseInsensitive) {
            let tail = rest[start.lowerBound...]
            let end = tail.firstIndex(where: { $0 == "\"" || $0 == "<" || $0 == "'" || $0 == " " }) ?? tail.endIndex
            if let url = URL.lenient(String(tail[..<end])) {
                urls.append(url)
            }
            rest = tail[end...]
        }
        return urls
    }
}

/// What a station is playing right now, from its ICY `StreamTitle` or HLS timed metadata.
public struct NowPlaying: Hashable, Sendable {
    /// The text as the station sent it.
    public let rawTitle: String
    /// The artist, when the title has the usual `Artist - Title` form.
    public let artist: String?
    /// The song title, or the whole text when it has no artist.
    public let title: String

    public init(artist: String?, title: String) {
        self.artist = artist
        self.title = title
        self.rawTitle = artist.map { "\($0) - \(title)" } ?? title
    }

    /// Parses a `StreamTitle` value such as `"Miles Davis - So What"`, or a whole ICY metadata
    /// block such as `StreamTitle='Miles Davis - So What';StreamUrl='';`. Returns `nil` for an
    /// empty title, which stations send between songs.
    public init?(streamTitle: String) {
        var text = streamTitle
        if let range = text.range(of: "StreamTitle='") {
            text = String(text[range.upperBound...])
            if let end = text.range(of: "';") ?? text.range(of: "'", options: .backwards) {
                text = String(text[..<end.lowerBound])
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "-", text != "|" else { return nil }
        rawTitle = text
        if let separator = text.range(of: " - ") {
            let artist = text[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = text[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                self.artist = artist
                self.title = title
                return
            }
        }
        artist = nil
        title = text
    }
}
