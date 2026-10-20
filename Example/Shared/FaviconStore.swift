import CoreGraphics
import Foundation
import ImageIO
import Observation
import RadioBrowserKit
import SwiftUI

/// Loads station favicons and remembers which ones work.
///
/// Favicons are entered by the community: many are missing, point at pages instead of images,
/// are SVGs, or are 16-pixel icons that would look blurry on a large tile. Only images at least
/// `minimumPixelSize` pixels wide are used; every other station gets a monogram tile.
@Observable
@MainActor
final class FaviconStore {
    enum Entry {
        case loading
        case loaded(Image)
        case failed
    }

    private(set) var entries: [URL: Entry] = [:]
    @ObservationIgnored private var tasks: [URL: Task<Data?, Never>] = [:]

    /// The smallest favicon worth showing, in pixels.
    nonisolated static let minimumPixelSize = 64

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "Wavelength/1.0 " + RadioBrowserConfiguration.defaultUserAgent]
        configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 128 << 20)
        return URLSession(configuration: configuration)
    }()

    func image(for url: URL?) -> Image? {
        guard let url, case let .loaded(image) = entries[url] else { return nil }
        return image
    }

    func hasLoaded(_ station: Station) -> Bool {
        image(for: station.faviconURL) != nil
    }

    /// Loads one favicon; `true` when it can be shown.
    @discardableResult
    func load(_ url: URL?) async -> Bool {
        guard let url else { return false }
        switch entries[url] {
        case .loaded: return true
        case .failed: return false
        default: break
        }
        let task: Task<Data?, Never>
        if let running = tasks[url] {
            task = running
        } else {
            task = Task.detached(priority: .utility) {
                await Self.fetch(url)
            }
            tasks[url] = task
            entries[url] = .loading
        }
        let data = await task.value
        tasks[url] = nil
        if case .loaded = entries[url] { return true }
        if let data, let image = Self.decode(data) {
            entries[url] = .loaded(image)
            return true
        }
        entries[url] = .failed
        return false
    }

    /// Loads the favicons of `stations`, a few at a time.
    func prefetch(_ stations: [Station], concurrency: Int = 8) async {
        let urls = Array(Set(stations.compactMap(\.faviconURL)))
        var index = 0
        while index < urls.count {
            let batch = urls[index..<min(index + concurrency, urls.count)]
            // Plain tasks on the main actor; the loads themselves run off it.
            let loads = batch.map { url in
                Task { await self.load(url) }
            }
            for load in loads {
                _ = await load.value
            }
            index += concurrency
        }
    }

    /// The stations with a working favicon first, otherwise in their original order.
    func ranked(_ stations: [Station]) -> [Station] {
        stations.filter { hasLoaded($0) } + stations.filter { !hasLoaded($0) }
    }

    /// How many of `stations` show a real favicon.
    func loadedCount(in stations: [Station]) -> Int {
        stations.filter { hasLoaded($0) }.count
    }

    // MARK: - Network and decoding

    /// The image bytes, or `nil` when the URL does not return an image that is large enough.
    private nonisolated static func fetch(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard largestRepresentation(in: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// The index and size of the largest image in the data (ICO files hold several), when it is at
    /// least `minimumPixelSize` on its short side.
    private nonisolated static func largestRepresentation(in data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: (index: Int, size: Int)?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { continue }
            let size = min(width, height)
            if size > (best?.size ?? 0) {
                best = (index, size)
            }
        }
        guard let best, best.size >= minimumPixelSize else { return nil }
        return best.index
    }

    /// The largest image, scaled down to at most 512 pixels.
    private static func decode(_ data: Data) -> Image? {
        guard let index = largestRepresentation(in: data),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}
