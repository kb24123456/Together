import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeItemDetailSheet: View {
    @Bindable var viewModel: HomeViewModel
    @State private var focusedField: Field?
    @State private var activeMenu: TaskEditorMenu?
    @State private var pendingAction: DetailEntryAction?
    @State private var isAwaitingDeleteConfirmation = false
    @State private var templateSaveState: CompactTemplateSaveState = .idle
    @State private var lastFocusedFieldBeforeMenu: Field?
    @State private var focusCoordinator = DetailTextInputFocusCoordinator()
    @State private var saveFeedbackNonce = 0
    @State private var isSaveButtonAnimating = false
    @State private var taskTemplates: [TaskTemplate] = []
    @State private var isLoadingTemplates = false
    @StateObject private var keyboardObserver = TaskEditorKeyboardObserver()
    @Namespace private var chipRowNamespace
    @Namespace private var categorySwitcherNamespace

    enum Field: Hashable {
        case title
        case notes
    }

    private enum DetailCategory {
        case task
        case project
    }

    private enum DetailEntryAction {
        case none
        case focus(Field)
        case menu(TaskEditorMenu)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.detailDraft != nil {
                    GeometryReader { proxy in
                        Group {
                            if isExpandedEditor {
                                expandedEditorLayout(proxy: proxy)
                            } else {
                                compactDetailLayout(proxy: proxy)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.clear)
        .overlay {
            if activeMenu != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissActiveMenu()
                    }
            }
        }
        .sheet(isPresented: isSecondaryMenuPresented, onDismiss: {
            restoreFocusAfterMenuIfNeeded(preferImmediateResponder: true)
        }) {
            if let menuBinding = activeMenuBinding {
                HomeDetailMenuSheet(
                    context: menuContext,
                    activeMenu: menuBinding,
                    viewModel: viewModel,
                    templates: taskTemplates,
                    isLoadingTemplates: isLoadingTemplates,
                    onTemplatePicked: { template in
                        let created = await viewModel.createTask(from: template)
                        if created {
                            dismissActiveMenu()
                        }
                    },
                    onTemplateDeleted: { template in
                        let deleted = await viewModel.deleteTaskTemplate(template.id)
                        if deleted {
                            taskTemplates.removeAll { $0.id == template.id }
                        }
                    },
                    disabledMenus: disabledMenus,
                    onDismiss: dismissActiveMenu
                )
                .presentationDetents(menuContext.detents)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
                .modifier(TaskEditorMenuPresentationSizingModifier())
            }
        }
        .presentationDetents([.height(316), .large], selection: $viewModel.detailDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: focusedField) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.markDetailForExpandedEditing()
            }
        }
        .onChange(of: viewModel.detailDetent) { _, newValue in
            guard newValue == .large else { return }
            performPendingActionIfNeeded()
        }
    }

    private var isExpandedEditor: Bool {
        viewModel.detailDetent == .large
    }

    private func compactDetailLayout(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelInlineActions()
                }

            VStack(alignment: .leading, spacing: 0) {
                compactHeaderSection
                compactMetaSection
                compactChipSection
                    .padding(.top, 14)
                compactActionButtons
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedEditorLayout(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            expandedCategorySwitcher
                .padding(.top, 18)
                .padding(.bottom, 8)

            expandedEditorSection
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            expandedBottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, 8))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var expandedCategorySwitcher: some View {
        HStack(spacing: 10) {
            ForEach(["模板", "任务", "项目"], id: \.self) { title in
                let isActive = expandedCategoryTitle == title

                Button {
                    if title == "模板" {
                        Task {
                            await openTemplateLibrary()
                        }
                    } else if isActive {
                        HomeInteractionFeedback.selection()
                        focusedField = .title
                    }
                } label: {
                    Text(title)
                        .font(AppTheme.typography.sized(18, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? AppTheme.colors.title : AppTheme.colors.textTertiary)
                        .scaleEffect(isActive ? 1 : 0.96)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 9)
                        .background(
                            ZStack {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.colors.surfaceElevated)
                                        .matchedGeometryEffect(
                                            id: "detail.categorySwitcher.selection",
                                            in: categorySwitcherNamespace
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
        .padding(.bottom, 10)
    }

    private func expandedBottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(currentStateText)
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(statusTextColor)

                chipRow { menu in
                    guard disabledMenus.contains(menu) == false else { return }
                    HomeInteractionFeedback.selection()
                    openMenu(menu)
                }

                expandedSaveButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [.clear, AppTheme.colors.surface.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.bottom, bottomInset)
        .animation(.interpolatingSpring(mass: 1.08, stiffness: 168, damping: 23, initialVelocity: 0.1), value: isExpandedEditor)
    }

    private var expandedSaveButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            triggerSaveButtonAnimation()
            if viewModel.hasUnsavedDetailChanges {
                Task {
                    await viewModel.saveDetailDraft()
                }
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        viewModel.detailDetent = .height(316)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .symbolEffect(.bounce, value: saveFeedbackNonce)
                Text("保存")
                    .font(AppTheme.typography.sized(15, weight: .bold))
            }
            .foregroundStyle(AppTheme.colors.title)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
        .padding(.horizontal, 10)
        .scaleEffect(isSaveButtonAnimating ? 0.95 : 1)
        .brightness(isSaveButtonAnimating ? -0.015 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isSaveButtonAnimating)
        .modifier(
            TaskEditorPrimaryActionOvershootModifier(
                trigger: isExpandedEditor,
                keyboardRevealOffset: primaryActionKeyboardRevealOffset
            )
        )
        .transition(.offset(y: 18).combined(with: .opacity))
    }

    private func triggerSaveButtonAnimation() {
        saveFeedbackNonce += 1
        isSaveButtonAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isSaveButtonAnimating = false
        }
    }

    private var primaryActionKeyboardRevealOffset: CGFloat {
        guard keyboardObserver.overlap > 0 else { return 0 }
        return min(max(keyboardObserver.overlap * 0.32, 104), 136)
    }

    private var compactHeaderSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.title))
            } label: {
                Text(viewModel.detailDraft?.title ?? "")
                    .font(AppTheme.typography.sized(32, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)

            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.notes))
            } label: {
                Text(compactNotesText)
                    .font(AppTheme.typography.sized(18, weight: .medium))
                    .foregroundStyle(compactNotesColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactMetaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentStateText)
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(statusTextColor)

            if viewModel.isPairModeActive {
                detailAssignmentSection
            }
        }
        .padding(.top, 38)
    }

    private var compactChipSection: some View {
        chipRow { menu in
            HomeInteractionFeedback.selection()
            expandToLarge(for: .menu(menu))
        }
        .opacity(0.94)
    }

    private var compactActionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                compactTemplateButton

                compactActionButton(
                    title: "编辑",
                    systemImage: "pencil",
                    tint: AppTheme.colors.body
                ) {
                    HomeInteractionFeedback.selection()
                    expandToLarge(for: .focus(.title))
                }

                compactDeleteButton
            }
        }
    }

    private var templateSaveButtonTitle: String {
        switch templateSaveState {
        case .idle:
            return "存模板"
        case .saved:
            return "成功"
        }
    }

    private var templateSaveButtonSystemImage: String {
        switch templateSaveState {
        case .idle:
            return "square.stack.3d.up.fill"
        case .saved:
            return "checkmark.circle.fill"
        }
    }

    private func handleTemplateSaveTap() {
        guard case .idle = templateSaveState else { return }
        Task {
            guard let result = await viewModel.saveCurrentDraftAsTemplateResult() else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    templateSaveState = .saved(
                        templateID: result.templateID,
                        isNewlyCreated: result.isNewlyCreated
                    )
                }
            }
        }
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactActionContent(
                title: title,
                systemImage: systemImage,
                tint: tint
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.72), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var compactTemplateButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            handleTemplateSaveTap()
        } label: {
            ZStack {
                if case .saved = templateSaveState {
                    compactActionContent(
                        title: "成功",
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.colors.body
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
                    compactActionContent(
                        title: "存模板",
                        systemImage: "bookmark",
                        tint: AppTheme.colors.body
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.72), lineWidth: 1)
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: templateSaveState)
        }
        .buttonStyle(.plain)
    }

    private var compactDeleteButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            if isAwaitingDeleteConfirmation {
                Task {
                    await viewModel.deleteSelectedItem()
                }
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isAwaitingDeleteConfirmation = true
                }
            }
        } label: {
            ZStack {
                if isAwaitingDeleteConfirmation {
                    compactDeleteContent(
                        title: "确认",
                        systemImage: "checkmark"
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
                    compactDeleteContent(
                        title: "移除",
                        systemImage: "trash"
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.68), lineWidth: 1)
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isAwaitingDeleteConfirmation)
        }
        .buttonStyle(.plain)
    }

    private func compactDeleteContent(
        title: String,
        systemImage: String
    ) -> some View {
        compactActionContent(
            title: title,
            systemImage: systemImage,
            tint: AppTheme.colors.coral
        )
    }

    private func compactActionContent(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .frame(height: 24, alignment: .center)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(AppTheme.typography.sized(17, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.interpolate)
                .frame(height: 24, alignment: .center)
        }
        .foregroundStyle(tint)
    }

    private var expandedEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailFocusableTextView(
                text: Binding(
                    get: { viewModel.detailDraft?.title ?? "" },
                    set: { viewModel.updateDraftTitle($0) }
                ),
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .title,
                placeholder: detailCategory == .project ? "项目标题" : "任务标题",
                font: AppTheme.typography.sizedUIFont(30, weight: .bold),
                textColor: UIColor(AppTheme.colors.title),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.62)),
                maximumNumberOfLines: 3
            )

            DetailFocusableTextView(
                text: Binding(
                    get: { viewModel.detailDraft?.notes ?? "" },
                    set: { viewModel.updateDraftNotes($0) }
                ),
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .notes,
                placeholder: "添加备注...",
                font: AppTheme.typography.sizedUIFont(16, weight: .medium),
                textColor: UIColor(AppTheme.colors.body.opacity(0.78)),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.74)),
                maximumNumberOfLines: 8
            )

            if viewModel.isPairModeActive {
                detailAssignmentSection
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var detailAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("归属与回应")
                .font(AppTheme.typography.sized(14, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))

            Picker(
                "归属与回应",
                selection: Binding(
                    get: { viewModel.detailDraft?.assigneeMode ?? .self },
                    set: { viewModel.updateDraftAssigneeMode($0) }
                )
            ) {
                Text("自己").tag(TaskAssigneeMode.`self`)
                Text("对方").tag(TaskAssigneeMode.partner)
                Text("一起").tag(TaskAssigneeMode.both)
            }
            .pickerStyle(.segmented)

            if viewModel.detailDraft?.assigneeMode == .partner {
                TextField(
                    "补一句说明或留言",
                    text: Binding(
                        get: { viewModel.detailDraft?.assignmentNote ?? "" },
                        set: { viewModel.updateDraftAssignmentNote($0) }
                    ),
                    axis: .vertical
                )
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.82))
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.colors.outline.opacity(0.14), lineWidth: 1)
                }
            }

            if selectedItemNeedsResponse {
                HStack(spacing: 10) {
                    responseActionButton(title: "接受", tint: AppTheme.colors.title) {
                        Task { await viewModel.respondToSelectedItem(response: .willing, message: nil) }
                    }
                    responseActionButton(title: "推迟", tint: AppTheme.colors.body) {
                        Task { await viewModel.respondToSelectedItem(response: .notAvailableNow, message: "稍后处理") }
                    }
                    responseActionButton(title: "拒绝", tint: AppTheme.colors.coral) {
                        Task { await viewModel.respondToSelectedItem(response: .notSuitable, message: "这次不合适") }
                    }
                }
            }
        }
    }

    private var selectedItemNeedsResponse: Bool {
        guard let item = viewModel.selectedItem else { return false }
        guard let actorID = viewModel.currentUserID else { return false }
        return item.requiresResponse && item.canActorRespond(actorID)
    }

    private func responseActionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(14, weight: .bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.colors.outline.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func chipRow(action: @escaping (TaskEditorMenu) -> Void) -> some View {
        TaskEditorChipRow(
            chips: chips,
            namespace: chipRowNamespace,
            trailingInset: 0,
            onChipTap: action,
            onClearTap: { chip in
                HomeInteractionFeedback.selection()
                guard chip.menu == .time else { return }
                viewModel.clearDraftDueTime()
            }
        )
    }

    private var detailCategory: DetailCategory {
        .task
    }

    private var menuContext: TaskEditorMenuContext {
        activeMenu == .template ? .templates : .task
    }

    private var disabledMenus: Set<TaskEditorMenu> {
        viewModel.detailDraft?.hasExplicitTime == true ? [] : [.reminder]
    }

    private var isSecondaryMenuPresented: Binding<Bool> {
        Binding(
            get: { activeMenu != nil },
            set: { isPresented in
                if isPresented == false {
                    dismissActiveMenu()
                }
            }
        )
    }

    private var activeMenuBinding: Binding<TaskEditorMenu>? {
        guard let activeMenu else { return nil }
        return Binding(
            get: { self.activeMenu ?? activeMenu },
            set: { self.activeMenu = $0 }
        )
    }

    private var expandedCategoryTitle: String {
        switch detailCategory {
        case .task:
            return "任务"
        case .project:
            return "项目"
        }
    }

    private var chips: [TaskEditorRenderedChip] {
        let snapshots: [TaskEditorChipSnapshot]
        switch detailCategory {
        case .task:
            snapshots = [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.date.rawValue,
                    title: taskDateTitle,
                    systemImage: "calendar",
                    menu: .date,
                    semanticValue: .date(viewModel.detailDraft?.dueAt ?? viewModel.selectedDate)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.time.rawValue,
                    title: taskTimeTitle,
                    systemImage: "clock",
                    menu: .time,
                    semanticValue: .time(viewModel.detailDraft?.dueAt),
                    showsTrailingClear: showsTimeClearButton
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.reminder.rawValue,
                    title: reminderTitle,
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(reminderOffset)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.repeatRule.rawValue,
                    title: repeatTitle,
                    systemImage: "arrow.triangle.2.circlepath",
                    menu: .repeatRule,
                    semanticValue: .repeatRule(
                        title: repeatTitle,
                        rank: viewModel.detailDraft?.repeatRule?.animationRank ?? 0
                    )
                )
            ]
        case .project:
            snapshots = []
        }

        return makeRenderedChips(from: snapshots)
    }

    private var taskDateTitle: String {
        localizedRelativeMonthDayText(viewModel.detailDraft?.dueAt ?? viewModel.selectedDate)
    }

    private var taskTimeTitle: String {
        guard
            viewModel.detailDraft?.hasExplicitTime == true,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "时间"
        }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else {
            return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        let delta = dueAt.timeIntervalSince(remindAt)
        return TaskEditorReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt, calendar: .current)
    }

    private var showsTimeClearButton: Bool {
        viewModel.detailDraft?.hasExplicitTime == true
    }

    private func localizedRelativeMonthDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func absoluteMonthDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private var compactNotesText: String {
        let notes = viewModel.detailDraft?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? "添加备注..." : notes
    }

    private var compactNotesColor: Color {
        let notes = viewModel.detailDraft?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? AppTheme.colors.textTertiary.opacity(0.74) : AppTheme.colors.body.opacity(0.78)
    }

    private var currentStateText: String {
        "\(statusDateText) · \(statusLabelText)"
    }

    private var statusTextColor: Color {
        statusLabelText == "已逾期"
        ? AppTheme.colors.coral
        : AppTheme.colors.body.opacity(0.84)
    }

    private var reminderOffset: TimeInterval? {
        guard
            let dueAt = viewModel.detailDraft?.dueAt,
            let remindAt = viewModel.detailDraft?.remindAt
        else { return nil }
        return dueAt.timeIntervalSince(remindAt)
    }

    private var statusDateText: String {
        if
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        {
            return rule.title(anchorDate: dueAt, calendar: .current)
        }
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "未安排" }
        return localizedRelativeMonthDayText(dueAt)
    }

    private func cancelInlineActions() {
        if isAwaitingDeleteConfirmation {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                isAwaitingDeleteConfirmation = false
            }
        }

        guard case let .saved(templateID, isNewlyCreated) = templateSaveState else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            templateSaveState = .idle
        }
        guard isNewlyCreated else { return }
        Task {
            _ = await viewModel.deleteTaskTemplate(templateID)
        }
    }

    private var statusLabelText: String {
        if let item = viewModel.selectedItem,
           item.isCompleted(on: viewModel.selectedDate, calendar: .current) || item.status == .completed {
            return "已完成"
        }
        if viewModel.detailDraft?.repeatRule != nil {
            return recurringStatusLabelText
        }
        if
            let draft = viewModel.detailDraft,
            let dueAt = draft.dueAt,
            isDraftOverdue(draft, dueAt: dueAt)
        {
            return "已超时"
        }
        return "进行中"
    }

    private var recurringStatusLabelText: String {
        guard let item = viewModel.selectedItem else { return "待完成" }
        if item.isOverdue(on: viewModel.selectedDate, calendar: .current) {
            if Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: .now) {
                return item.hasExplicitTime ? "已超时" : "已逾期"
            }
            return "已逾期"
        }
        return "待完成"
    }

    private func isDraftOverdue(_ draft: TaskDraft, dueAt: Date) -> Bool {
        let effectiveDueAt: Date
        if let item = viewModel.selectedItem {
            effectiveDueAt = item.occurrenceDueDate(on: viewModel.selectedDate, calendar: .current) ?? dueAt
        } else {
            effectiveDueAt = dueAt
        }
        if draft.hasExplicitTime {
            return effectiveDueAt <= .now
        }
        return effectiveDueAt < Calendar.current.startOfDay(for: .now)
    }

    private func expandToLarge(for action: DetailEntryAction) {
        cancelInlineActions()
        pendingAction = action

        if isExpandedEditor {
            performPendingActionIfNeeded()
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            viewModel.markDetailForExpandedEditing()
        }
    }

    private func performPendingActionIfNeeded() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .none:
            break
        case let .focus(field):
            DispatchQueue.main.async {
                focusedField = field
            }
        case let .menu(menu):
            openMenu(menu)
        }
    }

    private func restoreFocusAfterMenuIfNeeded(preferImmediateResponder: Bool = false) {
        guard let field = lastFocusedFieldBeforeMenu else { return }
        lastFocusedFieldBeforeMenu = nil
        focusedField = field

        guard preferImmediateResponder else { return }
        focusCoordinator.requestFocus(for: field)
        DispatchQueue.main.async {
            focusCoordinator.requestFocus(for: field)
        }
    }

    private func openMenu(_ menu: TaskEditorMenu) {
        guard disabledMenus.contains(menu) == false else { return }
        lastFocusedFieldBeforeMenu = focusedField ?? focusCoordinator.currentFocusedField ?? .title
        focusCoordinator.resignCurrentResponder()
        focusedField = nil
        withTransaction(HomeDetailMenuAnimation.presentationTransaction) {
            activeMenu = menu
        }
    }

    @MainActor
    private func openTemplateLibrary() async {
        HomeInteractionFeedback.selection()
        isLoadingTemplates = true
        taskTemplates = await viewModel.fetchTaskTemplates()
        isLoadingTemplates = false
        openMenu(.template)
    }

    private func dismissActiveMenu() {
        restoreFocusAfterMenuIfNeeded(preferImmediateResponder: true)
        withTransaction(HomeDetailMenuAnimation.dismissalTransaction) {
            activeMenu = nil
        }
    }

    private func makeRenderedChips(from snapshots: [TaskEditorChipSnapshot]) -> [TaskEditorRenderedChip] {
        snapshots.map { snapshot in
            TaskEditorRenderedChip(
                id: snapshot.id,
                title: snapshot.title,
                systemImage: snapshot.systemImage,
                menu: snapshot.menu,
                showsTrailingClear: snapshot.showsTrailingClear,
                transitionDirection: .up,
                semanticValue: snapshot.semanticValue
            )
        }
    }

}

