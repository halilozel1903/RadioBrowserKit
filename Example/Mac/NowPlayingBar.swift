import RadioBrowserKit
import SwiftUI

/// The bar at the bottom of the window: the station, what it is playing, play/pause and volume.
struct NowPlayingBar: View {
    @Bindable var player: RadioPlayer

    var body: some View {
        HStack(spacing: 16) {
            if let station = player.station {
                StationArtwork(station: station, cornerRadius: 8)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(detail(for: station))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 520, alignment: .leading)
                Spacer(minLength: 12)
                statusBadge
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(player.isActive ? "Pause" : "Play")
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $player.volume, in: 0...1)
                        .frame(width: 110)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Pick a station to start listening")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 76)
        .background(Theme.surface)
    }

    /// The song when the station sends one, else the country and format.
    private func detail(for station: Station) -> String {
        if let song = player.nowPlaying {
            return [song.artist, song.title].compactMap { $0 }.joined(separator: " — ")
        }
        if case let .failed(message) = player.state {
            return message
        }
        return station.caption
    }

    private var statusBadge: some View {
        let isLive = player.state == .playing
        return HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.red : Color.secondary)
                .frame(width: 7, height: 7)
            Text(player.state.label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
