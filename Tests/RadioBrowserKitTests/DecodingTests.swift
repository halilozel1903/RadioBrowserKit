import Foundation
import Testing
@testable import RadioBrowserKit

@Suite("Decoding")
struct DecodingTests {
    @Test func decodesAFullStation() throws {
        let stations = try Fixture.decode([Station].self, from: "stations")
        #expect(stations.count == 3)
        let jazz = stations[0]
        #expect(jazz.id == "9617a958-0601-11e8-ae97-52543be04c81")
        #expect(jazz.changeID == "4f2b9c1e-1111-4a5b-9c3d-0123456789ab")
        #expect(jazz.name == "Example Jazz Lounge")
        #expect(jazz.url?.absoluteString == "http://stream.example.org/jazz.pls")
        #expect(jazz.resolvedURL?.absoluteString == "http://stream.example.org:8000/jazz-128.mp3")
        #expect(jazz.streamURL == jazz.resolvedURL)
        #expect(jazz.homepage?.host == "jazz.example.org")
        #expect(jazz.tags == ["jazz", "smooth jazz", "lounge"])
        #expect(jazz.country == "Germany")
        #expect(jazz.countryCode == "DE")
        #expect(jazz.subdivisionCode == "DE-BY")
        #expect(jazz.state == "Bavaria")
        #expect(jazz.languages == ["german", "english"])
        #expect(jazz.languageCodes == ["de", "en"])
        #expect(jazz.votes == 4210)
        #expect(jazz.clickCount == 1873)
        #expect(jazz.clickTrend == -12)
        #expect(jazz.codec == "MP3")
        #expect(jazz.bitrate == 128)
        #expect(!jazz.isHLS)
        #expect(jazz.lastCheckOK)
        #expect(!jazz.isBroken)
        #expect(!jazz.hasSSLError)
        #expect(!jazz.hasExtendedInfo)
        #expect(jazz.latitude == 48.137)
        #expect(jazz.longitude == 11.575)
        #expect(jazz.lastCheckTime == Date(timeIntervalSince1970: 1_792_188_605))
        #expect(jazz.clickTimestamp != nil)
        #expect(jazz.formatDescription == "MP3 · 128 kbps")
        #expect(jazz.countryFlag == "🇩🇪")
    }

    @Test func decodesSparseAndHLSStations() throws {
        let stations = try Fixture.decode([Station].self, from: "stations")
        let news = stations[1]
        #expect(news.isHLS)
        #expect(news.streamKind == .hls)
        #expect(news.isBroken)
        #expect(news.hasSSLError)
        #expect(news.hasExtendedInfo)
        #expect(news.homepage == nil)
        #expect(news.faviconURL == nil)
        #expect(news.tags.isEmpty)
        #expect(news.state == nil)
        #expect(news.subdivisionCode == nil)
        #expect(news.latitude == nil)
        #expect(news.lastChangeTime != nil)
        #expect(news.lastCheckOKTime == nil)
        #expect(news.formatDescription == "AAC · HLS")
    }

    @Test func decodesNumbersAndBooleansSentAsStrings() throws {
        let stations = try Fixture.decode([Station].self, from: "stations")
        let pop = stations[2]
        #expect(pop.votes == 42)
        #expect(pop.bitrate == 96)
        #expect(pop.clickCount == 7)
        #expect(pop.clickTrend == 0)
        #expect(!pop.isHLS)
        #expect(pop.lastCheckOK)
        #expect(pop.latitude == 52.52)
        #expect(pop.resolvedURL == nil)
        #expect(pop.streamURL?.absoluteString == "http://radio.example.com/live%20stream")
        #expect(pop.countryFlag == nil)
        #expect(pop.formatDescription == "96 kbps")
        #expect(pop.changeID == nil)
    }

    @Test func rejectsAStationWithoutAnID() {
        let json = Data(#"[{"name": "No id"}]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Station].self, from: json)
        }
    }

    @Test func decodesCountries() throws {
        let countries = try Fixture.decode([Country].self, from: "countries")
        #expect(countries.map(\.code) == ["US", "DE", ""])
        #expect(countries[1].name == "Germany")
        #expect(countries[1].stationCount == 3988)
        #expect(countries[1].flag == "🇩🇪")
        #expect(countries[2].flag == nil)
        #expect(countries[2].id == "")
    }

    @Test func decodesTagsAndLanguages() throws {
        let tags = try Fixture.decode([StationTag].self, from: "tags")
        #expect(tags.map(\.name) == ["pop", "news", "jazz"])
        #expect(tags[2].stationCount == 1450)

        let languages = try Fixture.decode([StationLanguage].self, from: "languages")
        #expect(languages.map(\.code) == ["en", "de", nil])
        #expect(languages[1].displayName == "German")
    }

    @Test func decodesServersAndClicks() throws {
        let servers = try Fixture.decode([ServerMirror].self, from: "servers")
        #expect(servers.map(\.name) == [
            "de1.api.radio-browser.info",
            "de1.api.radio-browser.info",
            "fi1.api.radio-browser.info",
            "at1.api.radio-browser.info",
        ])
        #expect(MirrorPool.unique(servers.map(\.name)).count == 3)

        let click = try Fixture.decode(ClickResult.self, from: "click")
        #expect(click.ok)
        #expect(click.stationID == "9617a958-0601-11e8-ae97-52543be04c81")
        #expect(click.url?.port == 8000)
    }
}
