import SwiftUI
import UIKit

struct OCRImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var viewModel: OCRImportViewModel
    let appContext: AppContext

    @State private var selectedDetent: PresentationDetent = .medium
    @State private var activeDraftMenu: OCRDraftMenuSelection?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.colors.background
                    .ignoresSafeArea()

                flowContent
                    .transition(flowTransition)
                    .id(viewModel.flowState)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle) {
                        handleCancelOrBack()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.flowState == .review {
                        Button("确认导入") {
                            Task {
                                if await viewModel.apply(to: appContext) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.canApply == false || viewModel.draft.status == .applying)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .presentationBackground(AppTheme.colors.surface)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(viewModel.draft.status == .applying)
        .sheet(
            isPresented: Binding(
                get: { activeDraftMenu != nil },
                set: { isPresented in
                    if isPresented == false {
                        activeDraftMenu = nil
                    }
                }
            )
        ) {
            if let selection = activeDraftMenu,
               let taskBinding = taskBinding(selection.taskID),
               let menuBinding = activeMenuBinding {
                OCRTaskAttributeMenuSheet(
                    task: taskBinding,
                    activeMenu: menuBinding,
                    quickTimePresetMinutes: quickTimePresetMinutes,
                    onDismiss: {
                        activeDraftMenu = nil
                    }
                )
                .presentationDetents(TaskEditorMenuContext.taskInline.detents)
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
                .modifier(TaskEditorMenuPresentationSizingModifier())
            }
        }
        .onChange(of: viewModel.flowState) { _, newValue in
            withAnimation(flowAnimation) {
                selectedDetent = newValue.prefersLargeDetent ? .large : .medium
            }
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch viewModel.flowState {
        case .sourcePicker:
            sourcePicker
        case .camera:
            OCRCameraCapturePanel(
                onBack: viewModel.showSourcePicker,
                onImageCaptured: { image in
                    Task { await viewModel.processImage(image) }
                }
            )
        case .photos:
            OCRPhotoLibraryGridPanel(
                onBack: viewModel.showSourcePicker,
                onImageSelected: { image in
                    Task { await viewModel.processImage(image) }
                }
            )
        case .processing:
            processingView
        case .review:
            reviewView
        case .failed:
            failureView
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text("导入纸面任务")
                    .font(AppTheme.typography.textStyle(.title2, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)

                Text("拍照或选择照片，识别后先生成可编辑草稿。")
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.62))
            }

            VStack(spacing: AppTheme.spacing.md) {
                OCRSourceActionButton(
                    title: "相机",
                    subtitle: "拍摄纸面清单或白板",
                    systemImage: "camera.fill",
                    action: viewModel.showCamera
                )

                OCRSourceActionButton(
                    title: "照片",
                    subtitle: "从相册选择已有图片",
                    systemImage: "photo.on.rectangle.angled",
                    action: viewModel.showPhotos
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, AppTheme.spacing.xl)
        .padding(.bottom, AppTheme.spacing.lg)
    }

    private var processingView: some View {
        VStack(spacing: AppTheme.spacing.xl) {
            imagePreview(maxHeight: 280)

            VStack(spacing: AppTheme.spacing.md) {
                ProgressView()
                Text("正在识别文字")
                    .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, AppTheme.spacing.lg)
    }

    private var failureView: some View {
        VStack(spacing: AppTheme.spacing.xl) {
            imagePreview(maxHeight: 240)

            VStack(spacing: AppTheme.spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(AppTheme.typography.sized(30, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)

                Text(viewModel.errorMessage ?? "识别失败，请换一张更清晰的图片。")
                    .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                HStack(spacing: AppTheme.spacing.md) {
                    Button("重新拍照") {
                        viewModel.showCamera()
                    }
                    .buttonStyle(.bordered)

                    Button("选择照片") {
                        viewModel.showPhotos()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, AppTheme.spacing.lg)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                imagePreview(maxHeight: 180)

                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                    Text("识别到 \(viewModel.draft.taskDrafts.count) 条任务")
                        .font(AppTheme.typography.textStyle(.title3, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("确认前可以编辑标题、备注、子任务和属性。")
                        .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                }

                ForEach(viewModel.draft.taskDrafts) { task in
                    OCRTaskDraftEditor(
                        task: binding(for: task.id),
                        onOpenMenu: { menu in
                            activeDraftMenu = OCRDraftMenuSelection(taskID: task.id, menu: menu)
                        }
                    )
                }

                rawTextSection
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.vertical, AppTheme.spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var rawTextSection: some View {
        if viewModel.draft.rawText.isEmpty == false {
            DisclosureGroup {
                Text(viewModel.draft.rawText)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .regular))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppTheme.spacing.sm)
            } label: {
                Text("原始识别文本")
                    .font(AppTheme.typography.textStyle(.body, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func imagePreview(maxHeight: CGFloat) -> some View {
        if let sourceImage = viewModel.sourceImage {
            Image(uiImage: sourceImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.52), lineWidth: 1)
                }
        }
    }

    private var navigationTitle: String {
        switch viewModel.flowState {
        case .sourcePicker:
            return "OCR"
        case .camera:
            return "拍照"
        case .photos:
            return "照片"
        case .processing:
            return "识别中"
        case .review:
            return "确认任务"
        case .failed:
            return "识别失败"
        }
    }

    private var cancelTitle: String {
        viewModel.flowState == .sourcePicker ? "关闭" : "返回"
    }

    private func handleCancelOrBack() {
        if viewModel.flowState == .sourcePicker {
            dismiss()
        } else {
            viewModel.showSourcePicker()
        }
    }

    private var flowTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    private var flowAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .snappy(duration: 0.32, extraBounce: 0.02)
    }

    private func binding(for id: UUID) -> Binding<OCRImportTaskDraft> {
        Binding {
            viewModel.draft.taskDrafts.first { $0.id == id } ?? OCRImportTaskDraft(title: "")
        } set: { updated in
            viewModel.updateTask(updated)
        }
    }

    private func taskBinding(_ id: UUID) -> Binding<OCRImportTaskDraft>? {
        guard viewModel.draft.taskDrafts.contains(where: { $0.id == id }) else { return nil }
        return binding(for: id)
    }

    private var activeMenuBinding: Binding<TaskEditorMenu>? {
        guard let activeDraftMenu else { return nil }
        return Binding(
            get: { self.activeDraftMenu?.menu ?? activeDraftMenu.menu },
            set: { self.activeDraftMenu?.menu = $0 }
        )
    }

    private var quickTimePresetMinutes: [Int] {
        NotificationSettings.normalizedQuickTimePresetMinutes(
            appContext.sessionStore.currentUser?.preferences.quickTimePresetMinutes
            ?? NotificationSettings.defaultQuickTimePresetMinutes
        )
    }
}

private struct OCRDraftMenuSelection: Identifiable, Hashable {
    var id: String { "\(taskID.uuidString)-\(menu.rawValue)" }
    let taskID: UUID
    var menu: TaskEditorMenu
}

private struct OCRSourceActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.spacing.md) {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(22, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.colors.surfaceElevated, in: Circle())

                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(title)
                        .font(AppTheme.typography.textStyle(.title3, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text(subtitle)
                        .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.58))
                }

                Spacer(minLength: 0)
            }
            .padding(AppTheme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.colors.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct OCRTaskDraftEditor: View {
    @Binding var task: OCRImportTaskDraft
    let onOpenMenu: (TaskEditorMenu) -> Void

    @State private var newSubtaskTitle = ""

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

            TextField("任务标题", text: $task.title, axis: .vertical)
                .font(AppTheme.typography.sized(19, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1...3)
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
                .foregroundStyle(AppTheme.colors.body.opacity(canAddSubtask ? 0.72 : 0.38))
                .frame(width: HomeInlineTaskLayoutMetrics.actionSlotWidth, height: HomeInlineTaskLayoutMetrics.rowMinHeight, alignment: .trailing)

            TextField("添加子任务", text: $newSubtaskTitle)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addSubtask)

            Button("添加") {
                addSubtask()
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAddSubtask ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.34))
            .disabled(!canAddSubtask)
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
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .quaternarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        task.subtasks.append(OCRImportSubtaskDraft(title: trimmed))
        newSubtaskTitle = ""
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

            TextField("子任务标题", text: $subtask.title, axis: .vertical)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title.opacity(0.82))
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
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

private struct OCRTaskAttributeMenuSheet: View {
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
