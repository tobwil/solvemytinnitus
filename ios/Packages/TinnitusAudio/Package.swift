// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinnitusAudio",
    platforms: [.iOS("18.1"), .macOS(.v15)],
    products: [
        .library(name: "TinnitusAudio", targets: ["TinnitusAudio"]),
    ],
    dependencies: [
        .package(path: "../TinnitusCore"),
    ],
    targets: [
        .target(name: "TinnitusAudio", dependencies: ["TinnitusCore"]),
        .testTarget(name: "TinnitusAudioTests", dependencies: ["TinnitusAudio"]),
    ],
    swiftLanguageModes: [.v6]
)
