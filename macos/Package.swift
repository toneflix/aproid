// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aproid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Aproid", targets: ["Aproid"]),
        .library(name: "AproidKit", targets: ["AproidKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"4.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        // Protocol and networking. No UI, so it can be tested on its own.
        .target(
            name: "AproidKit",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        // The menu bar app.
        .executableTarget(
            name: "Aproid",
        .executableTarget(
            name: "Aproid",
            dependencies: ["AproidKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Linked by name so Shortcuts' metadata tool sees the app uses App Intents.
                .linkedFramework("AppIntents"),
                // Sparkle.framework is copied into Contents/Frameworks by bundle.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        ),
        .testTarget(name: "AproidKitTests", dependencies: ["AproidKit"]),
    ]
)
