// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aproid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Aproid", targets: ["Aproid"]),
        .library(name: "AproidKit", targets: ["AproidKit"]),
    ],
    targets: [
        // Protocol and networking. No UI, so it can be tested on its own.
        .target(name: "AproidKit"),
        // The menu bar app.
        .executableTarget(name: "Aproid", dependencies: ["AproidKit"]),
        .testTarget(name: "AproidKitTests", dependencies: ["AproidKit"]),
    ]
)
