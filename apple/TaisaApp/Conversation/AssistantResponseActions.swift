import SwiftUI
import TaisaContracts
import TaisaDesignSystem
import TaisaStorage

struct AssistantResponseActions: View {
    let response: AssistantResponseRecord
    let saveFeedback: (ResponseFeedbackDirection?, [ResponseQualityFactor]) -> Void
    let acceptProposal: (String) -> Void
    let dismissProposal: (String) -> Void

    @State private var showsExplanation = false
    @State private var showsFeedback = false
    @State private var direction: ResponseFeedbackDirection?
    @State private var factors: Set<ResponseQualityFactor>

    init(
        response: AssistantResponseRecord,
        saveFeedback: @escaping (ResponseFeedbackDirection?, [ResponseQualityFactor]) -> Void,
        acceptProposal: @escaping (String) -> Void,
        dismissProposal: @escaping (String) -> Void
    ) {
        self.response = response
        self.saveFeedback = saveFeedback
        self.acceptProposal = acceptProposal
        self.dismissProposal = dismissProposal
        _direction = State(initialValue: response.feedback?.direction)
        _factors = State(initialValue: Set(response.feedback?.factors ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            HStack(spacing: TaisaSpacing.compact.rawValue) {
                Button {
                    showsExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                        .frame(minHeight: TaisaControlMetric.headerActionHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TaisaColor.mutedForeground.color)
                .accessibilityLabel("About this response")
                .accessibilityIdentifier("conversation.response-info")

                feedbackButton(.helpful, systemImage: "hand.thumbsup", label: "Helpful")
                feedbackButton(.notHelpful, systemImage: "hand.thumbsdown", label: "Not helpful")

                Spacer()
            }

            if let proposal = response.proposal {
                proposalReview(proposal)
            }
        }
        .sheet(isPresented: $showsExplanation) {
            NavigationStack {
                List {
                    Section("Why this response") {
                        LabeledContent("Mode", value: response.metadata.mode.rawValue.capitalized)
                        LabeledContent("Approach", value: response.metadata.approach)
                        LabeledContent("Confidence", value: response.metadata.confidence.capitalized)
                        Text(response.metadata.inference)
                    }
                    if !response.sources.isEmpty {
                        Section("Information used") {
                            ForEach(response.sources, id: \.id) { source in
                                VStack(alignment: .leading, spacing: TaisaSpacing.tight.rawValue) {
                                    Text(source.sourceType.capitalized).font(.caption).foregroundStyle(.secondary)
                                    Text(source.excerpt ?? "Source unavailable")
                                }
                            }
                        }
                    }
                }
                .navigationTitle("About this response")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsExplanation = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsFeedback) {
            NavigationStack {
                ScrollView {
                    if let direction {
                        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                            feedbackFactors(for: direction)
                            Button("Remove rating", role: .destructive) {
                                removeRating()
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("conversation.feedback.remove")
                        }
                            .padding(TaisaSpacing.standard.rawValue)
                    }
                }
                .navigationTitle("Response feedback")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsFeedback = false }
                            .accessibilityIdentifier("conversation.feedback.done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func feedbackButton(
        _ value: ResponseFeedbackDirection, systemImage: String, label: String
    ) -> some View {
        Button {
            if direction != value {
                direction = value
                factors = []
                saveFeedback(value, [])
            }
            showsFeedback = true
        } label: {
            Image(systemName: direction == value ? "\(systemImage).fill" : systemImage)
                .frame(
                    minWidth: TaisaControlMetric.headerActionHeight,
                    minHeight: TaisaControlMetric.headerActionHeight
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(direction == value ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
        .accessibilityLabel(label)
        .accessibilityAddTraits(direction == value ? .isSelected : [])
        .accessibilityIdentifier(feedbackIdentifier(for: value))
    }

    private func feedbackIdentifier(for direction: ResponseFeedbackDirection) -> String {
        switch direction {
        case .helpful: "conversation.feedback.helpful"
        case .notHelpful: "conversation.feedback.not_helpful"
        }
    }

    private func feedbackFactors(for direction: ResponseFeedbackDirection) -> some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            Text(direction == .helpful ? "What worked well?" : "What could be better?")
                .font(.caption)
                .foregroundStyle(TaisaColor.mutedForeground.color)
            FlowLayout(spacing: TaisaSpacing.compact.rawValue) {
                ForEach(ResponseFeedbackCopy.options(for: direction), id: \.factor) { option in
                    Button(option.label) { toggle(option.factor, direction: direction) }
                        .buttonStyle(.bordered)
                        .tint(factors.contains(option.factor) ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
                        .accessibilityAddTraits(factors.contains(option.factor) ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("conversation.feedback-factors")
    }

    private func toggle(_ factor: ResponseQualityFactor, direction: ResponseFeedbackDirection) {
        if factors.contains(factor) { factors.remove(factor) } else { factors.insert(factor) }
        saveFeedback(direction, factors.sorted())
    }

    private func removeRating() {
        direction = nil
        factors = []
        saveFeedback(nil, [])
        showsFeedback = false
    }

    @ViewBuilder private func proposalReview(_ proposal: AssistantProposalRecord) -> some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            Text(proposal.state == .pending ? "Suggested action" : proposalStateLabel(proposal.state))
                .font(.caption)
                .foregroundStyle(TaisaColor.mutedForeground.color)
            Text(proposalSummary(proposal)).font(.body)
            if proposal.state == .pending {
                HStack {
                    Button("Add") { acceptProposal(proposal.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(TaisaColor.primaryAction.color)
                        .foregroundStyle(TaisaColor.foreground.color)
                        .accessibilityIdentifier("conversation.proposal.accept")
                    Button("Not now") { dismissProposal(proposal.id) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("conversation.proposal.dismiss")
                }
                .controlSize(.large)
            }
        }
        .padding(TaisaSpacing.control.rawValue)
        .background(
            TaisaColor.raisedSurface.color,
            in: RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue)
        )
        .accessibilityIdentifier("conversation.proposal-review")
    }

    private func proposalSummary(_ record: AssistantProposalRecord) -> String {
        guard let proposal = try? JSONDecoder().decode(
            CoachingProposal.self, from: record.canonicalPayload
        ) else { return "This suggestion is unavailable." }
        return switch proposal {
        case .goal(let value): value.title
        case .action(let value): value.title
        case .weeklyWork: "Add this action to the week"
        case .evidence(let value): value.statement
        case .memory: "Remember this for future coaching"
        case .insight(let value): value.body
        }
    }

    private func proposalStateLabel(_ state: AssistantProposalState) -> String {
        return switch state {
        case .pending: "Suggested action"
        case .accepted: "Added"
        case .dismissed: "Not added"
        case .superseded: "Replaced"
        case .stale: "No longer available"
        case .unsupported: "Unavailable"
        }
    }
}

private enum ResponseFeedbackCopy {
    struct Option { let factor: ResponseQualityFactor; let label: String }

    static func options(for direction: ResponseFeedbackDirection) -> [Option] {
        switch direction {
        case .helpful:
            [
                .init(factor: .intentAlignment, label: "Understood what I meant"),
                .init(factor: .coverage, label: "Covered what mattered"),
                .init(factor: .coachingStrategy, label: "Used the right approach"),
                .init(factor: .insightValue, label: "Added a useful insight"),
                .init(factor: .practicalUtility, label: "Gave me a practical next step"),
                .init(factor: .confidenceCalibration, label: "Confidence felt right"),
                .init(factor: .relationalFit, label: "Tone felt right"),
                .init(factor: .communicationClarity, label: "Was clear and easy to follow"),
                .init(factor: .evidenceFidelity, label: "Used my information accurately"),
            ]
        case .notHelpful:
            [
                .init(factor: .intentAlignment, label: "Missed what I meant"),
                .init(factor: .coverage, label: "Left out something important"),
                .init(factor: .coachingStrategy, label: "Used the wrong approach"),
                .init(factor: .insightValue, label: "Didn’t add a useful insight"),
                .init(factor: .practicalUtility, label: "Wasn’t practical enough"),
                .init(factor: .confidenceCalibration, label: "Confidence felt off"),
                .init(factor: .relationalFit, label: "Tone didn’t feel right"),
                .init(factor: .communicationClarity, label: "Was hard to follow"),
                .init(factor: .evidenceFidelity, label: "Used my information inaccurately"),
            ]
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        arrangement(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrangement(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: proposal.width ?? x, height: y + rowHeight), points)
    }
}