private enum CompactTemplateSaveState: Equatable {
    case idle
    case saved(templateID: UUID, isNewlyCreated: Bool)
}

private struct HomeDetailMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

private enum HomeDetailMenuAnimation {
    static let presentation = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let dismissal = Animation.spring(response: 0.4, dampingFraction: 0.94)

    static var presentationTransaction: Transaction {
        Transaction(animation: presentation)
    }

    static var dismissalTransaction: Transaction {
        Transaction(animation: dismissal)
    }
}

@MainActor
private final class DetailTextInputFocusCoordinator {
    weak var titleTextView: UITextView?
    weak var notesTextView: UITextView?
    private(set) var currentFocusedField: HomeItemDetailSheet.Field?
    private var pendingFocusField: HomeItemDetailSheet.Field?

    var isTransitioningFocus: Bool {
        pendingFocusField != nil
    }

    func register(_ textView: UITextView, for field: HomeItemDetailSheet.Field) {
        switch field {
        case .title:
            titleTextView = textView
        case .notes:
            notesTextView = textView
        }

        if pendingFocusField == field {
            DispatchQueue.main.async {
                self.requestFocus(for: field)
            }
        }
    }

    func resignCurrentResponder() {
        pendingFocusField = nil
        if titleTextView?.isFirstResponder == true {
            titleTextView?.resignFirstResponder()
        }
        if notesTextView?.isFirstResponder == true {
            notesTextView?.resignFirstResponder()
        }
    }

