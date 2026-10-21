import SwiftUI

public struct TaisaStreamingText: View {
    public enum Motion: Sendable, Equatable {
        case softWordResolution
        case instant

        public static let standard: Self = .softWordResolution
        public static let reduced: Self = .instant
    }

    private struct WordAttribute: TextAttribute { let index: Int }

    private struct WordRenderer: TextRenderer {
        let now: Date
        let revealDates: [Date]
        let motion: Motion

        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line {
                    var copy = context
                    let progress = revealProgress(for: run[WordAttribute.self]?.index)
                    copy.opacity = progress
                    if motion == .softWordResolution {
                        copy.addFilter(.blur(radius: TaisaEffect.streamingWordBlurRadius * (1 - progress)))
                    }
                    copy.draw(run)
                }
            }
        }

        private func revealProgress(for index: Int?) -> Double {
            guard motion == .softWordResolution, let index else { return 1 }
            guard revealDates.indices.contains(index) else { return 0 }
            let elapsed = now.timeIntervalSince(revealDates[index])
            let linear = min(max(elapsed / TaisaMotion.streamingWordFade, 0), 1)
            return TaisaMotion.streamingWordRevealCurve.value(at: linear)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let text: String
    private let onRevealComplete: @MainActor @Sendable () -> Void
    @State private var revealDates: [Date] = []
    @State private var revealIsComplete = true
    @State private var completedText = ""
    @State private var completionTask: Task<Void, Never>?

    public init(_ text: String, onRevealComplete: @escaping @MainActor @Sendable () -> Void = {}) {
        self.text = text
        self.onRevealComplete = onRevealComplete
    }

    @ViewBuilder public var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            let motion: Motion = reduceMotion ? .reduced : .standard
            TimelineView(.animation(paused: motion == .instant || revealIsComplete)) { timeline in
                renderedText.textRenderer(WordRenderer(now: timeline.date, revealDates: revealDates, motion: motion))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .onAppear { reconcileRevealDates() }
            .onChange(of: text) { _, _ in reconcileRevealDates() }
            .onChange(of: reduceMotion) { _, _ in reconcileRevealDates() }
            .onDisappear { completionTask?.cancel() }
        } else {
            Text(text).accessibilityLabel(text)
        }
    }

    nonisolated public static func chunks(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var result: [String] = []
        var chunk = ""
        var containsWord = false
        for character in text {
            if !character.isWhitespace, containsWord, chunk.last?.isWhitespace == true {
                result.append(chunk)
                chunk = ""
                containsWord = false
            }
            chunk.append(character)
            if !character.isWhitespace { containsWord = true }
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }

    nonisolated public static func revealDuration(wordCount: Int) -> Double {
        guard wordCount > 0 else { return 0 }
        return Double(wordCount - 1) * TaisaMotion.streamingWordGap + TaisaMotion.streamingWordFade
    }

    private var renderedText: Text {
        Self.chunks(in: text).enumerated().reduce(Text("")) { result, item in
            let word = Text(item.element).customAttribute(WordAttribute(index: item.offset))
            return Text("\(result)\(word)")
        }
    }

    private func reconcileRevealDates() {
        let wordCount = Self.chunks(in: text).count
        let now = Date()
        if revealDates.count < wordCount {
            let firstNewDate = max(now, revealDates.last.map { $0.addingTimeInterval(TaisaMotion.streamingWordGap) } ?? now)
            for offset in 0..<(wordCount - revealDates.count) {
                revealDates.append(firstNewDate.addingTimeInterval(Double(offset) * TaisaMotion.streamingWordGap))
            }
        }
        completionTask?.cancel()
        guard !reduceMotion, let lastReveal = revealDates.last else {
            revealIsComplete = true
            notifyCompletionIfNeeded(for: text)
            return
        }
        revealIsComplete = false
        let expectedText = text
        let delay = max(0, lastReveal.timeIntervalSince(now) + TaisaMotion.streamingWordFade)
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, text == expectedText else { return }
            revealIsComplete = true
            notifyCompletionIfNeeded(for: expectedText)
        }
    }

    private func notifyCompletionIfNeeded(for value: String) {
        guard !value.isEmpty, completedText != value else { return }
        completedText = value
        onRevealComplete()
    }
}
