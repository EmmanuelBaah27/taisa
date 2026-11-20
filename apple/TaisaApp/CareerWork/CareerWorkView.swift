import SwiftUI
import TaisaCareerWork
import TaisaDesignSystem
import TaisaStorage

struct TasksView: View {
    let model: CareerWorkModel
    var initialRoute: CareerWorkRoute?
    var openRecovery: () -> Void = {}

    var body: some View {
        CareerWorkView(model: model, root: .actions, initialRoute: initialRoute, openRecovery: openRecovery)
    }
}

struct GoalsView: View {
    let model: CareerWorkModel
    var initialRoute: CareerWorkRoute?
    var openRecovery: () -> Void = {}

    var body: some View {
        CareerWorkView(model: model, root: .goals, initialRoute: initialRoute, openRecovery: openRecovery)
    }
}

struct TaskDetailSheetContent: View {
    @State private var model: CareerWorkModel
    let actionID: String
    var openRecovery: () -> Void = {}
    var open: (CareerWorkRoute) -> Void = { _ in }
    var taskChanged: () -> Void = {}
    var dismiss: () -> Void = {}

    init(
        model: CareerWorkModel,
        actionID: String,
        openRecovery: @escaping () -> Void = {},
        open: @escaping (CareerWorkRoute) -> Void = { _ in },
        taskChanged: @escaping () -> Void = {},
        dismiss: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.actionID = actionID
        self.openRecovery = openRecovery
        self.open = open
        self.taskChanged = taskChanged
        self.dismiss = dismiss
    }

    var body: some View {
        Group {
            switch TaskDetailPresentation.resolve(model.state, actionID: actionID) {
            case .loading:
                ProgressView("Loading task…")
            case .unavailable:
                unavailableTask
            case let .failure(issue):
                failure(issue)
            case let .detail(detail, _):
                TaskDetailSheetView(
                    snapshot: detail,
                    model: model,
                    dismiss: dismiss
                )
                .background(TaisaColor.background.color.ignoresSafeArea())
            }
        }
        .task(id: actionID) {
            await model.select(.action(id: actionID))
        }
        .onChange(of: model.state.snapshot?.selectedActionDetail) { oldDetail, newDetail in
            if let oldDetail, let newDetail, oldDetail != newDetail { taskChanged() }
        }
        .accessibilityIdentifier("tasks.detail.sheet")
    }

    private var unavailableTask: some View {
        ContentUnavailableView {
            TaisaText(role: .heading, content: "Task unavailable")
        } description: {
            TaisaText(role: .body, color: .mutedForeground, content: "This task could not be loaded.")
        } actions: {
            TaisaButton(role: .primary, label: "Try again", icon: .refresh) {
                Task { await model.select(.action(id: actionID)) }
            }
        }
    }

    @ViewBuilder private func failure(_ issue: CareerWorkIssue) -> some View {
        ContentUnavailableView {
            TaisaText(role: .heading, content: issue == .recoveryRequired ? "Recovery required" : "Task unavailable")
        } description: {
            TaisaText(
                role: .body,
                color: .mutedForeground,
                content: issue == .recoveryRequired ? "Open recovery to restore secure access." : "Taisa couldn’t read this task securely."
            )
        } actions: {
            if issue == .recoveryRequired {
                TaisaButton(role: .primary, label: "Open recovery", icon: .recovery) { openRecovery() }
            } else {
                TaisaButton(role: .primary, label: "Try again", icon: .refresh) {
                    Task { await model.select(.action(id: actionID)) }
                }
            }
        }
    }
}

private struct TaskDetailSheetView: View {
    let snapshot: ActionDetailSnapshot
    let model: CareerWorkModel
    let dismiss: () -> Void

