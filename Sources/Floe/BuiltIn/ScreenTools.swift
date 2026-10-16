//
//  ScreenTools.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import CoreImage
import Vision

/// What a picture of the screen holds: the text of its QR codes and barcodes, and the text that can be read in it.
nonisolated struct ScreenReading: Equatable, Sendable {
    var codes: [String] = []
    var text = ""
}

/// The commands that look at the screen, and the QR code made from a text. Each is the system's own:
/// the color sampler, the capture that draws its crosshair, Vision and Core Image.
nonisolated enum ScreenTools {
    enum Tool {
        case pickColor, copyText
    }

    static let qrKeyword = "qr"

    // MARK: Color

    /// "#A1B2C3" for a color, as sRGB. Nil for one that has no sRGB form.
    static func hex(_ color: NSColor) -> String? {
        guard let color = color.usingColorSpace(.sRGB) else { return nil }
        let part: (CGFloat) -> Int = { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", part(color.redComponent), part(color.greenComponent), part(color.blueComponent))
    }

    /// The system's eyedropper. Nil when Escape ends it.
    @MainActor
    static func pickColor() async -> NSColor? {
        let sampler = NSColorSampler()
        let color = await withCheckedContinuation { continuation in
            sampler.show { continuation.resume(returning: $0) }
        }
        // The sampler is kept until it has answered.
        withExtendedLifetime(sampler) {}
        return color
    }

    // MARK: Reading

    /// The codes and the text Vision finds in a picture. Empty for one it finds nothing in. Off the main thread:
    /// reading takes seconds where no text model is installed.
    @concurrent
    static func read(_ image: CGImage) async -> ScreenReading {
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.automaticallyDetectsLanguage = true
        async let lines = try? text.perform(on: image)
        async let codes = try? DetectBarcodesRequest().perform(on: image)
        return await ScreenReading(
            codes: (codes ?? []).compactMap(\.payloadString),
            text: (lines ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        )
    }

    /// What goes to the clipboard, and the line that says so: a code's text before the text around it.
    static func copied(from reading: ScreenReading) -> (text: String, line: String)? {
        if !reading.codes.isEmpty {
            return (reading.codes.joined(separator: "\n"), String(localized: "Copied what the code says", bundle: .floe, comment: "Shown after a QR code or a barcode on the screen was read."))
        }
        guard !reading.text.isEmpty else { return nil }
        return (reading.text, String(localized: "Copied the text", bundle: .floe, comment: "Shown after text on the screen was read."))
    }

    /// The part of the screen the user drags over, taken by the system's own capture. Nil when Escape ends it.
    @concurrent
    static func capture() async -> CGImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("floe-screen-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try? await Shell.run(URL(fileURLWithPath: "/usr/sbin/screencapture"), ["-i", "-x", "-t", "png", file.path])
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: QR codes

    /// A QR code for a text, black on white with the quiet margin a reader needs. Nil for a text too long for one.
    static func qrCode(for text: String, side: CGFloat = 640) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(text.utf8), "inputCorrectionLevel": "M"]),
              let code = filter.outputImage, code.extent.width > 0
        else { return nil }
        // The generator draws one pixel a module: scaled by a whole number, the edges stay sharp.
        let scale = max(1, (side / (code.extent.width + 8)).rounded(.down))
        let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let margin = 4 * scale
        let frame = scaled.extent.insetBy(dx: -margin, dy: -margin)
        return CIContext().createCGImage(scaled.composited(over: CIImage(color: .white).cropped(to: frame)), from: frame)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    // MARK: Running

    /// Runs a tool and says what came of it. The task is for tests to wait on.
    @MainActor
    @discardableResult
    static func run(_ tool: Tool, say: @escaping @MainActor (String) -> Void) -> Task<Void, Never> {
        PanelWork.perform {
            switch tool {
            case .pickColor:
                guard let hex = await pickColor().flatMap(hex) else { return }
                NSPasteboard.general.copy(hex)
                say(String(localized: "Copied \(hex)", bundle: .floe, comment: "Shown briefly after copying. The placeholder is what was copied, such as a file name."))
            case .copyText:
                guard CGPreflightScreenCaptureAccess() else {
                    CGRequestScreenCaptureAccess()
                    say(String(localized: "Floe needs Screen Recording to read the screen. Allow it in System Settings, then try again.", bundle: .floe, comment: "Screen Recording is the name of a permission in System Settings."))
                    return
                }
                guard let image = await capture() else { return }
                guard let found = await copied(from: read(image)) else {
                    say(String(localized: "No text was found there", bundle: .floe))
                    return
                }
                NSPasteboard.general.copy(found.text)
                say(found.line)
            }
        }
    }
}

/// "qr https://example.com": the code for what was typed, to copy, look at or save.
struct QRCodeSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard let text = context.text(after: ScreenTools.qrKeyword) else { return SearchContribution() }
        return SearchContribution(pinned: [RootResult(item: .qrCode(text), section: nil)])
    }
}
