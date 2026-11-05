// swift-tools-version: 6.0

import PackageDescription

// Fuzzing harnesses for Floe's attacker-reachable parsers, kept out of the app because libFuzzer supplies its own
// main. Sources are symlinked, so the harness compiles the shipped file.
//
// On Linux, build with swiftc; swift build's main symbol fights libFuzzer's entry point:
//   mkdir -p Tests/Fuzzing/.build/release
//   swiftc -parse-as-library -O -sanitize=fuzzer,address \
//     -o Tests/Fuzzing/.build/release/FuzzIncomingLink \
//     Tests/Fuzzing/Sources/FuzzIncomingLink/*.swift
//   ./Tests/Fuzzing/.build/release/FuzzIncomingLink -max_total_time=60 Tests/Fuzzing/Corpus/IncomingLink
//
// On macOS, replay the corpus without libFuzzer:
//   swift build --package-path Tests/Fuzzing -c release -Xswiftc -DFUZZ_REPLAY
//   ./Tests/Fuzzing/.build/release/FuzzIncomingLink Tests/Fuzzing/Corpus/IncomingLink
let package = Package(
    name: "FloeFuzz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FuzzIncomingLink",
            path: "Sources/FuzzIncomingLink"
        ),
    ]
)
