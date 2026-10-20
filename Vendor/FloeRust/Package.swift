// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FloeRust",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FloeRust", targets: ["FloeRust"]),
    ],
    targets: [
        .binaryTarget(
            name: "CFloeRust",
            path: "Frameworks/CFloeRust.xcframework"
        ),
        .target(
            name: "FloeRust",
            dependencies: ["CFloeRust"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FendTests",
            dependencies: ["FloeRust"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
