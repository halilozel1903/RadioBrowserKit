import Foundation

/// A radio station from the Radio Browser database (`/json/stations/...`).
///
/// Stations are added and edited by the community and stream from third-party servers. Use
/// ``streamURL`` to play one (the server has already resolved playlists in `url_resolved`),
/// ``faviconURL`` for its logo and ``monogram`` for a generated tile when there is no logo.
public struct Station: Identifiable, Hashable, Sendable, Decodable {
    /// The station's stable `stationuuid`.
    public let id: String
    /// `changeuuid`: changes with every edit of the station.
    public let changeID: String?
    public let name: String
    /// The stream URL as entered (`url`); may be a playlist.
    public let url: URL?
    /// The stream URL after the server followed playlists and redirects (`url_resolved`).
    public let resolvedURL: URL?
    public let homepage: URL?
    /// The favicon field exactly as stored; see ``faviconURL``.
    public let favicon: String
    public let tags: [String]
    /// The country's English name, such as `"Germany"`.
    public let country: String
    /// ISO 3166-1 alpha-2, such as `"DE"`.
    public let countryCode: String
    /// ISO 3166-2 subdivision, such as `"DE-BY"`.
    public let subdivisionCode: String?
    public let state: String?
    public let languages: [String]
    public let languageCodes: [String]
    public let votes: Int
    public let clickCount: Int
    /// The change in clicks against the day before.
    public let clickTrend: Int
    /// `MP3`, `AAC`, `AAC+`, `OGG`… or empty when unknown.
    public let codec: String
    /// In kbit/s, `0` when unknown.
    public let bitrate: Int
    /// `true` when the stream is HTTP Live Streaming.
    public let isHLS: Bool
    /// `true` when the last check by the Radio Browser servers could play the stream.
    public let lastCheckOK: Bool
    public let lastChangeTime: Date?
    public let lastCheckTime: Date?
    public let lastCheckOKTime: Date?
    public let clickTimestamp: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let hasExtendedInfo: Bool
    public let hasSSLError: Bool

    public init(
        id: String,
        name: String,
        url: URL? = nil,
        resolvedURL: URL? = nil,
        homepage: URL? = nil,
        favicon: String = "",
        tags: [String] = [],
        country: String = "",
        countryCode: String = "",
        subdivisionCode: String? = nil,
        state: String? = nil,
        languages: [String] = [],
        languageCodes: [String] = [],
        votes: Int = 0,
        clickCount: Int = 0,
        clickTrend: Int = 0,
        codec: String = "",
        bitrate: Int = 0,
        isHLS: Bool = false,
        lastCheckOK: Bool = true,
        changeID: String? = nil,
        lastChangeTime: Date? = nil,
        lastCheckTime: Date? = nil,
        lastCheckOKTime: Date? = nil,
        clickTimestamp: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        hasExtendedInfo: Bool = false,
        hasSSLError: Bool = false
    ) {
        self.id = id
        self.changeID = changeID
        self.name = name
        self.url = url
        self.resolvedURL = resolvedURL
        self.homepage = homepage
        self.favicon = favicon
        self.tags = tags
        self.country = country
        self.countryCode = countryCode
        self.subdivisionCode = subdivisionCode
        self.state = state
        self.languages = languages
        self.languageCodes = languageCodes
        self.votes = votes
        self.clickCount = clickCount
        self.clickTrend = clickTrend
        self.codec = codec
        self.bitrate = bitrate
        self.isHLS = isHLS
        self.lastCheckOK = lastCheckOK
        self.lastChangeTime = lastChangeTime
        self.lastCheckTime = lastCheckTime
        self.lastCheckOKTime = lastCheckOKTime
        self.clickTimestamp = clickTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.hasExtendedInfo = hasExtendedInfo
        self.hasSSLError = hasSSLError
    }

