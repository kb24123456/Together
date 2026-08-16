import SwiftUI

struct HomeTaskCreationCard: View {
    @Bindable var viewModel: HomeViewModel
    let session: HomeTaskCreationSession
    let isExpanded: Bool
    let isInteractive: Bool
    let onDiscard: () -> Void
    let onCommit: @MainActor () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var notes: String
    @State private var newSubtaskTitle = ""
    @State private var activeSubtaskID: UUID?
    @State private var activeSubtaskTitle = ""
    @State private var showsNotesEditor: Bool
    @State private var showsSubtaskEditor: Bool
    @State private var schedulePresentation: ExistingTaskScheduleEditorPresentation?
    @State private var isResolvingTextInput = false

    private enum Field: Hashable {
        case title
        case notes
        case newSubtask
        case existingSubtask(UUID)
    }

    init(
        viewModel: HomeViewModel,
        session: HomeTaskCreationSession,
        isExpanded: Bool = true,
        isInteractive: Bool = true,
        onDiscard: @escaping () -> Void = {},
        onCommit: @escaping @MainActor () async -> Void = {}
    ) {
        self.viewModel = viewModel
        self.session = session
        self.isExpanded = isExpanded
        self.isInteractive = isInteractive
        self.onDiscard = onDiscard
        self.onCommit = onCommit
        let initialNotes = session.draft.notes ?? ""
        _title = State(initialValue: session.draft.title)
        _notes = State(initialValue: initialNotes)
        _showsNotesEditor = State(initialValue: initialNotes.isEmpty == false)
        _showsSubtaskEditor = State(initialValue: session.draft.subtasks.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            titleRow

            if isExpanded {
                notesSection
                    .transition(disclosureTransition)
                subtasksSection
                    .transition(disclosureTransition)
            }

            if isExpanded, let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.leading, 56)
                    .transition(disclosureTransition)
            }

