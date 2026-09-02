import SwiftUI

enum TaskDetailRoute: Hashable {
    case todo(UUID)
    case periodic(UUID)

    var id: UUID {
        switch self {
        case .todo(let id), .periodic(let id):
            id
        }
    }

    var domain: TaskMorphDomain {
        switch self {
        case .todo:
            .todo
        case .periodic:
            .periodic
        }
    }
}

extension View {
    @ViewBuilder
    func taskDetailMatchedTransitionSource(
        _ route: TaskDetailRoute,
        in namespace: Namespace.ID?,
        isEnabled: Bool
    ) -> some View {
        if isEnabled, let namespace {
            matchedTransitionSource(id: route, in: namespace)
        } else {
            self
        }
    }
}

struct TaskDetailPresentation: Identifiable, Hashable {
    let id: UUID
    let route: TaskDetailRoute

    init(
        id: UUID = UUID(),
        route: TaskDetailRoute
    ) {
        self.id = id
        self.route = route
    }

    func canReleaseSharedDraft(while activePresentation: TaskDetailPresentation?) -> Bool {
        activePresentation == nil || activePresentation?.id == id
    }
}

struct TaskDetailView: View {
    let presentation: TaskDetailPresentation
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let onDidDisappear: @MainActor (TaskDetailPresentation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isClosing = false
    @State private var didStartDisappearanceCleanup = false
    @State private var inputCommitRequestRevision: UInt = 0
    @State private var hasTransientInputChanges = false
    @State private var hasFocusedInput = false

    private var route: TaskDetailRoute {
        presentation.route
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .todo(let id):
                    todoDetail(id: id)
                case .periodic(let id):
                    periodicDetail(id: id)
                }
            }
            .background(AppTheme.colors.background.ignoresSafeArea())
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: cancelAndClose)
                        .labelStyle(.iconOnly)
                        .disabled(isClosing)
                        .accessibilityHint("放弃尚未确认的更改")
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isClosing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在保存任务")
                    } else {
                        Button("确认", systemImage: "checkmark") {
                            Task { await saveAndClose() }
                        }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .disabled(isConfirmationDisabled)
                        .accessibilityHint(
                            confirmationAccessibilityHint
                        )
                    }
                }
            }
        }
        .interactiveDismissDisabled(isClosing)
        .accessibilityAction(.escape) {
            cancelAndClose()
        }
        .onDisappear {
            guard didStartDisappearanceCleanup == false else { return }
            didStartDisappearanceCleanup = true
            onDidDisappear(presentation)
        }
    }

    @ViewBuilder
    private func todoDetail(id: UUID) -> some View {
        if let entry = homeViewModel.timelineEntry(for: id),
           let draft = homeViewModel.detailDraft {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                    TodoTaskDetailEditor(
                        entry: entry,
                        initialDraft: draft,
                        viewModel: homeViewModel,
                        isClosing: isClosing,
                        inputCommitRequestRevision: inputCommitRequestRevision,
                        onComplete: {
                            Task { await completeAndClose() }
                        },
                        onTransientInputChange: {
                            hasTransientInputChanges = $0
                        },
                        onFocusChange: {
                            hasFocusedInput = $0
                        }
                    )

                    detailError
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.sm)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                HomeTaskAttributeFooter(
                    entry: entry,
                    viewModel: homeViewModel,
                    isExpanded: isClosing == false,
                    allowsZoomTransition: hasFocusedInput == false
                )
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.xs)
                .padding(.bottom, AppTheme.spacing.sm)
            }
        } else {
            unavailableDetail
        }
    }

    @ViewBuilder
    private func periodicDetail(id: UUID) -> some View {
        if let task = routinesViewModel.tasks.first(where: { $0.id == id }),
           let draft = routinesViewModel.detailDraft {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                    PeriodicTaskDetailEditor(
                        task: task,
                        initialDraft: draft,
                        viewModel: routinesViewModel,
                        isClosing: isClosing,
                        inputCommitRequestRevision: inputCommitRequestRevision,
                        onComplete: {
                            Task { await completeAndClose() }
                        },
                        onFocusChange: {
                            hasFocusedInput = $0
                        }
                    )

                    detailError
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.sm)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                PeriodicTaskAttributeFooter(
                    task: task,
                    viewModel: routinesViewModel,
                    isExpanded: isClosing == false,
                    allowsZoomTransition: hasFocusedInput == false
                )
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.xs)
                .padding(.bottom, AppTheme.spacing.sm)
            }
        } else {
            unavailableDetail
        }
    }

    @ViewBuilder
    private var detailError: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(AppTheme.typography.scaled(13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(AppTheme.colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppTheme.spacing.sm)
        }
    }

    private var unavailableDetail: some View {
        ContentUnavailableView(
            "无法打开任务",
            systemImage: "exclamationmark.triangle",
            description: Text("任务可能已被删除或移动，请返回列表刷新后重试。")
        )
    }

    private var hasUnsavedChanges: Bool {
        if hasTransientInputChanges { return true }

        return switch route {
        case .todo:
            homeViewModel.hasUnsavedDetailChanges
        case .periodic(let id):
            routinesViewModel.tasks
                .first(where: { $0.id == id })
                .map(routinesViewModel.hasUnsavedInlineChanges(for:))
                ?? false
        }
    }

    private var hasValidTitle: Bool {
        let title = switch route {
        case .todo:
            homeViewModel.detailDraft?.title
        case .periodic:
            routinesViewModel.detailDraft?.title
        }
        return title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isConfirmationDisabled: Bool {
        hasUnsavedChanges == false || hasValidTitle == false
    }

    private var confirmationAccessibilityHint: String {
        if hasValidTitle == false {
            return "请先输入任务标题"
        }
        return hasUnsavedChanges
            ? "保存更改并关闭任务详情"
            : "任务内容尚未更改"
    }

    private func cancelAndClose() {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil
        dismiss()
    }

    @MainActor
    private func saveAndClose() async {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil

        guard isCurrentDetailAvailable else {
            dismiss()
            return
        }

        inputCommitRequestRevision &+= 1
        await Task.yield()
        await Task.yield()

        guard await persistCurrentDetail() else {
            isClosing = false
            return
        }

        dismiss()
    }

    private var isCurrentDetailAvailable: Bool {
        switch route {
        case .todo(let id):
            homeViewModel.timelineEntry(for: id) != nil && homeViewModel.detailDraft != nil
        case .periodic(let id):
            routinesViewModel.tasks.contains(where: { $0.id == id })
                && routinesViewModel.detailDraft != nil
        }
    }

    @MainActor
    private func completeAndClose() async {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil

        inputCommitRequestRevision &+= 1
        await Task.yield()
        await Task.yield()

        guard await persistCurrentDetail() else {
            isClosing = false
            return
        }

        let didComplete: Bool
        switch route {
        case .todo(let id):
            homeViewModel.dismissOperationError()
            await homeViewModel.completeItem(id, trigger: .taskExpansion)
            didComplete = homeViewModel.item(for: id)?.status == .completed
            if didComplete == false {
                errorMessage = homeViewModel.operationErrorMessage ?? "任务状态更新失败，请重试。"
            }
        case .periodic(let id):
            routinesViewModel.dismissOperationError()
            await routinesViewModel.toggleCompletion(taskID: id)
            if let task = routinesViewModel.tasks.first(where: { $0.id == id }) {
                didComplete = routinesViewModel.isCompleted(task)
            } else {
                didComplete = false
            }
            if didComplete == false {
                errorMessage = routinesViewModel.operationErrorMessage ?? "定期任务状态更新失败，请重试。"
            }
        }

        guard didComplete else {
            isClosing = false
            return
        }

        dismiss()
    }

    @MainActor
    private func persistCurrentDetail() async -> Bool {
        switch route {
        case .todo:
            let didSave = await homeViewModel.saveInlineDetailDraft()
            if didSave == false {
                errorMessage = homeViewModel.operationErrorMessage ?? "任务保存失败，请重试。"
            }
            return didSave
        case .periodic:
            let didSave = await routinesViewModel.saveInlineDetailDraft()
            if didSave == false {
                errorMessage = routinesViewModel.operationErrorMessage ?? "定期任务保存失败，请重试。"
            }
            return didSave
        }
    }

}

