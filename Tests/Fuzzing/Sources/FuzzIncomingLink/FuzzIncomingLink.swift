//
//  FuzzIncomingLink.swift
//  Project: Floe
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Adapted from Thaw's Fuzzing/Sources/FuzzSettingsURI/FuzzSettingsURI.swift. Floe's changes: the properties
//  check IncomingLink instead of SettingsURIParser, and the replay fails on a corpus it can't read or that is empty.
//  The entry point is Thaw's.
//
//  libFuzzer harness for IncomingLink, which reads the links any app can send Floe.
//  A failed property counts as a finding, like a crash.
//
//  -sanitize=fuzzer works only on Linux, so fuzzing runs in CI; -DFUZZ_REPLAY replays the corpus on macOS.
//

import Foundation

/// Called by libFuzzer for each generated input. It always returns 0; failures trap.
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
    let bytes = UnsafeRawBufferPointer(start: start, count: count)

    guard let text = String(bytes: bytes, encoding: .utf8), let url = URL(string: text) else {
        return 0
    }

    // Parsing is total and keeps no hidden state.
    let link = IncomingLink(url: url, oauthIsParked: false)
    let parked = IncomingLink(url: url, oauthIsParked: true)
    precondition(link == IncomingLink(url: url, oauthIsParked: false), "IncomingLink is not deterministic for \(text)")

    checkRoute(link, url: url, text: text)
    checkRoute(parked, url: url, text: text)
    checkReturn(link, url: url, text: text)
    checkParking(link, parked: parked, text: text)
    checkState(url, text: text)
    return 0
}

/// Each answer comes only from the scheme and host that name it, so no other link can reach a sign-in or Thaw's answer.
private func checkRoute(_ link: IncomingLink, url: URL, text: String) {
    let scheme = url.scheme?.lowercased()
    switch link {
    case .oauth:
        precondition(IncomingLink.isOAuthCallback(url), "Not a sign-in's return, yet routed as one: \(text)")
    case .thawAppearance:
        precondition(scheme == "floe", "Thaw's answer from another scheme: \(text)")
        precondition(url.host?.lowercased() == IncomingLink.thawAppearanceHost, "Thaw's answer from another host: \(text)")
    case .raycast:
        precondition(scheme.map(IncomingLink.redirectSchemes.contains) == true, "Sent to Raycast from another scheme: \(text)")
        precondition(!IncomingLink.isOAuthCallback(url), "A sign-in's return was sent to Raycast: \(text)")
    case .ignored:
        break
    }
    if scheme != "floe", !IncomingLink.redirectSchemes.contains(scheme ?? "") {
        precondition(link == .ignored, "A scheme Floe doesn't own was acted on: \(text)")
    }
}

/// With sign-in on, every sign-in's return reaches it.
private func checkReturn(_ link: IncomingLink, url: URL, text: String) {
    if IncomingLink.isOAuthCallback(url) {
        precondition(link == .oauth, "A sign-in's return went elsewhere: \(text)")
    }
}

/// Parking sign-in stops the returns and changes nothing else.
private func checkParking(_ link: IncomingLink, parked: IncomingLink, text: String) {
    precondition(parked != .oauth, "A sign-in's return got through while parked: \(text)")
    precondition(parked == (link == .oauth ? .ignored : link), "Parking changed another link: \(text)")
}

/// Only a sign-in's return has a state to answer with.
private func checkState(_ url: URL, text: String) {
    if IncomingLink.oauthState(of: url) != nil {
        precondition(IncomingLink.isOAuthCallback(url), "State read from a link that is no return: \(text)")
    }
}

#if FUZZ_REPLAY
    /// Replays every file in a corpus directory through the harness, for macOS where libFuzzer is unavailable.
    @main
    enum Replay {
        static func main() {
            let arguments = CommandLine.arguments
            guard arguments.count > 1 else {
                FileHandle.standardError.write(Data("usage: FuzzIncomingLink <corpus-dir>...\n".utf8))
                exit(2)
            }

            var replayed = 0
            for directory in arguments.dropFirst() {
                let url = URL(fileURLWithPath: directory)
                let files: [URL]
                do {
                    files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                } catch {
                    FileHandle.standardError.write(Data("can't read \(directory): \(error)\n".utf8))
                    exit(1)
                }

                for file in files {
                    guard let data = try? Data(contentsOf: file) else { continue }
                    data.withUnsafeBytes { raw in
                        guard let base = raw.baseAddress else { return }
                        _ = LLVMFuzzerTestOneInput(base, raw.count)
                    }
                    replayed += 1
                }
            }

            guard replayed > 0 else {
                FileHandle.standardError.write(Data("no corpus inputs to replay\n".utf8))
                exit(1)
            }
            print("replayed \(replayed) corpus inputs; all properties held")
        }
    }
#endif
