import Foundation

/// The parameters of `/json/stations/search`. Every filter is optional; unset ones are not sent.
///
/// ```swift
/// var search = StationSearch(name: "jazz")
/// search.countryCode = "US"
/// search.order = .clickCount
/// search.limit = 30
/// let stations = try await radio.searchStations(search)
/// ```
public struct StationSearch: Sendable, Hashable {
    /// Part of the name (case-insensitive), or the whole name with ``nameExact``.
    public var name: String?
    public var nameExact: Bool
    /// ISO 3166-1 alpha-2, such as `"DE"`.
    public var countryCode: String?
    /// The country's English name.
    public var country: String?
    public var state: String?
    /// A language name such as `"english"`.
    public var language: String?
    /// One tag, such as `"jazz"`, or the whole tag with ``tagExact``.
    public var tag: String?
    public var tagExact: Bool
    /// Stations that have every one of these tags.
    public var tagList: [String]
    /// `"MP3"`, `"AAC"`…
    public var codec: String?
    /// The lowest bitrate, in kbit/s.
    public var bitrateMin: Int?
    /// The highest bitrate, in kbit/s.
    public var bitrateMax: Int?
    public var order: StationOrder?
    /// Descending order (`reverse=true`): with ``StationOrder/clickCount``, most clicked first.
    public var reverse: Bool
    /// Leave out stations whose last check failed. On by default.
    public var hideBroken: Bool
    public var limit: Int?
    public var offset: Int?

    public init(
        name: String? = nil,
        nameExact: Bool = false,
        countryCode: String? = nil,
        country: String? = nil,
        state: String? = nil,
        language: String? = nil,
        tag: String? = nil,
        tagExact: Bool = false,
        tagList: [String] = [],
        codec: String? = nil,
        bitrateMin: Int? = nil,
        bitrateMax: Int? = nil,
        order: StationOrder? = nil,
        reverse: Bool = false,
        hideBroken: Bool = true,
        limit: Int? = 100,
        offset: Int? = nil
    ) {
        self.name = name
        self.nameExact = nameExact
        self.countryCode = countryCode
        self.country = country
        self.state = state
        self.language = language
        self.tag = tag
        self.tagExact = tagExact
        self.tagList = tagList
        self.codec = codec
        self.bitrateMin = bitrateMin
        self.bitrateMax = bitrateMax
        self.order = order
        self.reverse = reverse
        self.hideBroken = hideBroken
        self.limit = limit
        self.offset = offset
    }

    /// The query items, in a fixed order.
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            items.append(URLQueryItem(name: name, value: value))
        }
        add("name", name)
        if name != nil, nameExact { add("nameExact", "true") }
        add("countrycode", countryCode?.uppercased())
        add("country", country)
        add("state", state)
        add("language", language)
        add("tag", tag)
        if tag != nil, tagExact { add("tagExact", "true") }
        let tags = tagList.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !tags.isEmpty { add("tagList", tags.joined(separator: ",")) }
        add("codec", codec)
        add("bitrateMin", bitrateMin.map(String.init))
        add("bitrateMax", bitrateMax.map(String.init))
        add("order", order?.rawValue)
        if reverse { add("reverse", "true") }
        add("hidebroken", hideBroken ? "true" : "false")
        add("limit", limit.map { String(max(0, $0)) })
        add("offset", offset.map { String(max(0, $0)) })
        return items
    }
}

/// Sort orders for station lists.
public enum StationOrder: String, Sendable, Hashable, CaseIterable {
    case name
    case url
    case homepage
    case favicon
    case tags
    case country
    case state
    case language
    case votes
    case codec
    case bitrate
    case lastCheckOK = "lastcheckok"
    case lastCheckTime = "lastchecktime"
    case clickTimestamp = "clicktimestamp"
    case clickCount = "clickcount"
    case clickTrend = "clicktrend"
    case changeTimestamp = "changetimestamp"
    case random
}

/// Sort orders for countries, tags and languages.
public enum DirectoryOrder: String, Sendable, Hashable, CaseIterable {
    case name
    case stationCount = "stationcount"
}
