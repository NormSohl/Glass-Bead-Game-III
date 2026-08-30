// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GBGSound",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "GBGSound", targets: ["GBGSound"]),
    ],
    dependencies: [
        .package(path: "../GBGCore"),
    ],
    targets: [
        .target(name: "GBGSound", dependencies: ["GBGCore"]),
        .testTarget(name: "GBGSoundTests", dependencies: ["GBGSound"]),
    ]
)
