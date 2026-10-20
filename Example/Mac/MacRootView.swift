import RadioBrowserKit
import SwiftUI

/// What the sidebar can show.
enum SidebarItem: Hashable {
    case top
    case voted
    case search
    case country(String)
    case tag(String)
}

/// The sidebar with Top, Countries and Tags, the station grid, and the now-playing bar.
struct MacRootView: View {
    let scene: ScreenshotScene?

    @Environment(RadioStore.self) private var store
    @State private var selection: SidebarItem?
    @State private var searchText: String

    init(scene: ScreenshotScene?) {
        self.scene = scene
        _selection = State(initialValue: scene == .search ? .search : .top)
        _searchText = State(initialValue: scene == .search ? ScreenshotScene.searchText : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
            .navigationSplitViewStyle(.balanced)
            Divider()
            NowPlayingBar(player: store.player)
        }
        .task {
            await store.loadDirectory()
        }
        .signalsScreenshotReady(scene, when: isScreenshotReady)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Discover") {
                Label("Top stations", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarItem.top)
                Label("Most voted", systemImage: "heart")
                    .tag(SidebarItem.voted)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }
            Section("Countries") {
                if store.countries.isEmpty {
                    directoryPlaceholder
                }
                ForEach(store.countries.prefix(9)) { country in
                    SidebarRow(
                        title: country.displayName,
                        leading: country.flag ?? "🌐",
                        count: country.stationCount
                    )
                    .tag(SidebarItem.country(country.code))
                }
            }
            Section("Tags") {
                if store.tags.isEmpty {
                    directoryPlaceholder
                }
                ForEach(store.tags.prefix(10)) { tag in
                    SidebarRow(title: tag.name, leading: "#", count: tag.stationCount)
                        .tag(SidebarItem.tag(tag.name))
                }
            }
        }
        // An opaque sidebar: a translucent one can be captured as a blank white panel on CI.
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .safeAreaInset(edge: .bottom) {
            Label("Radio Browser community database", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface)
        }
        .navigationTitle("Wavelength")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    @ViewBuilder
    private var directoryPlaceholder: some View {
        if case let .failed(message) = store.directoryPhase {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .top {
        case .top:
            StationGridScreen(
                list: .topClicked,
                title: "Top stations",
                subtitle: "The most played stations on Radio Browser right now",
                scene: scene == .browse ? scene : nil
            )
        case .voted:
            StationGridScreen(list: .topVoted, title: "Most voted", subtitle: "The community's favorite stations", scene: nil)
        case let .country(code):
            let country = store.countries.first { $0.code == code }
            StationGridScreen(
                list: .country(code: code),
                title: [country?.flag, country?.displayName ?? code].compactMap { $0 }.joined(separator: " "),
                subtitle: country.map { "\($0.stationCount.formatted()) stations, most played first" } ?? "",
                scene: nil
            )
        case let .tag(tag):
            StationGridScreen(list: .tag(tag), title: "#\(tag)", subtitle: "Stations tagged \(tag), most played first", scene: nil)
        case .search:
            SearchScreen(text: $searchText, scene: scene == .search ? scene : nil)
        }
    }

    private var isScreenshotReady: Bool {
        guard let scene else { return false }
        let list: StationList = scene == .search ? .search(ScreenshotScene.searchText) : .topClicked
        let stations = store.stations(list)
        return store.directoryPhase == .loaded
            && store.phase(list) == .loaded
            && store.player.station != nil
            && store.favicons.loadedCount(in: Array(stations.prefix(12))) >= ScreenshotScene.minimumFavicons
    }
}

/// A sidebar row with a leading symbol and a station count.
private struct SidebarRow: View {
    let title: String
    let leading: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(leading)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(count.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A title, a subtitle and a grid of stations.
struct StationGridScreen: View {
    let list: StationList
    let title: String
    let subtitle: String
    let scene: ScreenshotScene?

    @Environment(RadioStore.self) private var store

    var body: some View {
        StationGrid(list: list, title: title, subtitle: subtitle, scene: scene)
            .task(id: list) {
                await store.load(list)
                selectFirstForScreenshot()
            }
    }

    private func selectFirstForScreenshot() {
        // The screenshot shows the first station in the player, ready to play; no audio plays.
        guard scene != nil, store.player.station == nil, let first = store.stations(list).first else { return }
        store.player.select(first)
    }
}

/// The search field and its results.
struct SearchScreen: View {
    @Binding var text: String
    let scene: ScreenshotScene?

    @Environment(RadioStore.self) private var store
    @State private var submitted = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Station name", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { submitted = text }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if submitted.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search Radio Browser", systemImage: "dot.radiowaves.left.and.right", description: Text("Type part of a station's name and press Return."))
            } else {
                StationGrid(
                    list: .search(submitted),
                    title: "“\(submitted)”",
                    subtitle: "Stations whose name contains \(submitted), most played first",
                    scene: scene
                )
            }
        }
        .onAppear {
            if submitted.isEmpty { submitted = text }
        }
        .task(id: submitted) {
            let query = submitted.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            await store.load(.search(query), force: scene == nil)
            if scene != nil, store.player.station == nil, let first = store.stations(.search(query)).first {
                store.player.select(first)
            }
        }
    }
}

/// The grid of station tiles with a header.
struct StationGrid: View {
    let list: StationList
    let title: String
    let subtitle: String
    let scene: ScreenshotScene?

    @Environment(RadioStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 220), spacing: 22, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                switch store.phase(list) {
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn't load stations", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            Task { await store.load(list, force: true) }
                        }
                    }
                case .loaded where store.stations(list).isEmpty:
                    ContentUnavailableView("No stations", systemImage: "radio")
                case .loaded:
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(store.stations(list)) { station in
                            StationTile(station: station)
                        }
                    }
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(28)
        }
    }
}

/// A station's favicon, name, country, format and tags. Click to play.
struct StationTile: View {
    let station: Station

    @Environment(RadioStore.self) private var store

    var body: some View {
        let isCurrent = store.player.station?.id == station.id
        Button {
            store.player.play(station)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                StationArtwork(station: station, cornerRadius: 16)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isCurrent ? Theme.accent : Color.white.opacity(0.06), lineWidth: isCurrent ? 3 : 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                Text(station.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(station.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(station.tags.prefix(2), id: \.self) { tag in
                        TagChip(text: tag, size: 10)
                    }
                }
                .frame(height: 16, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(station.homepage?.host ?? station.name)
    }
}
