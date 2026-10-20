import Foundation
import SwiftUI

/// Scenes used by CI to capture the README screenshots on the Mac and an Apple TV simulator.
/// Launch with `-screenshot <scene>`; normal launches are unaffected.
///
/// Every scene loads real stations from the live Radio Browser API and their real favicons.
/// Stations whose favicon is missing, broken or too small get a monogram tile drawn from their
/// name. If the API fails, the scene never reports ready and CI fails. No audio is played: the
/// player shows the selected live station, ready to play.
enum ScreenshotScene: String, CaseIterable, Sendable {
    /// Mac: Top stations in the grid, countries and tags in the sidebar.
    case browse
    /// Mac: a search for "jazz".
    case search
    /// Apple TV: the station rails.
    case home
    /// Apple TV: the now-playing screen of the most clicked station.
    case nowplaying

    static var current: ScreenshotScene? {
        guard var name = argument(after: "-screenshot") else { return nil }
        for prefix in ["mac-", "tv-"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return ScreenshotScene(rawValue: name)
    }

    /// The text the `search` scene searches for.
    static let searchText = "jazz"

    /// How many real favicons a scene needs on screen before it reports ready.
    static let minimumFavicons = 4

    /// Where to write the ready marker: `-screenshot-ready-file <path>` (the Mac script passes
    /// one), or `tmp/screenshot-ready` in the app's container (what the Apple TV script watches).
    static var readyMarkerURL: URL {
        if let path = argument(after: "-screenshot-ready-file") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshot-ready")
    }

    static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// Writes a progress line to standard error in screenshot scenes. Unlike `print`, it is not
/// buffered, so the CI log shows how far a scene got even when the app is killed.
func screenshotLog(_ message: @autoclosure () -> String) {
    guard ScreenshotScene.current != nil else { return }
    FileHandle.standardError.write(Data(("[screenshot] " + message() + "\n").utf8))
}

/// Called once a screenshot scene is on screen, on the Mac to render the window as a fallback.
@MainActor
enum ScreenshotReadiness {
    static var onReady: (@MainActor (ScreenshotScene) -> Void)?
}

extension View {
    /// Writes the ready marker once `isReady` is true: the live data has loaded and the favicons
    /// on screen are decoded. Nothing is written when loading fails, so CI fails instead of
    /// committing a broken capture.
    func signalsScreenshotReady(_ scene: ScreenshotScene?, when isReady: Bool) -> some View {
        task(id: isReady) {
            guard let scene, isReady, ScreenshotScene.current == scene else { return }
            // Let the grid lay out and the images fade in.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            screenshotLog("\(scene.rawValue) is ready")
            do {
                try scene.rawValue.write(to: ScreenshotScene.readyMarkerURL, atomically: true, encoding: .utf8)
                print("Screenshot scene \(scene.rawValue) is ready")
            } catch {
                print("Could not write the ready marker: \(error)")
            }
            await MainActor.run {
                ScreenshotReadiness.onReady?(scene)
            }
        }
    }
}
