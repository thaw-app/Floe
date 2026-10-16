//
//  ReturnRefusal.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// Return with no result to open: the panel shakes, and the field is outlined in red until the query changes.
final class ReturnRefusal: ObservableObject {
    /// Counts the refusals, so each one shakes the panel again.
    @Published private(set) var count = 0
    @Published private(set) var isShown = false

    func refuse() {
        count += 1
        isShown = true
    }

    func clear() {
        if isShown {
            isShown = false
        }
    }
}

/// Shakes the content sideways on each refusal; not at all under Reduce Motion.
struct RefusalShake: ViewModifier {
    @ObservedObject var refusal: ReturnRefusal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: reduceMotion ? 0 : refusal.count) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-8, duration: 0.05)
                CubicKeyframe(8, duration: 0.07)
                CubicKeyframe(-5, duration: 0.07)
                CubicKeyframe(5, duration: 0.07)
                CubicKeyframe(-2, duration: 0.06)
                CubicKeyframe(0, duration: 0.06)
            }
        }
    }
}