    enum CodingKeys: String, CodingKey {
        case stationuuid, changeuuid, name, url
        case urlResolved = "url_resolved"
        case homepage, favicon, tags, country, countrycode
        case iso31662 = "iso_3166_2"
        case state, language, languagecodes, votes, clickcount, clicktrend, codec, bitrate, hls
        case lastcheckok
        case lastchangetime = "lastchangetime_iso8601"
        case lastchecktime = "lastchecktime_iso8601"
        case lastcheckoktime = "lastcheckoktime_iso8601"
        case clicktimestamp = "clicktimestamp_iso8601"
        case geoLat = "geo_lat"
        case geoLong = "geo_long"
        case hasExtendedInfo = "has_extended_info"
        case sslError = "ssl_error"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let uuid = container.lenientString(.stationuuid)
        guard !uuid.isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.stationuuid,
                .init(codingPath: container.codingPath, debugDescription: "A station needs a stationuuid")
            )
        }
        id = uuid
        changeID = container.lenientOptionalString(.changeuuid)
        name = container.lenientString(.name).trimmingCharacters(in: .whitespacesAndNewlines)
        url = container.lenientURL(.url)
        resolvedURL = container.lenientURL(.urlResolved)
        homepage = container.lenientURL(.homepage)
        favicon = container.lenientString(.favicon).trimmingCharacters(in: .whitespacesAndNewlines)
        tags = container.commaSeparated(.tags)
        country = container.lenientString(.country).trimmingCharacters(in: .whitespaces)
        countryCode = container.lenientString(.countrycode).trimmingCharacters(in: .whitespaces).uppercased()
        subdivisionCode = container.lenientOptionalString(.iso31662)
        state = container.lenientOptionalString(.state)
        languages = container.commaSeparated(.language)
        languageCodes = container.commaSeparated(.languagecodes)
        votes = container.lenientInt(.votes)
        clickCount = container.lenientInt(.clickcount)
        clickTrend = container.lenientInt(.clicktrend)
        codec = container.lenientString(.codec).trimmingCharacters(in: .whitespaces)
        bitrate = container.lenientInt(.bitrate)
        isHLS = container.lenientBool(.hls)
        // Older servers leave it out; treat a missing value as working.
        lastCheckOK = container.contains(.lastcheckok) ? container.lenientBool(.lastcheckok) : true
        lastChangeTime = container.lenientDate(.lastchangetime)
        lastCheckTime = container.lenientDate(.lastchecktime)
        lastCheckOKTime = container.lenientDate(.lastcheckoktime)
        clickTimestamp = container.lenientDate(.clicktimestamp)
        latitude = container.lenientDouble(.geoLat)
        longitude = container.lenientDouble(.geoLong)
        hasExtendedInfo = container.lenientBool(.hasExtendedInfo)
        hasSSLError = container.lenientBool(.sslError)
    }
}

extension Station {
    /// The URL to play: `url_resolved`, else `url`.
    public var streamURL: URL? {
        resolvedURL ?? url
    }

    /// How the stream is delivered.
    public var streamKind: StreamKind {
        guard let streamURL else { return .direct }
        return StreamKind(url: streamURL, isHLS: isHLS)
    }

    /// The favicon as an http or https URL, or `nil` when the field is empty, `"null"`, relative
    /// or another scheme. Many favicons are plain http; see ``secureFaviconURL``.
    public var faviconURL: URL? {
        Favicon.url(from: favicon, homepage: homepage)
    }

    /// ``faviconURL`` upgraded to https, for apps that keep App Transport Security on. Not every
    /// server answers on https.
    public var secureFaviconURL: URL? {
        faviconURL.map(Favicon.upgradingToHTTPS)
    }

    /// Initials and a stable color for a generated logo tile.
    public var monogram: StationMonogram {
        StationMonogram(name: name)
    }

    /// The country's flag emoji, or `nil` without a valid country code.
    public var countryFlag: String? {
        Country.flag(for: countryCode)
    }

    /// "MP3 · 128 kbps", "AAC+ · HLS", or `nil` when nothing is known.
    public var formatDescription: String? {
        var parts: [String] = []
        if !codec.isEmpty, codec.uppercased() != "UNKNOWN" { parts.append(codec.uppercased()) }
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        if isHLS { parts.append("HLS") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `true` when the last check of the Radio Browser servers failed.
    public var isBroken: Bool {
        !lastCheckOK
    }
}
