import Combine
import SwiftUI
import UIKit

struct OCRReviewSheet: View {
    let session: OCRReviewSession
    let appContext: AppContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDetent: PresentationDetent
    @State private var activeDraftMenu: OCRReviewDraftMenuSelection?
    @State private var showsDiscardConfirmation = false
    @State private var showsImportError = false
    @State private var isSubmitting = false

    init(session: OCRReviewSession, appContext: AppContext) {
        self.session = session
        self.appContext = appContext
        _selectedDetent = State(initialValue: session.initialDetent.presentationDetent)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ForEach(viewModel.draft.taskDrafts) { task in
                        OCRTaskDraftEditor(
                            task: taskBinding(for: task.id),
                            onOpenMenu: { menu in
                                activeDraftMenu = OCRReviewDraftMenuSelection(
                                    taskID: task.id,
                                    menu: menu
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.bottom, AppTheme.spacing.xl)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { contentHeight in
                    promoteDetentIfNeeded(
                        measuredContentHeight: contentHeight,
                        keyboardIsVisible: false
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("确认任务")
            .navigationSubtitle("识别到 \(viewModel.draft.taskDrafts.count) 条任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: requestCancel)
                        .disabled(isApplying)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyDraft()
                    } label: {
                        if isApplying {
                            ProgressView()
                        } else {
                            Text("导入")
                        }
                    }
                    .disabled(viewModel.canApply == false || isApplying)
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(true)
        .confirmationDialog(
            "放弃本次 OCR 草稿？",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃草稿", role: .destructive, action: discardAndDismiss)
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("已编辑的任务、备注和子任务不会保存。")
        }
        .alert("导入失败", isPresented: $showsImportError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "无法导入任务，请稍后重试。")
        }
        .sheet(item: $activeDraftMenu) { selection in
            OCRTaskAttributeMenuSheet(
                task: taskBinding(for: selection.taskID),
                activeMenu: activeDraftMenuBinding,
                quickTimePresetMinutes: quickTimePresetMinutes,
                onDismiss: {
                    activeDraftMenu = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            promoteDetentIfNeeded(
                measuredContentHeight: 0,
                keyboardIsVisible: true
            )
        }
    }

    private var viewModel: OCRImportViewModel {
        session.viewModel
    }

    private var isApplying: Bool {
        isSubmitting || viewModel.draft.status == .applying
    }

    private var quickTimePresetMinutes: [Int] {
        NotificationSettings.normalizedQuickTimePresetMinutes(
            appContext.sessionStore.currentUser?.preferences.quickTimePresetMinutes
            ?? NotificationSettings.defaultQuickTimePresetMinutes
        )
    }

    private var activeDraftMenuBinding: Binding<TaskEditorMenu> {
        Binding {
            activeDraftMenu?.menu ?? .date
        } set: { menu in
            activeDraftMenu?.menu = menu
        }
    }

    private func taskBinding(for id: UUID) -> Binding<OCRImportTaskDraft> {
        Binding {
            viewModel.draft.taskDrafts.first { $0.id == id } ?? OCRImportTaskDraft(title: "")
        } set: { updated in
            viewModel.updateTask(updated)
        }
    }

    private func promoteDetentIfNeeded(
        measuredContentHeight: CGFloat,
        keyboardIsVisible: Bool
    ) {
        let current = selectedDetent == .large
            ? OCRReviewSheetDetent.large
            : OCRReviewSheetDetent.medium
        let resolved = OCRReviewDetentPolicy.resolvedDetent(
            current: current,
            measuredContentHeight: measuredContentHeight,
            availableHeight: session.availableHeight,
            keyboardIsVisible: keyboardIsVisible
        )
        guard resolved == .large, selectedDetent != .large else { return }

        if reduceMotion {
            selectedDetent = .large
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedDetent = .large
            }
        }
    }

    private func requestCancel() {
        guard session.hasUserChanges else {
            discardAndDismiss()
            return
        }
        showsDiscardConfirmation = true
    }

    private func discardAndDismiss() {
        session.discard()
        dismiss()
    }

    private func applyDraft() {
        guard isApplying == false else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            if await viewModel.apply(to: appContext) {
                dismiss()
            } else {
                showsImportError = true
            }
        }
    }
}

private struct OCRReviewDraftMenuSelection: Identifiable, Hashable {
    let taskID: UUID
    var menu: TaskEditorMenu

    var id: UUID {
        taskID
    }
}

private extension OCRReviewSheetDetent {
    var presentationDetent: PresentationDetent {
        switch self {
        case .medium: .medium
        case .large: .large
        }
    }
}

struct OCRTaskDraftEditor: View {
    @Binding var task: OCRImportTaskDraft
    let onOpenMenu: (TaskEditorMenu) -> Void

    @State private var newSubtaskTitle = ""
    @FocusState private var isNewSubtaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HomeInlineTaskLayoutMetrics.detailVerticalSpacing) {
            titleRow
            notesEditor

            ForEach($task.subtasks) { $subtask in
                OCRSubtaskDraftRow(subtask: $subtask)
            }

            addSubtaskRow
            attributePills
        }
        .padding(.vertical, AppTheme.spacing.sm)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: HomeInlineTaskLayoutMetrics.titleGap) {
            Button {
                task.isSelected.toggle()
            } label: {
                OCRSelectionBox(isSelected: task.isSelected)
            }
            .buttonStyle(.plain)
            .frame(width: HomeInlineTaskLayoutMetrics.actionSlotWidth, height: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .trailing)

            TextField(
                "任务标题",
                text: $task.title
            )
            .font(AppTheme.typography.sized(19, weight: .bold))
            .foregroundStyle(AppTheme.colors.title)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
        }
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .leading)
    }