    func markDidBeginEditing(_ field: HomeItemDetailSheet.Field) {
        currentFocusedField = field
        pendingFocusField = nil
    }

    func markDidEndEditing(_ field: HomeItemDetailSheet.Field) {
        if currentFocusedField == field {
            currentFocusedField = nil
        }
    }

    func requestFocus(for field: HomeItemDetailSheet.Field) {
        pendingFocusField = field
        let target: UITextView?
        let other: UITextView?

        switch field {
        case .title:
            target = titleTextView
            other = notesTextView
        case .notes:
            target = notesTextView
            other = titleTextView
        }

        if other?.isFirstResponder == true {
            other?.resignFirstResponder()
        }
        guard let target, target.window != nil else { return }
        guard !target.isFirstResponder else {
            currentFocusedField = field
            pendingFocusField = nil
            return
        }
        target.becomeFirstResponder()
        currentFocusedField = field
        pendingFocusField = nil
    }
}

private struct DetailFocusableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: HomeItemDetailSheet.Field?
    let focusCoordinator: DetailTextInputFocusCoordinator
    let field: HomeItemDetailSheet.Field
    let placeholder: String
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let maximumNumberOfLines: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> DetailTextViewContainer {
        let container = DetailTextViewContainer()
        container.textView.delegate = context.coordinator
        focusCoordinator.register(container.textView, for: field)
        container.textView.backgroundColor = .clear
        container.textView.textContainerInset = .zero
        container.textView.textContainer.lineFragmentPadding = 0
        container.textView.isScrollEnabled = false
        container.textView.keyboardDismissMode = .interactive
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        container.textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.textView.setContentHuggingPriority(.required, for: .vertical)
        container.textView.setContentCompressionResistancePriority(.required, for: .vertical)
        container.onDidMoveToWindow = {
            context.coordinator.syncFirstResponder(in: container.textView)
        }

        update(container, coordinator: context.coordinator)
        return container
    }

    func updateUIView(_ uiView: DetailTextViewContainer, context: Context) {
        context.coordinator.parent = self
        focusCoordinator.register(uiView.textView, for: field)
        update(uiView, coordinator: context.coordinator)
        context.coordinator.syncFirstResponder(in: uiView.textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DetailTextViewContainer, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else {
            return uiView.intrinsicContentSize
        }
        return uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    }

    private func update(_ container: DetailTextViewContainer, coordinator: Coordinator) {
        let textView = container.textView
        textView.font = font
        textView.textColor = textColor
        textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
        textView.textContainer.lineBreakMode = .byTruncatingTail
        if textView.text != text {
            textView.text = text
        }
        container.placeholderLabel.text = placeholder
        container.placeholderLabel.font = font
        container.placeholderLabel.textColor = placeholderColor
        container.placeholderLabel.isHidden = !text.isEmpty
        container.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DetailFocusableTextView

        init(parent: DetailFocusableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let updated = textView.text ?? ""
            if parent.text != updated {
                parent.text = updated
            }
            if let container = textView.superview as? DetailTextViewContainer {
                container.placeholderLabel.isHidden = !updated.isEmpty
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focusCoordinator.markDidBeginEditing(parent.field)
            if parent.focusedField != parent.field {
                parent.focusedField = parent.field
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focusCoordinator.markDidEndEditing(parent.field)
            if parent.focusedField == parent.field && !parent.focusCoordinator.isTransitioningFocus {
                parent.focusedField = nil
            }
        }

        func syncFirstResponder(in textView: UITextView) {
            let shouldFocus = parent.focusedField == parent.field
            if shouldFocus {
                guard !textView.isFirstResponder else { return }
                guard textView.window != nil else { return }
                textView.becomeFirstResponder()
            } else if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }
}

private final class DetailTextViewContainer: UIView {
    let textView = UITextView()
    let placeholderLabel = UILabel()
    var onDidMoveToWindow: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(textView)
        addSubview(placeholderLabel)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.numberOfLines = 0
        placeholderLabel.backgroundColor = .clear

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onDidMoveToWindow?()
    }

    override var intrinsicContentSize: CGSize {
        let fallbackWidth = window?.windowScene?.screen.bounds.width ?? 320
        let fittingWidth = bounds.width > 0 ? bounds.width : fallbackWidth - 52
        let textHeight = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(textHeight))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingWidth = size.width > 0 ? size.width : (bounds.width > 0 ? bounds.width : 320)
        let textHeight = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: fittingWidth, height: ceil(textHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

private enum HomeDetailMenu: String, Identifiable {
    case date
    case time
    case reminder
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(HomeDetailDateMenuDetent.self)]
        case .time:
            return [.custom(TaskEditorTaskMenuDetent.self)]
        case .reminder, .repeatRule:
            return [.custom(TaskEditorTaskMenuDetent.self)]
        }
    }
}

private struct HomeDetailDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            HomeDetailDatePickerSheet.preferredHeight + TaskEditorUnifiedMenuMetrics.topBarHeight,
            context.maxDetentValue * 0.72
        )
    }
}

