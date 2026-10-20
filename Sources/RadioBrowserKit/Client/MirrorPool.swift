import Foundation

/// The Radio Browser API servers a client sends requests to.
///
/// Radio Browser has no single API host; it runs a handful of equal mirrors and asks clients to
/// pick one at random. The pool loads the current list from `all.api.radio-browser.info/json/servers`
/// once, falls back to a built-in list when that fails, shuffles it so load spreads across
/// servers, and moves a server that failed to the back of the line.
public actor MirrorPool {
    private let discoveryURL: URL?
    private let fallback: [String]
    private let session: URLSession
    private let userAgent: String
    private let timeout: TimeInterval
    private let shuffle: @Sendable ([String]) -> [String]

    private var hosts: [String]?
    private var discovery: Task<[String], Never>?

    /// - Parameters:
    ///   - shuffle: Orders the mirrors; random by default. Tests pass `{ $0 }`.
    public init(
        discoveryURL: URL?,
        fallback: [String],
        session: URLSession = .shared,
        userAgent: String = RadioBrowserConfiguration.defaultUserAgent,
        timeout: TimeInterval = 10,
        shuffle: @escaping @Sendable ([String]) -> [String] = { $0.shuffled() }
    ) {
        self.discoveryURL = discoveryURL
        self.fallback = Self.unique(fallback)
        self.session = session
        self.userAgent = userAgent
        self.timeout = timeout
        self.shuffle = shuffle
    }

    /// The mirrors in the order requests try them: the current one first.
    public func orderedHosts() async -> [String] {
        if let hosts {
            return hosts
        }
        let task: Task<[String], Never>
        if let discovery {
            task = discovery
        } else {
            let url = discoveryURL
            let session = self.session
            let userAgent = self.userAgent
            let timeout = self.timeout
            task = Task {
                guard let url else { return [] }
                return (try? await Self.discover(url: url, session: session, userAgent: userAgent, timeout: timeout)) ?? []
            }
            discovery = task
        }
        let discovered = await task.value
        if let hosts {
            // Another caller finished first.
            return hosts
        }
        let list = shuffle(discovered.isEmpty ? fallback : discovered)
        hosts = list
        discovery = nil
        return list
    }

    /// The mirror the next request goes to.
    public func current() async -> String? {
        await orderedHosts().first
    }

    /// Moves `host` to the back, so the next request tries another mirror first.
    public func markFailed(_ host: String) {
        guard var list = hosts, let index = list.firstIndex(of: host), list.count > 1 else { return }
        list.remove(at: index)
        list.append(host)
        hosts = list
    }

    /// Forgets the list; the next request discovers the mirrors again.
    public func reset() {
        hosts = nil
        discovery?.cancel()
        discovery = nil
    }

    /// The host names from a `/json/servers` answer, without duplicates.
    public static func discover(url: URL, session: URLSession, userAgent: String, timeout: TimeInterval) async throws -> [String] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let servers = try JSONDecoder().decode([ServerMirror].self, from: data)
        return unique(servers.map(\.name))
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
