// swift-tools-version: 6.4
// Vendored from thaw-app/Thaw (ThawUI/); the commit is recorded in UPSTREAM. Tests are not carried over.
// Floe's own changes, to keep on a sync until Thaw has them: .panel glass without the extra hairline, focus rings
// that follow the capsule in ThawActionGroup and ThawCapsuleSegments, and ThawInk.supporting for unselected segments.

import PackageDescription

let package = Package(
    name: "ThawUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ThawUI", targets: ["ThawUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/buh/CompactSlider", from: "2.1.0"),
    ],
    targets: [
        .target(name: "ThawUI", dependencies: ["CompactSlider"]),
    ]
)