    private var notesEditor: some View {
        TextField(
            "添加备注...",
            text: Binding(
                get: { task.notes ?? "" },
                set: { task.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ),
            axis: .vertical
        )
        .font(AppTheme.typography.sized(16, weight: .medium))
        .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        .lineLimit(1...4)
        .textInputAutocapitalization(.sentences)
        .padding(.leading, HomeInlineTaskLayoutMetrics.titleLeadingInset)
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .leading)
    }

    private var addSubtaskRow: some View {
        HStack(alignment: .center, spacing: HomeInlineTaskLayoutMetrics.titleGap) {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(13, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(canAttemptAddSubtask ? 0.72 : 0.38))
                .frame(width: HomeInlineTaskLayoutMetrics.actionSlotWidth, height: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .trailing)

            TextField(
                "添加子任务",
                text: $newSubtaskTitle
            )
            .font(AppTheme.typography.sized(15, weight: .medium))
            .foregroundStyle(AppTheme.colors.title)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($isNewSubtaskFocused)
            .onSubmit {
                addSubtaskAfterFocusUpdate()
            }

            Button("添加") {
                addSubtaskAfterFocusUpdate()
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAttemptAddSubtask ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.34))
            .disabled(!canAttemptAddSubtask)
        }
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .leading)
    }

    private var attributePills: some View {
        HStack(spacing: HomeInlineTaskLayoutMetrics.attributeSpacing) {
            settingButton(title: dateTitle, systemImage: "calendar", menu: .date, isEnabled: true)
            settingButton(title: timeTitle, systemImage: "clock", menu: .time, isEnabled: true)
            settingButton(title: reminderTitle, systemImage: "bell", menu: .reminder, isEnabled: task.hasExplicitTime)
            settingButton(title: repeatTitle, systemImage: "arrow.triangle.2.circlepath", menu: .repeatRule, isEnabled: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingButton(title: String, systemImage: String, menu: TaskEditorMenu, isEnabled: Bool) -> some View {
        Button {
            onOpenMenu(menu)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(HomeInlineTaskLayoutMetrics.attributeIconSize, weight: .semibold))
                    .frame(width: HomeInlineTaskLayoutMetrics.attributeIconWidth)

                Text(title)
                    .font(AppTheme.typography.sized(HomeInlineTaskLayoutMetrics.attributeTextSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(AppTheme.colors.title.opacity(isEnabled ? 0.72 : 0.32))
            .padding(.horizontal, HomeInlineTaskLayoutMetrics.attributeHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.attributeMinHeight)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAttemptAddSubtask: Bool {
        canAddSubtask || isNewSubtaskFocused
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        task.subtasks.append(OCRImportSubtaskDraft(title: trimmed))
        newSubtaskTitle = ""
    }

    private func addSubtaskAfterFocusUpdate() {
        Task { @MainActor in
            newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
            isNewSubtaskFocused = false
            await Task.yield()
            addSubtask()
        }
    }

    private var dateTitle: String {
        guard let dueAt = task.dueAt else { return "日期" }
        return dueAt.formatted(.dateTime.month().day())
    }

    private var timeTitle: String {
        guard task.hasExplicitTime, let dueAt = task.dueAt else { return "时间" }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let dueAt = task.dueAt, let remindAt = task.remindAt else { return "提醒" }
        let offset = dueAt.timeIntervalSince(remindAt)
        return TaskEditorReminderPreset.preset(for: offset)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        task.repeatRule?.title(anchorDate: task.dueAt ?? .now, calendar: .current) ?? "重复"
    }
}

private struct OCRSubtaskDraftRow: View {
    @Binding var subtask: OCRImportSubtaskDraft

    var body: some View {
        HStack(alignment: .center, spacing: HomeInlineTaskLayoutMetrics.titleGap) {
            Button {
                subtask.isSelected.toggle()
            } label: {
                OCRSelectionBox(isSelected: subtask.isSelected)
                    .frame(width: HomeInlineTaskLayoutMetrics.checkboxSize, height: HomeInlineTaskLayoutMetrics.checkboxSize)
            }
            .buttonStyle(.plain)
            .frame(width: HomeInlineTaskLayoutMetrics.actionSlotWidth, height: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .trailing)

            TextField(
                "子任务标题",
                text: $subtask.title
            )
            .font(AppTheme.typography.sized(15, weight: .medium))
            .foregroundStyle(AppTheme.colors.title.opacity(0.82))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
        }
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .leading)
    }
}

private struct OCRSelectionBox: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .strokeBorder(
                    AppTheme.colors.body.opacity(isSelected ? 0.18 : 0.42),
                    style: StrokeStyle(lineWidth: 1.6, dash: [3.6, 4.4])
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(15, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.56))
            }
        }
        .frame(width: HomeInlineTaskLayoutMetrics.checkboxSize, height: HomeInlineTaskLayoutMetrics.checkboxSize)
    }
}

