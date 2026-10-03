// swift-tools-version: 6.4
import PackageDescription

// The Swift 6 language mode with the main actor as the default isolation, and the two features that
// SWIFT_APPROACHABLE_CONCURRENCY adds to it in project.yml. Keep the two files in step.
let concurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Floe",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Vendor/ThawUI"),
        .package(path: "Vendor/ThawConcurrency"),
        // Keep in step with project.yml.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-algorithms", exact: "1.2.1"),
        .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.1.3"),
        // Only swift-async-algorithms uses this. Held back because 1.7 does not build with the Xcode 27 beta.
        .package(url: "https://github.com/apple/swift-collections", exact: "1.6.0"),
        .package(path: "Vendor/FendCore"),
    ],
    targets: [
        .executableTarget(
            name: "Floe",
            dependencies: [
                "ThawUI",
                "ThawConcurrency",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "FendCore", package: "FendCore"),
            ],
            resources: [.process("Resources")],
            swiftSettings: concurrency
        ),
        // The test bundle links the app's code, so it loads Sparkle.framework too. SwiftPM puts the
        // framework beside the bundle, three levels above the bundle's binary, and adds no rpath for it.
        .testTarget(
            name: "FloeTests",
            dependencies: [
                "Floe",
                .product(name: "FendCore", package: "FendCore"),
            ],
            swiftSettings: concurrency,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])
            ]
        ),
    ]
)
