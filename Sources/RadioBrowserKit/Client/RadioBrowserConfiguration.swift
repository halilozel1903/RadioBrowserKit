import Foundation

/// Settings for a ``RadioBrowserClient``.
public struct RadioBrowserConfiguration: Sendable {
    /// The User-Agent every request sends. Radio Browser asks apps to send a descriptive one.
    public static let defaultUserAgent = "RadioBrowserKit/1.0"

    /// Where the list of API servers comes from.
    public static let defaultDiscoveryURL = URL(string: "https://all.api.radio-browser.info/json/servers")!

    /// Servers used when discovery fails.
    public static let defaultFallbackMirrors = [
        "de1.api.radio-browser.info",
        "de2.api.radio-browser.info",
        "fi1.api.radio-browser.info",
        "at1.api.radio-browser.info",
    ]

    public var session: URLSession
    /// Sent as `User-Agent`. Use your app's name and version, such as `"MyRadio/2.1"`.
    public var userAgent: String
    /// The server list to discover mirrors from, or `nil` to use ``fallbackMirrors`` only.
    public var discoveryURL: URL?
    /// Mirror host names, used when discovery is off or fails.
    public var fallbackMirrors: [String]
    /// How many different mirrors one request may try before it gives up.
    public var maxMirrorAttempts: Int
    /// The timeout of each request, in seconds.
    public var timeout: TimeInterval
    /// `"https"`; tests can use another scheme.
    public var scheme: String

    public init(
        session: URLSession = .shared,
        userAgent: String = RadioBrowserConfiguration.defaultUserAgent,
        discoveryURL: URL? = RadioBrowserConfiguration.defaultDiscoveryURL,
        fallbackMirrors: [String] = RadioBrowserConfiguration.defaultFallbackMirrors,
        maxMirrorAttempts: Int = 3,
        timeout: TimeInterval = 15,
        scheme: String = "https"
    ) {
        self.session = session
        self.userAgent = userAgent
        self.discoveryURL = discoveryURL
        self.fallbackMirrors = fallbackMirrors
        self.maxMirrorAttempts = max(1, maxMirrorAttempts)
        self.timeout = timeout
        self.scheme = scheme
    }

    /// One fixed server and no discovery, for a self-hosted server or tests.
    public static func server(_ host: String, session: URLSession = .shared, userAgent: String = defaultUserAgent) -> RadioBrowserConfiguration {
        RadioBrowserConfiguration(session: session, userAgent: userAgent, discoveryURL: nil, fallbackMirrors: [host], maxMirrorAttempts: 1)
    }
}

/// Errors thrown by ``RadioBrowserClient``.
public enum RadioBrowserError: Error, Sendable, Equatable, LocalizedError {
    /// The server answered with a status outside 200–299.
    case http(status: Int, host: String)
    /// The response was not the JSON the endpoint returns.
    case decoding(type: String, description: String)
    /// The request did not reach a server or got no answer.
    case transport(URLError)
    /// The response was not an HTTP response.
    case invalidResponse
    /// There is no mirror to send the request to.
    case noMirrorAvailable
    /// A path or parameter could not be made into a URL.
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .http(status, host): "Radio Browser (\(host)) answered HTTP \(status)."
        case let .decoding(type, description): "Couldn't read the \(type) from Radio Browser: \(description)"
        case let .transport(error): error.localizedDescription
        case .invalidResponse: "Radio Browser sent an invalid response."
        case .noMirrorAvailable: "No Radio Browser server is available."
        case let .invalidRequest(detail): "Invalid request: \(detail)"
        }
    }

    /// Worth trying again on another mirror: the network failed or the server had a problem.
    var triesAnotherMirror: Bool {
        switch self {
        case let .http(status, _): status == 429 || status >= 500
        case .transport, .invalidResponse: true
        case .decoding, .noMirrorAvailable, .invalidRequest: false
        }
    }
}
