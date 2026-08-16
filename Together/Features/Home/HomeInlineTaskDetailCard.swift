import SwiftUI

struct HomeInlineTaskDetailCard: View {
    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel
    let isExpanded: Bool
    let isCollapsing: Bool
    let cascadeElapsed: TimeInterval
    let cascadeRowCount: Int

    @State private var newSubtaskTitle = ""
    @State private var notesDraft = ""
    @State private var activeSubtaskID: UUID?
    @State private var activeSubtaskTitle = ""
    @State private var showsSubtaskComposer = false
    @State private var isCommittingSubtask = false
    @State private var isEditingNotes = false
    @State private var isCommittingNotes = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case existingSubtask(UUID)
        case newSubtask
        case notes
    }

    var body: some View {
        let subtasks = viewModel.inlineDetailDraft?.subtasks ?? []

        VStack(alignment: .leading, spacing: HomeInlineTaskLayoutMetrics.detailVerticalSpacing) {
            notesRow
                .taskMorphCascade(
                    elapsed: cascadeElapsed,
                    index: 0,
                    rowCount: cascadeRowCount,
                    isCollapsing: isCollapsing
                )

            VStack(alignment: .leading, spacing: HomeInlineTaskLayoutMetrics.subtaskSpacing) {
                ForEach(subtasks, id: \.id) { subtask in
                    subtaskRow(subtask)
                        .taskMorphCascade(
                            elapsed: cascadeElapsed,
                            index: cascadeIndex(for: subtask, in: subtasks),
                            rowCount: cascadeRowCount,
                            isCollapsing: isCollapsing
                        )
                }
            }

            if showsSubtaskComposer {
                newSubtaskRow
                    .taskMorphCascade(
                        elapsed: cascadeElapsed,
                        index: subtasks.count + 1,
                        rowCount: cascadeRowCount,
                        isCollapsing: isCollapsing
                    )
            } else {
                disclosureButton(title: "添加子任务", systemImage: "plus") {
                    showsSubtaskComposer = true
                    Task { @MainActor in
                        await Task.yield()
                        focusedField = .newSubtask
                    }
                }
                .taskMorphCascade(
                    elapsed: cascadeElapsed,
                    index: subtasks.count + 1,
                    rowCount: cascadeRowCount,
                    isCollapsing: isCollapsing
                )
            }
        }
        .padding(.top, HomeInlineTaskLayoutMetrics.detailTopPadding)
        .padding(.bottom, HomeInlineTaskLayoutMetrics.detailBottomPadding)
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .notes, newValue != .notes, isCommittingNotes == false {
                commitNotes()
            }
            guard case let .existingSubtask(id) = oldValue,
                  newValue != oldValue,
                  isCommittingSubtask == false
            else { return }
            commitExistingSubtask(id)
        }
        .onChange(of: viewModel.inlineDetailDraft?.subtasks) { _, subtasks in
            guard let activeSubtaskID,
                  subtasks?.contains(where: { $0.id == activeSubtaskID }) == true
            else {
                self.activeSubtaskID = nil
                activeSubtaskTitle = ""
                return
            }
        }
        .onAppear { notesDraft = viewModel.inlineDetailDraft?.notes ?? entry.notes ?? "" }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded == false, isEditingNotes else { return }
            commitNotes()
        }
    }

    private func cascadeIndex(
        for subtask: TaskSubtaskDraft,
        in subtasks: [TaskSubtaskDraft]
    ) -> Int {
        (subtasks.firstIndex(where: { $0.id == subtask.id }) ?? 0) + 1
    }

    @ViewBuilder
    private var notesRow: some View {
        if isEditingNotes {
            HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                Image(systemName: "note.text")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                    .frame(width: HomeInlineTaskLayoutMetrics.checkboxSize, height: 32)

                TextField("添加备注", text: $notesDraft, axis: .vertical)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .notes)
                    .submitLabel(.done)
                    .onSubmit(commitNotes)
                    .onChange(of: notesDraft) { _, notes in
                        guard isEditingNotes else { return }
                        viewModel.updateDraftNotes(notes)
                    }

                Button("确认", action: commitNotes)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.sky)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.vertical, -6)
                    .buttonStyle(.plain)
            }
        } else {
            let notes = viewModel.inlineDetailDraft?.notes ?? entry.notes ?? ""
            disclosureButton(
                title: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "添加备注" : notes,
                systemImage: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "plus" : "note.text",
                isPlaceholder: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                notesDraft = notes
                isEditingNotes = true
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .notes
                }
            }
        }
    }

    private func disclosureButton(
        title: String,
        systemImage: String,
        isPlaceholder: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(isPlaceholder ? 0.68 : 0.76))
                .frame(
                    width: HomeInlineTaskLayoutMetrics.checkboxSize,
                    height: 32
                )

            Button(action: action) {
                Text(title)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(isPlaceholder ? 0.72 : 0.82))
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .frame(minHeight: 44)
            .padding(.vertical, -6)
            .buttonStyle(.plain)
        }
    }

    private func subtaskRow(_ subtask: TaskSubtaskDraft) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            Button {
                viewModel.toggleDetailDraftSubtask(subtask.id)
            } label: {
                SubtaskCompletionMark(isCompleted: subtask.isCompleted)
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44, alignment: .center)
            }
            .padding(.horizontal, -8)
            .padding(.vertical, -10)
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "恢复子任务" : "完成子任务")

            if activeSubtaskID == subtask.id {
                TextField("子任务标题", text: $activeSubtaskTitle)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .strikethrough(subtask.isCompleted)
                    .focused($focusedField, equals: .existingSubtask(subtask.id))
                    .submitLabel(.done)
                    .onSubmit { commitExistingSubtaskAfterSnapshot(subtask.id) }

                Button("确认") {
                    commitExistingSubtaskAfterSnapshot(subtask.id)
                }
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.vertical, -6)
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    viewModel.deleteDetailDraftSubtask(subtask.id)
                    activeSubtaskID = nil
                    focusedField = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 40, height: 44)
                }
                .padding(.vertical, -6)
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
                        .strikethrough(subtask.isCompleted)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑子任务 \(subtask.title)")
            }
        }
    }

    private var newSubtaskRow: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                .frame(
                    width: HomeInlineTaskLayoutMetrics.checkboxSize,
                    height: 32
                )

            TextField("添加子任务", text: $newSubtaskTitle)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .focused($focusedField, equals: .newSubtask)
                .submitLabel(.done)
                .onSubmit(addSubtaskAfterSnapshot)

            Button("添加", action: addSubtaskAfterSnapshot)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.vertical, -6)
                .buttonStyle(.plain)
                .accessibilityHint("提交当前输入的子任务")
        }
    }

    private func commitNotes() {
        guard isEditingNotes, isCommittingNotes == false else { return }
        isCommittingNotes = true
        notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
        focusedField = nil
        viewModel.updateDraftNotes(notesDraft)
        isEditingNotes = false
        isCommittingNotes = false
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
        viewModel.addDetailDraftSubtask(title: trimmed)
        newSubtaskTitle = ""
        showsSubtaskComposer = false
    }

    private func commitExistingSubtaskAfterSnapshot(_ id: UUID) {
        guard isCommittingSubtask == false else { return }
        isCommittingSubtask = true
        Task { @MainActor in
            activeSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: activeSubtaskTitle)
            focusedField = nil
            await Task.yield()
            commitExistingSubtask(id)
            isCommittingSubtask = false
        }
    }

    private func commitExistingSubtask(_ id: UUID) {
        guard activeSubtaskID == id else { return }
        let trimmed = activeSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        viewModel.updateDetailDraftSubtask(id, title: trimmed)
        activeSubtaskID = nil
        activeSubtaskTitle = ""
    }
}

