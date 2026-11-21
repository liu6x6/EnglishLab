// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "WhisperCppKit", targets: ["WhisperCppKit"])
    ],
    targets: [
        .binaryTarget(name: "CWhisper", path: "whisper.xcframework"),
        .target(name: "WhisperCppKit", dependencies: ["CWhisper"])
    ]
)
