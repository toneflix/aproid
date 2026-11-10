// swift-tools-version:5.9
import Foundation
import PackageDescription

// Shortcuts finds the app's actions through metadata built from compiler output Xcode normally asks for.
// These flags ask SwiftPM's compiler and linker for the same files; bundle.sh hands them to Apple's tool.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let intentsFlags = ["-emit-const-values", "-Xfrontend", "-const-gather-protocols-file", "-Xfrontend", "\(packageDir)/AppIntentsProtocols.json"]

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
            dependencies: ["AproidKit"],
            swiftSettings: [.unsafeFlags(intentsFlags)],
            linkerSettings: [
                .linkedFramework("AppIntents"),
                .unsafeFlags(["-Xlinker", "-dependency_info", "-Xlinker", "\(packageDir)/.build/Aproid_dependency_info.dat"]),
            ]
        ),
        .testTarget(name: "AproidKitTests", dependencies: ["AproidKit"]),
    ]
)