private struct HomeDetailMenuSheet: View {
    let context: TaskEditorMenuContext
    @Binding var activeMenu: TaskEditorMenu
    @Bindable var viewModel: HomeViewModel
    let templates: [TaskTemplate]
    let isLoadingTemplates: Bool
    let onTemplatePicked: (TaskTemplate) async -> Void
    let onTemplateDeleted: (TaskTemplate) async -> Void
    let disabledMenus: Set<TaskEditorMenu>
    let onDismiss: () -> Void

    @State private var stagedDate: Date
    @State private var stagedTime: Date?
    @State private var stagedReminderOffset: TimeInterval?
    @State private var stagedRepeatRule: ItemRepeatRule?

    @State private var didEditDate = false
    @State private var didEditTime = false
    @State private var didEditReminder = false
    @State private var didEditRepeatRule = false

    init(
        context: TaskEditorMenuContext,
        activeMenu: Binding<TaskEditorMenu>,
        viewModel: HomeViewModel,
        templates: [TaskTemplate],
        isLoadingTemplates: Bool,
        onTemplatePicked: @escaping (TaskTemplate) async -> Void,
        onTemplateDeleted: @escaping (TaskTemplate) async -> Void,
        disabledMenus: Set<TaskEditorMenu>,
        onDismiss: @escaping () -> Void
    ) {
        self.context = context
        _activeMenu = activeMenu
        self.viewModel = viewModel
        self.templates = templates
        self.isLoadingTemplates = isLoadingTemplates
        self.onTemplatePicked = onTemplatePicked
        self.onTemplateDeleted = onTemplateDeleted
        self.disabledMenus = disabledMenus
        self.onDismiss = onDismiss

        let draft = viewModel.detailDraft
        let initialDueDate = draft?.dueAt ?? viewModel.selectedDate
        let initialDate = Calendar.current.startOfDay(for: initialDueDate)
        let initialTime = draft?.hasExplicitTime == true ? draft?.dueAt : nil

        _stagedDate = State(initialValue: initialDate)
        _stagedTime = State(initialValue: initialTime)
        _stagedReminderOffset = State(initialValue: Self.reminderOffset(for: draft, fallbackDate: initialDate))
        _stagedRepeatRule = State(initialValue: draft?.repeatRule)
    }

