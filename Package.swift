// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RadioBrowserKit",
    platforms: [
        .macOS(.v14),
        .tvOS(.v17),
        .iOS(.v17),
    ],
    products: [
        .library(name: "RadioBrowserKit", targets: ["RadioBrowserKit"]),
    ],
    targets: [
        .target(name: "RadioBrowserKit"),
        .testTarget(
            name: "RadioBrowserKitTests",
            dependencies: ["RadioBrowserKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
