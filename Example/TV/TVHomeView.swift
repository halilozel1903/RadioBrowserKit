import RadioBrowserKit
import SwiftUI

/// The home screen: a fixed header with the brand and the station that is selected, and rails
/// of top, most voted and tagged stations below it.
struct TVHomeView: View {
    let scene: ScreenshotScene?
    @Environment(RadioStore.self) private var store

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            if let message = failure {
                TVMessage(title: "Couldn't load stations", message: message) {
                    Task { await loadAll(force: true) }
                }
            } else if store.phase(.topClicked) == .loaded {
                content
            } else {
                ProgressView()
            }
        }
        .task {
            await loadAll(force: false)
        }
        .signalsScreenshotReady(scene, when: isScreenshotReady)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 80)
                .padding(.top, 50)
                .padding(.bottom, 10)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(TVRail.allCases) { rail in
                        let stations = store.stations(rail.list)
                        if !stations.isEmpty {
                            TVStationRail(title: rail.title, subtitle: subtitle(for: rail), stations: Array(stations.prefix(20)))
                        }
                    }
                    Text("Stations from the Radio Browser community database (radio-browser.info). Streams are run by the stations.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 80)
                        .padding(.bottom, 60)
                }
                .padding(.top, 10)
            }
            // The header stays put above the rails; clip the scroll view so cards scrolled up
            // don't draw over it.
            .clipped()
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("WAVELENGTH")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(8)
            Spacer()
            Text("Live internet radio · Radio Browser")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for rail: TVRail) -> String? {
        switch rail {
        case .top: "Most played right now"
        case .voted: "The community's favorites"
        default: nil
        }
    }

    private var failure: String? {
        if case let .failed(message) = store.phase(.topClicked) { return message }
        return nil
    }

    private func loadAll(force: Bool) async {
        // The first rail first, so the screen fills quickly; the rest together.
        let store = self.store
        await store.load(.topClicked, force: force)
        let loads = TVRail.allCases.dropFirst().map { rail in
            Task { await store.load(rail.list, force: force) }
        }
        for load in loads {
            await load.value
        }
    }

    private var isScreenshotReady: Bool {
        guard scene != nil else { return false }
        // The rails on screen: the first three.
        let visible = TVRail.allCases.prefix(3)
        let loaded = visible.allSatisfy { store.phase($0.list) == .loaded && !store.stations($0.list).isEmpty }
        let first = Array(store.stations(.topClicked).prefix(6))
        return loaded && store.favicons.loadedCount(in: first) >= ScreenshotScene.minimumFavicons
    }
}