private enum TaskDetailEditorFocus: Hashable {
    case title
    case notes
    case existingSubtask(UUID)
    case newSubtask
}

private enum TaskDetailEditorLayout {
    static let actionColumnWidth: CGFloat = 44
    static let columnSpacing: CGFloat = 2
    static let textColumnInset = actionColumnWidth + columnSpacing
}

private struct TodoTaskDetailEditor: View {
    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel
    let isClosing: Bool
    let inputCommitRequestRevision: UInt
    let onComplete: () -> Void
    let onTransientInputChange: (Bool) -> Void
    let onFocusChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: TaskDetailEditorFocus?
    @State private var title: String
    @State private var notes: String
    @State private var editingSubtaskID: UUID?
    @State private var editingSubtaskTitle = ""
    @State private var newSubtaskTitle = ""
    @State private var didRequestInitialFocus = false

    init(
        entry: HomeTimelineEntry,
        initialDraft: TaskDraft,
        viewModel: HomeViewModel,
        isClosing: Bool,
        inputCommitRequestRevision: UInt,
        onComplete: @escaping () -> Void,
        onTransientInputChange: @escaping (Bool) -> Void,
        onFocusChange: @escaping (Bool) -> Void
    ) {
        self.entry = entry
        self.viewModel = viewModel
        self.isClosing = isClosing
        self.inputCommitRequestRevision = inputCommitRequestRevision
        self.onComplete = onComplete
        self.onTransientInputChange = onTransientInputChange
        self.onFocusChange = onFocusChange
        _title = State(initialValue: initialDraft.title)
        _notes = State(initialValue: initialDraft.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            identitySection
            subtaskSection
            TaskDetailMetadataFooter(createdAt: entry.createdAt)
        }
        .task {
            guard didRequestInitialFocus == false else { return }
            didRequestInitialFocus = true
            await Task.yield()
            guard Task.isCancelled == false, isClosing == false else { return }
            focusedField = .title
        }
        .onChange(of: focusedField) { oldValue, newValue in
            onFocusChange(newValue != nil)
            guard case .existingSubtask(let id) = oldValue,
                  newValue != oldValue
            else { return }
            commitExistingSubtask(id)
        }
        .onChange(of: viewModel.detailDraft?.subtasks) { _, subtasks in
            guard let editingSubtaskID,
                  subtasks?.contains(where: { $0.id == editingSubtaskID }) == true
            else {
                self.editingSubtaskID = nil
                editingSubtaskTitle = ""
                return
            }
        }
        .onChange(of: inputCommitRequestRevision) { _, revision in
            guard revision > 0 else { return }
            flushFocusedInputForCommit()
        }
        .onDisappear {
            onFocusChange(false)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack(alignment: .top, spacing: TaskDetailEditorLayout.columnSpacing) {
                completionButton

                TextField("任务标题", text: $title, axis: .vertical)
                    .font(AppTheme.typography.scaled(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(taskTitleColor)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...8 : 1...4)
                    .focused($focusedField, equals: .title)
                    .frame(minHeight: 44, alignment: .leading)
                    .onChange(of: title) { _, value in
                        viewModel.updateDraftTitle(value)
                    }
                    .onSubmit(commitTitleSnapshot)
                    .accessibilityIdentifier("together.task-detail.title")
            }

            TextField("添加备注", text: $notes, axis: .vertical)
                .font(AppTheme.typography.scaled(15, weight: .regular, relativeTo: .body))
                .foregroundStyle(taskBodyColor)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...6)
                .focused($focusedField, equals: .notes)
                .onChange(of: notes) { _, value in
                    viewModel.updateDraftNotes(value)
                }
                .padding(.leading, TaskDetailEditorLayout.textColumnInset)
                .accessibilityIdentifier("together.task-detail.notes")
        }
        .padding(.vertical, AppTheme.spacing.xs)
    }

