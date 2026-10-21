import SwiftUI
import TaisaCareerWork
import TaisaDesignSystem
import TaisaStorage

struct CareerWorkView: View {
    @State private var model: CareerWorkModel
    @State private var selectedRoute: CareerWorkRoute?
    @State private var showsCreateGoal = false
    @State private var editor: CareerWorkEditor?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var openRecovery: () -> Void = {}

    init(model: CareerWorkModel, openRecovery: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        _selectedRoute = State(initialValue: model.route == .overview ? nil : model.route)
        self.openRecovery = openRecovery
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    collection
                        .navigationTitle("Career Work")
                } detail: {
                    detail
                }
            } else {
                NavigationStack {
                    collection
                        .navigationTitle("Career Work")
                        .navigationDestination(item: $selectedRoute) { _ in detail }
                }
            }
        }
        .accessibilityIdentifier("career-work.root")
        .task { if model.state == .idle { await model.load() } }
        .onChange(of: selectedRoute) { _, route in
            guard let route else { return }
            Task { await model.select(route) }
        }
        .sheet(isPresented: $showsCreateGoal) {
            GoalEditorSheet { title, detail in
                await model.createGoal(title: title, detail: detail)
                selectedRoute = model.route
            }
        }
        .sheet(item: $editor) { editor in
            CareerWorkEditorSheet(editor: editor) { title, detail, date, actionID in
                switch editor {
                case .milestone: await model.createMilestone(title: title, targetAtMS: date.milliseconds)
                case .action: await model.createAction(title: title, detail: detail, dueAtMS: date.milliseconds)
                case .evidence: await model.addEvidence(actionID: actionID, title: title, detail: detail, occurredAtMS: date.milliseconds)
                }
            }
        }
    }

    @ViewBuilder private var collection: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading Career Work…")
        case .empty:
            ContentUnavailableView {
                Label("Start with one meaningful goal", systemImage: "target")
            } description: {
                Text("Break it into milestones and actions, then keep the evidence that shows your progress.")
            } actions: {
                Button("Create goal") { showsCreateGoal = true }
            }
            .accessibilityIdentifier("career-work.empty")
            .toolbar { createToolbar }
        case let .content(snapshot, isRefreshing, issue):
            List(selection: $selectedRoute) {
                if let issue { issueRow(issue) }
                goalSection("Active", goals: snapshot.overview.active)
                goalSection("Paused", goals: snapshot.overview.paused)
                goalSection("Completed", goals: snapshot.overview.completed)
                goalSection("Archived", goals: snapshot.overview.archived)
                if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
            }
            .refreshable { await model.load() }
            .toolbar { createToolbar }
        case let .failure(issue):
            failure(issue)
        }
    }

    @ToolbarContentBuilder private var createToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Create goal", systemImage: "plus") { showsCreateGoal = true }
                .accessibilityLabel("Create a career goal")
        }
    }

    private func goalSection(_ title: String, goals: [GoalRecord]) -> some View {
        Section(title) {
            ForEach(goals, id: \.id) { goal in
                Button {
                    selectedRoute = .goal(id: goal.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.title)
                        if !goal.detail.isEmpty { Text(goal.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .tag(CareerWorkRoute.goal(id: goal.id))
                .accessibilityLabel("\(title) goal, \(goal.title)")
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let detailTitle {
            detailContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    TaisaChildPageHeader(detailTitle,
                        mode: horizontalSizeClass == .regular ? .detail : .back,
                        back: { selectedRoute = nil }
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
                .background(TaisaColor.background.color.ignoresSafeArea())
        } else {
            ContentUnavailableView("Select career work", systemImage: "target", description: Text("Choose a goal, action, or evidence item to inspect it."))
        }
    }

    @ViewBuilder private var detailContent: some View {
        if let goal = model.state.snapshot?.selectedGoal {
            CareerGoalDetail(
                snapshot: goal,
                isArchived: model.state.snapshot?.overview.archived.contains(where: { $0.id == goal.goal.id }) == true,
                model: model,
                open: { selectedRoute = $0 },
                add: { editor = $0 }
            )
        } else if let action = model.state.snapshot?.selectedAction {
            CareerActionDetail(action: action)
        } else if let evidence = model.state.snapshot?.selectedEvidence {
            CareerEvidenceDetail(evidence: evidence)
        }
    }

    private var detailTitle: String? {
        if let goal = model.state.snapshot?.selectedGoal { return goal.goal.title }
        if let action = model.state.snapshot?.selectedAction { return action.title }
        if let evidence = model.state.snapshot?.selectedEvidence { return evidence.title }
        return nil
    }

    private func issueRow(_ issue: CareerWorkIssue) -> some View {
        Button {
            if issue == .recoveryRequired { openRecovery() }
            else { Task { await model.retry() } }
        } label: {
            Label(issue == .conflict ? "This changed elsewhere. Review the latest version." : "Career Work needs attention", systemImage: "exclamationmark.triangle")
        }
    }

    private func failure(_ issue: CareerWorkIssue) -> some View {
        ContentUnavailableView {
            Label(issue == .recoveryRequired ? "Recovery required" : "Career Work unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(issue == .recoveryRequired ? "Open recovery to restore secure access." : "Taisa couldn’t read your encrypted career work.")
        } actions: {
            if issue == .recoveryRequired {
                Button("Open recovery", action: openRecovery).accessibilityIdentifier("career-work.recovery")
            } else {
                Button("Try again") { Task { await model.retry() } }.accessibilityIdentifier("career-work.retry")
            }
        }
    }
}

private struct CareerGoalDetail: View {
    let snapshot: CareerGoalSnapshot
    let isArchived: Bool
    let model: CareerWorkModel
    let open: (CareerWorkRoute) -> Void
    let add: (CareerWorkEditor) -> Void

    var body: some View {
        List {
            Section("Progress") { Text(snapshot.progress.summary) }
            Section("Add work") {
                Button("Add milestone", systemImage: "flag") { add(.milestone) }
                Button("Add action", systemImage: "checklist") { add(.action) }
                Button("Add evidence", systemImage: "doc.badge.plus") { add(.evidence(actions: snapshot.actions)) }
            }
            if !snapshot.milestones.isEmpty {
                Section("Milestones") {
                    ForEach(snapshot.milestones, id: \.id) { milestone in
                        Label(milestone.title, systemImage: milestone.status == "completed" ? "checkmark.circle.fill" : "circle")
                            .accessibilityLabel("Milestone \(milestone.title), \(milestone.status)")
                    }
                }
            }
            if !snapshot.actions.isEmpty {
                Section("Actions") {
                    ForEach(snapshot.actions, id: \.id) { action in
                        Button { open(.action(id: action.id)) } label: {
                            Label(action.title, systemImage: action.status == "completed" ? "checkmark.circle.fill" : "circle")
                        }
                        .accessibilityLabel("Action \(action.title), \(action.status)")
                    }
                }
            }
            if !snapshot.evidence.isEmpty {
                Section("Evidence") {
                    ForEach(snapshot.evidence, id: \.id) { evidence in
                        Button { open(.evidence(id: evidence.id)) } label: {
                            VStack(alignment: .leading) {
                                Label(evidence.title, systemImage: "doc.text")
                                if let provenance = snapshot.provenance.first(where: { $0.evidenceID == evidence.id }) {
                                    Text("Origin: \(provenance.origin.rawValue.capitalized)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                            .accessibilityLabel("Evidence \(evidence.title)")
                    }
                }
            }
            Section("Status") {
                lifecycleButtons
                if isArchived {
                    Button("Restore goal", systemImage: "arrow.uturn.backward") { Task { await model.restoreSelectedGoal() } }
                } else {
                    Button("Archive goal", systemImage: "archivebox") { Task { await model.archiveSelectedGoal() } }
                }
            }
        }
        .accessibilityIdentifier("career-work.goal.detail")
    }

    @ViewBuilder private var lifecycleButtons: some View {
        switch GoalStatus(rawValue: snapshot.goal.status) {
        case .active:
            Button("Pause goal", systemImage: "pause.circle") { Task { await model.transitionSelectedGoal(to: .paused) } }
            Button("Complete goal", systemImage: "checkmark.circle") { Task { await model.transitionSelectedGoal(to: .completed) } }
        case .paused:
            Button("Resume goal", systemImage: "play.circle") { Task { await model.transitionSelectedGoal(to: .active) } }
        case .completed:
            Button("Reopen goal", systemImage: "arrow.uturn.backward.circle") { Task { await model.transitionSelectedGoal(to: .active) } }
        case nil: EmptyView()
        }
    }
}

enum CareerWorkEditor: Identifiable {
    case milestone
    case action
    case evidence(actions: [ActionRecord])

    var id: String {
        switch self { case .milestone: "milestone"; case .action: "action"; case .evidence: "evidence" }
    }
}

private extension Date {
    var milliseconds: Int64 { Int64((timeIntervalSince1970 * 1_000).rounded()) }
}

private struct CareerWorkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: CareerWorkEditor
    let save: (String, String, Date, String?) async -> Void
    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var actionID: String?

    private var name: String {
        switch editor { case .milestone: "milestone"; case .action: "action"; case .evidence: "evidence" }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                if case .milestone = editor { EmptyView() } else { TextField("Optional details", text: $detail, axis: .vertical) }
                DatePicker(editorDateLabel, selection: $date, displayedComponents: .date)
                if case let .evidence(actions) = editor, !actions.isEmpty {
                    Picker("Related action", selection: $actionID) {
                        Text("Goal overall").tag(String?.none)
                        ForEach(actions, id: \.id) { Text($0.title).tag(String?.some($0.id)) }
                    }
                }
            }
            .navigationTitle("New \(name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(title, detail, date, actionID); dismiss() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save career \(name)")
                }
            }
        }
    }

    private var editorDateLabel: String {
        switch editor { case .milestone: "Target date"; case .action: "Due date"; case .evidence: "Occurred" }
    }
}

struct CareerWorkProposalReviewView: View {
    let title: String
    let exactChange: String
    let source: String
    let accept: () -> Void
    let correct: () -> Void
    let reject: () -> Void

    var body: some View {
        Form {
            Section("Proposed change") {
                Text(title).font(.headline)
                Text(exactChange)
                LabeledContent("Source", value: source)
            }
            Section("Review") {
                Button("Accept change", systemImage: "checkmark") { accept() }
                Button("Correct before accepting", systemImage: "pencil") { correct() }
                Button("Reject change", systemImage: "xmark", role: .destructive) { reject() }
            }
        }
        .navigationTitle("Review proposal")
        .accessibilityIdentifier("career-work.proposal.review")
    }
}

private struct CareerActionDetail: View {
    let action: ActionRecord
    var body: some View {
        Form {
            LabeledContent("Status", value: action.status.capitalized)
            if !action.detail.isEmpty { Section("Details") { Text(action.detail) } }
            if let due = action.dueAtMS { LabeledContent("Due", value: Date(timeIntervalSince1970: Double(due) / 1_000).formatted(date: .abbreviated, time: .omitted)) }
        }
        .accessibilityIdentifier("career-work.action.detail")
    }
}

private struct CareerEvidenceDetail: View {
    let evidence: EvidenceRecord
    var body: some View {
        Form {
            LabeledContent("Occurred", value: Date(timeIntervalSince1970: Double(evidence.occurredAtMS) / 1_000).formatted(date: .abbreviated, time: .omitted))
            if !evidence.detail.isEmpty { Section("Details") { Text(evidence.detail) } }
        }
        .accessibilityIdentifier("career-work.evidence.detail")
    }
}

private struct GoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    let save: (String, String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal title", text: $title)
                TextField("Optional details", text: $detail, axis: .vertical)
            }
            .navigationTitle("New goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(title, detail); dismiss() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save career goal")
                }
            }
        }
    }
}
