import AppKit
import SwiftUI

/// Prepares the window of a screenshot scene: a fixed size of 1440 × 900 points, centered, dark,
/// no state restoration, the app in front.
///
/// scripts/screenshots-mac.sh waits for the ready marker, then captures the window with
/// `screencapture -l <window id>`. When that fails it launches the scene again with
/// `-render-screenshot <file>`, and the app draws its own window into a PNG once the scene is
/// ready (images included) and quits.
struct ScreenshotWindow: NSViewRepresentable {
    let scene: ScreenshotScene

    func makeNSView(context: Context) -> NSView {
        ConfiguringView(scene: scene)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        private let scene: ScreenshotScene
        private var isConfigured = false

        init(scene: ScreenshotScene) {
            self.scene = scene
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !isConfigured else { return }
            isConfigured = true

            window.appearance = NSAppearance(named: .darkAqua)
            window.isRestorable = false
            window.setContentSize(NSSize(width: 1440, height: 900))
            window.center()
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)

            if let path = ScreenshotScene.argument(after: "-render-screenshot") {
                ScreenshotReadiness.onReady = { _ in
                    ScreenshotRenderer.render(window, to: path)
                }
            }
        }
    }
}

/// The fallback: draws the window into a 2x bitmap with `cacheDisplay`, refuses a blank result,
/// writes the PNG and quits. Exits with status 1 on any failure so the CI script can give up.
@MainActor
enum ScreenshotRenderer {
    static func render(_ window: NSWindow, to path: String) {
        // The frame view holds the title bar and toolbar as well as the content.
        guard let view = window.contentView?.superview ?? window.contentView else {
            return fail("The window has no content view")
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let bounds = view.bounds
        let scale: CGFloat = 2
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(bounds.width * scale),
                  pixelsHigh: Int(bounds.height * scale),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              )
        else { return fail("Could not create a bitmap for \(bounds)") }

        // The bitmap's size in points against its pixel size makes the view draw at 2x.
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)

        guard distinctColorCount(in: bitmap) > 120 else {
            return fail("The rendered image is blank or has no artwork in it")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return fail("Could not encode the PNG")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return fail("Could not write \(path): \(error.localizedDescription)")
        }
        print("Rendered \(path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh), \(png.count) bytes)")
        exit(0)
    }

    /// Samples a grid of pixels. A window without images has few colors; favicons and monograms add many more.
    private static func distinctColorCount(in bitmap: NSBitmapImageRep) -> Int {
        var colors = Set<UInt32>()
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 120)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                colors.insert(channel(color.redComponent) << 16 | channel(color.greenComponent) << 8 | channel(color.blueComponent))
            }
        }
        return colors.count
    }

    private static func channel(_ component: CGFloat) -> UInt32 {
        UInt32(min(255, max(0, (component * 255).rounded())))
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("Screenshot failed: \(message)\n".utf8))
        exit(1)
    }
}
