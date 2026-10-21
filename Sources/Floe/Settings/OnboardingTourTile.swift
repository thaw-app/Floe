//
//  OnboardingTourTile.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// What a tile of the tour shows above its caption: something typed and what it finds, or the hotkey's keys.
enum TourDemo {
    case search(query: String, rows: [TourRow])
    case keys([String])
    /// A question typed for Ask AI, over the marks of what can answer it, lit one at a time.
    case ask(query: String, marks: [String])
    /// One Mac's settings going to another through iCloud.
    case sync
}

/// The marks of the AI services and tools, as SVG files in Floe's resources, drawn in the text's color.
enum AIMark {
    static let all = ["claude", "openai", "apple-intelligence", "opencode", "pi", "ollama", "lmstudio", "openrouter", "zai"]

    // The resources' own bundle: `Bundle.floe` is the language inside it, which holds only the strings.
    #if SWIFT_PACKAGE
        private static let bundle = Bundle.module
    #else
        private static let bundle = Bundle.main
    #endif

    static func image(_ name: String) -> NSImage? {
        guard let url = bundle.url(forResource: "ai-mark-\(name)", withExtension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// One result of a demo search: its symbol, its title, and what sits at the end of the row.
struct TourRow {
    let symbol: String
    let title: String
    var trailing: String?
}

/// A card of the tour in Thaw's bento style: a small demo over the feature's name and a caption.
/// Flat fills and hairlines, since the window's own vibrancy is the only glass the page needs.
struct OnboardingTourTile: View {
    let symbol: String
    let title: String
    let caption: String
    let demo: TourDemo
    let index: Int
    let appeared: Bool

    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    /// One loop of a demo, in seconds.
    private static let period: TimeInterval = 4.5

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            stage
            captionBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onboardingCard()
        .thawHoverLift()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .thawAnimation(ThawMotion.settle.delay(Double(index) * 0.04), value: appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title). \(caption)"))
    }

    /// The loops are staggered by the tile's place, so the grid never types in unison. Paused in a window in the
    /// background, and still under Reduce Motion.
    private var stage: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !appearsActive || reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate) / Self.period + Double(index) * 0.13
            TourDemoContent(demo: demo, phase: reduceMotion ? 1 : elapsed.truncatingRemainder(dividingBy: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.top, ThawSpacing.inset)
        .clipped()
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            HStack(spacing: ThawSpacing.compact) {
                OnboardingIconTile(symbol: symbol)
                Text(verbatim: title)
                    .font(ThawType.heading)
                    .lineLimit(1)
            }
            Text((try? AttributedString(markdown: caption)) ?? AttributedString(caption))
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.bottom, ThawSpacing.row)
    }
}

/// The surface the welcome's cards share: a flat fill and a hairline, since the window's vibrancy is the glass.
extension View {
    func onboardingCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
        return background(shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
            .clipShape(shape)
    }
}

/// A symbol in a small colored square, as a settings pane is named in a sidebar.
struct OnboardingIconTile: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A demo drawn from a phase in 0..<1, so it owns no state: the query types itself out, the rows arrive once it
/// is whole, and the frame at phase 1 is the finished one.
private struct TourDemoContent: View {
    let demo: TourDemo
    let phase: Double

    var body: some View {
        switch demo {
        case let .search(query, rows):
            search(query: query, rows: rows)
        case let .keys(keys):
            keycaps(keys)
        case let .ask(query, marks):
            ask(query: query, marks: marks)
        case .sync:
            sync
        }
    }

    private func field(_ query: String, typing: Bool) -> some View {
        let typed = query.prefix(Int((min(phase / 0.5, 1) * Double(query.count)).rounded()))
        return HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(verbatim: String(typed))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: 12)
                .opacity(typing ? 1 : 0)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// Once the question is typed, each mark lights in turn, as each of them can be the one that answers.
    private func ask(query: String, marks: [String]) -> some View {
        let answering = phase >= 0.5
        let lit = answering ? min(Int((phase - 0.5) / 0.5 * Double(marks.count)), marks.count - 1) : -1
        return VStack(alignment: .leading, spacing: 8) {
            field(query, typing: !answering)
            HStack(spacing: 14) {
                ForEach(Array(marks.enumerated()), id: \.offset) { position, mark in
                    if let image = AIMark.image(mark) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(position == lit ? Color.primary : Color.secondary)
                            .opacity(position == lit || phase >= 1 ? 1 : 0.45)
                            .scaleEffect(position == lit ? 1.15 : 1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.15), value: lit)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A dot carries the settings from one Mac up to iCloud and down to the other.
    private var sync: some View {
        HStack(spacing: 6) {
            Image(systemName: "laptopcomputer")
            track(progress: min(phase / 0.45, 1))
            Image(systemName: "icloud")
                .foregroundStyle(Color.accentColor)
            track(progress: max(0, min((phase - 0.45) / 0.45, 1)))
            Image(systemName: "desktopcomputer")
        }
        // Sized to fit a tile one column wide: the tracks give way before the computers do.
        .font(.system(size: 18))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func track(progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 2)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .offset(x: (geometry.size.width - 6) * progress)
                    .opacity(progress > 0 && progress < 1 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 12, maxWidth: 28)
        .frame(height: 10)
    }

    private func search(query: String, rows: [TourRow]) -> some View {
        // Typing takes the first half of the loop, the rows hold for the rest.
        let found = phase >= 0.55
        return VStack(alignment: .leading, spacing: 4) {
            field(query, typing: !found)
            ForEach(Array(rows.enumerated()), id: \.offset) { position, row in
                resultRow(row, selected: position == 0)
                    .opacity(found ? 1 : 0)
                    .offset(y: found ? 0 : 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: found)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func resultRow(_ row: TourRow, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: row.symbol)
                .frame(width: 14)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(verbatim: row.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing = row.trailing {
                Text(verbatim: trailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// The hotkey's keys go down one after another, then all together, as a hand presses them.
    private func keycaps(_ keys: [String]) -> some View {
        let down = Int(phase * Double(keys.count + 2))
        return HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { position, key in
                let pressed = position < down && phase < 0.85
                Text(verbatim: key)
                    .font(.system(size: 15, weight: .medium))
                    .frame(minWidth: 34, minHeight: 34)
                    .padding(.horizontal, key.count > 1 ? 8 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(pressed ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(pressed ? 0 : 0.2), radius: 0, y: pressed ? 0 : 1.5)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                    .offset(y: pressed ? 1.5 : 0)
            }
        }
        .animation(.easeOut(duration: 0.1), value: down)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
