import SwiftUI
import TaisaCareerWork
import TaisaDesignSystem
import TaisaStorage

struct CareerWorkView: View {
    @State private var model: CareerWorkModel
    @State private var selectedRoute: CareerWorkRoute?
    @State private var showsCreateGoal = false
    @State private var showsCreateAction = false
    @State private var editor: CareerWorkEditor?
    @State private var recentlyDeletedActionID: String?
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
        .sheet(isPresented: $showsCreateAction) {
            ActionEditorSheet(goals: allGoals, milestones: model.state.snapshot?.selectedGoal?.milestones ?? []) { draft in
                await model.createAction(draft)
                showsCreateAction = false
                if model.duplicateGate == nil {
                    selectedRoute = model.route
                }
            }
        }
        .sheet(isPresented: duplicateReviewPresented) {
            ActionDuplicateReviewSheet(review: model.duplicateGate) { decision in
                await model.resolveDuplicate(decision)
                showsCreateAction = false
                selectedRoute = model.route
            } cancel: {
                model.cancelDuplicateReview()
            }
        }
    }

    @ViewBuilder private var collection: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading Career Work…")
        case .empty:
            ContentUnavailableView {
                VStack {
                    CentralIcon(.goal).frame(width: 32, height: 32)
                    TaisaText(role: .heading, content: "Start with one meaningful goal")
                }
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
                actionCollection(snapshot.actions)
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
            TaisaToolbarAction(label: "Create an action", icon: .add) { showsCreateAction = true }
                .accessibilityIdentifier("career-work.action.create")
        }
        ToolbarItem(placement: .topBarTrailing) {
            TaisaToolbarAction(label: "Create a career goal", icon: .goal) { showsCreateGoal = true }
        }
    }

    private func actionCollection(_ actions: [ActionRecord]) -> some View {
        Section {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(ActionLifecycleFilter.allCases, id: \.self) { lifecycle in
                        TaisaButton(
                            role: .secondary,
                            shape: .capsule,
                            label: lifecycle.rawValue.capitalized,
                            size: .small,
                            isSelected: model.actionFilter.lifecycle == lifecycle
                        ) {
                            Task { await model.setActionFilter(.init(lifecycle: lifecycle)) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            ForEach(actions, id: \.id) { action in
                Button { selectedRoute = .action(id: action.id) } label: {
                    TaisaRow(title: action.title, supporting: action.dueDay.map { "Due \($0.rawValue)" }, icon: .action)
                }
                .buttonStyle(.plain)
                .tag(CareerWorkRoute.action(id: action.id))
                .accessibilityLabel("Action \(action.title), \(action.status)")
            }
            if let recentlyDeletedActionID {
                TaisaButton(role: .secondary, label: "Undo deleted action", icon: .undo) {
                    Task {
                        await model.restoreAction(id: recentlyDeletedActionID)
                        self.recentlyDeletedActionID = nil
                        selectedRoute = model.route
                    }
                }
                .accessibilityIdentifier("career-work.action.restore")
            }
        } header: {
            Text("Actions")
        }
        .accessibilityIdentifier("career-work.actions.collection")
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
            ContentUnavailableView {
                VStack {
                    CentralIcon(.goal).frame(width: 32, height: 32)
                    TaisaText(role: .heading, content: "Select career work")
                }
            } description: {
                Text("Choose a goal, action, or evidence item to inspect it.")
            }
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
        } else if let action = model.state.snapshot?.selectedActionDetail {
            CareerActionDetail(snapshot: action, goals: allGoals, model: model) {
                recentlyDeletedActionID = action.action.id
                selectedRoute = nil
            }
        } else if let evidence = model.state.snapshot?.selectedEvidence {
            CareerEvidenceDetail(evidence: evidence)
        }
    }

    private var allGoals: [GoalRecord] {
        guard let overview = model.state.snapshot?.overview else { return [] }
        return overview.active + overview.paused + overview.completed
    }

    private var duplicateReviewPresented: Binding<Bool> {
        Binding(
            get: { model.duplicateGate != nil },
            set: { if !$0 { model.cancelDuplicateReview() } }
        )
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
            TaisaRow(title: issue == .conflict ? "This changed elsewhere. Review the latest version." : "Career Work needs attention", icon: .warning, emphasis: .attention)
        }
    }

    private func failure(_ issue: CareerWorkIssue) -> some View {
        ContentUnavailableView {
            VStack {
                CentralIcon(.warning).frame(width: 32, height: 32)
                TaisaText(role: .heading, content: issue == .recoveryRequired ? "Recovery required" : "Career Work unavailable")
            }
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
                TaisaButton(role: .secondary, label: "Add milestone", icon: .milestone) { add(.milestone) }
                TaisaButton(role: .secondary, label: "Add action", icon: .action) { add(.action) }
                TaisaButton(role: .secondary, label: "Add evidence", icon: .evidence) { add(.evidence(actions: snapshot.actions)) }
            }
            if !snapshot.milestones.isEmpty {
                Section("Milestones") {
                    ForEach(snapshot.milestones, id: \.id) { milestone in
                        TaisaRow(title: milestone.title, supporting: milestone.status, icon: milestone.status == "completed" ? .completed : .incomplete)
                            .accessibilityLabel("Milestone \(milestone.title), \(milestone.status)")
                    }
                }
            }
            if !snapshot.actions.isEmpty {
                Section("Actions") {
                    ForEach(snapshot.actions, id: \.id) { action in
                        Button { open(.action(id: action.id)) } label: {
                            TaisaRow(title: action.title, supporting: action.status, icon: action.status == "completed" ? .completed : .incomplete)
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
                                TaisaRow(title: evidence.title, icon: .evidence)
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
                    TaisaButton(role: .secondary, label: "Restore goal", icon: .undo) { Task { await model.restoreSelectedGoal() } }
                } else {
                    TaisaButton(role: .secondary, label: "Archive goal", icon: .drop) { Task { await model.archiveSelectedGoal() } }
                }
            }
        }
        .accessibilityIdentifier("career-work.goal.detail")
    }

    @ViewBuilder private var lifecycleButtons: some View {
        switch GoalStatus(rawValue: snapshot.goal.status) {
        case .active:
            TaisaButton(role: .secondary, label: "Pause goal", icon: .pause) { Task { await model.transitionSelectedGoal(to: .paused) } }
            TaisaButton(role: .primary, label: "Complete goal", icon: .completed) { Task { await model.transitionSelectedGoal(to: .completed) } }
        case .paused:
            TaisaButton(role: .primary, label: "Resume goal", icon: .play) { Task { await model.transitionSelectedGoal(to: .active) } }
        case .completed:
            TaisaButton(role: .secondary, label: "Reopen goal", icon: .undo) { Task { await model.transitionSelectedGoal(to: .active) } }
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
                TaisaButton(role: .primary, label: "Accept change", icon: .completed) { accept() }
                TaisaButton(role: .secondary, label: "Correct before accepting", icon: .edit) { correct() }
                TaisaButton(role: .destructive, label: "Reject change", icon: .cross) { reject() }
            }
        }
        .navigationTitle("Review proposal")
        .accessibilityIdentifier("career-work.proposal.review")
    }
}

