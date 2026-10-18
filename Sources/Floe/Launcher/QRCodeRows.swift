//
//  QRCodeRows.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The QR code for what was typed after "qr": Return copies the picture.
final class QRCodeRows {
    var host = RowHost()
    /// Where the picture is copied to. Tests replace it, so they leave the clipboard alone.
    var pasteboard = NSPasteboard.general
    /// Where Save to Downloads writes, and how Quick Look shows a file. Tests replace both, so they touch neither.
    var downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    var preview: (URL) -> Void = { QuickLookPresenter.shared.show($0) }

    /// Return on a QR code: the picture goes to the clipboard.
    func copyQRCode(for text: String) {
        guard let image = ScreenTools.qrCode(for: text) else {
            host.showHUD(String(localized: "That is too long for a QR code", bundle: .floe))
            return
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
        host.leave()
        host.showHUD(String(localized: "Copied the QR code", bundle: .floe))
    }

    func qrCodeActions(for text: String) -> [ItemAction?] {
        [
            nil,
            ItemAction(title: String(localized: "Quick Look", bundle: .floe, comment: "The name of the macOS feature that previews a file."), symbol: "eye") { [weak self] in
                self?.writeQRCode(for: text, to: FileManager.default.temporaryDirectory).map { self?.preview($0) }
            },
            ItemAction(title: String(localized: "Save to Downloads", bundle: .floe), symbol: "arrow.down.circle") { [weak self] in
                guard let self, let folder = downloads,
                      let file = writeQRCode(for: text, to: folder) else { return }
                host.leave()
                host.showHUD(String(localized: "Saved \(file.lastPathComponent)", bundle: .floe, comment: "Shown briefly after saving. The placeholder is the name of the file."))
            },
        ]
    }

    /// Writes the code as a PNG that takes no other file's name. Nil when there is no code or it cannot be written.
    func writeQRCode(for text: String, to folder: URL) -> URL? {
        guard let data = ScreenTools.qrCode(for: text).flatMap(ScreenTools.png) else { return nil }
        let name = String(localized: "QR Code", bundle: .floe, comment: "The kind of a result, shown beside its title, and the name of the file it is saved as.")
        var file = folder.appendingPathComponent("\(name).png")
        var number = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("\(name) \(number).png")
            number += 1
        }
        return (try? data.write(to: file, options: .withoutOverwriting)) == nil ? nil : file
    }
}

extension QRCodeRows: RowOwner {
    func returnTitle(for item: RootItem) -> String? {
        guard case .qrCode = item else { return nil }
        return String(localized: "Copy Image", bundle: .floe, comment: "A button that copies a picture.")
    }

    func open(_ item: RootItem, flags _: NSEvent.ModifierFlags) -> Bool {
        guard case let .qrCode(text) = item else { return false }
        copyQRCode(for: text)
        return true
    }

    func actions(for item: RootItem) -> [ItemAction?]? {
        guard case let .qrCode(text) = item else { return nil }
        return qrCodeActions(for: text)
    }
}
