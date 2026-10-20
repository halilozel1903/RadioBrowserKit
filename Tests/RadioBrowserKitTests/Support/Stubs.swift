import Foundation
@testable import RadioBrowserKit

/// Recorded JSON responses in `Fixtures/`. The stations are made up; the shapes are Radio Browser's.
enum Fixture {
    struct Missing: Error {
        let name: String
    }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw Missing(name: name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

/// A canned HTTP response.
struct StubResponse: Sendable {
    var status: Int
    var body: Data

    static func json(_ fixture: String) throws -> StubResponse {
        try StubResponse(status: 200, body: Fixture.data(fixture))
    }

    static func status(_ status: Int) -> StubResponse {
        StubResponse(status: status, body: Data())
    }
}

typealias StubHandler = @Sendable (URLRequest) throws -> StubResponse

/// Answers requests from a handler registered for the request's host, so every test can run in
/// parallel with hosts of its own. Nothing ever reaches the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let handler = StubRegistry.shared.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        StubRegistry.shared.record(request)
        do {
            let stub = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }

    override func stopLoading() {}
}

final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    private let lock = NSLock()
    private var handlers: [String: StubHandler] = [:]
    private var requests: [URLRequest] = []

    func register(_ handler: @escaping StubHandler, for host: String) {
        lock.withLock { handlers[host.lowercased()] = handler }
    }

    func handler(for host: String) -> StubHandler? {
        lock.withLock { handlers[host.lowercased()] }
    }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func requests(toHosts hosts: Set<String>) -> [URLRequest] {
        lock.withLock { requests.filter { hosts.contains($0.url?.host?.lowercased() ?? "") } }
    }
}

/// A unique host name for one test.
func stubHost(_ label: String) -> String {
    "\(label)-\(UUID().uuidString.lowercased()).radio.test"
}

func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// A client on one stubbed mirror, without discovery.
struct StubbedClient {
    let host: String
    let client: RadioBrowserClient

    init(userAgent: String = RadioBrowserConfiguration.defaultUserAgent, handler: @escaping StubHandler) {
        host = stubHost("mirror")
        StubRegistry.shared.register(handler, for: host)
        client = RadioBrowserClient(configuration: .server(host, session: stubSession(), userAgent: userAgent))
    }

    var requests: [URLRequest] {
        StubRegistry.shared.requests(toHosts: [host])
    }

    var lastPath: String? {
        requests.last?.url?.path
    }

    var lastQuery: [String: String] {
        guard let url = requests.last?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        var query: [String: String] = [:]
        for item in items {
            query[item.name] = item.value ?? ""
        }
        return query
    }
}
