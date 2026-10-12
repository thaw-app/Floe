//
//  PanelChannel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Private inherited pipes, not broadcast notifications: only the parent and its child can send
/// commands here. Writes are ordered off the main thread so a busy peer cannot freeze the UI.
final class PanelChannel {
    private let input: FileHandle
    private let output: FileHandle
    private let writer = DispatchQueue(label: "org.thaw.floe.panel-writer")
    private var buffer = Data()
    private var closed = false
    var receive: (PanelPacket) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
        // A closed peer is a failed write, never a signal that kills the launcher.
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func start() {
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.accept(data) }
        }
    }

    private func accept(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { close(); onClose(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONDecoder().decode(PanelPacket.self, from: line) else {
                close()
                onClose()
                return
            }
            receive(message)
        }
        if buffer.count > 4 * 1_048_576 {
            close()
            onClose()
        }
    }

    func send(_ packet: PanelPacket) {
        guard !closed, var data = try? JSONEncoder().encode(packet) else { return }
        data.append(10)
        let output = output
        writer.async { [data] in try? output.write(contentsOf: data) }
    }

    func drain(then completion: @escaping @MainActor @Sendable () -> Void) {
        writer.async { DispatchQueue.main.async(execute: completion) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        input.readabilityHandler = nil
        try? input.close()
        let output = output
        writer.async { try? output.close() }
    }
}
