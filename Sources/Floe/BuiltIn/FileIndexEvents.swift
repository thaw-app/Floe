//
//  FileIndexEvents.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreServices
import Foundation

/// One thing the file system reported under the indexed folder.
nonisolated enum FileIndexChange: Hashable, Sendable {
    /// Something directly in this folder was added, removed or renamed.
    case folder(String)
    /// Events below this folder were lost: everything under it is read again.
    case subtree(String)
    /// The indexed folder itself was moved or replaced.
    case everything
}

/// The file system's events for the index: one stream over the folder, reporting folders and not single files.
nonisolated enum FileIndexEvents {
    /// How long the system gathers events before it reports them.
    static let latency: CFTimeInterval = 1

    /// What one report from the stream asks of the index, each folder once and in the order reported.
    static func changes(paths: [String], flags: [FSEventStreamEventFlags]) -> [FileIndexChange] {
        let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
        let unrelated = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        var seen = Set<FileIndexChange>()
        var changes: [FileIndexChange] = []
        for (path, flag) in zip(paths, flags) where flag & unrelated == 0 {
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                return [.everything]
            }
            let change = flag & lost != 0 ? FileIndexChange.subtree(path) : .folder(path)
            if seen.insert(change).inserted {
                changes.append(change)
            }
        }
        return changes
    }

    /// Folders the index never lists, so the stream need not report them: most of what changes under home is in Library.
    /// The system takes eight at most.
    static func excludedPaths(under root: String) -> [String] {
        ["Library", ".Trash", ".cache", ".npm", ".cargo", ".rustup"].map { root + "/" + $0 }
    }

    /// Starts a stream over `root`. The returned closure stops it; it does nothing when the stream could not start.
    static let watch: @Sendable (String, @escaping @Sendable ([FileIndexChange]) -> Void) -> (@Sendable () -> Void) = { root, deliver in
        let stream = Stream(root: root, deliver: deliver)
        guard stream.start() else { return { /* nothing was started */ } }
        return { stream.stop() }
    }

    /// The stream holds this, so a callback in flight never finds it gone. `stream` is only touched on `queue` once started.
    private final class Stream: @unchecked Sendable {
        private let root: String
        private let deliver: @Sendable ([FileIndexChange]) -> Void
        private let queue = DispatchQueue(label: "floe.file-index-events", qos: .utility)
        private var stream: FSEventStreamRef?

        init(root: String, deliver: @escaping @Sendable ([FileIndexChange]) -> Void) {
            self.root = root
            self.deliver = deliver
        }

        func start() -> Bool {
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<Stream>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<Stream>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
            guard let stream = FSEventStreamCreate(
                nil, Self.callback, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), FileIndexEvents.latency, flags
            ) else { return false }
            self.stream = stream
            FSEventStreamSetExclusionPaths(stream, FileIndexEvents.excludedPaths(under: root) as CFArray)
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                self.stream = nil
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return false
            }
            return true
        }

        func stop() {
            queue.async {
                guard let stream = self.stream else { return }
                self.stream = nil
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }

        private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let stream = Unmanaged<Stream>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let changes = FileIndexEvents.changes(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
            if !changes.isEmpty, stream.stream != nil {
                stream.deliver(changes)
            }
        }
    }
}