    @State private var checklistTitle = ""
    @State private var completionEvidence = ""
    @State private var isAddingSubtask = false
    @State private var isCompleting = false
    @State private var showsArchive = false
    @State private var showsDelete = false
    @State private var showsDueDatePicker = false
    @State private var draftDueDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.standard.rawValue) {
            ScrollView {
                VStack(alignment: .leading, spacing: TaisaSpacing.standard.rawValue) {
                    TaisaText(role: .sheetTitle, content: snapshot.action.title)
                        .accessibilityAddTraits(.isHeader)

                    TaisaButton(
                        role: .ghost,
                        shape: .capsule,
                        label: dueText,
                        icon: .calendar,
                        size: .small,
                        layout: .intrinsic,
                        accessibilityLabel: dueText == "Due" ? "Set due date" : "Change due date, \(dueText)"
                    ) {
                        draftDueDate = currentDueDate ?? Date()
                        showsDueDatePicker = true
                    }

                    if !snapshot.checklist.isEmpty {
                        VStack(alignment: .leading, spacing: TaisaSpacing.compact.rawValue) {
                            TaisaText(role: .sectionLabel, color: .mutedForeground, content: "Sub-tasks")
                            ForEach(snapshot.checklist, id: \.id) { item in
                                TaisaPressable(action: {
                                    Task {
                                        await model.setChecklistItemCompleted(
                                            id: item.id,
                                            completed: item.state != .completed
                                        )
                                    }
                                }) {
                                    HStack(spacing: TaisaSpacing.control.rawValue) {
                                        CentralIcon(
                                            item.state == .completed ? .completed : .incomplete,
                                            color: item.state == .completed ? .completed : .foreground
                                        )
                                            .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                                        TaisaText(role: .taskTitle, content: item.title)
                                            .strikethrough(item.state == .completed)
                                        Spacer()
                                    }
                                    .frame(minHeight: TaisaControlMetric.taskControl)
                                    .contentShape(Rectangle())
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    TaisaButton(
                                        role: .destructive,
                                        label: "Delete",
                                        icon: .delete,
                                        size: .small,
                                        layout: .intrinsic
                                    ) {
                                        Task { await model.removeChecklistItem(id: item.id) }
                                    }
                                }
                            }
                        }
                    }

                    if isAddingSubtask {
                        TaisaField(
                            "Sub-task title",
                            text: $checklistTitle,
                            placeholder: "Add a sub-task",
                            labelPresentation: .placeholderOnly
                        )
                        HStack(spacing: TaisaSpacing.compact.rawValue) {
                            TaisaSecondaryCapsuleButton {
                                checklistTitle = ""
                                isAddingSubtask = false
                            } label: {
                                TaisaText(role: .buttonLabel, content: "Cancel")
                                    .padding(.horizontal, TaisaSpacing.standard.rawValue)
                            }
                            TaisaButton(
                                role: .primary,
                                label: "Add",
                                icon: .add,
                                size: .small,
                                layout: .intrinsic,
                                isEnabled: !trimmedChecklistTitle.isEmpty
                            ) {
                                let title = trimmedChecklistTitle
                                checklistTitle = ""
                                isAddingSubtask = false
                                Task { await model.addChecklistItem(title: title) }
                            }
                        }
                    } else {
                        TaisaPressable(action: { isAddingSubtask = true }) {
                            HStack(spacing: TaisaSpacing.compact.rawValue) {
                                CentralIcon(.add)
                                    .frame(
                                        width: TaisaControlMetric.compactActionIcon,
                                        height: TaisaControlMetric.compactActionIcon
                                    )
                                TaisaText(role: .buttonLabel, content: "Add sub-task")
                            }
                            .frame(minHeight: TaisaControlMetric.taskControl)
                        }
                    }

                    if isCompleting {
                        TaisaField(
                            "Completion evidence",
                            text: $completionEvidence,
                            placeholder: "What shows this is complete?"
                        )
                    }
                }
                .padding(.top, TaisaSpacing.control.rawValue)
            }

            HStack(spacing: TaisaSpacing.standard.rawValue) {
                completionButton
                Spacer()
                TaisaGroupedIconActions(
                    [
                        .init(icon: .drop, accessibilityLabel: "Archive task") { showsArchive = true },
                        .init(icon: .delete, role: .destructive, accessibilityLabel: "Delete task") { showsDelete = true },
                    ],
                    elevation: .floating
                )
            }
        }
        .padding(TaisaSpacing.standard.rawValue)
        .accessibilityIdentifier("career-work.task-detail")
        .modifier(TaisaConfirmationDialog(
            title: "Archive this task?",
            isPresented: $showsArchive,
            confirmLabel: "Archive task",
            cancelLabel: "Keep task"
        ) {
            Task { await model.dropSelectedAction() }
        })
        .sheet(isPresented: $showsDueDatePicker) {
            TaisaGraphicalDatePickerSheet(
                selection: draftDueDate,
                commit: { selected in
                    let draft = actionDraft(dueDate: selected)
                    Task {
                        _ = await model.editSelectedAction(
                            draft,
                            expectedUpdatedAtMS: snapshot.action.updatedAtMS
                        )
                    }
                }
            )
        }
        .modifier(TaisaConfirmationDialog(
            title: "Delete this task?",
            isPresented: $showsDelete,
            confirmLabel: "Delete task",
            cancelLabel: "Keep task",
            role: .destructive
        ) {
            Task {
                if await model.deleteSelectedAction() { dismiss() }
            }
        })
    }

    @ViewBuilder private var completionButton: some View {
        if snapshot.action.status == ActionStatus.completed.rawValue {
            TaisaSecondaryCapsuleButton(elevation: .floating) {
                Task { await model.reopenSelectedAction() }
            } label: {
                secondaryActionLabel("Reopen", icon: .undo)
            }
        } else if isCompleting {
            TaisaButton(
                role: .primary,
                shape: .capsule,
                label: "Save completion",
                icon: .completed,
                size: .small,
                layout: .intrinsic,
                isEnabled: !trimmedCompletionEvidence.isEmpty
            ) {
                let evidence = trimmedCompletionEvidence
                completionEvidence = ""
                isCompleting = false
                Task { await model.completeSelectedAction(evidenceTitle: evidence) }
            }
        } else {
            TaisaSecondaryCapsuleButton(elevation: .floating) {
                isCompleting = true
            } label: {
                secondaryActionLabel("Mark as Done", icon: .completed, iconColor: .completed)
            }
        }
    }

    private func secondaryActionLabel(
        _ label: String,
        icon: CentralIconName,
        iconColor: TaisaColor = .foreground
    ) -> some View {
        HStack(spacing: TaisaSpacing.compact.rawValue) {
            CentralIcon(icon, color: iconColor)
                .frame(width: TaisaControlMetric.compactActionIcon, height: TaisaControlMetric.compactActionIcon)
            TaisaText(role: .buttonLabel, content: label)
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
    }

    private var dueText: String {
        actionDueText(snapshot.action)?.replacingOccurrences(of: "Due ", with: "") ?? "Due"
    }

    private var currentDueDate: Date? {
        if let dueDay = snapshot.action.dueDay {
            let values = dueDay.rawValue.split(separator: "-").compactMap { Int($0) }
            guard values.count == 3 else { return nil }
            return Calendar.current.date(
                from: DateComponents(year: values[0], month: values[1], day: values[2])
            )
        }
        return snapshot.action.dueAtMS.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }

    private func actionDraft(dueDate: Date) -> ActionDraft {
        let parent: ActionParentContext
        if let goalID = snapshot.action.goalID, let milestoneID = snapshot.action.milestoneID {
            parent = .milestone(goalID: goalID, milestoneID: milestoneID)
        } else if let goalID = snapshot.action.goalID {
            parent = .goal(id: goalID)
        } else {
            parent = .standalone
        }
        return ActionDraft(
            title: snapshot.action.title,
            detail: snapshot.action.detail,
            parent: parent,
            dueDay: dueDate.actionDueDay
        )
    }

    private var trimmedChecklistTitle: String {
        checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCompletionEvidence: String {
        completionEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TaskDetailPresentation: Equatable {
    case loading
    case unavailable
    case failure(CareerWorkIssue)
    case detail(ActionDetailSnapshot, CareerWorkProductSnapshot)

    static func resolve(_ state: CareerWorkState, actionID: String) -> Self {
        switch state {
        case .idle, .loading:
            return .loading
        case .empty:
            return .unavailable
        case let .failure(issue):
            return .failure(issue)
        case let .content(snapshot, isRefreshing, issue):
            if let issue { return .failure(issue) }
            if let detail = snapshot.selectedActionDetail, detail.action.id == actionID {
                return .detail(detail, snapshot)
            }
            return isRefreshing ? .loading : .unavailable
        }
    }
}

fileprivate enum CareerWorkRoot {
    case actions
    case goals

    var title: String { self == .actions ? "Tasks" : "Goals" }
}

struct CareerWorkView: View {
    @State private var model: CareerWorkModel
    @State private var selectedRoute: CareerWorkRoute?
    private let root: CareerWorkRoot
    @State private var showsCreateGoal = false
    @State private var showsCreateAction = false
    @State private var actionEditorInitial: ActionDraft?
    @State private var showsActionFilters = false
    @State private var editor: CareerWorkEditor?
    @State private var selectedTaskID: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var openRecovery: () -> Void = {}

    init(model: CareerWorkModel, openRecovery: @escaping () -> Void = {}) {
        self.init(model: model, root: .goals, initialRoute: nil, openRecovery: openRecovery)
    }

    fileprivate init(model: CareerWorkModel, root: CareerWorkRoot, initialRoute: CareerWorkRoute?, openRecovery: @escaping () -> Void) {
        _model = State(initialValue: model)
        _selectedRoute = State(initialValue: initialRoute ?? (model.route == .overview ? nil : model.route))
        _selectedTaskID = State(initialValue: nil)
        self.root = root
        self.openRecovery = openRecovery
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    collection
                        .navigationTitle(root.title)
                } detail: {
                    detail
                }
            } else {
                collection
                    .navigationTitle(root.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(item: $selectedRoute) { _ in detail }
            }
        }
        .accessibilityIdentifier(root == .actions ? "tasks.root" : "goals.root")
        .task {
            if let selectedRoute, selectedRoute != model.route { await model.select(selectedRoute) }
            else if model.state == .idle { await model.load() }
        }
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
                case .evidence: await model.addEvidence(actionID: actionID, title: title, detail: detail, occurredAtMS: date.milliseconds)
                }
            }
        }
        .sheet(isPresented: $showsCreateAction) {
            ActionEditorSheet(goals: allGoals, milestones: allMilestones, initial: actionEditorInitial) { draft in
                let shouldDismiss = await model.createAction(draft)
                if shouldDismiss {
                    showsCreateAction = false
                }
                if shouldDismiss, model.duplicateGate == nil {
                    actionEditorInitial = nil
                    selectedRoute = nil
                }
                return shouldDismiss
            }
        }
        .sheet(isPresented: $showsActionFilters) {
            ActionFilterSheet(filter: model.actionFilter, goals: allGoals, milestones: allMilestones) { filter in
                await model.setActionFilter(filter)
                showsActionFilters = false
            }
        }
        .sheet(isPresented: duplicateReviewPresented) {
            ActionDuplicateReviewSheet(review: model.duplicateGate) { decision in
                await model.resolveDuplicate(decision)
                showsCreateAction = false
                selectedRoute = decision == .openExisting ? model.route : nil
            } cancel: {
                model.cancelDuplicateReview()
            }
        }
        .sheet(isPresented: taskDetailPresented, onDismiss: refreshTasksAfterTaskDetail) {
            if let actionID = selectedTaskID {
                TaisaExpandableSheet {
                    TaskDetailSheetContent(
                        model: model,
                        actionID: actionID,
                        openRecovery: openRecovery,
                        open: openTaskDetailRoute,
                        dismiss: { selectedTaskID = nil }
                    )
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
                VStack {
                    CentralIcon(root == .actions ? .action : .goal)
                        .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                    TaisaText(role: .heading, content: root == .actions ? "Add your first task" : "Start with one meaningful goal")
                }
            } description: {
                TaisaText(
                    role: .body,
                    color: .mutedForeground,
                    content: root == .actions ? "Capture one concrete commitment you want to move forward." : "Break it into milestones and tasks, then keep the evidence that shows your progress."
                )
            } actions: {
                if root == .actions {
                    TaisaButton(role: .secondary, label: "Create task", icon: .add) { showsCreateAction = true }
                } else {
                    TaisaButton(role: .primary, label: "Create goal", icon: .goal) { showsCreateGoal = true }
                }
            }
            .accessibilityIdentifier(root == .actions ? "tasks.empty" : "goals.empty")
            .toolbar { createToolbar }
        case let .content(snapshot, isRefreshing, issue):
            if root == .actions {
                ScrollView {
                    LazyVStack(spacing: TaisaSpacing.compact.rawValue) {
                        if let issue { issueRow(issue) }
                        taskCollection(snapshot.actions)
                        if isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                    }
                    .padding(.horizontal, TaisaSpacing.content.rawValue)
                    .padding(.vertical, TaisaSpacing.control.rawValue)
                }
                .refreshable { await model.load() }
                .toolbar { createToolbar }
            } else {
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
            }
        case let .failure(issue):
            failure(issue)
        }
    }

    @ToolbarContentBuilder private var createToolbar: some ToolbarContent {
        if root == .actions {
            ToolbarItem(placement: .topBarTrailing) {
                TaisaToolbarAction(label: "Create task", icon: .add) { showsCreateAction = true }
                    .accessibilityIdentifier("tasks.create")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                TaisaToolbarAction(label: "Create a goal", icon: .goal) { showsCreateGoal = true }
            }
        }
    }

    private func taskCollection(_ actions: [ActionRecord]) -> some View {
        VStack(spacing: TaisaSpacing.compact.rawValue) {
            TaisaButton(role: .secondary, label: "Filter tasks") { showsActionFilters = true }
                .accessibilityIdentifier("tasks.filters")
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
                            Task {
                                let current = model.actionFilter
                                await model.setActionFilter(.init(lifecycle: lifecycle, goalID: current.goalID, milestoneID: current.milestoneID, due: current.due, weekStartMS: current.weekStartMS, origin: current.origin))
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            ForEach(actions, id: \.id) { action in
                TaisaPressable(action: { selectedTaskID = action.id }) {
                    TaisaTaskRow(title: action.title, dueLabel: actionDueText(action)?.replacingOccurrences(of: "Due ", with: ""))
                }
                .accessibilityLabel("Task \(action.title), \(action.status)")
            }
            if let deletedActions = model.state.snapshot?.deletedActions, !deletedActions.isEmpty {
                ForEach(deletedActions, id: \.id) { action in
                    HStack {
                        TaisaRow(title: action.title, supporting: "Deleted task", icon: .delete)
                        TaisaButton(role: .secondary, label: "Restore", icon: .undo) {
                            Task { await model.restoreAction(id: action.id); selectedRoute = model.route }
                        }
                    }
                    .accessibilityIdentifier("career-work.action.restore")
                }
            }
        }
        .accessibilityIdentifier("tasks.collection")
    }

    private func goalSection(_ title: String, goals: [GoalRecord]) -> some View {
        Section(title) {
            ForEach(goals, id: \.id) { goal in
                TaisaPressable(action: {
                    selectedRoute = .goal(id: goal.id)
                }) {
                    TaisaRow(title: goal.title, supporting: goal.detail.isEmpty ? nil : goal.detail, icon: .goal)
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
                    CentralIcon(.goal)
                        .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                    TaisaText(role: .heading, content: "Select career work")
                }
            } description: {
                TaisaText(role: .body, color: .mutedForeground, content: "Choose a goal, task, or evidence item to inspect it.")
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
                add: { editor = $0 },
                addAction: {
                    actionEditorInitial = ActionDraft(title: "", detail: "", parent: .goal(id: goal.goal.id), dueDay: nil)
                    showsCreateAction = true
                }
            )
        } else if let action = model.state.snapshot?.selectedActionDetail {
            CareerActionDetail(
                snapshot: action,
                goals: allGoals,
                milestones: allMilestones,
                model: model,
                open: { selectedRoute = $0 },
                deleted: { selectedRoute = nil }
            )
        } else if let evidence = model.state.snapshot?.selectedEvidence {
            CareerEvidenceDetail(evidence: evidence)
        }
    }

    private var allGoals: [GoalRecord] {
        guard let overview = model.state.snapshot?.overview else { return [] }
        return overview.active + overview.paused + overview.completed
    }

    private var allMilestones: [MilestoneRecord] { model.state.snapshot?.milestones ?? [] }

    private var duplicateReviewPresented: Binding<Bool> {
        Binding(
            get: { model.duplicateGate != nil },
            set: { if !$0 { model.cancelDuplicateReview() } }
        )
    }

    private var taskDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedTaskID != nil },
            set: { if !$0 { selectedTaskID = nil } }
        )
    }

    private func refreshTasksAfterTaskDetail() {
        model.returnToOverview()
        Task { await model.load() }
    }

    private func openTaskDetailRoute(_ route: CareerWorkRoute) {
        switch route {
        case let .action(id):
            selectedTaskID = id
        case .goal, .evidence:
            selectedTaskID = nil
            selectedRoute = route
        case .overview:
            selectedTaskID = nil
        }
    }

    private var detailTitle: String? {
        if let goal = model.state.snapshot?.selectedGoal { return goal.goal.title }
        if let action = model.state.snapshot?.selectedAction { return action.title }
        if let evidence = model.state.snapshot?.selectedEvidence { return evidence.title }
        return nil
    }

    private func issueRow(_ issue: CareerWorkIssue) -> some View {
        TaisaPressable(action: {
            if issue == .recoveryRequired { openRecovery() }
            else { Task { await model.retry() } }
        }) {
            TaisaRow(title: issue == .conflict ? "This changed elsewhere. Review the latest version." : "Career Work needs attention", icon: .warning, emphasis: .attention)
        }
    }

    private func failure(_ issue: CareerWorkIssue) -> some View {
        ContentUnavailableView {
            VStack {
                CentralIcon(.warning)
                    .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                TaisaText(role: .heading, content: issue == .recoveryRequired ? "Recovery required" : "Career Work unavailable")
            }
        } description: {
            TaisaText(role: .body, color: .mutedForeground, content: issue == .recoveryRequired ? "Open recovery to restore secure access." : "Taisa couldn’t read your encrypted career work.")
        } actions: {
            if issue == .recoveryRequired {
                TaisaButton(role: .primary, label: "Open recovery", icon: .recovery) { openRecovery() }
                    .accessibilityIdentifier("career-work.recovery")
            } else {
                TaisaButton(role: .primary, label: "Try again", icon: .refresh) { Task { await model.retry() } }
                    .accessibilityIdentifier("career-work.retry")
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
    let addAction: () -> Void

    var body: some View {
        List {
            Section("Progress") { TaisaRow(title: snapshot.progress.summary, icon: .goal) }
            Section("Add work") {
                TaisaButton(role: .secondary, label: "Add milestone", icon: .milestone) { add(.milestone) }
                TaisaButton(role: .secondary, label: "Add task", icon: .action) { addAction() }
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
                Section("Tasks") {
                    ForEach(snapshot.actions, id: \.id) { action in
                        TaisaPressable(action: { open(.action(id: action.id)) }) {
                            TaisaRow(title: action.title, supporting: action.status, icon: action.status == "completed" ? .completed : .incomplete)
                        }
                        .accessibilityLabel("Task \(action.title), \(action.status)")
                    }
                }
            }
            if !snapshot.evidence.isEmpty {
                Section("Evidence") {
                    ForEach(snapshot.evidence, id: \.id) { evidence in
                        TaisaPressable(action: { open(.evidence(id: evidence.id)) }) {
                            VStack(alignment: .leading) {
                                TaisaRow(title: evidence.title, icon: .evidence)
                                if let provenance = snapshot.provenance.first(where: { $0.evidenceID == evidence.id }) {
                                    TaisaText(role: .metadata, color: .mutedForeground, content: "Origin: \(provenance.origin.rawValue.capitalized)")
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
    case evidence(actions: [ActionRecord])

    var id: String {
        switch self { case .milestone: "milestone"; case .evidence: "evidence" }
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
        switch editor { case .milestone: "milestone"; case .evidence: "evidence" }
    }

    var body: some View {
        NavigationStack {
            Form {
                TaisaField("Title", text: $title)
                if case .milestone = editor { EmptyView() } else { TaisaField("Optional details", text: $detail, kind: .multiline) }
                TaisaDateField(editorDateLabel, selection: $date)
                if case let .evidence(actions) = editor, !actions.isEmpty {
                    TaisaPicker("Related task", selection: $actionID, options: [nil] + actions.map { Optional($0.id) }) { id in
                        id.flatMap { selected in actions.first(where: { $0.id == selected })?.title } ?? "Goal overall"
                    }
                }
                TaisaButton(role: .primary, label: "Save", icon: .completed, isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task { await save(title, detail, date, actionID); dismiss() }
                }
                .accessibilityLabel("Save career \(name)")
                TaisaButton(role: .secondary, label: "Cancel") { dismiss() }
            }
            .navigationTitle("New \(name)")
        }
    }

    private var editorDateLabel: String {
        switch editor { case .milestone: "Target date"; case .evidence: "Occurred" }
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
                TaisaText(role: .childHeaderTitle, content: title)
                TaisaText(role: .body, content: exactChange)
                TaisaRow(title: "Source", supporting: source, icon: .evidence)
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
    let milestones: [MilestoneRecord]
    let model: CareerWorkModel
    let open: (CareerWorkRoute) -> Void
    let deleted: () -> Void
    @State private var checklistTitle = ""
    @State private var completionEvidence = ""
    @State private var showsComplete = false
    @State private var showsDrop = false
    @State private var showsDelete = false
    @State private var showsEdit = false

    var body: some View {
        List {
            Section("Task") {
                TaisaStatusSurface(statusRole, label: snapshot.action.status.capitalized)
                if !snapshot.action.detail.isEmpty { TaisaRow(title: snapshot.action.detail) }
                if let due = actionDueText(snapshot.action) {
                    TaisaRow(title: "Due", supporting: due.replacingOccurrences(of: "Due ", with: ""), icon: .action)
                }
                if let goal = snapshot.goal {
                    TaisaPressable(action: { open(.goal(id: goal.id)) }) {
                        TaisaRow(title: goal.title, supporting: parentNotice(snapshot.goalAvailability), icon: .goal, emphasis: parentEmphasis(snapshot.goalAvailability))
                    }
                        .accessibilityIdentifier("career-work.action.parent-goal")
                }
                if let milestone = snapshot.milestone {
                    TaisaPressable(action: { open(.goal(id: milestone.goalID)) }) {
                        TaisaRow(title: milestone.title, supporting: parentNotice(snapshot.milestoneAvailability), icon: .milestone, emphasis: parentEmphasis(snapshot.milestoneAvailability))
                    }
                        .accessibilityIdentifier("career-work.action.parent-milestone")
                }
            }
            Section("Checklist") {
                ForEach(snapshot.checklist, id: \.id) { item in
                    HStack {
                        TaisaPressable(action: {
                            Task { await model.setChecklistItemCompleted(id: item.id, completed: item.state != .completed) }
                        }) {
                            TaisaRow(
                                title: item.title,
                                supporting: item.state == .promoted ? "Promoted to task" : nil,
                                icon: item.state == .completed ? .completed : .incomplete
                            )
                        }
                        if item.state == .pending {
                            TaisaMenu(label: "More", actions: [
                                ("Promote to task", .standard, { Task { await model.promoteChecklistItem(id: item.id) } }),
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
                    ForEach(snapshot.currentEvidence, id: \.id) { evidence in
                        TaisaPressable(action: { open(.evidence(id: evidence.id)) }) {
                            TaisaRow(title: evidence.title, supporting: evidence.detail, icon: .evidence)
                        }
                    }
                    ForEach(snapshot.supersededEvidence, id: \.id) { evidence in
                        TaisaPressable(action: { open(.evidence(id: evidence.id)) }) {
                            TaisaRow(title: evidence.title, supporting: "Corrected completion", icon: .undo)
                        }
                    }
                }
                .accessibilityIdentifier("career-work.action.evidence")
            }
            if !snapshot.events.isEmpty {
                Section {
                    ForEach(snapshot.events, id: \.id) { event in
                        HStack(alignment: .top) {
                            CentralIcon(.history)
                                .frame(width: TaisaControlMetric.standardIcon, height: TaisaControlMetric.standardIcon)
                            TaisaRow(title: event.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, supporting: event.detail)
                        }
                    }
                } header: { Text("History") }
                    .accessibilityIdentifier("career-work.action.history")
            }
            Section("Manage") { lifecycleControls }
        }
        .accessibilityIdentifier("career-work.action.detail")
        .modifier(TaisaConfirmationDialog(title: "Complete this task?", isPresented: $showsComplete, confirmLabel: "Complete task", cancelLabel: "Keep working") {
            Task { await model.completeSelectedAction(evidenceTitle: completionEvidence) }
        })
        .modifier(TaisaConfirmationDialog(title: "Drop this task?", isPresented: $showsDrop, confirmLabel: "Drop task", cancelLabel: "Keep task", role: .destructive) {
            Task { await model.dropSelectedAction() }
        })
        .modifier(TaisaConfirmationDialog(title: "Delete this task?", isPresented: $showsDelete, confirmLabel: "Delete task", cancelLabel: "Keep task", role: .destructive) {
            Task {
                if await model.deleteSelectedAction() { deleted() }
            }
        })
        .sheet(isPresented: $showsEdit) {
            ActionEditorSheet(goals: goals, milestones: milestones, initial: currentDraft, editing: true) { draft in
                let saved = await model.editSelectedAction(draft, expectedUpdatedAtMS: snapshot.action.updatedAtMS)
                if saved {
                    showsEdit = false
                }
                return saved
            }
        }
    }

    @ViewBuilder private var lifecycleControls: some View {
        TaisaButton(role: .secondary, label: "Edit task", icon: .edit) { showsEdit = true }
        switch ActionStatus(rawValue: snapshot.action.status) {
        case .active:
            TaisaField("Completion evidence", text: $completionEvidence, placeholder: "What shows this is complete?")
            TaisaButton(role: .primary, label: "Complete task", icon: .completeAction, isEnabled: !completionEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { showsComplete = true }
            TaisaButton(role: .secondary, label: "Drop task", icon: .drop) { showsDrop = true }
        case .completed, .dropped:
            TaisaButton(role: .secondary, label: "Reopen task", icon: .undo) { Task { await model.reopenSelectedAction() } }
            if snapshot.action.status == ActionStatus.completed.rawValue, let completionEvent = latestCompletionEvent {
                TaisaButton(role: .secondary, label: "Correct mistaken completion", icon: .undo) {
                    Task { await model.correctSelectedCompletion(eventID: completionEvent.id) }
                }
                .accessibilityIdentifier("career-work.action.correct-completion")
            }
        case nil:
            EmptyView()
        }
        TaisaButton(role: .destructive, label: "Delete task", icon: .delete) { showsDelete = true }
            .accessibilityIdentifier("career-work.action.delete")
    }

    private var trimmedChecklistTitle: String { checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var latestCompletionEvent: ActionEventRecord? { snapshot.events.last(where: { $0.kind == .completed }) }
    private func parentNotice(_ availability: ActionParentAvailability?) -> String? {
        switch availability {
        case .inactive: "Parent is inactive"
        case .deleted: "Parent was deleted"
        case .available, nil: nil
        }
    }
    private func parentEmphasis(_ availability: ActionParentAvailability?) -> TaisaRowEmphasis {
        availability == .inactive || availability == .deleted ? .attention : .standard
    }
    private var currentDraft: ActionDraft {
        let parent: ActionParentContext
        if let goalID = snapshot.action.goalID, let milestoneID = snapshot.action.milestoneID {
            parent = .milestone(goalID: goalID, milestoneID: milestoneID)
        } else if let goalID = snapshot.action.goalID {
            parent = .goal(id: goalID)
        } else {
            parent = .standalone
        }
        let dueDay = snapshot.action.dueDay ?? snapshot.action.dueAtMS.map { Date(timeIntervalSince1970: Double($0) / 1_000).actionDueDay }
        return ActionDraft(title: snapshot.action.title, detail: snapshot.action.detail, parent: parent, dueDay: dueDay)
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


private enum ActionFilterParentChoice: Hashable {
    case all, goal(String), milestone(String, String)
}

private enum ActionFilterWeekChoice: Hashable { case all, thisWeek }
private enum ActionFilterOriginChoice: Hashable { case all, manual }

private struct ActionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goals: [GoalRecord]
    let milestones: [MilestoneRecord]
    let apply: (ActionCollectionFilter) async -> Void
    @State private var lifecycle: ActionLifecycleFilter
    @State private var parent: ActionFilterParentChoice
    @State private var due: ActionDueFilter
    @State private var week: ActionFilterWeekChoice
    @State private var origin: ActionFilterOriginChoice

    init(filter: ActionCollectionFilter, goals: [GoalRecord], milestones: [MilestoneRecord], apply: @escaping (ActionCollectionFilter) async -> Void) {
        self.goals = goals
        self.milestones = milestones
        self.apply = apply
        _lifecycle = State(initialValue: filter.lifecycle)
        _parent = State(initialValue: Self.parentChoice(filter))
        _due = State(initialValue: filter.due)
        _week = State(initialValue: filter.weekStartMS == nil ? .all : .thisWeek)
        _origin = State(initialValue: filter.origin == nil ? .all : .manual)
    }

    var body: some View {
        NavigationStack {
            Form {
                TaisaPicker("Lifecycle", selection: $lifecycle, options: ActionLifecycleFilter.allCases) { $0.rawValue.capitalized }
                TaisaPicker("Relationship", selection: $parent, options: parentOptions, label: parentLabel)
                TaisaPicker("Due", selection: $due, options: ActionDueFilter.allCases) { dueLabel($0) }
                TaisaPicker("Week", selection: $week, options: [.all, .thisWeek]) { $0 == .all ? "Any week" : "This week" }
                TaisaPicker("Origin", selection: $origin, options: [.all, .manual]) { $0 == .all ? "Any origin" : "Manual" }
                TaisaButton(role: .primary, label: "Apply filters") { Task { await apply(filter) } }
                TaisaButton(role: .secondary, label: "Cancel") { dismiss() }
            }
            .navigationTitle("Filter tasks")
            .accessibilityIdentifier("career-work.action.filter-sheet")
        }
    }

    private var parentOptions: [ActionFilterParentChoice] {
        [.all] + goals.map { .goal($0.id) } + milestones.map { .milestone($0.goalID, $0.id) }
    }
    private func parentLabel(_ choice: ActionFilterParentChoice) -> String {
        switch choice {
        case .all: "Any relationship"
        case let .goal(id): goals.first(where: { $0.id == id })?.title ?? "Goal"
        case let .milestone(_, id): milestones.first(where: { $0.id == id })?.title ?? "Milestone"
        }
    }
    private func dueLabel(_ value: ActionDueFilter) -> String {
        switch value { case .all: "Any due date"; case .overdue: "Overdue"; case .due: "Due today"; case .noDueDay: "No due date" }
    }
    private var filter: ActionCollectionFilter {
        let relationship: (String?, String?) = switch parent {
        case .all: (nil, nil)
        case let .goal(id): (id, nil)
        case let .milestone(goalID, milestoneID): (goalID, milestoneID)
        }
        return .init(lifecycle: lifecycle, goalID: relationship.0, milestoneID: relationship.1, due: due, weekStartMS: week == .thisWeek ? Self.currentWeekStartMS : nil, origin: origin == .manual ? .manual : nil)
    }
    private static func parentChoice(_ filter: ActionCollectionFilter) -> ActionFilterParentChoice {
        if let milestoneID = filter.milestoneID { return .milestone(filter.goalID ?? "", milestoneID) }
        if let goalID = filter.goalID { return .goal(goalID) }
        return .all
    }
    private static var currentWeekStartMS: Int64 {
        let start = (try? WeekCalendar(timeZone: .current).week(containing: Date()).start) ?? Date()
        return Int64((start.timeIntervalSince1970 * 1_000).rounded())
    }
}

private func actionDueText(_ action: ActionRecord) -> String? {
    if let dueDay = action.dueDay { return "Due \(dueDay.rawValue)" }
    guard let dueAtMS = action.dueAtMS else { return nil }
    return "Due \(Date(timeIntervalSince1970: Double(dueAtMS) / 1_000).actionDueDay.rawValue)"
}

private struct ActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goals: [GoalRecord]
    let milestones: [MilestoneRecord]
    let save: (ActionDraft) async -> Bool
    let isEditing: Bool
    @State private var title = ""
    @State private var detail = ""
    @State private var parent: ActionParentChoice = .standalone
    @State private var dueDate: Date?

    init(goals: [GoalRecord], milestones: [MilestoneRecord], initial: ActionDraft? = nil, editing: Bool = false, save: @escaping (ActionDraft) async -> Bool) {
        self.goals = goals
        self.milestones = milestones
        self.save = save
        isEditing = editing
        _title = State(initialValue: initial?.title ?? "")
        _detail = State(initialValue: initial?.detail ?? "")
        _parent = State(initialValue: initial.map(Self.choice) ?? .standalone)
        _dueDate = State(initialValue: initial?.dueDay.flatMap(Self.date))
    }

    var body: some View {
        NavigationStack {
            TaisaColor.background.color
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TaskComposerView(title: $title, dueDate: $dueDate) {
                        Task {
                            if await save(draft) { dismiss() }
                        }
                    }
                }
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .accessibilityIdentifier("tasks.editor")
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
        return ActionDraft(title: trimmedTitle, detail: detail, parent: context, dueDay: dueDate?.actionDueDay)
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
                    TaisaButton(role: .secondary, label: "Open existing task", icon: .action) { Task { await decide(.openExisting) } }
                    TaisaButton(role: .primary, label: "Create separate task", icon: .add) { Task { await decide(.createSeparate) } }
                    TaisaButton(role: .secondary, label: "Cancel") { cancel() }
                }
            }
            .navigationTitle("Similar task found")
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
            TaisaRow(title: "Occurred", supporting: Date(timeIntervalSince1970: Double(evidence.occurredAtMS) / 1_000).formatted(date: .abbreviated, time: .omitted), icon: .evidence)
            if !evidence.detail.isEmpty { Section("Details") { TaisaText(role: .body, content: evidence.detail) } }
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
                TaisaField("Goal title", text: $title)
                TaisaField("Optional details", text: $detail, kind: .multiline)
                TaisaButton(role: .primary, label: "Save", icon: .completed, isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task { await save(title, detail); dismiss() }
                }
                .accessibilityLabel("Save career goal")
                TaisaButton(role: .secondary, label: "Cancel") { dismiss() }
            }
            .navigationTitle("New goal")
        }
    }
}
