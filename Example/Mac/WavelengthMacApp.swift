import RadioBrowserKit
import SwiftUI

/// Wavelength for the Mac: top stations, countries and tags from the Radio Browser community
/// database in a sidebar, a grid of stations with their favicons, and a now-playing bar.
@main
struct WavelengthMacApp: App {
    @State private var store: RadioStore
    private let scene = ScreenshotScene.current

    init() {
        _store = State(initialValue: RadioStore.make(for: ScreenshotScene.current))
    }

    var body: some Scene {
        WindowGroup("Wavelength") {
            MacRootView(scene: scene)
                .environment(store)
                .environment(store.favicons)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(scene == nil ? nil : .dark)
                .tint(Theme.accent)
                .background {
                    if let scene {
                        ScreenshotWindow(scene: scene)
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
    }
}
