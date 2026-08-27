// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GBGCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "GBGCore", targets: ["GBGCore"]),
    ],
    targets: [
        .target(name: "GBGCore"),
        .testTarget(name: "GBGCoreTests", dependencies: ["GBGCore"]),
    ]
)
