// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubtitleKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SubtitleKit", targets: ["SubtitleKit"])
    ],
    targets: [
        .target(name: "SubtitleKit"),
        .testTarget(name: "SubtitleKitTests", dependencies: ["SubtitleKit"])
    ]
)
