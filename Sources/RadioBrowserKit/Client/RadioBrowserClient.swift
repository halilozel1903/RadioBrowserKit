import Foundation

/// A client for the [Radio Browser API](https://api.radio-browser.info), the free community
/// database of internet radio stations.
///
/// ```swift
/// let radio = RadioBrowserClient()
/// let top = try await radio.topClickedStations(limit: 20)
/// let jazz = try await radio.searchStations(StationSearch(tag: "jazz", order: .clickCount, reverse: true))
/// let countries = try await radio.countries()
/// ```
///
/// Requests go to a random mirror from `all.api.radio-browser.info/json/servers` (or a built-in
/// list when that is unreachable) and move on to the next mirror when one fails. Every request
/// sends a descriptive User-Agent. The client is `Sendable`; share one per app.
public final class RadioBrowserClient: Sendable {
    /// A client with the default configuration.
    public static let shared = RadioBrowserClient()

    public let configuration: RadioBrowserConfiguration
    public let mirrors: MirrorPool

    public init(configuration: RadioBrowserConfiguration = RadioBrowserConfiguration()) {
        self.configuration = configuration
        self.mirrors = MirrorPool(
            discoveryURL: configuration.discoveryURL,
            fallback: configuration.fallbackMirrors,
            session: configuration.session,
            userAgent: configuration.userAgent,
            timeout: min(configuration.timeout, 10)
        )
    }

    /// A client with an explicit mirror pool, for tests or to share one pool.
    public init(configuration: RadioBrowserConfiguration, mirrors: MirrorPool) {
        self.configuration = configuration
        self.mirrors = mirrors
    }

    // MARK: - Stations

    /// Stations matching `search` (`/json/stations/search`).
    public func searchStations(_ search: StationSearch) async throws -> [Station] {
        try await get("json/stations/search", query: search.queryItems)
    }

    /// Stations whose name contains `name`, most clicked first.
    public func searchStations(named name: String, limit: Int = 50, hideBroken: Bool = true) async throws -> [Station] {
        try await searchStations(StationSearch(name: name, order: .clickCount, reverse: true, hideBroken: hideBroken, limit: limit))
    }

    /// The most clicked stations (`/json/stations/topclick`).
    public func topClickedStations(limit: Int = 50, offset: Int = 0, hideBroken: Bool = true) async throws -> [Station] {
        try await get("json/stations/topclick", query: listQuery(limit: limit, offset: offset, hideBroken: hideBroken))
    }

    /// The most voted stations (`/json/stations/topvote`).
    public func topVotedStations(limit: Int = 50, offset: Int = 0, hideBroken: Bool = true) async throws -> [Station] {
        try await get("json/stations/topvote", query: listQuery(limit: limit, offset: offset, hideBroken: hideBroken))
    }

    /// The stations with these ids (`/json/stations/byuuid`), for example saved favorites.
    public func stations(ids: [String]) async throws -> [Station] {
        guard !ids.isEmpty else { return [] }
        return try await get("json/stations/byuuid", query: [URLQueryItem(name: "uuids", value: ids.joined(separator: ","))])
    }

    // MARK: - Directory

    /// Countries with their station counts (`/json/countries`). By default the countries with
    /// the most stations come first.
    public func countries(order: DirectoryOrder = .stationCount, reverse: Bool = true, hideBroken: Bool = true, limit: Int? = nil) async throws -> [Country] {
        try await get("json/countries", query: directoryQuery(order: order, reverse: reverse, hideBroken: hideBroken, limit: limit))
    }

    /// Tags with their station counts (`/json/tags`), most used first by default.
    public func tags(order: DirectoryOrder = .stationCount, reverse: Bool = true, hideBroken: Bool = true, limit: Int? = 100) async throws -> [StationTag] {
        try await get("json/tags", query: directoryQuery(order: order, reverse: reverse, hideBroken: hideBroken, limit: limit))
    }

    /// Languages with their station counts (`/json/languages`), most used first by default.
    public func languages(order: DirectoryOrder = .stationCount, reverse: Bool = true, hideBroken: Bool = true, limit: Int? = nil) async throws -> [StationLanguage] {
        try await get("json/languages", query: directoryQuery(order: order, reverse: reverse, hideBroken: hideBroken, limit: limit))
    }

    // MARK: - Clicks

    /// Counts a click for the station (`/json/url/{stationuuid}`) and returns its stream URL.
    ///
    /// Radio Browser ranks stations by clicks: call this when the user starts playing a station.
    /// The server counts at most one click per station and IP address a day.
    @discardableResult
    public func countClick(stationID: String) async throws -> ClickResult {
        let id = stationID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
            throw RadioBrowserError.invalidRequest("\"\(stationID)\" is not a station uuid")
        }
        return try await get("json/url/" + id.lowercased())
    }

    // MARK: - Any endpoint

    /// Decodes any API path, such as `json/stations/bycountrycodeexact/DE`, into `T`.
    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send(path: path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RadioBrowserError.decoding(type: String(describing: T.self), description: String(describing: error))
        }
    }

    /// The URL of `path` on `host`.
    public func url(path: String, query: [URLQueryItem] = [], host: String) throws -> URL {
        var components = URLComponents()
        components.scheme = configuration.scheme
        components.host = host
        components.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw RadioBrowserError.invalidRequest(path)
        }
        return url
    }

    // MARK: - Transport

    /// Sends a GET to the current mirror, trying other mirrors when one is down.
    func send(path: String, query: [URLQueryItem]) async throws -> (Data, String) {
        let hosts = await mirrors.orderedHosts()
        guard !hosts.isEmpty else { throw RadioBrowserError.noMirrorAvailable }
        var lastError = RadioBrowserError.noMirrorAvailable
        for host in hosts.prefix(configuration.maxMirrorAttempts) {
            try Task.checkCancellation()
            do {
                return (try await perform(path: path, query: query, host: host), host)
            } catch let error as RadioBrowserError where error.triesAnotherMirror {
                lastError = error
                await mirrors.markFailed(host)
            }
        }
        throw lastError
    }

    private func perform(path: String, query: [URLQueryItem], host: String) async throws -> Data {
        var request = URLRequest(url: try url(path: path, query: query, host: host), timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (Data, URLResponse)
        do {
            result = try await configuration.session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw RadioBrowserError.transport(error)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw RadioBrowserError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RadioBrowserError.http(status: http.statusCode, host: host)
        }
        return data
    }

    private func listQuery(limit: Int, offset: Int, hideBroken: Bool) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(max(0, limit)))]
        if offset > 0 { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        items.append(URLQueryItem(name: "hidebroken", value: hideBroken ? "true" : "false"))
        return items
    }

    private func directoryQuery(order: DirectoryOrder, reverse: Bool, hideBroken: Bool, limit: Int?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "order", value: order.rawValue),
            URLQueryItem(name: "reverse", value: reverse ? "true" : "false"),
            URLQueryItem(name: "hidebroken", value: hideBroken ? "true" : "false"),
        ]
        if let limit { items.append(URLQueryItem(name: "limit", value: String(max(0, limit)))) }
        return items
    }
}
