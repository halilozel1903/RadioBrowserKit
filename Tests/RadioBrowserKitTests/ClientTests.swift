import Foundation
import Testing
@testable import RadioBrowserKit

@Suite("Client")
struct ClientTests {
    @Test func searchSendsEveryParameter() async throws {
        let stub = StubbedClient { _ in try .json("stations") }
        var search = StationSearch(name: "jazz", countryCode: "de", language: "german", tag: "smooth jazz", codec: "MP3")
        search.bitrateMin = 128
        search.order = .clickCount
        search.reverse = true
        search.limit = 30
        search.offset = 60

        let stations = try await stub.client.searchStations(search)

        #expect(stations.count == 3)
        #expect(stub.lastPath == "/json/stations/search")
        let query = stub.lastQuery
        #expect(query["name"] == "jazz")
        #expect(query["countrycode"] == "DE")
        #expect(query["language"] == "german")
        #expect(query["tag"] == "smooth jazz")
        #expect(query["codec"] == "MP3")
        #expect(query["bitrateMin"] == "128")
        #expect(query["order"] == "clickcount")
        #expect(query["reverse"] == "true")
        #expect(query["hidebroken"] == "true")
        #expect(query["limit"] == "30")
        #expect(query["offset"] == "60")
        #expect(query["nameExact"] == nil)
    }

    @Test func searchLeavesOutUnsetFilters() {
        let items = StationSearch(name: "  ", hideBroken: false, limit: nil).queryItems
        #expect(items.map(\.name) == ["hidebroken"])
        #expect(items.first?.value == "false")
    }

    @Test func sendsTheUserAgent() async throws {
        let stub = StubbedClient { _ in try .json("stations") }
        _ = try await stub.client.topClickedStations(limit: 5)
        let request = try #require(stub.requests.last)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "RadioBrowserKit/1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        let custom = StubbedClient(userAgent: "MyRadio/2.1") { _ in try .json("stations") }
        _ = try await custom.client.topVotedStations()
        #expect(custom.requests.last?.value(forHTTPHeaderField: "User-Agent") == "MyRadio/2.1")
    }

    @Test func topLists() async throws {
        let stub = StubbedClient { _ in try .json("stations") }
        _ = try await stub.client.topClickedStations(limit: 12, offset: 24)
        #expect(stub.lastPath == "/json/stations/topclick")
        #expect(stub.lastQuery == ["limit": "12", "offset": "24", "hidebroken": "true"])

        _ = try await stub.client.topVotedStations(limit: 10, hideBroken: false)
        #expect(stub.lastPath == "/json/stations/topvote")
        #expect(stub.lastQuery == ["limit": "10", "hidebroken": "false"])
    }

    @Test func directoryEndpoints() async throws {
        let stub = StubbedClient { request in
            switch request.url?.path {
            case "/json/countries": return try StubResponse.json("countries")
            case "/json/tags": return try StubResponse.json("tags")
            case "/json/languages": return try StubResponse.json("languages")
            default: return StubResponse.status(404)
            }
        }
        let countries = try await stub.client.countries()
        #expect(countries.count == 3)
        #expect(stub.lastQuery == ["order": "stationcount", "reverse": "true", "hidebroken": "true"])

        let tags = try await stub.client.tags(order: .name, reverse: false, limit: 20)
        #expect(tags.first?.name == "pop")
        #expect(stub.lastQuery == ["order": "name", "reverse": "false", "hidebroken": "true", "limit": "20"])

        let languages = try await stub.client.languages()
        #expect(languages.count == 3)
        #expect(stub.lastPath == "/json/languages")
    }

    @Test func countsAClick() async throws {
        let stub = StubbedClient { _ in try .json("click") }
        let result = try await stub.client.countClick(stationID: "9617A958-0601-11E8-AE97-52543BE04C81")
        #expect(result.ok)
        #expect(stub.lastPath == "/json/url/9617a958-0601-11e8-ae97-52543be04c81")
    }

    @Test func rejectsAnInvalidStationID() async {
        let stub = StubbedClient { _ in try .json("click") }
        await #expect(throws: RadioBrowserError.self) {
            try await stub.client.countClick(stationID: "../stations")
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func reportsHTTPErrors() async {
        let stub = StubbedClient { _ in .status(404) }
        do {
            _ = try await stub.client.topClickedStations()
            Issue.record("Expected an error")
        } catch let error as RadioBrowserError {
            #expect(error == .http(status: 404, host: stub.host))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func reportsDecodingErrors() async {
        let stub = StubbedClient { _ in StubResponse(status: 200, body: Data(#"{"not": "a list"}"#.utf8)) }
        do {
            _ = try await stub.client.topClickedStations()
            Issue.record("Expected an error")
        } catch let RadioBrowserError.decoding(type, _) {
            #expect(type == "Array<Station>")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func fetchesStationsByID() async throws {
        let stub = StubbedClient { _ in try .json("stations") }
        let none = try await stub.client.stations(ids: [])
        #expect(none.isEmpty)
        #expect(stub.requests.isEmpty)
        _ = try await stub.client.stations(ids: ["a", "b"])
        #expect(stub.lastPath == "/json/stations/byuuid")
        #expect(stub.lastQuery["uuids"] == "a,b")
    }
}
