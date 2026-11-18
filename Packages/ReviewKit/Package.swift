// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReviewKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ReviewKit", targets: ["ReviewKit"])
    ],
    targets: [
        .target(name: "ReviewKit"),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"])
    ]
)