    var body: some View {
        TaskEditorUnifiedMenuSheet(
            context: context,
            activeMenu: $activeMenu,
            disabledMenus: stagedDisabledMenus,
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
                selectedDate: stagedDateBinding,
                selectionFeedback: HomeInteractionFeedback.selection,
                onDismiss: {},
                dismissesOnSelection: false
            )
        case .time:
            TaskEditorTimePickerSheet(
                selectedTime: stagedTimeBinding,
                anchorDate: stagedDate,
                quickPresetMinutes: viewModel.quickTimePresetMinutes,
                savesOnQuickPresetSelection: false,
                showsPrimaryButton: false,
                selectionFeedback: HomeInteractionFeedback.selection,
                primaryFeedback: HomeInteractionFeedback.selection,
                onTimeSaved: nil,
                onDismiss: {}
            )
        case .reminder:
            TaskEditorOptionList(
                options: reminderOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .repeatRule:
            TaskEditorOptionList(
                options: repeatOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .subtasks:
            EmptyView()
        case .template:
            ComposerTemplatePickerSheet(
                templates: templates,
                isLoading: isLoadingTemplates,
                onSelect: { template in
                    Task { await onTemplatePicked(template) }
                },
                onDelete: onTemplateDeleted
            )
        }
    }

    private var reminderOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不提醒", isSelected: stagedReminderOffset == nil) {
            stagedReminderOffset = nil
            didEditReminder = true
        }] + TaskEditorReminderPreset.allCases.map { preset in
            TaskEditorOptionRow(
                title: preset.title,
                isSelected: stagedReminderOffset == preset.secondsBeforeTarget
            ) {
                stagedReminderOffset = preset.secondsBeforeTarget
                didEditReminder = true
            }
        }
    }

    private var repeatOptions: [TaskEditorOptionRow] {
        let anchorDate = stagedDate
        let selectedTitle = stagedRepeatRule?.title(anchorDate: anchorDate, calendar: .current) ?? "不重复"
        return TaskEditorRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: anchorDate)
            return TaskEditorOptionRow(title: title, isSelected: selectedTitle == title) {
                stagedRepeatRule = preset.makeRule(anchorDate: anchorDate)
                didEditRepeatRule = true
            }
        }
    }

    private var stagedDateBinding: Binding<Date> {
        Binding(
            get: { stagedDate },
            set: { newValue in
                stagedDate = Calendar.current.startOfDay(for: newValue)
                didEditDate = true
            }
        )
    }

    private var stagedTimeBinding: Binding<Date?> {
        Binding(
            get: { stagedTime },
            set: { newValue in
                stagedTime = newValue
                didEditTime = true
            }
        )
    }

    private func applyChangesAndDismiss() {
        if didEditDate {
            viewModel.updateDraftDueDate(stagedDate)
        }

        if didEditTime, let stagedTime {
            if viewModel.detailDraft?.dueAt == nil, didEditDate == false {
                ensureDueDateExists()
            }
            viewModel.updateDraftDueTime(stagedTime)
        }

        if didEditReminder {
            if let remindAt = stagedReminderContext.remindAt {
                if viewModel.detailDraft?.dueAt == nil, didEditDate == false, didEditTime == false {
                    ensureDueDateExists()
                }
                viewModel.updateDraftReminder(remindAt)
            } else {
                viewModel.setDraftReminderEnabled(false)
            }
        }

        if didEditRepeatRule {
            if stagedRepeatRule != nil, viewModel.detailDraft?.dueAt == nil, didEditDate == false, didEditTime == false {
                ensureDueDateExists()
            }
            viewModel.updateDraftRepeatRule(stagedRepeatRule)
        }

        onDismiss()
    }

    private var stagedReminderContext: TaskEditorStagedReminderContext {
        TaskEditorStagedReminderContext(
            selectedDate: stagedDate,
            selectedTime: stagedTime,
            reminderOffset: stagedReminderOffset
        )
    }

    private var stagedDisabledMenus: Set<TaskEditorMenu> {
        guard context == .task else { return disabledMenus }
        return stagedReminderContext.isReminderMenuDisabled ? [.reminder] : []
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }

    private static func reminderOffset(for draft: TaskDraft?, fallbackDate: Date) -> TimeInterval? {
        guard let remindAt = draft?.remindAt else { return nil }
        let dueAt = draft?.dueAt ?? fallbackDate
        let target = draft?.hasExplicitTime == true
            ? dueAt
            : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
        return target.timeIntervalSince(remindAt)
    }
}

