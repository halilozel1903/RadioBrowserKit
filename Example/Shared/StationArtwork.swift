import RadioBrowserKit
import SwiftUI

/// The look of Wavelength, the example app.
enum Theme {
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.33)
    static let background = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.15)
    /// The light card behind favicons: most logos are drawn for a white web page.
    static let faviconBackdrop = Color(red: 0.95, green: 0.95, blue: 0.96)
}

/// A station's favicon on a light card, or a generated monogram tile when the station has no
/// usable favicon. The monogram is drawn from the station's real name; it stands in for a
/// missing logo, it is not a logo.
struct StationArtwork: View {
    let station: Station
    var cornerRadius: CGFloat = 14

    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let image = favicons.image(for: station.faviconURL) {
                    Theme.faviconBackdrop
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(side * 0.1)
                        .transition(.opacity)
                } else {
                    MonogramTile(monogram: station.monogram, side: side)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: station.faviconURL) {
            await favicons.load(station.faviconURL)
        }
        .accessibilityHidden(true)
    }
}

/// Initials on a gradient picked from the station's name.
struct MonogramTile: View {
    let monogram: StationMonogram
    let side: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(hue: monogram.hue, saturation: 0.55, brightness: 0.62),
                    Color(hue: monogram.hue, saturation: 0.7, brightness: 0.3),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(monogram.initials)
                .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: side * 0.1, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(side * 0.08)
        }
    }
}

/// A small tag capsule.
struct TagChip: View {
    let text: String
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, size * 0.25)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }
}

extension RadioPlayer.State {
    /// "Ready to play", "Live"…
    var label: String {
        switch self {
        case .idle: "Not playing"
        case .ready: "Ready to play"
        case .connecting: "Connecting…"
        case .playing: "Live"
        case .paused: "Paused"
        case .failed: "Can't play this stream"
        }
    }
}
