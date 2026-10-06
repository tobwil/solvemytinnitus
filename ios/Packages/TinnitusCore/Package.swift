// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinnitusCore",
    defaultLocalization: "de",
    platforms: [.iOS("18.1"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "TinnitusCore", targets: ["TinnitusCore"]),
    ],
    targets: [
        .target(name: "TinnitusCore"),
        .testTarget(name: "TinnitusCoreTests", dependencies: ["TinnitusCore"]),
    ],
    swiftLanguageModes: [.v6]
)
