import Foundation
import Testing
@testable import RadioBrowserKit

@Suite("Favicons and monograms")
struct FaviconTests {
    @Test func acceptsHTTPAndHTTPS() {
        #expect(Favicon.url(from: "https://example.org/logo.png")?.absoluteString == "https://example.org/logo.png")
        #expect(Favicon.url(from: " http://example.org/a b.png ")?.absoluteString == "http://example.org/a%20b.png")
        #expect(Favicon.url(from: "//cdn.example.org/logo.svg")?.scheme == "https")
    }

    @Test func rejectsUnusableValues() {
        #expect(Favicon.url(from: "") == nil)
        #expect(Favicon.url(from: "null") == nil)
        #expect(Favicon.url(from: "logo.png") == nil)
        #expect(Favicon.url(from: "data:image/png;base64,AAAA") == nil)
        #expect(Favicon.url(from: "ftp://example.org/logo.png") == nil)
        // A relative path needs a homepage.
        #expect(Favicon.url(from: "/logo.png") == nil)
    }

    @Test func resolvesPathsAgainstTheHomepage() throws {
        let stations = try Fixture.decode([Station].self, from: "stations")
        #expect(stations[2].faviconURL?.absoluteString == "http://radio.example.com/images/icon.png")
        #expect(stations[0].faviconURL?.absoluteString == "http://jazz.example.org/logo-512.png")
        #expect(stations[0].secureFaviconURL?.absoluteString == "https://jazz.example.org/logo-512.png")
    }

    @Test func upgradesToHTTPS() throws {
        let url = try #require(URL(string: "http://example.org:80/logo.png"))
        #expect(Favicon.upgradingToHTTPS(url).absoluteString == "https://example.org/logo.png")
        let secure = try #require(URL(string: "https://example.org/logo.png"))
        #expect(Favicon.upgradingToHTTPS(secure) == secure)
    }

    @Test func monogramInitials() {
        #expect(StationMonogram(name: "Radio Paradise").initials == "RP")
        #expect(StationMonogram(name: "The Jazz Groove").initials == "JG")
        #expect(StationMonogram(name: "BBC Radio 1").initials == "B1")
        #expect(StationMonogram(name: "1LIVE").initials == "1L")
        #expect(StationMonogram(name: "  ").initials == "♪")
        #expect(StationMonogram(name: "café del mar").initials == "CM")
    }

    @Test func monogramHueIsStable() {
        let first = StationMonogram(name: "SWR3")
        let second = StationMonogram(name: "swr3")
        #expect(first.hue == second.hue)
        #expect(first.hue >= 0 && first.hue < 1)
        #expect(StationMonogram(name: "SWR3").hue != StationMonogram(name: "NDR 2").hue)
    }

    @Test func flags() {
        #expect(Country.flag(for: "tr") == "🇹🇷")
        #expect(Country.flag(for: "USA") == nil)
        #expect(Country.flag(for: "1A") == nil)
    }
}

@Suite("Streams and metadata")
struct StreamTests {
    @Test func streamKinds() throws {
        let hls = try #require(URL(string: "https://example.org/live/master.m3u8"))
        let pls = try #require(URL(string: "http://example.org/listen.pls"))
        let mp3 = try #require(URL(string: "http://example.org:8000/stream"))
        #expect(StreamKind(url: hls) == .hls)
        #expect(StreamKind(url: pls) == .playlist)
        #expect(StreamKind(url: mp3) == .direct)
        #expect(StreamKind(url: mp3, isHLS: true) == .hls)
    }

    @Test func readsPLS() {
        let text = """
        [playlist]
        NumberOfEntries=2
        File1=http://stream.example.org:8000/live
        Title1=Example
        File2=https://backup.example.org/live
        Version=2
        """
        #expect(StreamPlaylist.urls(in: text).map(\.absoluteString) == [
            "http://stream.example.org:8000/live",
            "https://backup.example.org/live",
        ])
    }

    @Test func readsM3UAndASX() {
        let m3u = "#EXTM3U\n#EXTINF:-1,Example\nhttp://stream.example.org/live.mp3\n"
        #expect(StreamPlaylist.firstURL(in: Data(m3u.utf8))?.absoluteString == "http://stream.example.org/live.mp3")
        let asx = #"<asx version="3.0"><entry><ref href="http://stream.example.org/asx"/></entry></asx>"#
        #expect(StreamPlaylist.urls(in: asx).first?.absoluteString == "http://stream.example.org/asx")
    }

    @Test func parsesStreamTitles() throws {
        let song = try #require(NowPlaying(streamTitle: "Miles Davis - So What"))
        #expect(song.artist == "Miles Davis")
        #expect(song.title == "So What")
        #expect(song.rawTitle == "Miles Davis - So What")

        let block = try #require(NowPlaying(streamTitle: "StreamTitle='Daft Punk - One More Time';StreamUrl='';"))
        #expect(block.artist == "Daft Punk")
        #expect(block.title == "One More Time")

        let show = try #require(NowPlaying(streamTitle: "Morning News"))
        #expect(show.artist == nil)
        #expect(show.title == "Morning News")

        #expect(NowPlaying(streamTitle: "  ") == nil)
        #expect(NowPlaying(streamTitle: "StreamTitle='';") == nil)
        #expect(NowPlaying(streamTitle: " - ") == nil)
    }

    #if canImport(AVFoundation)
    @Test func combinesTitleAndArtistMetadata() {
        #expect(RadioPlayer.nowPlaying(fromTitle: "So What", artist: "Miles Davis") == NowPlaying(artist: "Miles Davis", title: "So What"))
        #expect(RadioPlayer.nowPlaying(fromTitle: "Miles Davis - So What", artist: nil)?.artist == "Miles Davis")
        #expect(RadioPlayer.nowPlaying(fromTitle: nil, artist: nil) == nil)
    }

    @MainActor
    @Test func selectingAStationDoesNotConnect() throws {
        let stations = try Fixture.decode([Station].self, from: "stations")
        let player = RadioPlayer(client: nil)
        #expect(player.state == .idle)
        player.select(stations[0])
        #expect(player.state == .ready)
        #expect(player.station?.id == stations[0].id)
        #expect(player.player.currentItem == nil)
        player.stop()
        #expect(player.state == .idle)
        #expect(player.station == nil)
    }
    #endif
}
