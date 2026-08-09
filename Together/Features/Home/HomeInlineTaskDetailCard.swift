import SwiftUI

struct HomeInlineTaskDetailCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel
    let isExpanded: Bool
    let showsAddNote: Bool
    let onAddNote: () -> Void

    @State private var newSubtaskTitle = ""
    @State private var activeSubtaskID: UUID?
    @State private var activeSubtaskTitle = ""
    @State private var showsSubtaskComposer = false
    @State private var isCommittingSubtask = false
    @State private var revealStep = 0
    @State private var revealTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case existingSubtask(UUID)
        case newSubtask
    }

    var body: some View {
        let subtasks = viewModel.inlineDetailDraft?.subtasks ?? []
        let firstSubtaskStep = showsAddNote ? 2 : 1

        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            if showsAddNote {
                disclosureButton(title: "添加备注", systemImage: "plus", action: onAddNote)
                    .opacity(revealStep >= 1 ? 1 : 0)
            }

            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                subtaskRow(subtask)
                    .opacity(revealStep >= firstSubtaskStep + index ? 1 : 0)
            }

            if showsSubtaskComposer {
                newSubtaskRow
                    .opacity(revealStep >= finalRevealStep(subtaskCount: subtasks.count) ? 1 : 0)
            } else {
                disclosureButton(title: "添加子任务", systemImage: "plus") {
                    showsSubtaskComposer = true
                    Task { @MainActor in
                        await Task.yield()
                        focusedField = .newSubtask
                    }
                }
                .opacity(revealStep >= finalRevealStep(subtaskCount: subtasks.count) ? 1 : 0)
            }
        }
        .padding(.top, AppTheme.spacing.xxs)
        .onChange(of: focusedField) { oldValue, newValue in
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
        .onAppear {
            updateRevealState(isExpanded, subtaskCount: subtasks.count)
        }
        .onChange(of: isExpanded) { _, expanded in
            updateRevealState(expanded, subtaskCount: subtasks.count)
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func disclosureButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Image(systemName: systemImage)
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

    private func subtaskRow(_ subtask: TaskSubtaskDraft) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Button {
                viewModel.toggleDetailDraftSubtask(subtask.id)
            } label: {
                SubtaskCompletionMark(isCompleted: subtask.isCompleted)
                    .frame(width: 20, height: 20)
                    .frame(width: 40, height: 44, alignment: .center)
            }
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
                .frame(minWidth: 44, minHeight: 36)
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    viewModel.deleteDetailDraftSubtask(subtask.id)
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

            Button("添加", action: addSubtaskAfterSnapshot)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(minWidth: 44, minHeight: 36)
                .buttonStyle(.plain)
                .accessibilityHint("提交当前输入的子任务")
        }
    }

    private func finalRevealStep(subtaskCount: Int) -> Int {
        (showsAddNote ? 2 : 1) + subtaskCount
    }

    private func updateRevealState(_ expanded: Bool, subtaskCount: Int) {
        revealTask?.cancel()
        let finalStep = finalRevealStep(subtaskCount: subtaskCount)

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) {
                revealStep = expanded ? finalStep : 0
            }
            return
        }

        revealTask = Task { @MainActor in
            if expanded {
                revealStep = 0
                for step in 1...max(1, finalStep) {
                    guard Task.isCancelled == false else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        revealStep = step
                    }
                    try? await Task.sleep(for: .milliseconds(24))
                }
            } else {
                for step in stride(from: revealStep, through: 0, by: -1) {
                    guard Task.isCancelled == false else { return }
                    withAnimation(.easeIn(duration: 0.09)) {
                        revealStep = step
                    }
                    try? await Task.sleep(for: .milliseconds(18))
                }
            }
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
    @State private var controlsVisible = false
    @State private var revealTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        expandedControls
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.top, AppTheme.spacing.xs)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(isExpanded && controlsVisible)
            .onAppear { updateControlsVisibility(isExpanded) }
            .onChange(of: isExpanded) { _, expanded in
                updateControlsVisibility(expanded)
            }
            .onDisappear {
                revealTask?.cancel()
                revealTask = nil
            }
        .sheet(item: $schedulePresentation) { presentation in
            ExistingTaskDateTimeEditorSheet(
                presentation: presentation,
                selectionFeedback: HomeInteractionFeedback.selection,
                onChange: { draft in
                    viewModel.updateDraftSchedule(date: draft.selectedDate, time: draft.selectedTime)
                }
            )
        }
    }

    private var expandedControls: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            attributeButton(title: dateTitle, systemImage: "calendar") {
                openSchedule(.date)
            }
            attributeButton(title: timeTitle, systemImage: "clock") {
                openSchedule(.time)
            }

            Menu {
                Button("不提醒") {
                    HomeInteractionFeedback.selection()
                    viewModel.setDraftReminderEnabled(false)
                }
                if viewModel.inlineDetailDraft?.hasExplicitTime == true,
                   let dueAt = viewModel.inlineDetailDraft?.dueAt {
                    ForEach(TaskEditorReminderPreset.allCases) { preset in
                        Button(preset.title) {
                            HomeInteractionFeedback.selection()
                            viewModel.updateDraftReminder(dueAt.addingTimeInterval(-preset.secondsBeforeTarget))
                        }
                    }
                } else {
                    Button("先设置时间") {
                        openSchedule(.time)
                    }
                }
            } label: {
                HomeMorphAttributeLabel(
                    icon: "bell",
                    title: reminderTitle,
                    isConfigured: viewModel.inlineDetailDraft?.remindAt != nil
                )
            }
            .buttonStyle(HomeMorphAttributeButtonStyle())

            Button {
                HomeInteractionFeedback.selection()
                viewModel.updateDraftUrgent(!(viewModel.inlineDetailDraft?.isUrgent ?? false))
            } label: {
                HomeMorphAttributeLabel(
                    icon: viewModel.inlineDetailDraft?.isUrgent == true ? "flag.fill" : "flag",
                    title: "",
                    isConfigured: viewModel.inlineDetailDraft?.isUrgent == true,
                    tint: viewModel.inlineDetailDraft?.isUrgent == true ? AppTheme.colors.coral : nil,
                    isCircular: true
                )
            }
            .buttonStyle(HomeMorphAttributeButtonStyle())
            .accessibilityLabel("紧急")
            .accessibilityValue(viewModel.inlineDetailDraft?.isUrgent == true ? "已开启" : "已关闭")

            Spacer(minLength: 0)
        }
    }

    private func attributeButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            action()
        } label: {
            HomeMorphAttributeLabel(
                icon: systemImage,
                title: title,
                isConfigured: title != "日期" && title != "时间"
            )
        }
        .buttonStyle(HomeMorphAttributeButtonStyle())
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

    private func openSchedule(_ section: ExistingTaskScheduleEditorSection) {
        let draft = viewModel.inlineDetailDraft
        schedulePresentation = ExistingTaskScheduleEditorPresentation(
            initialSection: section,
            dueAt: draft?.dueAt,
            hasExplicitTime: draft?.hasExplicitTime ?? false,
            fallbackDate: viewModel.selectedDate
        )
    }

    private func updateControlsVisibility(_ expanded: Bool) {
        revealTask?.cancel()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) {
                controlsVisible = expanded
            }
            return
        }

        revealTask = Task { @MainActor in
            if expanded {
                let subtaskCount = viewModel.inlineDetailDraft?.subtasks.count ?? entry.subtasks.count
                try? await Task.sleep(for: .milliseconds(90 + 24 * (subtaskCount + 2)))
                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    controlsVisible = true
                }
            } else {
                withAnimation(.easeIn(duration: 0.09)) {
                    controlsVisible = false
                }
            }
        }
    }
}