struct HomeTaskAttributeFooter: View {
    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel
    let isExpanded: Bool

    @State private var schedulePresentation: ExistingTaskScheduleEditorPresentation?

    var body: some View {
        expandedControls
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .allowsHitTesting(isExpanded)
        .sheet(item: $schedulePresentation) { presentation in
            DateTimePickerSheet(
                presentation: presentation,
                selectionFeedback: HomeInteractionFeedback.selection,
                onChange: { draft in
                    viewModel.updateDraftSchedule(
                        date: draft.selectedDate,
                        time: draft.selectedTime,
                        reminderOffset: draft.reminderOffset
                    )
                }
            )
        }
    }

    private var expandedControls: some View {
        TaskAttributeToolbarRail {
            attributeButton(
                title: dateTitle,
                systemImage: "calendar",
                isConfigured: viewModel.inlineDetailDraft?.dueAt != nil
            ) {
                openSchedule()
            }
            attributeButton(
                title: timeTitle,
                systemImage: "clock",
                isConfigured: viewModel.inlineDetailDraft?.hasExplicitTime == true
            ) {
                openSchedule()
            }

            attributeButton(
                title: reminderTitle,
                systemImage: "bell",
                isConfigured: viewModel.inlineDetailDraft?.remindAt != nil
            ) {
                openSchedule()
            }

            Button {
                HomeInteractionFeedback.selection()
                viewModel.updateDraftUrgent(!(viewModel.inlineDetailDraft?.isUrgent ?? false))
            } label: {
                TaskAttributeLabel(
                    icon: viewModel.inlineDetailDraft?.isUrgent == true ? "flag.fill" : "flag",
                    title: "",
                    isConfigured: viewModel.inlineDetailDraft?.isUrgent == true,
                    tint: viewModel.inlineDetailDraft?.isUrgent == true ? AppTheme.colors.coral : nil,
                    isCircular: true,
                    alignsToCardCorner: true,
                    isFocusForeground: true
                )
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .accessibilityLabel("紧急")
            .accessibilityValue(viewModel.inlineDetailDraft?.isUrgent == true ? "已开启" : "已关闭")

            if canShowFollowButton {
                Button {
                    HomeInteractionFeedback.selection()
                    Task { await viewModel.toggleTaskFollow(entry.itemID) }
                } label: {
                    TaskAttributeLabel(
                        icon: "scope",
                        title: "",
                        isConfigured: isFollowed,
                        tint: isFollowed ? AppTheme.colors.violet : nil,
                        isCircular: true,
                        alignsToCardCorner: true,
                        isFocusForeground: true
                    )
                }
                .buttonStyle(TaskMorphAttributeButtonStyle())
                .disabled(viewModel.isUpdatingTaskFollow(entry.itemID))
                .accessibilityLabel(isFollowed ? "已关注" : "关注任务")
                .accessibilityValue(isFollowed ? "已开启" : "已关闭")
                .accessibilityHint(isFollowed ? "轻点取消关注" : "轻点在实时活动中关注此任务")
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, HomeInlineTaskLayoutMetrics.expandedAttributeLeadingInset)
    }

    private var isFollowed: Bool {
        viewModel.item(for: entry.itemID)?.isFollowed == true
    }

    private var canShowFollowButton: Bool {
        guard let item = viewModel.item(for: entry.itemID) else { return false }
        return item.repeatRule == nil && item.status != .completed && item.completedAt == nil
    }

    private func attributeButton(
        title: String,
        systemImage: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            action()
        } label: {
            TaskAttributeLabel(
                icon: systemImage,
                title: title,
                isConfigured: isConfigured,
                usesContinuousCapsule: true,
                alignsToCardCorner: true,
                horizontalPadding: 8,
                isFocusForeground: true
            )
        }
        .buttonStyle(TaskMorphAttributeButtonStyle())
    }

    private var dateTitle: String {
        guard let date = viewModel.inlineDetailDraft?.dueAt else { return "日期" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        return date.formatted(.dateTime.month().day())
    }

    private var timeTitle: String {
        guard viewModel.inlineDetailDraft?.hasExplicitTime == true,
              let date = viewModel.inlineDetailDraft?.dueAt
        else { return "时间" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let draft = viewModel.inlineDetailDraft,
              let remindAt = draft.remindAt
        else { return "提醒" }
        return TaskSharedAttributeText.reminderLead(
            dueAt: draft.dueAt,
            hasExplicitTime: draft.hasExplicitTime,
            remindAt: remindAt,
            calendar: .current
        )
    }

    private func openSchedule() {
        let draft = viewModel.inlineDetailDraft
        schedulePresentation = ExistingTaskScheduleEditorPresentation(
            dueAt: draft?.dueAt,
            hasExplicitTime: draft?.hasExplicitTime ?? false,
            remindAt: draft?.remindAt,
            fallbackDate: viewModel.selectedDate
        )
    }

}

struct HomeTaskCompactSummary: View {
    let entry: HomeTimelineEntry
    let progress: CGFloat
    let opacity: CGFloat

    private var content: TaskSharedIdentityContent {
        TaskSharedIdentityContent.make(entry: entry)
    }

    private var hasContent: Bool {
        content.visibleElements.isDisjoint(with: [.progress, .time, .reminder]) == false
    }

    var body: some View {
        TaskSharedAttributeBand(
            content: content,
            elements: [.time, .reminder, .progress]
        )
        .allowsHitTesting(false)
        .opacity(opacity)
        .frame(height: hasContent ? 20 * progress : 0, alignment: .top)
        .padding(.top, hasContent ? AppTheme.spacing.xs * progress : 0)
        .clipped()
        .accessibilityHidden(progress < 0.999)
    }
}

struct SubtaskCompletionMark: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isCompleted ? Color.clear : AppTheme.colors.body.opacity(0.34),
                    lineWidth: 1.1
                )

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isCompleted)
            }
        }
    }
}
