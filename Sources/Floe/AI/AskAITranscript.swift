//
//  AskAITranscript.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The conversation in the answer view: the earlier turns, then the question being answered with its
/// answer as it arrives and a line that says who answered and where.
struct AskAITranscript: View, Equatable {
    let turns: [AskAIModel.Turn]
    let question: String
    let shown: MarkdownContent
    let state: AskAIModel.State
    let source: AskAI.Source?
    /// Whether the last request went without the oldest turns.
    let leftOutTurns: Bool
    let scroll: AskAIModel.Scroll
    let askAgain: () -> Void
    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0
    /// The height the conversation scrolls in.
    @State private var viewport: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One arrow press moves the answer by about three lines.
    private static let scrollStep: CGFloat = 60
    private static let currentTurn = "current"

    /// What a new question changes, so the view scrolls to it once: a turn joined the earlier ones, or the question was replaced.
    private struct Asked: Equatable {
        let turns: Int
        let question: String
    }

    /// `askAgain` is left out: it does the same thing each time the view is made.
    static func == (lhs: AskAITranscript, rhs: AskAITranscript) -> Bool {
        lhs.turns == rhs.turns && lhs.question == rhs.question && lhs.shown == rhs.shown && lhs.state == rhs.state
            && lhs.source == rhs.source && lhs.leftOutTurns == rhs.leftOutTurns && lhs.scroll == rhs.scroll
    }

    var body: some View {
        if turns.isEmpty, shown.text.isEmpty {
            // A first question with no text yet: there is nothing to scroll.
            VStack(spacing: 0) {
                AskAIQuestion(text: question)
                pending.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            conversation
        }
    }

    @ViewBuilder
    private var pending: some View {
        if case let .failed(message) = state {
            ThawEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "No answer",
                caption: .verbatim(message),
                actionTitle: "Ask Again",
                action: askAgain
            )
        } else {
            ThawEmptyState(
                systemImage: AskAI.symbol,
                title: "Waiting for the answer…",
                caption: source.map { "\($0.line)" },
                isLoading: true
            )
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(turns) { turn in
                        // A finished turn never changes, so a batch of the answer under it draws none of it again.
                        AskAITurnView(turn: turn).equatable()
                        Divider().padding(.horizontal, 18)
                    }
                    current
                        // As tall as the view once it follows a turn, so its question can be brought to the top.
                        .frame(minHeight: turns.isEmpty ? nil : viewport, alignment: .top)
                        .id(Self.currentTurn)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in offset = new }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, new in viewport = new }
            .onChange(of: scroll) { _, scroll in
                // Home and End ask for more lines than there are; the scroll view stops at its ends.
                let step = CGFloat(max(-10000, min(scroll.lines, 10000))) * Self.scrollStep
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { position.scrollTo(y: max(0, offset + step)) }
            }
            .onChange(of: Asked(turns: turns.count, question: question)) {
                proxy.scrollTo(Self.currentTurn, anchor: .top)
            }
        }
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: 0) {
            AskAIQuestion(text: question)
            VStack(alignment: .leading, spacing: 14) {
                if !shown.text.isEmpty {
                    // Thaw's reading size and line spacing, for text that is read rather than scanned.
                    MarkdownView(content: shown, font: ThawType.body, lineSpacing: 6, loadsImages: false)
                } else if state == .asking || state == .answering {
                    HStack(spacing: ThawSpacing.row) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the answer…").foregroundStyle(.secondary)
                    }
                    // Read as one thing: the spinner alone says nothing.
                    .accessibilityElement(children: .combine)
                }
                if case let .failed(message) = state {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                if let source, !shown.text.isEmpty {
                    Label(source.line, systemImage: source.isOnThisMac ? "desktopcomputer" : "network")
                        .font(ThawType.footnote)
                        .foregroundStyle(.secondary)
                }
                if leftOutTurns {
                    Text(String(localized: "The oldest questions and answers were not sent with this one.", bundle: .floe, comment: "A note under an AI answer in a long conversation: only the most recent questions and answers went along as context."))
                        .font(ThawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A question in the conversation, as a heading over its answer.
struct AskAIQuestion: View {
    let text: String

    var body: some View {
        HStack(spacing: ThawSpacing.row) {
            Image(systemName: AskAI.symbol).font(.system(size: 17)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).font(.system(size: 17, weight: .semibold)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 54)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A turn that was answered: its question and the answer as it was parsed then.
struct AskAITurnView: View, Equatable {
    let turn: AskAIModel.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AskAIQuestion(text: turn.question)
            MarkdownView(content: turn.shown, font: ThawType.body, lineSpacing: 6, loadsImages: false)
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 18, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