struct HomeTaskCompactSummary: View {
    let entry: HomeTimelineEntry
    let isExpanded: Bool

    private var content: TaskSharedIdentityContent {
        TaskSharedIdentityContent.make(entry: entry)
    }

    private var hasContent: Bool {
        content.visibleElements.isDisjoint(with: [.progress, .time, .reminder]) == false
    }

    var body: some View {
        TaskSharedAttributeBand(
            content: content,
            elements: [.progress, .time, .reminder]
        )
        .allowsHitTesting(false)
        .opacity(isExpanded ? 0 : 1)
        .frame(height: isExpanded || hasContent == false ? 0 : 20, alignment: .top)
        .padding(.top, isExpanded || hasContent == false ? 0 : AppTheme.spacing.xs)
        .clipped()
        .animation(.easeOut(duration: 0.09), value: isExpanded)
    }
}

struct HomeMorphAttributeLabel: View {
    let icon: String
    let title: String
    let isConfigured: Bool
    var tint: Color? = nil
    var isCircular = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .frame(width: 16)

            if title.isEmpty == false {
                Text(title)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .foregroundStyle(
            tint ?? (isConfigured
                ? AppTheme.colors.title.opacity(0.76)
                : AppTheme.colors.body.opacity(0.52))
        )
        .padding(.horizontal, isCircular ? 0 : 11)
        .frame(width: isCircular ? 34 : nil, height: 34)
        .background(
            AppTheme.colors.surfaceElevated,
            in: isCircular
                ? AnyShape(Circle())
                : AnyShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        )
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct HomeMorphAttributeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.smooth(duration: 0.14, extraBounce: 0), value: configuration.isPressed)
    }
}

struct SubtaskCompletionMark: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isCompleted ? Color.clear : AppTheme.colors.body.opacity(0.42),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3.2, 4])
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
