// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VocabularyKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VocabularyKit", targets: ["VocabularyKit"])
    ],
    targets: [
        .target(
            name: "VocabularyKit",
            resources: [.copy("Resources/ecdict.sqlite")]
        ),
        .testTarget(name: "VocabularyKitTests", dependencies: ["VocabularyKit"])
    ]
)
