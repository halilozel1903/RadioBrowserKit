import RadioBrowserKit
import SwiftUI

/// The `nowplaying` screenshot scene: loads the live top stations and opens the now-playing
/// screen of the most played one whose favicon loads.
struct TVNowPlayingLauncher: View {
    let scene: ScreenshotScene?
    @Environment(RadioStore.self) private var store

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            if let station = store.stations(.topClicked).first {
                TVNowPlayingView(station: station, scene: scene)
            } else if case let .failed(message) = store.phase(.topClicked) {
                TVMessage(title: "Couldn't load stations", message: message) {
                    Task { await store.load(.topClicked, force: true) }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await store.load(.topClicked)
        }
    }
}

/// A station's now-playing screen: its logo, name, country, language, tags and format, the
/// player's state and the song when the station sends one, a play button, and more stations
/// with the same tag.
struct TVNowPlayingView: View {
    let station: Station
    let scene: ScreenshotScene?

    @Environment(RadioStore.self) private var store
    @FocusState private var playFocused: Bool

    private var player: RadioPlayer { store.player }
    private var isCurrent: Bool { player.station?.id == station.id }
    private var similarList: StationList? {
        station.tags.first.map { StationList.tag($0) } ?? (station.countryCode.isEmpty ? nil : .country(code: station.countryCode))
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 70) {
                    // Not a button: the logo never moves under the text.
                    StationArtwork(station: station, cornerRadius: 28)
                        .frame(width: 400, height: 400)
                        .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
                    details
                }
                .padding(.horizontal, 100)
                .padding(.top, 60)
                Spacer(minLength: 20)
                similar
            }
        }
        .onAppear {
            // Select the station, ready to play. The screenshot scene stops here; no audio plays.
            if !isCurrent {
                player.select(station)
            }
            playFocused = true
        }
        .task(id: similarList) {
            if let similarList {
                await store.load(similarList)
            }
        }
        .signalsScreenshotReady(scene, when: isScreenshotReady)
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(hue: station.monogram.hue, saturation: 0.45, brightness: 0.22),
                Theme.background,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isCurrent && player.state == .playing ? Color.red : Theme.accent)
                    .frame(width: 14, height: 14)
                Text((isCurrent ? player.state.label : "Ready to play").uppercased())
                    .font(.system(size: 22, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.accent)
            }
            Text(station.name)
                .font(.system(size: 60, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if isCurrent, let song = player.nowPlaying {
                Label([song.artist, song.title].compactMap { $0 }.joined(separator: " — "), systemImage: "music.note")
                    .font(.system(size: 28, weight: .semibold))
            }
            Text(facts)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
            if !station.tags.isEmpty {
                HStack(spacing: 12) {
                    ForEach(station.tags.prefix(5), id: \.self) { tag in
                        TagChip(text: tag, size: 20)
                    }
                }
            }
            Text(stats)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            HStack(spacing: 30) {
                Button {
                    if isCurrent {
                        player.togglePlayback()
                    } else {
                        player.play(station)
                    }
                } label: {
                    Label(isCurrent && player.isActive ? "Pause" : "Play", systemImage: isCurrent && player.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .padding(.horizontal, 30)
                }
                .focused($playFocused)
                if let host = station.homepage?.host {
                    Text(host)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "🇩🇪 Germany · German · MP3 · 128 kbps".
    private var facts: String {
        let language = station.languages.first.map { $0.capitalized }
        return [station.countryLine, language, station.formatDescription].compactMap { $0 }.joined(separator: " · ")
    }

    /// "12,345 votes · 6,789 clicks in the last day".
    private var stats: String {
        "\(station.votes.formatted()) votes · \(station.clickCount.formatted()) clicks in the last day"
    }

    @ViewBuilder
    private var similar: some View {
        if let similarList {
            let stations = store.stations(similarList).filter { $0.id != station.id }
            if !stations.isEmpty {
                TVStationRail(
                    title: "More like this",
                    subtitle: station.tags.first.map { "#" + $0 } ?? station.countryLine,
                    stations: Array(stations.prefix(16))
                )
                .padding(.bottom, 40)
            }
        }
    }

    private var isScreenshotReady: Bool {
        guard scene != nil, player.station?.id == station.id, store.favicons.hasLoaded(station) else { return false }
        guard let similarList else { return true }
        return store.phase(similarList) == .loaded
    }
}