struct OCRTaskAttributeMenuSheet: View {
    @Binding var task: OCRImportTaskDraft
    @Binding var activeMenu: TaskEditorMenu
    let quickTimePresetMinutes: [Int]
    let onDismiss: () -> Void

    @State private var stagedDate: Date
    @State private var stagedTime: Date?
    @State private var stagedReminderOffset: TimeInterval?
    @State private var stagedRepeatRule: ItemRepeatRule?

    init(
        task: Binding<OCRImportTaskDraft>,
        activeMenu: Binding<TaskEditorMenu>,
        quickTimePresetMinutes: [Int],
        onDismiss: @escaping () -> Void
    ) {
        _task = task
        _activeMenu = activeMenu
        self.quickTimePresetMinutes = quickTimePresetMinutes
        self.onDismiss = onDismiss

        let draft = task.wrappedValue
        let initialDueDate = draft.dueAt ?? Calendar.current.startOfDay(for: .now)
        let initialDate = Calendar.current.startOfDay(for: initialDueDate)
        let initialTime = draft.hasExplicitTime ? draft.dueAt : nil
        let initialReminder = Self.reminderOffset(for: draft)

        _stagedDate = State(initialValue: initialDate)
        _stagedTime = State(initialValue: initialTime)
        _stagedReminderOffset = State(initialValue: initialReminder)
        _stagedRepeatRule = State(initialValue: draft.repeatRule)
    }

    var body: some View {
        TaskEditorUnifiedMenuSheet(
            context: .taskInline,
            activeMenu: $activeMenu,
            disabledMenus: stagedTime == nil ? [.reminder] : [],
            selectionFeedback: HomeInteractionFeedback.selection,
            switcherPlacement: .bottom,
            onClose: onDismiss,
            onSave: applyChangesAndDismiss
        ) { menu in
            menuContent(for: menu)
        }
    }

    @ViewBuilder
    private func menuContent(for menu: TaskEditorMenu) -> some View {
        switch menu {
        case .date:
            TaskEditorDatePickerSheet(
                selectedDate: $stagedDate,
                selectionFeedback: HomeInteractionFeedback.selection,
                onDismiss: {},
                dismissesOnSelection: false
            )
        case .time:
            TaskEditorTimePickerSheet(
                selectedTime: $stagedTime,
                anchorDate: stagedDate,
                quickPresetMinutes: quickTimePresetMinutes,
                savesOnQuickPresetSelection: false,
                showsPrimaryButton: false,
                selectionFeedback: HomeInteractionFeedback.selection,
                primaryFeedback: HomeInteractionFeedback.selection,
                onTimeSaved: nil,
                onDismiss: {}
            )
        case .reminder:
            TaskEditorReminderOptionList(
                selectedOffset: stagedReminderOffset,
                selectionFeedback: HomeInteractionFeedback.selection,
                onSelect: { offset in
                    stagedReminderOffset = offset
                }
            )
        case .repeatRule:
            TaskEditorOptionList(
                options: repeatOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .subtasks, .template, .periodicReminder, .periodicCycle:
            EmptyView()
        }
    }

    private var repeatOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不重复", isSelected: stagedRepeatRule == nil) {
            stagedRepeatRule = nil
        }] + TaskEditorRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: stagedDate)
            return TaskEditorOptionRow(
                title: title,
                isSelected: title == stagedRepeatRule?.title(anchorDate: stagedDate, calendar: .current)
            ) {
                stagedRepeatRule = preset.makeRule(anchorDate: stagedDate)
            }
        }
    }

    private func applyChangesAndDismiss() {
        let dueAt = stagedTime.map { Self.merge(date: stagedDate, timeSource: $0) } ?? stagedDate
        task.dueAt = dueAt
        task.hasExplicitTime = stagedTime != nil
        task.remindAt = stagedReminderOffset.map {
            Self.reminderTargetDate(dueAt: dueAt, hasExplicitTime: stagedTime != nil).addingTimeInterval(-$0)
        }
        task.repeatRule = stagedRepeatRule
        onDismiss()
    }

    private static func reminderOffset(for task: OCRImportTaskDraft) -> TimeInterval? {
        guard let dueAt = task.dueAt, let remindAt = task.remindAt else { return nil }
        let target = reminderTargetDate(dueAt: dueAt, hasExplicitTime: task.hasExplicitTime)
        return target.timeIntervalSince(remindAt)
    }

    private static func reminderTargetDate(dueAt: Date, hasExplicitTime: Bool) -> Date {
        guard hasExplicitTime else {
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
        }
        return dueAt
    }

    private static func merge(date: Date, timeSource: Date) -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? date
    }
}
