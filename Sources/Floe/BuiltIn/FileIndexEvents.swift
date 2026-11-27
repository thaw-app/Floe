//
//  FileIndexEvents.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
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
        let reported = zip(paths, flags).filter { $0.1 & unrelated == 0 }
        if reported.contains(where: { $0.1 & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 }) {
            return [.everything]
        }
        return Array(reported.map { path, flag in flag & lost != 0 ? FileIndexChange.subtree(path) : .folder(path) }.uniqued())
    }

    /// Folders the index never lists, so the stream need not report them: most of what changes under home is in Library.
    /// The system takes eight at most.
    static func excludedPaths(under root: String) -> [String] {
        ["Library", ".Trash", ".cache", ".npm", ".cargo", ".rustup"].map { root + "/" + $0 }
    }

    /// What names the numbering of a folder's events. A saved event number is only good on the same one:
    /// a disk that was erased, or another disk at the same path, counts from somewhere else.
    static func volume(of root: String) -> String? {
        var info = stat()
        guard stat(root, &info) == 0, let identifier = FSEventsCopyUUIDForDevice(info.st_dev) else { return nil }
        return CFUUIDCreateString(nil, identifier) as String?
    }

    /// Starts a stream over root, from now on or with everything since an earlier event first. Each report comes
    /// with the event it ends at. The returned closure stops the stream; nil when none could start, so the index
    /// knows it cannot follow the disk.
    static let watch: @Sendable (String, UInt64?, @escaping @Sendable ([FileIndexChange], UInt64) -> Void) -> (@Sendable () -> Void)? = { root, since, deliver in
        let stream = Stream(root: root, since: since, deliver: deliver)
        guard stream.start() else { return nil }
        return { stream.stop() }
    }

    /// The stream holds this, so a callback in flight never finds it gone. `events` is only touched on `queue` once started.
    private final class Stream: @unchecked Sendable {
        private let root: String
        private let since: UInt64?
        private let deliver: @Sendable ([FileIndexChange], UInt64) -> Void
        private let queue = DispatchQueue(label: "floe.file-index-events", qos: .utility)
        private var events: FSEventStreamRef?

        init(root: String, since: UInt64?, deliver: @escaping @Sendable ([FileIndexChange], UInt64) -> Void) {
            self.root = root
            self.since = since
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
                nil, Self.callback, &context, [root] as CFArray, since ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow), FileIndexEvents.latency, flags
            ) else { return false }
            events = stream
            FSEventStreamSetExclusionPaths(stream, FileIndexEvents.excludedPaths(under: root) as CFArray)
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                events = nil
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return false
            }
            return true
        }

        func stop() {
            queue.async {
                guard let stream = self.events else { return }
                self.events = nil
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }

        private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, eventIDs in
            guard let info, count > 0 else { return }
            let stream = Unmanaged<Stream>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let changes = FileIndexEvents.changes(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
            if !changes.isEmpty, stream.events != nil {
                stream.deliver(changes, eventIDs[count - 1])
            }
        }
    }
}