private struct HomeDetailDatePickerSheet: View {
    static let gridRowHeight: CGFloat = 36
    static let gridRowSpacing: CGFloat = 10
    static let gridColumnSpacing: CGFloat = 0
    static let weekdayRowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 8
    static let topBottomPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 10
    static let headerToGridSpacing: CGFloat = 10
    static let calendarGridHeight: CGFloat =
        (gridRowHeight * 6)
        + (gridRowSpacing * 5)
    static let preferredHeight: CGFloat =
        (topBottomPadding * 2)
        + headerHeight
        + headerToGridSpacing
        + weekdayRowHeight
        + contentSpacing
        + calendarGridHeight

    @Bindable var viewModel: HomeViewModel
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: HomeDetailMonthTransitionDirection = .forward

    init(viewModel: HomeViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let initialDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        _displayedMonth = State(
            initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let headerInset = headerHorizontalInset(for: proxy.size.width)

            VStack(alignment: .leading, spacing: Self.headerToGridSpacing) {
                HStack(spacing: 10) {
                    Text(monthTitle)
                        .font(AppTheme.typography.sized(21, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        calendarButton(systemName: "chevron.left") {
                            shiftMonth(by: -1)
                        }

                        Button("Today") {
                            HomeInteractionFeedback.selection()
                            selectDate(Date())
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(minWidth: 84, minHeight: 40)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )

                        calendarButton(systemName: "chevron.right") {
                            shiftMonth(by: 1)
                        }
                    }
                }
                .frame(height: Self.headerHeight)
                .padding(.horizontal, headerInset)

                VStack(spacing: Self.contentSpacing) {
                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridColumnSpacing
                    ) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.weekdayRowHeight)
                        }
                    }

                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridRowSpacing
                    ) {
                        ForEach(monthCells) { cell in
                            Button {
                                HomeInteractionFeedback.selection()
                                selectDate(cell.date)
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(
                                            isToday(cell.date) && !isSelected(cell.date)
                                            ? AppTheme.colors.coral
                                            : .clear,
                                            lineWidth: 1.6
                                        )
                                        .background(
                                            Circle()
                                                .fill(isSelected(cell.date) ? AppTheme.colors.coral : .clear)
                                        )

                                    Text("\(Calendar.current.component(.day, from: cell.date))")
                                        .font(AppTheme.typography.sized(18, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(dayTextColor(for: cell))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.gridRowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: Self.calendarGridHeight, alignment: .top)
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .id(monthIdentity)
        .transition(monthTransition)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: displayedMonth)
        .padding(.vertical, Self.topBottomPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing), count: 7)
    }

    private func headerHorizontalInset(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(availableWidth - (Self.horizontalPadding * 2), 0)
        let columnWidth = max((gridWidth - (Self.gridColumnSpacing * 6)) / 7, 0)
        let firstColumnCenterX = Self.horizontalPadding + (columnWidth / 2)
        let visualDayHalfWidth = min(widestDayLabelWidth, columnWidth) / 2
        return max(firstColumnCenterX - visualDayHalfWidth, Self.horizontalPadding)
    }

    private var selectedDate: Date {
        viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var monthIdentity: String {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var monthTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: transitionDirection.removalEdge).combined(with: .opacity)
        )
    }

