import SwiftUI
import TaisaContracts
import TaisaDesignSystem
import TaisaStorage

struct AssistantResponseActions: View {
    let response: AssistantResponseRecord
    let saveFeedback: (ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void
    let acceptProposal: (String) -> Void
    let dismissProposal: (String) -> Void

    @State private var showsExplanation = false
    @State private var showsFeedback = false
    @State private var feedbackEditor: ResponseFeedbackEditorState

    init(
        response: AssistantResponseRecord,
        saveFeedback: @escaping (ResponseFeedbackDirection?, [ResponseQualityFactor], String?) -> Void,
        acceptProposal: @escaping (String) -> Void,
        dismissProposal: @escaping (String) -> Void
    ) {
        self.response = response
        self.saveFeedback = saveFeedback
        self.acceptProposal = acceptProposal
        self.dismissProposal = dismissProposal
        _feedbackEditor = State(initialValue: ResponseFeedbackEditorState(feedback: response.feedback))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            HStack(spacing: TaisaSpacing.compact.rawValue) {
                Button {
                    showsExplanation = true
                } label: {
                    CentralIcon(.circleInfo)
                        .frame(
                            width: AssistantResponseActionsLayout.iconSize,
                            height: AssistantResponseActionsLayout.iconSize
                        )
                        .frame(width: AssistantResponseActionsLayout.hitWidth)
                        .frame(minHeight: TaisaControlMetric.headerActionHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TaisaColor.mutedForeground.color)
                .accessibilityLabel("About this response")
                .accessibilityIdentifier("conversation.response-info")

                feedbackButton(.helpful, icon: .thumbsUp, label: "Helpful")
                feedbackButton(.notHelpful, icon: .thumbsDown, label: "Not helpful")

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
        .sheet(isPresented: $showsFeedback, onDismiss: { feedbackEditor.discardDraft() }) {
            NavigationStack {
                ScrollView {
                    if let direction = feedbackEditor.direction {
                        VStack(alignment: .leading, spacing: TaisaSpacing.section.rawValue) {
                            feedbackFactors(for: direction)
                            feedbackDetail
                            Button("Remove rating", role: .destructive) {
                                removeRating()
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: TaisaControlMetric.headerActionHeight)
                            .accessibilityIdentifier("conversation.feedback.remove")
                        }
                        .padding(TaisaSpacing.standard.rawValue)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Response feedback")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            feedbackEditor.discardDraft()
                            showsFeedback = false
                        }
                        .accessibilityIdentifier("conversation.feedback.close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save feedback") {
                            persist(feedbackEditor.commit())
                            showsFeedback = false
                        }
                        .accessibilityIdentifier("conversation.feedback.save")
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func feedbackButton(
        _ value: ResponseFeedbackDirection, icon: CentralIconName, label: String
    ) -> some View {
        Button {
            persist(feedbackEditor.begin(value))
            showsFeedback = true
        } label: {
            CentralIcon(icon)
                .frame(
                    width: AssistantResponseActionsLayout.iconSize,
                    height: AssistantResponseActionsLayout.iconSize
                )
                .frame(width: AssistantResponseActionsLayout.hitWidth)
                .frame(minHeight: TaisaControlMetric.headerActionHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(feedbackEditor.direction == value ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
        .accessibilityLabel(label)
        .accessibilityAddTraits(feedbackEditor.direction == value ? .isSelected : [])
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
                    Button(option.label) { feedbackEditor.toggle(option.factor) }
                        .buttonStyle(.bordered)
                        .tint(feedbackEditor.draftFactors.contains(option.factor) ? TaisaColor.foreground.color : TaisaColor.mutedForeground.color)
                        .accessibilityAddTraits(feedbackEditor.draftFactors.contains(option.factor) ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("conversation.feedback-factors")
    }

    private var feedbackDetail: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
            Text("Add more detail (optional)")
                .font(.caption)
                .foregroundStyle(TaisaColor.mutedForeground.color)
            TextEditor(text: Binding(
                get: { feedbackEditor.draftDetail },
                set: { feedbackEditor.draftDetail = String($0.prefix(ResponseFeedbackEditorState.detailLimit)) }
            ))
            .frame(minHeight: 112)
            .padding(TaisaSpacing.compact.rawValue)
            .background(
                TaisaColor.raisedSurface.color,
                in: RoundedRectangle(cornerRadius: TaisaRadius.control.rawValue)
            )
            .accessibilityLabel("Add more detail (optional)")
            .accessibilityIdentifier("conversation.feedback.detail")
        }
    }

    private func removeRating() {
        persist(feedbackEditor.remove())
        showsFeedback = false
    }

    private func persist(_ mutation: ResponseFeedbackMutation?) {
        guard let mutation else { return }
        switch mutation {
        case let .save(direction, factors, detail):
            saveFeedback(direction, factors, detail)
        case .remove:
            saveFeedback(nil, [], nil)
        }
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

private enum AssistantResponseActionsLayout {
    static let iconSize: CGFloat = 16
    static let hitWidth = TaisaSpacing.section.rawValue
}

enum ResponseFeedbackMutation: Equatable {
    case save(
        direction: ResponseFeedbackDirection,
        factors: [ResponseQualityFactor],
        detail: String?
    )
    case remove
}

struct ResponseFeedbackEditorState {
    static let detailLimit = 4_000

    private(set) var direction: ResponseFeedbackDirection?
    private var committedFactors: Set<ResponseQualityFactor>
    private var committedDetail: String
    var draftFactors: Set<ResponseQualityFactor>
    var draftDetail: String

    init(feedback: ResponseFeedbackRecord?) {
        direction = feedback?.direction
        committedFactors = Set(feedback?.factors ?? [])
        committedDetail = feedback?.detail ?? ""
        draftFactors = committedFactors
        draftDetail = committedDetail
    }

    mutating func begin(_ selectedDirection: ResponseFeedbackDirection) -> ResponseFeedbackMutation? {
        guard direction != selectedDirection else {
            discardDraft()
            return nil
        }
        direction = selectedDirection
        committedFactors = []
        committedDetail = ""
        discardDraft()
        return .save(direction: selectedDirection, factors: [], detail: nil)
    }

    mutating func toggle(_ factor: ResponseQualityFactor) {
        if draftFactors.contains(factor) {
            draftFactors.remove(factor)
        } else {
            draftFactors.insert(factor)
        }
    }

    mutating func commit() -> ResponseFeedbackMutation? {
        guard let direction else { return nil }
        committedFactors = draftFactors
        committedDetail = String(draftDetail.prefix(Self.detailLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        draftDetail = committedDetail
        return .save(
            direction: direction,
            factors: committedFactors.sorted(),
            detail: committedDetail.isEmpty ? nil : committedDetail
        )
    }

    mutating func discardDraft() {
        draftFactors = committedFactors
        draftDetail = committedDetail
    }

    mutating func remove() -> ResponseFeedbackMutation {
        direction = nil
        committedFactors = []
        committedDetail = ""
        discardDraft()
        return .remove
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
