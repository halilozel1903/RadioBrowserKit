import RadioBrowserKit
import SwiftUI

/// Wavelength for Apple TV: rails of live stations from the Radio Browser community database and
/// a now-playing screen.
@main
struct WavelengthTVApp: App {
    @State private var store: RadioStore

    init() {
        _store = State(initialValue: RadioStore.make(for: ScreenshotScene.current))
    }

    var body: some Scene {
        WindowGroup {
            TVRootView(scene: ScreenshotScene.current)
                .environment(store)
                .environment(store.favicons)
                .preferredColorScheme(.dark)
        }
    }
}

struct TVRootView: View {
    let scene: ScreenshotScene?
    @State private var path: [Station] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if scene == .nowplaying {
                    TVNowPlayingLauncher(scene: scene)
                } else {
                    TVHomeView(scene: scene)
                }
            }
            .navigationDestination(for: Station.self) { station in
                TVNowPlayingView(station: station, scene: nil)
            }
        }
    }
}

/// The rails of the home screen.
enum TVRail: CaseIterable, Identifiable {
    case top
    case voted
    case jazz
    case classical
    case news

    var id: Self { self }

    var title: String {
        switch self {
        case .top: "Top stations"
        case .voted: "Most voted"
        case .jazz: "Jazz"
        case .classical: "Classical"
        case .news: "News"
        }
    }

    var list: StationList {
        switch self {
        case .top: .topClicked
        case .voted: .topVoted
        case .jazz: .tag("jazz")
        case .classical: .tag("classical")
        case .news: .tag("news")
        }
    }
}

/// A row title and a horizontal, focusable rail of station cards.
struct TVStationRail: View {
    let title: String
    let subtitle: String?
    let stations: [Station]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 48) {
                    ForEach(stations) { station in
                        TVStationCard(station: station)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
            // Focused cards grow; let them draw outside the rail.
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

/// A station card. Only the artwork is the focusable card, so the system's lift and parallax
/// move the logo and never the text: the name and country sit below it.
struct TVStationCard: View {
    let station: Station
    static let side: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink(value: station) {
                StationArtwork(station: station, cornerRadius: 0)
                    .frame(width: Self.side, height: Self.side)
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                Text(station.countryLine ?? station.formatDescription ?? " ")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.side, alignment: .leading)
        }
    }
}

/// A full-screen message with a retry button.
struct TVMessage: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            Button("Try Again", action: retry)
        }
    }
}
