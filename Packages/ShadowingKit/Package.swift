// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShadowingKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ShadowingKit", targets: ["ShadowingKit"])
    ],
    targets: [
        .target(name: "ShadowingKit"),
        .testTarget(name: "ShadowingKitTests", dependencies: ["ShadowingKit"])
    ]
)
