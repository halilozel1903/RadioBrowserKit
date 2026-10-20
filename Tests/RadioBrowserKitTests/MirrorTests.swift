import Foundation
import Testing
@testable import RadioBrowserKit

@Suite("Mirrors")
struct MirrorTests {
    /// A discovery host that lists the given mirrors.
    private func discovery(listing mirrors: [String]) -> URL {
        let host = stubHost("all")
        let body = try? JSONEncoder().encode(mirrors.map { ["name": $0, "ip": "203.0.113.1"] })
        StubRegistry.shared.register({ _ in StubResponse(status: 200, body: body ?? Data()) }, for: host)
        return URL(string: "https://\(host)/json/servers")!
    }

    @Test func usesTheDiscoveredMirrors() async {
        let a = stubHost("a"), b = stubHost("b")
        let pool = MirrorPool(discoveryURL: discovery(listing: [a, b, a]), fallback: ["fallback.test"], session: stubSession(), shuffle: { $0 })
        #expect(await pool.orderedHosts() == [a, b])
        #expect(await pool.current() == a)
    }

    @Test func fallsBackWhenDiscoveryFails() async {
        let broken = stubHost("all")
        StubRegistry.shared.register({ _ in .status(503) }, for: broken)
        let pool = MirrorPool(
            discoveryURL: URL(string: "https://\(broken)/json/servers"),
            fallback: ["de1.api.radio-browser.info", "DE1.api.radio-browser.info", "fi1.api.radio-browser.info"],
            session: stubSession(),
            shuffle: { $0 }
        )
        #expect(await pool.orderedHosts() == ["de1.api.radio-browser.info", "fi1.api.radio-browser.info"])
    }

    @Test func shufflesTheMirrors() async {
        let pool = MirrorPool(discoveryURL: nil, fallback: ["a.test", "b.test", "c.test"], shuffle: { Array($0.reversed()) })
        #expect(await pool.orderedHosts() == ["c.test", "b.test", "a.test"])
    }

    @Test func defaultsMatchRadioBrowser() {
        let configuration = RadioBrowserConfiguration()
        #expect(configuration.discoveryURL?.absoluteString == "https://all.api.radio-browser.info/json/servers")
        #expect(configuration.fallbackMirrors == [
            "de1.api.radio-browser.info",
            "de2.api.radio-browser.info",
            "fi1.api.radio-browser.info",
            "at1.api.radio-browser.info",
        ])
        #expect(configuration.userAgent == "RadioBrowserKit/1.0")
    }

    @Test func movesAFailedMirrorToTheBack() async {
        let pool = MirrorPool(discoveryURL: nil, fallback: ["a.test", "b.test", "c.test"], shuffle: { $0 })
        _ = await pool.orderedHosts()
        await pool.markFailed("a.test")
        #expect(await pool.orderedHosts() == ["b.test", "c.test", "a.test"])
        await pool.markFailed("unknown.test")
        #expect(await pool.current() == "b.test")
    }

    @Test func failsOverToTheNextMirror() async throws {
        let down = stubHost("down"), up = stubHost("up")
        StubRegistry.shared.register({ _ in .status(502) }, for: down)
        StubRegistry.shared.register({ _ in try .json("tags") }, for: up)
        let session = stubSession()
        let configuration = RadioBrowserConfiguration(session: session, discoveryURL: nil, fallbackMirrors: [down, up])
        let pool = MirrorPool(discoveryURL: nil, fallback: [down, up], session: session, shuffle: { $0 })
        let client = RadioBrowserClient(configuration: configuration, mirrors: pool)

        let tags = try await client.tags()

        #expect(tags.count == 3)
        #expect(StubRegistry.shared.requests(toHosts: [down]).count == 1)
        #expect(StubRegistry.shared.requests(toHosts: [up]).count == 1)
        // The next request goes straight to the mirror that worked.
        #expect(await pool.current() == up)
    }

    @Test func failsOverOnUnreachableMirrors() async throws {
        let missing = stubHost("missing"), up = stubHost("up")
        StubRegistry.shared.register({ _ in try .json("countries") }, for: up)
        let session = stubSession()
        let pool = MirrorPool(discoveryURL: nil, fallback: [missing, up], session: session, shuffle: { $0 })
        let client = RadioBrowserClient(
            configuration: RadioBrowserConfiguration(session: session, discoveryURL: nil, fallbackMirrors: [missing, up]),
            mirrors: pool
        )
        let countries = try await client.countries()
        #expect(countries.count == 3)
    }

    @Test func doesNotFailOverOnClientErrors() async {
        let first = stubHost("first"), second = stubHost("second")
        StubRegistry.shared.register({ _ in .status(400) }, for: first)
        StubRegistry.shared.register({ _ in try .json("tags") }, for: second)
        let session = stubSession()
        let pool = MirrorPool(discoveryURL: nil, fallback: [first, second], session: session, shuffle: { $0 })
        let client = RadioBrowserClient(
            configuration: RadioBrowserConfiguration(session: session, discoveryURL: nil, fallbackMirrors: [first, second]),
            mirrors: pool
        )
        await #expect(throws: RadioBrowserError.http(status: 400, host: first)) {
            try await client.tags()
        }
        #expect(StubRegistry.shared.requests(toHosts: [second]).isEmpty)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let hosts = (0..<4).map { stubHost("down\($0)") }
        for host in hosts {
            StubRegistry.shared.register({ _ in .status(500) }, for: host)
        }
        let session = stubSession()
        let pool = MirrorPool(discoveryURL: nil, fallback: hosts, session: session, shuffle: { $0 })
        let client = RadioBrowserClient(
            configuration: RadioBrowserConfiguration(session: session, discoveryURL: nil, fallbackMirrors: hosts, maxMirrorAttempts: 2),
            mirrors: pool
        )
        await #expect(throws: RadioBrowserError.self) {
            try await client.topVotedStations()
        }
        #expect(StubRegistry.shared.requests(toHosts: Set(hosts)).count == 2)
    }
}
