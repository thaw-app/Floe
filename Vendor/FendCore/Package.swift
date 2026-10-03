// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FendCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FendCore", targets: ["FendCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "CFendCore",
            path: "Frameworks/CFendCore.xcframework"
        ),
        .target(
            name: "FendCore",
            dependencies: ["CFendCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FendCoreTests",
            dependencies: ["FendCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