    private var widestDayLabelWidth: CGFloat {
        #if canImport(UIKit)
        let font = AppTheme.typography.sizedUIFont(18, weight: .semibold)
        return (1...31)
            .map { "\($0)" }
            .map { NSString(string: $0).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        #else
        return 0
        #endif
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthCells: [HomeDetailCalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [HomeDetailCalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                HomeDetailCalendarDayCell(
                    date: current,
                    isInDisplayedMonth: calendar.isDate(current, equalTo: displayedMonth, toGranularity: .month)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }
        return cells
    }

    private func calendarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTheme.typography.sized(15, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        transitionDirection = amount >= 0 ? .forward : .backward
        HomeInteractionFeedback.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        viewModel.updateDraftDueDate(Calendar.current.startOfDay(for: date))
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: HomeDetailCalendarDayCell) -> Color {
        if isSelected(cell.date) {
            return .white
        }
        if isToday(cell.date) {
            return AppTheme.colors.coral
        }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }
}

private struct HomeDetailTimePickerSheet: View {
    @Bindable var viewModel: HomeViewModel
    let quickPresetMinutes: [Int]
    let onDismiss: () -> Void
    @State private var selectedTime: Date

    init(
        viewModel: HomeViewModel,
        quickPresetMinutes: [Int],
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.onDismiss = onDismiss

        let detailDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let baseTime = viewModel.detailDraft?.dueAt
            ?? Self.roundedTimeSeed(for: detailDate)
            ?? detailDate
        _selectedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickPresetMinutes, id: \.self) { minutes in
                    Button {
                        HomeInteractionFeedback.selection()
                        applyQuickPreset(minutes)
                    } label: {
                        Text(relativePresetTitle(minutes))
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(HomeDetailMenuOptionButtonStyle())
                    .modifier(HomeDetailMenuOptionGlassModifier())
                }
            }
            .padding(.top, HomeDetailTimePickerMetrics.verticalInset)
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            TaskEditorSingleColumnTimeWheel(
                selection: $selectedTime,
                minuteInterval: 5
            )
            .frame(maxWidth: .infinity)
            .frame(height: HomeDetailTimePickerMetrics.pickerHeight)
            .clipped()
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            HStack {
                Button {
                    HomeInteractionFeedback.selection()
                    saveSelection()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text("添加")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: HomeDetailMenuOptionMetrics.height)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(HomeDetailMenuOptionButtonStyle())
                .modifier(HomeDetailMenuOptionGlassModifier())
            }
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.verticalInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private static func roundedTimeSeed(for date: Date) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let roundedMinute = Int((Double(minute) / 5).rounded()) * 5
        let minuteOverflow = roundedMinute / 60
        let normalizedMinute = roundedMinute % 60
        let normalizedHour = (hour + minuteOverflow) % 24

        return calendar.date(
            bySettingHour: normalizedHour,
            minute: normalizedMinute,
            second: 0,
            of: date
        )
    }

    private static func offsetTimeSeed(minutesFromNow: Int, for date: Date) -> Date {
        let calendar = Calendar.current
        let future = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let components = calendar.dateComponents([.hour, .minute], from: future)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    private func applyQuickPreset(_ minutes: Int) {
        let date = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let presetTime = Self.offsetTimeSeed(minutesFromNow: minutes, for: date)
        selectedTime = presetTime
        saveSelection(presetTime)
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func saveSelection(_ value: Date? = nil) {
        ensureDueDateExists()
        viewModel.updateDraftDueTime(value ?? selectedTime)
        onDismiss()
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct HomeDetailMinuteIntervalWheelPicker: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale(identifier: "zh_CN")
        picker.minuteInterval = minuteInterval
        picker.setDate(Self.rounded(selection, minuteInterval: minuteInterval), animated: false)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.didChange(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        let roundedSelection = Self.rounded(selection, minuteInterval: minuteInterval)

        if abs(selection.timeIntervalSince(roundedSelection)) > 0.5 {
            DispatchQueue.main.async {
                selection = roundedSelection
            }
        }

        if abs(uiView.date.timeIntervalSince(roundedSelection)) > 0.5 {
            uiView.setDate(roundedSelection, animated: context.coordinator.hasAppeared)
        }

        context.coordinator.hasAppeared = true
    }

    private static func rounded(_ date: Date, minuteInterval: Int) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / Double(minuteInterval)).rounded()) * minuteInterval

        let hourBaseDate = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date

        return calendar.date(byAdding: .minute, value: roundedMinute, to: hourBaseDate) ?? hourBaseDate
    }

    final class Coordinator: NSObject {
        var parent: HomeDetailMinuteIntervalWheelPicker
        var hasAppeared = false

        init(_ parent: HomeDetailMinuteIntervalWheelPicker) {
            self.parent = parent
        }

        @objc func didChange(_ sender: UIDatePicker) {
            parent.selection = HomeDetailMinuteIntervalWheelPicker.rounded(
                sender.date,
                minuteInterval: parent.minuteInterval
            )
        }
    }
}

private struct HomeDetailOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct HomeDetailCalendarDayCell: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

private enum HomeDetailMonthTransitionDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward:
            return .trailing
        case .backward:
            return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward:
            return .leading
        case .backward:
            return .trailing
        }
    }
}

