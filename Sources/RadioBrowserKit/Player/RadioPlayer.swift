#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import Foundation
import Observation

/// A small internet radio player on `AVPlayer`.
///
/// It plays HLS (`.m3u8`) and plain Icecast or Shoutcast streams, opens `.pls` and `.m3u`
/// playlists, counts a click with Radio Browser when a station starts, and reads the song that
/// is on from ICY `StreamTitle` metadata or HLS timed metadata, where the station sends it.
///
/// ```swift
/// @State private var player = RadioPlayer()
///
/// Button("Play") { player.play(station) }
/// Text(player.nowPlaying?.title ?? station.name)
/// ```
///
/// `select(_:)` puts a station in the player without connecting, for a "ready to play" state.
@MainActor
@Observable
public final class RadioPlayer {
    public enum State: Equatable, Sendable {
        /// No station.
        case idle
        /// A station is selected and not started.
        case ready
        /// Connecting or buffering.
        case connecting
        case playing
        case paused
        case failed(String)
    }

    public private(set) var station: Station?
    public private(set) var state: State = .idle
    /// The current song, when the station sends metadata.
    public private(set) var nowPlaying: NowPlaying?
    /// From 0 to 1.
    public var volume: Float {
        get {
            access(keyPath: \.volume)
            return player.volume
        }
        set {
            withMutation(keyPath: \.volume) {
                player.volume = min(1, max(0, newValue))
            }
        }
    }

    /// The underlying player, for AirPlay routes or an `AVRoutePickerView`.
    public let player = AVPlayer()

    private let client: RadioBrowserClient?
    private let session: URLSession
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var metadataReceiver: MetadataReceiver?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - client: Counts a click when a station starts; `nil` to never count clicks.
    ///   - session: Loads playlist files.
    public init(client: RadioBrowserClient? = .shared, session: URLSession = .shared) {
        self.client = client
        self.session = session
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.timeControlStatusChanged()
            }
        }
    }

    /// `true` while playing or connecting.
    public var isActive: Bool {
        state == .playing || state == .connecting
    }

    /// Selects `station` without connecting to it, and stops whatever was playing.
    public func select(_ station: Station) {
        stopPlayback()
        self.station = station
        nowPlaying = nil
        state = .ready
    }

    /// Plays `station`, replacing the current one.
    public func play(_ station: Station) {
        select(station)
        start(station)
    }

    /// Plays the selected station, or resumes it.
    public func play() {
        guard let station else { return }
        if state == .paused, player.currentItem != nil {
            player.play()
            state = .connecting
        } else if state != .playing, state != .connecting {
            start(station)
        }
    }

    /// Pauses. A live stream resumes at the live edge when it is far behind.
    public func pause() {
        guard player.currentItem != nil else { return }
        player.pause()
        state = .paused
    }

    public func togglePlayback() {
        isActive ? pause() : play()
    }

    /// Stops and forgets the station.
    public func stop() {
        stopPlayback()
        station = nil
        nowPlaying = nil
        state = .idle
    }

    // MARK: - Loading

    private func start(_ station: Station) {
        guard let url = station.streamURL else {
            state = .failed("This station has no stream URL.")
            return
        }
        generation += 1
        let current = generation
        state = .connecting
        if let client {
            let id = station.id
            Task.detached(priority: .utility) {
                _ = try? await client.countClick(stationID: id)
            }
        }
        let session = self.session
        loadTask = Task { [weak self] in
            var streamURL = url
            if station.streamKind == .playlist {
                if let response = try? await session.data(from: url), let first = StreamPlaylist.firstURL(in: response.0) {
                    streamURL = first
                }
            }
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.startItem(url: streamURL)
        }
    }

    private func startItem(url: URL) {
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let receiver = MetadataReceiver { [weak self] value in
            self?.nowPlaying = value
        }
        output.setDelegate(receiver, queue: .main)
        item.add(output)
        metadataReceiver = receiver
        itemStatusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
            let failed = item.status == .failed
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, failed else { return }
                self.state = .failed(message ?? "The stream could not be played.")
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func stopPlayback() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        metadataReceiver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func timeControlStatusChanged() {
        guard player.currentItem != nil else { return }
        if case .failed = state { return }
        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            state = .connecting
        case .paused:
            if state != .ready { state = .paused }
        @unknown default:
            break
        }
    }

    // MARK: - Metadata

    /// The song from a group of timed metadata: ICY `StreamTitle`, or a title and artist from
    /// ID3 or common metadata in HLS.
    nonisolated static func nowPlaying(fromTitle title: String?, artist: String?) -> NowPlaying? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty, !title.isEmpty {
            return NowPlaying(artist: artist, title: title)
        }
        return NowPlaying(streamTitle: title.isEmpty ? artist : title)
    }
}

/// Receives timed metadata on the main queue and passes the song on.
private final class MetadataReceiver: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    private let onUpdate: @MainActor (NowPlaying?) -> Void

    init(onUpdate: @escaping @MainActor (NowPlaying?) -> Void) {
        self.onUpdate = onUpdate
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        var title: String?
        var artist: String?
        for group in groups {
            for item in group.items {
                guard let value = item.stringValue else { continue }
                switch item.identifier {
                case .some(.icyMetadataStreamTitle), .some(.commonIdentifierTitle), .some(.id3MetadataTitleDescription):
                    title = value
                case .some(.commonIdentifierArtist), .some(.id3MetadataLeadPerformer):
                    artist = value
                default:
                    break
                }
            }
        }
        guard title != nil || artist != nil else { return }
        let song = RadioPlayer.nowPlaying(fromTitle: title, artist: artist)
        // The delegate queue is the main queue.
        MainActor.assumeIsolated {
            onUpdate(song)
        }
    }
}
#endif