            if isExpanded {
                attributeBar
                    .padding(.top, AppTheme.spacing.xxs)
                    .transition(disclosureTransition)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .onAppear { updateFocus(isExpanded && isInteractive) }
        .onChange(of: isInteractive) { _, interactive in
            updateFocus(interactive && isExpanded)
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard case let .existingSubtask(id) = oldValue,
                  oldValue != newValue,
                  isResolvingTextInput == false
            else { return }
            commitExistingSubtask(id)
        }
        .sheet(item: $schedulePresentation) { presentation in
            DateTimePickerSheet(
                presentation: presentation,
                selectionFeedback: HomeInteractionFeedback.selection,
                onChange: { draft in
                    viewModel.updateTaskCreationSchedule(
                        date: draft.selectedDate,
                        time: draft.selectedTime,
                        reminderOffset: draft.reminderOffset
                    )
                }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新建待办")
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    AppTheme.colors.body.opacity(0.30),
                    lineWidth: 1.2
                )
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            TextField("任务标题", text: $title, axis: .vertical)
                .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
                .lineLimit(1...3)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit(confirmTitleAfterSnapshot)
                .onChange(of: title) { _, value in
                    viewModel.updateTaskCreationDraft { $0.title = value }
                }

            if focusedField == .title {
                Button("确认", action: confirmTitleAfterSnapshot)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.sky)
                    .frame(minWidth: 44, minHeight: 40)
                    .buttonStyle(.plain)
            } else {
                Button(role: .cancel) {
                    focusedField = nil
                    onDiscard()
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放弃新建任务")
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if showsNotesEditor {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Color.clear.frame(width: 40, height: 36)

                TextField("添加备注", text: $notes, axis: .vertical)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .notes)
                    .submitLabel(.done)
                    .onSubmit(confirmNotesAfterSnapshot)
                    .onChange(of: notes) { _, value in
                        updateNotes(value)
                    }

                if focusedField == .notes {
                    Button("确认", action: confirmNotesAfterSnapshot)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.sky)
                        .frame(minWidth: 44, minHeight: 36)
                        .buttonStyle(.plain)
                }
            }
        } else {
            revealButton("添加备注") {
                showsNotesEditor = true
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .notes
                }
            }
        }
    }

    @ViewBuilder
    private var subtasksSection: some View {
        if showsSubtaskEditor {
            ForEach(session.draft.subtasks) { subtask in
                creationSubtaskRow(subtask)
            }

            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Image(systemName: "plus")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.42))
                    .frame(width: 40, height: 36, alignment: .trailing)

                TextField("添加子任务", text: $newSubtaskTitle)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .focused($focusedField, equals: .newSubtask)
                    .submitLabel(.done)
                    .onSubmit(addSubtaskAfterSnapshot)

                if focusedField == .newSubtask {
                    Button("添加", action: addSubtaskAfterSnapshot)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.sky)
                        .frame(minWidth: 44, minHeight: 36)
                        .buttonStyle(.plain)
                }
            }
        } else {
            revealButton("添加子任务") {
                showsSubtaskEditor = true
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .newSubtask
                }
            }
        }
    }

    private func revealButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.42))
                .frame(width: 40, height: 36, alignment: .trailing)

            Button(action: action) {
                Text(title)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.48))
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func creationSubtaskRow(_ subtask: TaskSubtaskDraft) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            SubtaskCompletionMark(isCompleted: subtask.isCompleted)
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44, alignment: .center)
                .padding(.horizontal, -8)
                .padding(.vertical, -10)

            if activeSubtaskID == subtask.id {
                TextField("子任务标题", text: $activeSubtaskTitle)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .focused($focusedField, equals: .existingSubtask(subtask.id))
                    .submitLabel(.done)
                    .onSubmit { commitExistingSubtaskAfterSnapshot(subtask.id) }

                Button("确认") {
                    commitExistingSubtaskAfterSnapshot(subtask.id)
                }
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(minWidth: 44, minHeight: 36)
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    viewModel.updateTaskCreationDraft { draft in
                        draft.subtasks.removeAll { $0.id == subtask.id }
                    }
                    activeSubtaskID = nil
                    focusedField = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除子任务")
            } else {
                Button {
                    activeSubtaskID = subtask.id
                    activeSubtaskTitle = subtask.title
                    Task { @MainActor in
                        await Task.yield()
                        focusedField = .existingSubtask(subtask.id)
                    }
                } label: {
                    Text(subtask.title)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var attributeBar: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            ScrollView(.horizontal) {
                HStack(spacing: AppTheme.spacing.xs) {
                    scheduleAttributeButton(
                        title: dateText,
                        systemImage: "calendar",
                        isConfigured: true
                    )
                    scheduleAttributeButton(
                        title: session.draft.hasExplicitTime ? (timeText ?? "时间") : "时间",
                        systemImage: "clock",
                        isConfigured: session.draft.hasExplicitTime
                    )
                    scheduleAttributeButton(
                        title: reminderText ?? "提醒",
                        systemImage: "bell",
                        isConfigured: session.draft.remindAt != nil
                    )

                    Button {
                        HomeInteractionFeedback.selection()
                        focusedField = nil
                        viewModel.updateTaskCreationDraft { $0.isUrgent.toggle() }
                    } label: {
                        TaskAttributeLabel(
                            icon: session.draft.isUrgent ? "flag.fill" : "flag",
                            title: "",
                            isConfigured: session.draft.isUrgent,
                            tint: session.draft.isUrgent ? AppTheme.colors.coral : nil,
                            isCircular: true
                        )
                    }
                    .buttonStyle(TaskMorphAttributeButtonStyle())
                    .accessibilityLabel("紧急")
                    .accessibilityValue(session.draft.isUrgent ? "已开启" : "已关闭")
                }
            }
            .scrollIndicators(.hidden)

            Button(action: commitCard) {
                Group {
                    if session.phase == .committing || session.phase == .committed {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                            .font(AppTheme.typography.sized(16, weight: .bold))
                    }
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppTheme.colors.title))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .disabled(canAttemptCommit == false || session.phase != .editing)
            .opacity(canAttemptCommit ? 1 : 0.38)
            .accessibilityLabel("添加任务")
        }
    }

    private func scheduleAttributeButton(
        title: String,
        systemImage: String,
        isConfigured: Bool
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            focusedField = nil
            openSchedule()
        } label: {
            TaskAttributeLabel(
                icon: systemImage,
                title: title,
                isConfigured: isConfigured
            )
        }
        .buttonStyle(TaskMorphAttributeButtonStyle())
    }

    private var dateText: String {
        guard let date = session.draft.dueAt else { return "今天" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        return date.formatted(.dateTime.month().day())
    }

    private var timeText: String? {
        guard session.draft.hasExplicitTime else { return nil }
        return session.draft.dueAt?.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }

    private var reminderText: String? {
        guard let remindAt = session.draft.remindAt else { return nil }
        return TaskSharedAttributeText.reminderLead(
            dueAt: session.draft.dueAt,
            hasExplicitTime: session.draft.hasExplicitTime,
            remindAt: remindAt,
            calendar: .current
        )
    }

    private func openSchedule() {
        schedulePresentation = ExistingTaskScheduleEditorPresentation(
            dueAt: session.draft.dueAt,
            hasExplicitTime: session.draft.hasExplicitTime,
            remindAt: session.draft.remindAt,
            fallbackDate: viewModel.selectedDate
        )
    }

    private var canAttemptCommit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || focusedField == .title
    }

    private var disclosureTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.04)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    private func updateFocus(_ shouldFocus: Bool) {
        if shouldFocus {
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
            }
        } else {
            focusedField = nil
            schedulePresentation = nil
        }
    }

    private func updateNotes(_ value: String) {
        viewModel.updateTaskCreationDraft {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.notes = trimmed.isEmpty ? nil : value
        }
    }

    private func confirmTitleAfterSnapshot() {
        Task { @MainActor in
            title = TextInputSnapshotReader.resolvedText(fallback: title)
            viewModel.updateTaskCreationDraft { $0.title = title }
            focusedField = nil
        }
    }

    private func confirmNotesAfterSnapshot() {
        Task { @MainActor in
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            updateNotes(notes)
            focusedField = nil
        }
    }

    private func addSubtaskAfterSnapshot() {
        Task { @MainActor in
            newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
            focusedField = nil
            await Task.yield()
            addSubtask()
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            focusedField = .newSubtask
            return
        }
        viewModel.updateTaskCreationDraft { draft in
            draft.subtasks.append(TaskSubtaskDraft(title: trimmed, sortOrder: draft.subtasks.count))
        }
        newSubtaskTitle = ""
        focusedField = .newSubtask
    }

    private func commitExistingSubtaskAfterSnapshot(_ id: UUID) {
        guard isResolvingTextInput == false else { return }
        isResolvingTextInput = true
        Task { @MainActor in
            activeSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: activeSubtaskTitle)
            focusedField = nil
            await Task.yield()
            commitExistingSubtask(id)
            isResolvingTextInput = false
        }
    }

    private func commitExistingSubtask(_ id: UUID) {
        guard activeSubtaskID == id else { return }
        let trimmed = activeSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        viewModel.updateTaskCreationDraft { draft in
            guard let index = draft.subtasks.firstIndex(where: { $0.id == id }) else { return }
            draft.subtasks[index].title = trimmed
        }
        activeSubtaskID = nil
        activeSubtaskTitle = ""
    }

    private func commitCard() {
        HomeInteractionFeedback.selection()
        Task { @MainActor in
            await resolveFocusedInputBeforeCommit()
            await onCommit()
        }
    }

    @MainActor
    private func resolveFocusedInputBeforeCommit() async {
        switch focusedField {
        case .title:
            title = TextInputSnapshotReader.resolvedText(fallback: title)
            viewModel.updateTaskCreationDraft { $0.title = title }
        case .notes:
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            updateNotes(notes)
        case .newSubtask:
            newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
            addSubtask()
        case let .existingSubtask(id):
            activeSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: activeSubtaskTitle)
            commitExistingSubtask(id)
        case nil:
            break
        }
        focusedField = nil
        await Task.yield()
    }
}