    private var completionButton: some View {
        Button(action: onComplete) {
            TaskDetailCompletionMark()
                .frame(
                    width: TaskDetailEditorLayout.actionColumnWidth,
                    height: TaskDetailEditorLayout.actionColumnWidth
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isClosing || isTitleEmpty)
        .accessibilityLabel("完成任务")
        .accessibilityHint("保存当前更改并完成任务")
    }

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subtasks, id: \.id) { subtask in
                subtaskRow(subtask)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: 8))
                                    .combined(with: .scale(scale: 0.98, anchor: .topLeading)),
                                removal: .opacity
                            )
                    )
            }

            newSubtaskRow
        }
    }

    private var subtasks: [TaskSubtaskDraft] {
        viewModel.detailDraft?.subtasks ?? []
    }

    private func subtaskRow(_ subtask: TaskSubtaskDraft) -> some View {
        HStack(spacing: TaskDetailEditorLayout.columnSpacing) {
            Button {
                subtask.isCompleted
                    ? HomeInteractionFeedback.selection()
                    : HomeInteractionFeedback.completion()
                viewModel.toggleDetailDraftSubtask(subtask.id)
            } label: {
                SubtaskCompletionMark(isCompleted: subtask.isCompleted)
                    .frame(width: 20, height: 20)
                    .frame(
                        width: TaskDetailEditorLayout.actionColumnWidth,
                        height: TaskDetailEditorLayout.actionColumnWidth
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "恢复子任务" : "完成子任务")

            if editingSubtaskID == subtask.id {
                TextField("子任务标题", text: $editingSubtaskTitle)
                    .font(AppTheme.typography.scaled(16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(taskBodyColor)
                    .focused($focusedField, equals: .existingSubtask(subtask.id))
                    .submitLabel(.done)
                    .onChange(of: editingSubtaskTitle) { _, value in
                        viewModel.updateDetailDraftSubtask(subtask.id, title: value)
                    }
                    .onSubmit {
                        commitExistingSubtaskSnapshot(subtask.id)
                    }

                Button(role: .destructive) {
                    HomeInteractionFeedback.delete()
                    if reduceMotion {
                        viewModel.deleteDetailDraftSubtask(subtask.id)
                    } else {
                        withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                            viewModel.deleteDetailDraftSubtask(subtask.id)
                        }
                    }
                    editingSubtaskID = nil
                    editingSubtaskTitle = ""
                    focusedField = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除子任务")
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    editingSubtaskID = subtask.id
                    editingSubtaskTitle = subtask.title
                    focusedField = .existingSubtask(subtask.id)
                } label: {
                    Text(subtask.title)
                        .font(AppTheme.typography.scaled(16, weight: .medium, relativeTo: .body))
                        .foregroundStyle(taskBodyColor)
                        .strikethrough(subtask.isCompleted)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑子任务 \(subtask.title)")
            }
        }
    }

    private var newSubtaskRow: some View {
        HStack(spacing: TaskDetailEditorLayout.columnSpacing) {
            Image(systemName: "plus")
                .font(AppTheme.typography.scaled(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(AppTheme.colors.bodySecondary)
                .frame(
                    width: TaskDetailEditorLayout.actionColumnWidth,
                    height: TaskDetailEditorLayout.actionColumnWidth
                )

            TextField("添加子任务", text: $newSubtaskTitle)
                .font(AppTheme.typography.scaled(16, weight: .medium, relativeTo: .body))
                .foregroundStyle(taskBodyColor)
                .focused($focusedField, equals: .newSubtask)
                .submitLabel(.done)
                .onSubmit(addSubtaskSnapshot)
                .onChange(of: newSubtaskTitle) { _, value in
                    onTransientInputChange(
                        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    )
                }

            Button("添加", action: addSubtaskSnapshot)
                .font(AppTheme.typography.scaled(13, weight: .semibold, relativeTo: .footnote))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .opacity(canAddSubtask ? 1 : 0)
                .disabled(canAddSubtask == false)
                .accessibilityHidden(canAddSubtask == false)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: canAddSubtask)
        }
    }

    private var canAddSubtask: Bool {
        newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskTitleColor: Color {
        colorScheme == .light ? AppTheme.colors.taskFocusTitle : AppTheme.colors.title
    }

    private var taskBodyColor: Color {
        colorScheme == .light ? AppTheme.colors.taskFocusBody : AppTheme.colors.body
    }

    private func commitTitleSnapshot() {
        title = TextInputSnapshotReader.resolvedText(fallback: title)
        viewModel.updateDraftTitle(title)
    }

    private func commitExistingSubtaskSnapshot(_ id: UUID) {
        editingSubtaskTitle = TextInputSnapshotReader.resolvedText(
            fallback: editingSubtaskTitle
        )
        focusedField = nil
        commitExistingSubtask(id)
    }

    private func commitExistingSubtask(_ id: UUID) {
        guard editingSubtaskID == id else { return }
        let trimmed = editingSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        viewModel.updateDetailDraftSubtask(id, title: trimmed)
        editingSubtaskID = nil
        editingSubtaskTitle = ""
    }

    private func addSubtaskSnapshot() {
        newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
        focusedField = nil
        addSubtask()
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        if reduceMotion {
            viewModel.addDetailDraftSubtask(title: trimmed)
        } else {
            withAnimation(.smooth(duration: 0.30, extraBounce: 0)) {
                viewModel.addDetailDraftSubtask(title: trimmed)
            }
        }
        HomeInteractionFeedback.selection()
        newSubtaskTitle = ""
        onTransientInputChange(false)
    }

    private func flushFocusedInputForCommit() {
        switch focusedField {
        case .title:
            commitTitleSnapshot()
        case .notes:
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            viewModel.updateDraftNotes(notes)
        case .existingSubtask(let id):
            commitExistingSubtaskSnapshot(id)
        case .newSubtask:
            addSubtaskSnapshot()
        case nil:
            break
        }
    }
}

private struct PeriodicTaskDetailEditor: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isClosing: Bool
    let inputCommitRequestRevision: UInt
    let onComplete: () -> Void
    let onFocusChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: TaskDetailEditorFocus?
    @State private var title: String
    @State private var notes: String
    @State private var didRequestInitialFocus = false

    init(
        task: PeriodicTask,
        initialDraft: RoutineInlineDraft,
        viewModel: RoutinesViewModel,
        isClosing: Bool,
        inputCommitRequestRevision: UInt,
        onComplete: @escaping () -> Void,
        onFocusChange: @escaping (Bool) -> Void
    ) {
        self.task = task
        self.viewModel = viewModel
        self.isClosing = isClosing
        self.inputCommitRequestRevision = inputCommitRequestRevision
        self.onComplete = onComplete
        self.onFocusChange = onFocusChange
        _title = State(initialValue: initialDraft.title)
        _notes = State(initialValue: initialDraft.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                HStack(alignment: .top, spacing: TaskDetailEditorLayout.columnSpacing) {
                    completionButton

                    TextField("定期任务标题", text: $title, axis: .vertical)
                        .font(AppTheme.typography.scaled(22, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(taskTitleColor)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...8 : 1...4)
                        .focused($focusedField, equals: .title)
                        .frame(minHeight: 44, alignment: .leading)
                        .onChange(of: title) { _, value in
                            viewModel.updateDraftTitle(value)
                        }
                        .onSubmit(commitTitleSnapshot)
                        .accessibilityIdentifier("together.periodic-task-detail.title")
                }

                TextField("添加备注", text: $notes, axis: .vertical)
                    .font(AppTheme.typography.scaled(15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(taskBodyColor)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(1...6)
                    .focused($focusedField, equals: .notes)
                    .onChange(of: notes) { _, value in
                        viewModel.updateDraftNotes(value)
                    }
                    .padding(.leading, TaskDetailEditorLayout.textColumnInset)
                    .accessibilityIdentifier("together.periodic-task-detail.notes")
            }
            .padding(.vertical, AppTheme.spacing.xs)

            TaskDetailMetadataFooter(createdAt: task.createdAt)
        }
        .task {
            guard didRequestInitialFocus == false else { return }
            didRequestInitialFocus = true
            await Task.yield()
            guard Task.isCancelled == false, isClosing == false else { return }
            focusedField = .title
        }
        .onChange(of: focusedField) { _, newValue in
            onFocusChange(newValue != nil)
        }
        .onChange(of: inputCommitRequestRevision) { _, revision in
            guard revision > 0 else { return }
            flushFocusedInputForCommit()
        }
        .onDisappear {
            onFocusChange(false)
        }
    }

    private var completionButton: some View {
        Button(action: onComplete) {
            TaskDetailCompletionMark()
                .frame(
                    width: TaskDetailEditorLayout.actionColumnWidth,
                    height: TaskDetailEditorLayout.actionColumnWidth
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isClosing || isTitleEmpty)
        .accessibilityLabel("完成定期任务")
        .accessibilityHint("保存当前更改并完成本周期任务")
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskTitleColor: Color {
        colorScheme == .light ? AppTheme.colors.taskFocusTitle : AppTheme.colors.title
    }

    private var taskBodyColor: Color {
        colorScheme == .light ? AppTheme.colors.taskFocusBody : AppTheme.colors.body
    }

    private func commitTitleSnapshot() {
        title = TextInputSnapshotReader.resolvedText(fallback: title)
        viewModel.updateDraftTitle(title)
    }

    private func flushFocusedInputForCommit() {
        switch focusedField {
        case .title:
            commitTitleSnapshot()
        case .notes:
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            viewModel.updateDraftNotes(notes)
        case .existingSubtask, .newSubtask, nil:
            break
        }
    }
}

private struct TaskDetailCompletionMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(AppTheme.colors.body.opacity(0.30), lineWidth: 1.2)
            .frame(width: 28, height: 28)
    }
}

private struct TaskDetailMetadataFooter: View {
    let createdAt: Date
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Label {
            Text("创建至今 \(TaskLifecycleFormatting.relativeDuration(since: createdAt))")
        } icon: {
            Image(systemName: "hourglass")
                .accessibilityHidden(true)
        }
        .font(AppTheme.typography.scaled(11, weight: .regular, relativeTo: .caption2))
        .foregroundStyle(
            AppTheme.colors.body.opacity(colorSchemeContrast == .increased ? 0.78 : 0.48)
        )
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}