private enum HomeDetailReminderPreset: CaseIterable, Identifiable {
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { title }

    var secondsBeforeTarget: TimeInterval {
        switch self {
        case .atTime:
            return 0
        case .fiveMinutes:
            return 300
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1_800
        case .oneHour:
            return 3_600
        case .oneDay:
            return 86_400
        }
    }

    var title: String {
        switch self {
        case .atTime:
            return "准时提醒"
        case .fiveMinutes:
            return "提前 5 分钟"
        case .fifteenMinutes:
            return "提前 15 分钟"
        case .thirtyMinutes:
            return "提前 30 分钟"
        case .oneHour:
            return "提前 1 小时"
        case .oneDay:
            return "提前 1 天"
        }
    }

    var chipTitle: String {
        switch self {
        case .atTime:
            return "准时"
        case .fiveMinutes:
            return "5 分钟"
        case .fifteenMinutes:
            return "15 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .oneDay:
            return "1 天"
        }
    }

    static func preset(for secondsBeforeTarget: TimeInterval) -> HomeDetailReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum HomeDetailRepeatPreset: CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case weekdays
    case biweekly
    case quarterly
    case halfYear

    var id: String { String(describing: self) }

    func title(anchorDate: Date) -> String {
        makeRule(anchorDate: anchorDate).title(anchorDate: anchorDate)
    }

    func makeRule(anchorDate: Date) -> ItemRepeatRule {
        let calendar = Calendar.current
        switch self {
        case .daily:
            return ItemRepeatRule(frequency: .daily)
        case .weekly:
            return ItemRepeatRule(
                frequency: .weekly,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .monthly:
            return ItemRepeatRule(
                frequency: .monthly,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .weekdays:
            return ItemRepeatRule(
                frequency: .weekly,
                weekdays: [2, 3, 4, 5, 6]
            )
        case .biweekly:
            return ItemRepeatRule(
                frequency: .weekly,
                interval: 2,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .quarterly:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 3,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .halfYear:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 6,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        }
    }
}

private struct HomeDetailMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct HomeDetailMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum HomeDetailMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

private enum HomeDetailTimePickerMetrics {
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 214
}
