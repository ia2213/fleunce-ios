// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FleunceCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FleunceCore", targets: ["FleunceCore"])],
    targets: [
        .target(name: "FleunceCore", path: "Core"),
        .testTarget(name: "FleunceCoreTests", dependencies: ["FleunceCore"], path: "Tests")
    ]
)
