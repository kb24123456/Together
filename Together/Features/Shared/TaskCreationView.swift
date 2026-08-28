import SwiftUI

enum TaskCreationDestination: Equatable, Identifiable {
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

enum TaskCreationTransitionSource: Hashable {
    case addButton
}

struct TaskCreationView: View {
    let destination: TaskCreationDestination
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let onCancel: () -> Void
    let onCreated: (TaskMorphDomain, UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: FocusedField?
    @State private var title: String
    @State private var notes: String
    @State private var newSubtaskTitle = ""
    @State private var editingSubtaskID: UUID?
    @State private var editingSubtaskTitle = ""
    @State private var schedulePresentation: ExistingTaskScheduleEditorPresentation?
    @State private var pendingTodoScheduleDraft: ExistingTaskScheduleDraft?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private enum FocusedField: Hashable {
        case title
        case notes
        case newSubtask
        case existingSubtask(UUID)
    }

    init(
        destination: TaskCreationDestination,
        homeViewModel: HomeViewModel,
        routinesViewModel: RoutinesViewModel,
        onCancel: @escaping () -> Void,
        onCreated: @escaping (TaskMorphDomain, UUID) -> Void
    ) {
        self.destination = destination
        self.homeViewModel = homeViewModel
        self.routinesViewModel = routinesViewModel
        self.onCancel = onCancel
        self.onCreated = onCreated

        switch destination {
        case .todo:
            _title = State(initialValue: homeViewModel.taskCreationSession?.draft.title ?? "")
            _notes = State(initialValue: homeViewModel.taskCreationSession?.draft.notes ?? "")
        case .periodic:
            _title = State(initialValue: routinesViewModel.creationSession?.draft.title ?? "")
            _notes = State(initialValue: routinesViewModel.creationSession?.draft.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                    identitySection

                    switch destination {
                    case .todo:
                        todoDetails
                    case .periodic:
                        EmptyView()
                    }

                    if let visibleErrorMessage {
                        Label(visibleErrorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(AppTheme.typography.scaled(13, weight: .medium, relativeTo: .footnote))
                            .foregroundStyle(AppTheme.colors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.sm)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                creationAttributeBar
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.top, AppTheme.spacing.xs)
                    .padding(.bottom, AppTheme.spacing.sm)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .background(AppTheme.colors.background.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                        .disabled(isSaving)
                        .accessibilityHint("放弃当前未保存的草稿")
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在添加任务")
                    } else {
                        Button("添加", systemImage: "checkmark") {
                            Task { await save() }
                        }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .disabled(isTitleEmpty)
                        .accessibilityHint(isTitleEmpty ? "请先输入任务标题" : "保存任务并返回列表")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(item: $schedulePresentation, onDismiss: applyPendingTodoSchedule) { presentation in
            DateTimePickerSheet(
                presentation: presentation,
                selectionFeedback: HomeInteractionFeedback.selection,
                onChange: { draft in
                    pendingTodoScheduleDraft = draft
                }
            )
        }
        .task {
            await Task.yield()
            guard isSaving == false else { return }
            focusedField = .title
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard case .existingSubtask(let id) = oldValue,
                  newValue != oldValue
            else { return }
            commitExistingSubtask(id)
        }
        .accessibilityAction(.escape) {
            cancel()
        }
    }

    private var navigationTitle: String {
        switch destination {
        case .todo:
            "新建待办"
        case .periodic:
            "新建定期任务"
        }
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleErrorMessage: String? {
        errorMessage ?? {
            switch destination {
            case .todo:
                homeViewModel.taskCreationSession?.errorMessage
            case .periodic:
                routinesViewModel.creationSession?.errorMessage
            }
        }()
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            TextField("任务标题", text: $title, axis: .vertical)
                .font(AppTheme.typography.scaled(22, weight: .bold, relativeTo: .title2))
                .foregroundStyle(colorScheme == .light ? AppTheme.colors.taskFocusTitle : AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 1...8 : 1...3)
                .focused($focusedField, equals: .title)
                .onChange(of: title) { _, value in
                    updateTitle(value)
                    errorMessage = nil
                }
                .onSubmit {
                    Task { await save() }
                }
                .accessibilityIdentifier("together.task-creation.title")

            TextField("添加备注", text: $notes, axis: .vertical)
                .font(AppTheme.typography.scaled(15, weight: .regular, relativeTo: .body))
                .foregroundStyle(colorScheme == .light ? AppTheme.colors.taskFocusBody : AppTheme.colors.body)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...6)
                .focused($focusedField, equals: .notes)
                .onChange(of: notes) { _, value in
                    updateNotes(value)
                    errorMessage = nil
                }
                .accessibilityIdentifier("together.task-creation.notes")
        }
        .padding(.vertical, AppTheme.spacing.xs)
    }

    private var todoDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Text("子任务")
                .font(AppTheme.typography.scaled(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(AppTheme.colors.bodySecondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(todoSubtasks, id: \.id) { subtask in
                    todoSubtaskRow(subtask)
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
    }

    @ViewBuilder
    private var creationAttributeBar: some View {
        switch destination {
        case .todo:
            todoAttributeToolbar
        case .periodic:
            periodicAttributeToolbar
        }
    }

    private var todoSubtasks: [TaskSubtaskDraft] {
        homeViewModel.taskCreationSession?.draft.subtasks ?? []
    }

    private var todoAttributeToolbar: some View {
        TaskAttributeToolbarRail {
            creationAttributeButton(
                title: todoDateTitle,
                systemImage: "calendar",
                isConfigured: homeViewModel.taskCreationSession?.draft.dueAt != nil
            ) {
                openSchedule()
            }

            creationAttributeButton(
                title: todoTimeTitle,
                systemImage: "clock",
                isConfigured: homeViewModel.taskCreationSession?.draft.hasExplicitTime == true
            ) {
                openSchedule()
            }

            creationAttributeButton(
                title: todoReminderTitle,
                systemImage: "bell",
                isConfigured: homeViewModel.taskCreationSession?.draft.remindAt != nil
            ) {
                openSchedule()
            }

            Button {
                HomeInteractionFeedback.selection()
                let isUrgent = homeViewModel.taskCreationSession?.draft.isUrgent ?? false
                homeViewModel.updateTaskCreationDraft { $0.isUrgent = isUrgent == false }
            } label: {
                let isUrgent = homeViewModel.taskCreationSession?.draft.isUrgent == true
                TaskAttributeLabel(
                    icon: isUrgent ? "flag.fill" : "flag",
                    title: "",
                    isConfigured: isUrgent,
                    tint: isUrgent ? AppTheme.colors.coral : nil,
                    isCircular: true,
                    isFocusForeground: true,
                    usesLightweightBackground: true
                )
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .accessibilityLabel("紧急")
            .accessibilityValue(homeViewModel.taskCreationSession?.draft.isUrgent == true ? "已开启" : "已关闭")

            Button {
                HomeInteractionFeedback.selection()
                let isFollowed = homeViewModel.taskCreationSession?.draft.shouldFollowOnCreation ?? false
                homeViewModel.updateTaskCreationDraft { $0.shouldFollowOnCreation = isFollowed == false }
            } label: {
                let isFollowed = homeViewModel.taskCreationSession?.draft.shouldFollowOnCreation == true
                TaskAttributeLabel(
                    icon: "scope",
                    title: "",
                    isConfigured: isFollowed,
                    tint: isFollowed ? AppTheme.colors.sky : nil,
                    isCircular: true,
                    isFocusForeground: true,
                    usesLightweightBackground: true
                )
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .accessibilityLabel(homeViewModel.taskCreationSession?.draft.shouldFollowOnCreation == true ? "已关注" : "关注任务")
            .accessibilityValue(homeViewModel.taskCreationSession?.draft.shouldFollowOnCreation == true ? "已开启" : "已关闭")
            .accessibilityHint(
                homeViewModel.taskCreationSession?.draft.shouldFollowOnCreation == true
                    ? "轻点取消关注"
                    : "轻点创建任务后在实时活动中关注"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func creationAttributeButton(
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
                horizontalPadding: 8,
                isFocusForeground: true,
                usesLightweightBackground: true,
                animatesTitleChanges: true
            )
        }
        .buttonStyle(TaskMorphAttributeButtonStyle())
    }

    private func todoSubtaskRow(_ subtask: TaskSubtaskDraft) -> some View {
        HStack(spacing: 2) {
            Button {
                subtask.isCompleted ? HomeInteractionFeedback.selection() : HomeInteractionFeedback.completion()
                homeViewModel.toggleDetailDraftSubtask(subtask.id)
            } label: {
                SubtaskCompletionMark(isCompleted: subtask.isCompleted)
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "恢复子任务" : "完成子任务")

            if editingSubtaskID == subtask.id {
                TextField("子任务标题", text: $editingSubtaskTitle)
                    .font(AppTheme.typography.scaled(16, weight: .medium, relativeTo: .body))
                    .focused($focusedField, equals: .existingSubtask(subtask.id))
                    .submitLabel(.done)
                    .onSubmit { commitExistingSubtaskAfterSnapshot(subtask.id) }

                Button("确认") {
                    commitExistingSubtaskAfterSnapshot(subtask.id)
                }
                .font(AppTheme.typography.scaled(13, weight: .semibold, relativeTo: .footnote))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    HomeInteractionFeedback.delete()
                    homeViewModel.deleteDetailDraftSubtask(subtask.id)
                    editingSubtaskID = nil
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
                        .foregroundStyle(colorScheme == .light ? AppTheme.colors.taskFocusBody : AppTheme.colors.body)
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
        let canAddSubtask = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        return HStack(spacing: 2) {
            Image(systemName: "plus")
                .font(AppTheme.typography.scaled(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(AppTheme.colors.bodySecondary)
                .frame(width: 44, height: 44)

            TextField("添加子任务", text: $newSubtaskTitle)
                .font(AppTheme.typography.scaled(16, weight: .medium, relativeTo: .body))
                .focused($focusedField, equals: .newSubtask)
                .submitLabel(.done)
                .onSubmit(addSubtaskAfterSnapshot)

            Button("添加", action: addSubtaskAfterSnapshot)
                .font(AppTheme.typography.scaled(13, weight: .semibold, relativeTo: .footnote))
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .opacity(canAddSubtask ? 1 : 0)
                .disabled(canAddSubtask == false)
                .accessibilityHidden(canAddSubtask == false)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.14),
                    value: canAddSubtask
                )
        }
    }

    private var periodicAttributeToolbar: some View {
        TaskAttributeAdaptiveRail {
            periodicAttributeControls
        }
    }

    @ViewBuilder
    private var periodicAttributeControls: some View {
        periodicCycleMenu
        periodicTargetDayControl
        InlineTimePickerControl(
            selection: periodicRule?.hasTargetTime == true ? periodicTimeDate : nil,
            fallbackSelection: .now,
            fillsAvailableWidth: false,
            onCommit: { value in
                if let value {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                    if let hour = components.hour, let minute = components.minute {
                        routinesViewModel.updateDraftTargetTime(hour: hour, minute: minute)
                    }
                } else {
                    routinesViewModel.clearDraftTargetTime()
                }
            }
        )
        periodicReminderMenu
    }

    private var periodicCycleMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                Button {
                    routinesViewModel.updateDraftCycle(cycle)
                } label: {
                    if periodicCycle == cycle {
                        Label(cycle.title, systemImage: "checkmark")
                    } else {
                        Text(cycle.title)
                    }
                }
            }
        } label: {
            periodicSettingLabel(
                icon: "arrow.triangle.2.circlepath",
                title: periodicCycle.title,
                isConfigured: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("定期任务维度，当前为\(periodicCycle.title)")
    }

    @ViewBuilder
    private var periodicTargetDayControl: some View {
        if periodicCycle == .daily {
            periodicSettingLabel(icon: "calendar", title: "每天", isConfigured: true)
        } else {
            Menu {
                periodicTargetDayOptions
                if periodicRule?.hasTargetDay == true {
                    Divider()
                    Button("清除目标日", role: .destructive) {
                        routinesViewModel.clearDraftTargetDay()
                    }
                }
            } label: {
                periodicSettingLabel(
                    icon: "calendar",
                    title: periodicTargetDayTitle,
                    isConfigured: periodicRule?.hasTargetDay == true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("目标日期，当前为\(periodicTargetDayTitle)")
        }
    }

    @ViewBuilder
    private var periodicTargetDayOptions: some View {
        switch periodicCycle {
        case .daily:
            periodicTargetDayOption("每天", timing: .dayOfPeriod(1))
        case .weekly:
            ForEach(1...7, id: \.self) { day in
                periodicTargetDayOption(
                    RoutineTargetText.weekdayText(for: day),
                    timing: .dayOfPeriod(day)
                )
            }
        case .monthly:
            ForEach([1, 5, 10, 15, 20, 25, 31], id: \.self) { day in
                periodicTargetDayOption(
                    day == 31 ? "最后一天" : "\(day) 号",
                    timing: .dayOfPeriod(day)
                )
            }
        case .quarterly:
            periodicTargetDayOption("第 1 天", timing: .dayOfPeriod(1))
            periodicTargetDayOption("第 30 天", timing: .dayOfPeriod(30))
            periodicTargetDayOption("结束前 14 天", timing: .daysBeforeEnd(14))
        case .yearly:
            periodicTargetDayOption("第 1 天", timing: .dayOfPeriod(1))
            periodicTargetDayOption("第 180 天", timing: .dayOfPeriod(180))
            periodicTargetDayOption("结束前 30 天", timing: .daysBeforeEnd(30))
        }
    }

    private func periodicTargetDayOption(
        _ title: String,
        timing: PeriodicReminderRule.Timing
    ) -> some View {
        Button {
            routinesViewModel.updateDraftTargetDay(timing)
        } label: {
            if periodicRule?.timing == timing {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var periodicReminderMenu: some View {
        Menu {
            Button {
                routinesViewModel.updateDraftReminder(leadMinutes: nil)
            } label: {
                if periodicRule?.hasReminder == true {
                    Text("关闭提醒")
                } else {
                    Label("关闭提醒", systemImage: "checkmark")
                }
            }

            Divider()
            periodicReminderOption("准时", minutes: 0)
            periodicReminderOption("提前 5 分钟", minutes: 5)
            periodicReminderOption("提前 15 分钟", minutes: 15)
            periodicReminderOption("提前 30 分钟", minutes: 30)
            periodicReminderOption("提前 1 小时", minutes: 60)
            periodicReminderOption("提前 1 天", minutes: 1_440)

        } label: {
            periodicSettingLabel(
                icon: "bell",
                title: periodicReminderTitle,
                isConfigured: periodicRule?.hasReminder == true
            )
        }
        .buttonStyle(.plain)
        .disabled(periodicRule?.hasCompleteTarget(for: periodicCycle) != true)
        .accessibilityLabel("定期任务提醒，当前为\(periodicReminderTitle)")
    }

    private func periodicReminderOption(_ title: String, minutes: Int) -> some View {
        Button {
            routinesViewModel.updateDraftReminder(leadMinutes: minutes)
        } label: {
            if periodicRule?.reminderLeadMinutes == minutes {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func periodicSettingLabel(
        icon: String,
        title: String,
        isConfigured: Bool
    ) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured,
            usesContinuousCapsule: true,
            horizontalPadding: 8,
            isFocusForeground: true,
            fillsAvailableWidth: false,
            usesLightweightBackground: true
        )
    }

    private var periodicCycle: PeriodicCycle {
        routinesViewModel.creationSession?.draft.cycle ?? routinesViewModel.selectedCycle
    }

    private var periodicRule: PeriodicReminderRule? {
        routinesViewModel.creationSession?.draft.reminderRules.first
    }

    private var periodicTimeDate: Date {
        Calendar.current.date(
            from: DateComponents(hour: periodicRule?.hour, minute: periodicRule?.minute)
        ) ?? .now
    }

    private var periodicTargetDayTitle: String {
        guard let timing = periodicRule?.timing else { return "目标日" }
        switch periodicCycle {
        case .daily:
            return "每天"
        case .weekly:
            if case .dayOfPeriod(let day) = timing {
                return RoutineTargetText.weekdayText(for: day)
            }
            return "目标日"
        case .monthly:
            switch timing {
            case .dayOfPeriod(let day) where day >= 31: return "最后一天"
            case .dayOfPeriod(let day): return "\(day)号"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(1): return "最后一天"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            case .weekdayOfMonth(let ordinal, let weekday):
                return "\(ordinal.title)\(RoutineTargetText.absoluteWeekdayText(for: weekday))"
            case .lastBusinessDay: return "最后工作日"
            }
        case .quarterly, .yearly:
            switch timing {
            case .dayOfPeriod(let day): return "第\(day)天"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(1): return "最后一天"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            case .lastBusinessDay: return "最后工作日"
            case .weekdayOfMonth: return "目标日"
            }
        }
    }

    private var periodicReminderTitle: String {
        guard let rule = periodicRule, rule.hasReminder else { return "提醒" }
        switch rule.reminderLeadMinutes {
        case 0: return "准时"
        case 5: return "提前5分"
        case 15: return "提前15分"
        case 30: return "提前30分"
        case 60: return "提前1时"
        case 1_440: return "提前1天"
        default: return "提醒"
        }
    }

    private var todoDateTitle: String {
        guard let date = homeViewModel.taskCreationSession?.draft.dueAt else { return "日期" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        return date.formatted(.dateTime.month().day())
    }

    private var todoTimeTitle: String {
        guard homeViewModel.taskCreationSession?.draft.hasExplicitTime == true,
              let date = homeViewModel.taskCreationSession?.draft.dueAt
        else { return "时间" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var todoReminderTitle: String {
        guard let draft = homeViewModel.taskCreationSession?.draft,
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
        let draft = homeViewModel.taskCreationSession?.draft
        pendingTodoScheduleDraft = nil
        schedulePresentation = ExistingTaskScheduleEditorPresentation(
            dueAt: draft?.dueAt,
            hasExplicitTime: draft?.hasExplicitTime ?? false,
            remindAt: draft?.remindAt,
            fallbackDate: homeViewModel.selectedDate
        )
    }

    private func applyPendingTodoSchedule() {
        guard let draft = pendingTodoScheduleDraft else { return }
        pendingTodoScheduleDraft = nil

        let update = {
            homeViewModel.updateTaskCreationSchedule(
                date: draft.selectedDate,
                time: draft.selectedTime,
                reminderOffset: draft.reminderOffset
            )
        }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.16), update)
        } else {
            withAnimation(.smooth(duration: 0.26, extraBounce: 0), update)
        }
    }

    private func updateTitle(_ value: String) {
        switch destination {
        case .todo:
            homeViewModel.updateTaskCreationDraft { $0.title = value }
        case .periodic:
            routinesViewModel.updateCreationDraft { $0.title = value }
        }
    }

    private func updateNotes(_ value: String) {
        switch destination {
        case .todo:
            homeViewModel.updateTaskCreationDraft {
                $0.notes = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
        case .periodic:
            routinesViewModel.updateCreationDraft {
                $0.notes = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
        }
    }

    private func addSubtaskAfterSnapshot() {
        newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            focusedField = .newSubtask
            return
        }
        if reduceMotion {
            homeViewModel.addDetailDraftSubtask(title: trimmed)
            newSubtaskTitle = ""
        } else {
            withAnimation(.smooth(duration: 0.30, extraBounce: 0)) {
                homeViewModel.addDetailDraftSubtask(title: trimmed)
                newSubtaskTitle = ""
            }
        }
        HomeInteractionFeedback.selection()
        focusedField = .newSubtask
    }

    private func commitExistingSubtaskAfterSnapshot(_ id: UUID) {
        editingSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: editingSubtaskTitle)
        focusedField = nil
        commitExistingSubtask(id)
    }

    private func commitExistingSubtask(_ id: UUID) {
        guard editingSubtaskID == id else { return }
        let trimmed = editingSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            homeViewModel.updateDetailDraftSubtask(id, title: trimmed)
        }
        editingSubtaskID = nil
        editingSubtaskTitle = ""
    }

    private func flushFocusedInput() {
        switch focusedField {
        case .title:
            title = TextInputSnapshotReader.resolvedText(fallback: title)
            updateTitle(title)
        case .notes:
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            updateNotes(notes)
        case .newSubtask:
            newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
            let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                homeViewModel.addDetailDraftSubtask(title: trimmed)
                newSubtaskTitle = ""
            }
        case .existingSubtask(let id):
            editingSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: editingSubtaskTitle)
            commitExistingSubtask(id)
        case nil:
            break
        }
        focusedField = nil
    }

    @MainActor
    private func save() async {
        guard isSaving == false else { return }
        flushFocusedInput()
        await Task.yield()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            errorMessage = "请输入任务标题。"
            HomeInteractionFeedback.validation()
            focusedField = .title
            return
        }

        title = trimmedTitle
        updateTitle(trimmedTitle)
        isSaving = true
        errorMessage = nil

        let result: TaskCreationPersistenceResult = switch destination {
        case .todo:
            await homeViewModel.commitTaskCreation()
        case .periodic:
            await routinesViewModel.commitTaskCreation()
        }

        switch result {
        case .failed(let message):
            errorMessage = message
            isSaving = false
            HomeInteractionFeedback.validation()
        case .saved(let id):
            HomeInteractionFeedback.completion()
            switch destination {
            case .todo:
                homeViewModel.finalizeCommittedTaskCreation()
            case .periodic:
                routinesViewModel.finalizeTaskCreation()
            }
            onCreated(destination.domain, id)
        }
    }

    private func cancel() {
        guard isSaving == false else { return }
        focusedField = nil
        switch destination {
        case .todo:
            homeViewModel.discardTaskCreation()
        case .periodic:
            routinesViewModel.discardTaskCreation()
        }
        onCancel()
    }
}
