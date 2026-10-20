import Foundation
import Observation
import RadioBrowserKit

/// A list of stations the app can show.
enum StationList: Hashable, Sendable {
    case topClicked
    case topVoted
    case country(code: String)
    case tag(String)
    case search(String)
}

/// The app's data: the countries and tags directory and station lists, all from one
/// `RadioBrowserClient` on the live Radio Browser API, plus the player.
@Observable
@MainActor
final class RadioStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let client: RadioBrowserClient
    let favicons: FaviconStore
    let player: RadioPlayer
    /// Screenshot scenes put stations whose favicon loads first and show only those they checked.
    let prefersLoadedFavicons: Bool
    /// How many times a request is tried before the error is shown.
    private let attempts: Int

    private(set) var countries: [Country] = []
    private(set) var tags: [StationTag] = []
    private(set) var directoryPhase: Phase = .idle
    private(set) var lists: [StationList: [Station]] = [:]
    private(set) var phases: [StationList: Phase] = [:]

    init(client: RadioBrowserClient, player: RadioPlayer, prefersLoadedFavicons: Bool = false, attempts: Int = 1) {
        self.client = client
        self.player = player
        self.favicons = FaviconStore()
        self.prefersLoadedFavicons = prefersLoadedFavicons
        self.attempts = max(1, attempts)
    }

    /// A store on the live API. Screenshot scenes retry failed requests a few times (on other
    /// mirrors), since a capture must not show an error, and never count clicks.
    static func make(for scene: ScreenshotScene?) -> RadioStore {
        if scene != nil {
            return RadioStore(client: .shared, player: RadioPlayer(client: nil), prefersLoadedFavicons: true, attempts: 4)
        }
        return RadioStore(client: .shared, player: RadioPlayer(client: .shared))
    }

    // MARK: - Directory

    /// The countries and tags with the most stations.
    func loadDirectory() async {
        guard directoryPhase != .loading, directoryPhase != .loaded else { return }
        directoryPhase = .loading
        do {
            let client = self.client
            let (countries, tags) = try await Self.retrying(attempts: attempts) {
                async let countries = client.countries(limit: 40)
                async let tags = client.tags(limit: 60)
                return try await (countries, tags)
            }
            self.countries = countries.filter { !$0.code.isEmpty && $0.stationCount > 0 }
            self.tags = tags.filter { !Self.genericTags.contains($0.name.lowercased()) && $0.name.count > 1 }
            directoryPhase = .loaded
        } catch {
            directoryPhase = .failed(error.localizedDescription)
        }
    }

    /// Tags on so many stations that they say nothing.
    private static let genericTags: Set<String> = ["music", "radio", "fm", "am", "webradio", "web radio", "internet radio", "online radio", "local radio", "variety"]

    // MARK: - Stations

    func stations(_ list: StationList) -> [Station] {
        lists[list] ?? []
    }

    func phase(_ list: StationList) -> Phase {
        phases[list] ?? .idle
    }

    /// Loads a list once (search lists every time).
    func load(_ list: StationList, force: Bool = false) async {
        let current = phase(list)
        guard current != .loading else { return }
        if current == .loaded, !force { return }
        phases[list] = .loading
        do {
            let client = self.client
            var stations = try await Self.retrying(attempts: attempts) {
                try await Self.fetch(list, from: client)
            }
            stations = Self.removingDuplicates(stations)
            if prefersLoadedFavicons {
                // Check the favicons of the first stations and put the ones that load first. Many
                // stations have no favicon or a broken one; those get a monogram tile.
                let candidates = Array(stations.prefix(36))
                await favicons.prefetch(candidates)
                stations = favicons.ranked(candidates)
            }
            lists[list] = stations
            phases[list] = .loaded
        } catch is CancellationError {
            phases[list] = .idle
        } catch {
            phases[list] = .failed(error.localizedDescription)
        }
    }

    private nonisolated static func fetch(_ list: StationList, from client: RadioBrowserClient) async throws -> [Station] {
        switch list {
        case .topClicked:
            return try await client.topClickedStations(limit: 80)
        case .topVoted:
            return try await client.topVotedStations(limit: 80)
        case let .country(code):
            return try await client.searchStations(StationSearch(countryCode: code, order: .clickCount, reverse: true, limit: 80))
        case let .tag(tag):
            return try await client.searchStations(StationSearch(tag: tag, tagExact: true, order: .clickCount, reverse: true, limit: 80))
        case let .search(text):
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return [] }
            return try await client.searchStations(StationSearch(name: query, order: .clickCount, reverse: true, limit: 80))
        }
    }

    /// The same station is often listed several times (one per stream quality). Keep the first.
    private static func removingDuplicates(_ stations: [Station]) -> [Station] {
        var seen = Set<String>()
        return stations.filter { station in
            let key = station.name.lowercased().filter { $0.isLetter || $0.isNumber }
            return !station.name.isEmpty && seen.insert(key.isEmpty ? station.id : key).inserted
        }
    }

    /// Runs `operation`, trying again after a pause when it fails, up to `attempts` times.
    private nonisolated static func retrying<T: Sendable>(
        attempts: Int,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < attempts, !Task.isCancelled else { throw error }
                print("Request failed (attempt \(attempt) of \(attempts)): \(error)")
                try await Task.sleep(for: .seconds(Double(attempt) * 2))
                attempt += 1
            }
        }
    }
}

extension Country {
    /// "United States" instead of the database's "The United States Of America".
    var displayName: String {
        Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? name
    }
}

extension Station {
    /// "🇩🇪 Germany", or nothing without a country.
    var countryLine: String? {
        guard !countryCode.isEmpty else { return country.isEmpty ? nil : country }
        let name = Locale(identifier: "en_US").localizedString(forRegionCode: countryCode) ?? country
        return [countryFlag, name].compactMap { $0 }.joined(separator: " ")
    }

    /// "🇩🇪 Germany · MP3 · 128 kbps".
    var caption: String {
        [countryLine, formatDescription].compactMap { $0 }.joined(separator: " · ")
    }
}