private struct CareerActionDetail: View {
    let snapshot: ActionDetailSnapshot
    let goals: [GoalRecord]
    let model: CareerWorkModel
    let deleted: () -> Void
    @State private var checklistTitle = ""
    @State private var completionEvidence = ""
    @State private var showsComplete = false
    @State private var showsDrop = false
    @State private var showsDelete = false
    @State private var showsEdit = false

    var body: some View {
        List {
            Section("Action") {
                TaisaStatusSurface(statusRole, label: snapshot.action.status.capitalized)
                if !snapshot.action.detail.isEmpty { TaisaRow(title: snapshot.action.detail) }
                if let dueDay = snapshot.action.dueDay { LabeledContent("Due", value: dueDay.rawValue) }
                if let goal = snapshot.goal { LabeledContent("Goal", value: goal.title) }
                if let milestone = snapshot.milestone { LabeledContent("Milestone", value: milestone.title) }
            }
            Section("Checklist") {
                ForEach(snapshot.checklist, id: \.id) { item in
                    HStack {
                        Button {
                            Task { await model.setChecklistItemCompleted(id: item.id, completed: item.state != .completed) }
                        } label: {
                            TaisaRow(
                                title: item.title,
                                supporting: item.state == .promoted ? "Promoted to action" : nil,
                                icon: item.state == .completed ? .completed : .incomplete
                            )
                        }
                        .buttonStyle(.plain)
                        if item.state == .pending {
                            TaisaMenu(label: "More", actions: [
                                ("Promote to action", .standard, { Task { await model.promoteChecklistItem(id: item.id) } }),
                                ("Remove", .destructive, { Task { await model.removeChecklistItem(id: item.id) } }),
                            ])
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                TaisaField("New checklist item", text: $checklistTitle, placeholder: "Add a next step")
                TaisaButton(role: .secondary, label: "Add checklist item", icon: .add, isEnabled: !trimmedChecklistTitle.isEmpty) {
                    let title = trimmedChecklistTitle
                    checklistTitle = ""
                    Task { await model.addChecklistItem(title: title) }
                }
            }
            .accessibilityIdentifier("career-work.action.checklist")
            if !snapshot.currentEvidence.isEmpty || !snapshot.supersededEvidence.isEmpty {
                Section("Evidence") {
                    ForEach(snapshot.currentEvidence, id: \.id) { TaisaRow(title: $0.title, supporting: $0.detail, icon: .evidence) }
                    ForEach(snapshot.supersededEvidence, id: \.id) { TaisaRow(title: $0.title, supporting: "Corrected completion", icon: .undo) }
                }
                .accessibilityIdentifier("career-work.action.evidence")
            }
            if !snapshot.events.isEmpty {
                Section {
                    ForEach(snapshot.events, id: \.id) { event in
                        HStack(alignment: .top) {
                            CentralIcon(.history).frame(width: 24, height: 24)
                            TaisaRow(title: event.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, supporting: event.detail)
                        }
                    }
                } header: { Text("History") }
                    .accessibilityIdentifier("career-work.action.history")
            }
            Section("Manage") { lifecycleControls }
        }
        .accessibilityIdentifier("career-work.action.detail")
        .modifier(TaisaConfirmationDialog(title: "Complete this action?", isPresented: $showsComplete, confirmLabel: "Complete action", cancelLabel: "Keep working") {
            Task { await model.completeSelectedAction(evidenceTitle: completionEvidence) }
        })
        .modifier(TaisaConfirmationDialog(title: "Drop this action?", isPresented: $showsDrop, confirmLabel: "Drop action", cancelLabel: "Keep action", role: .destructive) {
            Task { await model.dropSelectedAction() }
        })
        .modifier(TaisaConfirmationDialog(title: "Delete this action?", isPresented: $showsDelete, confirmLabel: "Delete action", cancelLabel: "Keep action", role: .destructive) {
            Task { await model.deleteSelectedAction(); deleted() }
        })
        .sheet(isPresented: $showsEdit) {
            ActionEditorSheet(goals: goals, milestones: snapshot.milestone.map { [$0] } ?? [], initial: currentDraft) { draft in
                await model.editSelectedAction(draft, expectedUpdatedAtMS: snapshot.action.updatedAtMS)
                showsEdit = false
            }
        }
    }

    @ViewBuilder private var lifecycleControls: some View {
        TaisaButton(role: .secondary, label: "Edit action", icon: .edit) { showsEdit = true }
        switch ActionStatus(rawValue: snapshot.action.status) {
        case .active:
            TaisaField("Completion evidence", text: $completionEvidence, placeholder: "What shows this is complete?")
            TaisaButton(role: .primary, label: "Complete action", icon: .completeAction, isEnabled: !completionEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { showsComplete = true }
            TaisaButton(role: .secondary, label: "Drop action", icon: .drop) { showsDrop = true }
        case .completed, .dropped:
            TaisaButton(role: .secondary, label: "Reopen action", icon: .undo) { Task { await model.reopenSelectedAction() } }
        case nil:
            EmptyView()
        }
        TaisaButton(role: .destructive, label: "Delete action", icon: .delete) { showsDelete = true }
            .accessibilityIdentifier("career-work.action.delete")
    }

    private var trimmedChecklistTitle: String { checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var currentDraft: ActionDraft {
        let parent: ActionParentContext
        if let goalID = snapshot.action.goalID, let milestoneID = snapshot.action.milestoneID {
            parent = .milestone(goalID: goalID, milestoneID: milestoneID)
        } else if let goalID = snapshot.action.goalID {
            parent = .goal(id: goalID)
        } else {
            parent = .standalone
        }
        return ActionDraft(title: snapshot.action.title, detail: snapshot.action.detail, parent: parent, dueDay: snapshot.action.dueDay)
    }
    private var statusRole: TaisaStatusRole {
        switch ActionStatus(rawValue: snapshot.action.status) {
        case .completed: .completed
        case .dropped: .dropped
        case .active, nil: .active
        }
    }
}

private enum ActionParentChoice: Hashable {
    case standalone
    case goal(String)
    case milestone(String, String)
}

private enum ActionDueChoice: Hashable { case none, date }

private struct ActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goals: [GoalRecord]
    let milestones: [MilestoneRecord]
    let save: (ActionDraft) async -> Void
    let isEditing: Bool
    @State private var title = ""
    @State private var detail = ""
    @State private var parent: ActionParentChoice = .standalone
    @State private var dueChoice: ActionDueChoice = .none
    @State private var dueDate = Date()

    init(goals: [GoalRecord], milestones: [MilestoneRecord], initial: ActionDraft? = nil, save: @escaping (ActionDraft) async -> Void) {
        self.goals = goals
        self.milestones = milestones
        self.save = save
        isEditing = initial != nil
        _title = State(initialValue: initial?.title ?? "")
        _detail = State(initialValue: initial?.detail ?? "")
        _parent = State(initialValue: initial.map(Self.choice) ?? .standalone)
        _dueChoice = State(initialValue: initial?.dueDay == nil ? .none : .date)
        _dueDate = State(initialValue: initial?.dueDay.flatMap(Self.date) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                TaisaField("Action title", text: $title, placeholder: "What needs to happen?")
                TaisaField("Details", text: $detail, placeholder: "Optional context", kind: .multiline)
                TaisaPicker("Parent", selection: $parent, options: parentOptions, label: parentLabel)
                TaisaPicker("Due", selection: $dueChoice, options: [.none, .date]) { $0 == .none ? "No due date" : "Choose a date" }
                if dueChoice == .date { TaisaDateField("Due date", selection: $dueDate) }
                TaisaButton(role: .primary, label: "Create action", icon: .add, isEnabled: !trimmedTitle.isEmpty) {
                    Task { await save(draft) }
                }
                TaisaButton(role: .secondary, label: "Cancel") { dismiss() }
            }
            .navigationTitle(isEditing ? "Edit action" : "New action")
            .accessibilityIdentifier("career-work.action.editor")
        }
    }

    private var parentOptions: [ActionParentChoice] {
        [.standalone] + goals.map { .goal($0.id) } + milestones.map { .milestone($0.goalID, $0.id) }
    }
    private func parentLabel(_ choice: ActionParentChoice) -> String {
        switch choice {
        case .standalone: "Standalone"
        case let .goal(id): goals.first(where: { $0.id == id })?.title ?? "Goal"
        case let .milestone(_, id): milestones.first(where: { $0.id == id })?.title ?? "Milestone"
        }
    }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draft: ActionDraft {
        let context: ActionParentContext = switch parent {
        case .standalone: .standalone
        case let .goal(id): .goal(id: id)
        case let .milestone(goalID, milestoneID): .milestone(goalID: goalID, milestoneID: milestoneID)
        }
        return ActionDraft(title: trimmedTitle, detail: detail, parent: context, dueDay: dueChoice == .date ? dueDate.actionDueDay : nil)
    }

    private static func choice(_ draft: ActionDraft) -> ActionParentChoice {
        switch draft.parent {
        case .standalone: .standalone
        case let .goal(id): .goal(id)
        case let .milestone(goalID, milestoneID): .milestone(goalID, milestoneID)
        }
    }

    private static func date(_ day: ActionDueDay) -> Date? {
        let values = day.rawValue.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }
}

private struct ActionDuplicateReviewSheet: View {
    let review: ActionDuplicateReview?
    let decide: (ActionDuplicateDecision) async -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Possible duplicates") {
                    ForEach(review?.candidates ?? [], id: \.id) { TaisaRow(title: $0.title, supporting: $0.detail, icon: .warning, emphasis: .attention) }
                }
                Section("Choose") {
                    TaisaButton(role: .secondary, label: "Open existing action", icon: .action) { Task { await decide(.openExisting) } }
                    TaisaButton(role: .primary, label: "Create separate action", icon: .add) { Task { await decide(.createSeparate) } }
                    TaisaButton(role: .secondary, label: "Cancel") { cancel() }
                }
            }
            .navigationTitle("Similar action found")
            .accessibilityIdentifier("career-work.action.duplicate-review")
        }
    }
}

private extension Date {
    var actionDueDay: ActionDueDay {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return ActionDueDay(rawValue: String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!))!
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
