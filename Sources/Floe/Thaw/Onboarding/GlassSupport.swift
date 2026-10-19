//
//  GlassSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the window background only; the tour draws its own icon tiles.

import AppKit
import SwiftUI
import ThawUI

/// A behind-window blend that also makes its window non-opaque, used as the
/// onboarding ground. SwiftUI has no behind-window blend, so this is not a
/// ThawGlass tier; content drawn over it uses .thawGlass(_:in:).
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        makeWindowTransparent(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        configure(nsView)
        makeWindowTransparent(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = false
    }

    private func makeWindowTransparent(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
