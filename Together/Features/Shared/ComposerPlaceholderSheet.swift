import SwiftUI
#if canImport(UIKit)
import UIKit
import CoreText
#endif

struct ComposerPlaceholderSheet: View {
    let route: ComposerRoute
    let appContext: AppContext
    let initialTitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var draftState: ComposerDraftState
    @State private var activeMenu: TaskEditorMenu?
    @State private var isSaving = false
    @State private var lastFocusedFieldBeforeMenu: ComposerField?
    @State private var focusedField: ComposerField?
    @State private var hasScheduledInitialTitleFocus = false
    @State private var focusCoordinator = ComposerTextInputFocusCoordinator()
    @StateObject private var keyboardObserver = TaskEditorKeyboardObserver()
    @Namespace private var categorySwitcherNamespace
    @Namespace private var chipRowNamespace
    @State private var displayedChips: [TaskEditorRenderedChip] = []
    @State private var pendingChipSnapshots: [TaskEditorChipSnapshot]?
    @State private var primaryActionFeedbackNonce = 0
    @State private var isPrimaryActionAnimating = false
    @State private var isLoadingTemplates = false
    @State private var taskTemplates: [TaskTemplate] = []
    @State private var isPeriodicSubtaskMode: Bool = false
    @State private var isProjectSubtaskMode: Bool = false

    init(route: ComposerRoute, appContext: AppContext, initialTitle: String? = nil) {
        self.route = route
        self.appContext = appContext
        self.initialTitle = initialTitle
        let initialCategory: ComposerCategory = {
            switch route {
            case .newProject: return .project
            case .newPeriodicTask: return .periodic
            case .newTask: return .task
            }
        }()
        let initialDraft = ComposerDraftState(
            initialCategory: initialCategory,
            referenceDate: appContext.homeViewModel.selectedDate
        )
        var seededDraft = initialDraft
        if let initialTitle, !initialTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            seededDraft.title = initialTitle
        }
        _draftState = State(
            initialValue: seededDraft
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                categorySwitcher
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                ComposerPage(
                    category: draftState.category,
                    draftState: $draftState,
                    isPairMode: appContext.sessionStore.isViewingPairSpace,
                    templates: taskTemplates,
                    isLoadingTemplates: isLoadingTemplates,
                    onTemplatePicked: applyTemplate,
                    onTemplateDeleted: { template in
                        await deleteTemplate(template)
                    },
                    focusedField: $focusedField,
                    focusCoordinator: focusCoordinator,
                    isPeriodicSubtaskMode: isPeriodicSubtaskMode,
                    isProjectSubtaskMode: isProjectSubtaskMode
                )
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.colors.surface)
            .overlay(alignment: .bottom) {
                bottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, 8))
            }
            .overlay {
                if activeMenu != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissActiveMenu()
                        }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: isSecondaryMenuPresented, onDismiss: {
            restoreKeyboardFocusIfNeeded(preferImmediateResponder: true)
            playPendingChipUpdatesIfNeeded()
        }) {
            if let menuBinding = activeMenuBinding {
                ComposerEditorMenuSheet(
                    context: menuContext,
                    activeMenu: menuBinding,
                    draftState: $draftState,
                    quickTimePresetMinutes: NotificationSettings.normalizedQuickTimePresetMinutes(
                        appContext.sessionStore.currentUser?.preferences.quickTimePresetMinutes
                        ?? NotificationSettings.defaultQuickTimePresetMinutes
                    ),
                    templates: taskTemplates,
                    isLoadingTemplates: isLoadingTemplates,
                    onTemplatePicked: { template in
                        applyTemplate(template)
                    },
                    onTemplateDeleted: { template in
                        await deleteTemplate(template)
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
        .onAppear {
            guard !hasScheduledInitialTitleFocus else { return }
            hasScheduledInitialTitleFocus = true
            displayedChips = makeRenderedChips(from: currentChipSnapshots, previous: displayedChips)
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
        .onChange(of: currentChipSnapshots) { _, newSnapshots in
            if activeMenu != nil {
                pendingChipSnapshots = newSnapshots
            } else {
                applyRenderedChips(newSnapshots, animated: !displayedChips.isEmpty)
            }
        }
        .onChange(of: draftState.category) { _, newCategory in
            if isPeriodicSubtaskMode { isPeriodicSubtaskMode = false }
            if isProjectSubtaskMode { isProjectSubtaskMode = false }
            guard newCategory == .template else { return }
            Task {
                await loadTemplates()
            }
        }
    }

    private var categorySwitcher: some View {
        HStack(spacing: 10) {
            ForEach(ComposerCategory.allCases) { category in
                Button {
                    ComposerButtonHaptics.selection()
                    let fieldToRestore = focusedField ?? focusCoordinator.currentFocusedField ?? .title
                    focusCoordinator.prepareFocusTransition(to: fieldToRestore)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        draftState.category = category
                    }
                    focusedField = fieldToRestore
                    DispatchQueue.main.async {
                        focusCoordinator.requestFocus(for: fieldToRestore)
                    }
                } label: {
                    Text(category.title)
                        .font(AppTheme.typography.sized(18, weight: draftState.category == category ? .bold : .semibold))
                        .foregroundStyle(
                            draftState.category == category
                            ? AppTheme.colors.title
                            : AppTheme.colors.textTertiary
                        )
                        .scaleEffect(draftState.category == category ? 1 : 0.96)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 9)
                        .background(
                            ZStack {
                                if draftState.category == category {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.colors.surfaceElevated)
                                        .matchedGeometryEffect(
                                            id: "composer.categorySwitcher.selection",
                                            in: categorySwitcherNamespace
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 10)
    }

    private func bottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: draftState.hasMeaningfulContent ? 12 : 0) {
                if showsTemplateButton {
                    templateCapsuleButton
                }

                if draftState.category != .template {
                    HStack(alignment: .center, spacing: 12) {
                        chipRow(trailingInset: 0)
                    }
                }

                if draftState.category != .template, draftState.hasMeaningfulContent {
                    stackedPrimaryActionButton
                }
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
        .animation(.interpolatingSpring(mass: 1.08, stiffness: 168, damping: 23, initialVelocity: 0.1), value: draftState.hasMeaningfulContent)
    }

    private var showsTemplateButton: Bool {
        false
    }

    private var templateCapsuleButton: some View {
        Button {
            ComposerButtonHaptics.selection()
            openMenu(.template)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "bookmark")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .padding(.trailing, 2)
                Text("模板")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.body.opacity(0.84))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var stackedPrimaryActionButton: some View {
        primaryActionButtonBody
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .modifier(
                TaskEditorPrimaryActionOvershootModifier(
                    trigger: draftState.hasMeaningfulContent,
                    keyboardRevealOffset: primaryActionKeyboardRevealOffset
                )
            )
            .transition(.offset(y: 18).combined(with: .opacity))
    }

    private var primaryActionKeyboardRevealOffset: CGFloat {
        guard keyboardObserver.overlap > 0 else { return 0 }
        return min(max(keyboardObserver.overlap * 0.32, 104), 136)
    }

    private var primaryActionButtonBody: some View {
        Button {
            ComposerButtonHaptics.primary()
            triggerPrimaryActionAnimation()
            Task {
                await save()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .symbolEffect(.bounce, value: primaryActionFeedbackNonce)

                Text(addButtonTitle)
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
        .disabled(isSaving)
        .scaleEffect(isSaving ? 0.98 : (isPrimaryActionAnimating ? 0.95 : 1))
        .brightness(isPrimaryActionAnimating ? -0.015 : 0)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isPrimaryActionAnimating)
    }

    private func triggerPrimaryActionAnimation() {
        primaryActionFeedbackNonce += 1
        isPrimaryActionAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isPrimaryActionAnimating = false
        }
    }

    private func chipRow(trailingInset: CGFloat) -> some View {
        TaskEditorChipRow(
            chips: chipsForCurrentCategory,
            namespace: chipRowNamespace,
            trailingInset: trailingInset,
            onChipTap: { menu in
                guard disabledMenus.contains(menu) == false else { return }
                ComposerButtonHaptics.selection()
                if menu == .subtasks && (draftState.category == .periodic || draftState.category == .project) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        if draftState.category == .periodic {
                            isPeriodicSubtaskMode.toggle()
                        } else {
                            isProjectSubtaskMode.toggle()
                        }
                    }
                } else {
                    openMenu(menu)
                }
            },
            onClearTap: { chip in
                ComposerButtonHaptics.selection()
                if chip.menu == .subtasks {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        isPeriodicSubtaskMode = false
                        isProjectSubtaskMode = false
                    }
                } else {
                    clearChipValue(chip)
                }
            }
        )
    }

    private var chipAnimationKey: String {
        chipsForCurrentCategory.map(\.id).joined(separator: "|")
    }

    private var chipsForCurrentCategory: [TaskEditorRenderedChip] {
        if displayedChips.isEmpty {
            return makeRenderedChips(from: currentChipSnapshots, previous: [])
        }
        return displayedChips
    }

    private var currentChipSnapshots: [TaskEditorChipSnapshot] {
        switch draftState.category {
        case .template:
            return []
        case .task:
            return [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.date.rawValue,
                    title: draftState.taskDateText,
                    systemImage: "calendar",
                    menu: .date,
                    semanticValue: .date(draftState.taskDate)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.time.rawValue,
                    title: draftState.taskTimeText,
                    systemImage: "clock",
                    menu: .time,
                    semanticValue: .time(draftState.taskTime),
                    showsTrailingClear: draftState.taskTime != nil
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.reminder.rawValue,
                    title: draftState.reminderSummaryText(for: .task),
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(draftState.taskReminderOffset)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.repeatRule.rawValue,
                    title: draftState.repeatSummaryText,
                    systemImage: "arrow.triangle.2.circlepath",
                    menu: .repeatRule,
                    semanticValue: .repeatRule(
                        title: draftState.repeatSummaryText,
                        rank: draftState.repeatRule?.animationRank ?? 0
                    )
                )
            ]
        case .periodic:
            return [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.periodicCycle.rawValue,
                    title: draftState.periodicCycle.title,
                    systemImage: "arrow.clockwise",
                    menu: .periodicCycle,
                    semanticValue: .periodicCycle(draftState.periodicCycle)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.periodicReminder.rawValue,
                    title: draftState.periodicReminderSummaryText,
                    systemImage: "bell",
                    menu: .periodicReminder,
                    semanticValue: .periodicReminder(draftState.periodicReminderEnabled)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.subtasks.rawValue,
                    title: draftState.periodicSubtaskSummaryText,
                    systemImage: "checklist",
                    menu: .subtasks,
                    semanticValue: .subtasks(draftState.periodicSubtasks.count),
                    showsTrailingClear: isPeriodicSubtaskMode
                )
            ]
        case .project:
            return [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.date.rawValue,
                    title: draftState.projectDateText,
                    systemImage: "calendar",
                    menu: .date,
                    semanticValue: .optionalDate(draftState.projectTargetDate)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.subtasks.rawValue,
                    title: draftState.projectSubtaskSummaryText,
                    systemImage: "checklist",
                    menu: .subtasks,
                    semanticValue: .subtasks(draftState.projectSubtasks.count),
                    showsTrailingClear: isProjectSubtaskMode
                )
            ]
        }
    }

    private func applyRenderedChips(_ snapshots: [TaskEditorChipSnapshot], animated: Bool) {
        let nextChips = makeRenderedChips(from: snapshots, previous: displayedChips)
        let shouldAnimateLayout = animated && displayedChips.map(\.id) != nextChips.map(\.id)

        if shouldAnimateLayout {
            withAnimation(ComposerChipAnimation.layoutSpring) {
                displayedChips = nextChips
            }
        } else {
            displayedChips = nextChips
        }
    }

    private func makeRenderedChips(
        from snapshots: [TaskEditorChipSnapshot],
        previous: [TaskEditorRenderedChip]
    ) -> [TaskEditorRenderedChip] {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return snapshots.map { snapshot in
            TaskEditorRenderedChip(
                id: snapshot.id,
                title: snapshot.title,
                systemImage: snapshot.systemImage,
                menu: snapshot.menu,
                showsTrailingClear: snapshot.showsTrailingClear,
                transitionDirection: transitionDirection(
                    from: previousByID[snapshot.id]?.semanticValue,
                    to: snapshot.semanticValue
                ),
                semanticValue: snapshot.semanticValue
            )
        }
    }

    private func transitionDirection(
        from previousValue: TaskEditorChipSemanticValue?,
        to newValue: TaskEditorChipSemanticValue
    ) -> TaskEditorChipTextTransitionDirection {
        guard let previousValue else { return .up }
        return TaskEditorChipSemanticValue.direction(from: previousValue, to: newValue)
    }

    private func playPendingChipUpdatesIfNeeded() {
        guard let pendingChipSnapshots else { return }
        applyRenderedChips(pendingChipSnapshots, animated: true)
        self.pendingChipSnapshots = nil
    }

    private var addButtonTitle: String {
        switch draftState.category {
        case .project, .periodic:
            return "创建"
        default:
            return "添加"
        }
    }

    private var menuContext: TaskEditorMenuContext {
        if activeMenu == .template || draftState.category == .template {
            return .templates
        }
        switch draftState.category {
        case .template:
            return .templates
        case .task:
            return .task
        case .periodic:
            return .periodic
        case .project:
            return .project
        }
    }

    private var disabledMenus: Set<TaskEditorMenu> {
        switch draftState.category {
        case .template:
            return []
        case .task:
            return draftState.taskTime == nil ? [.reminder] : []
        case .periodic:
            return []
        case .project:
            return []
        }
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

    private func openMenu(_ menu: TaskEditorMenu) {
        guard disabledMenus.contains(menu) == false else { return }
        lastFocusedFieldBeforeMenu = focusedField
        focusCoordinator.resignCurrentResponder()
        focusedField = nil
        withTransaction(ComposerMenuAnimation.presentationTransaction) {
            activeMenu = menu
        }
        if menu == .template {
            Task {
                await loadTemplates()
            }
        }
    }

    private func restoreKeyboardFocusIfNeeded(preferImmediateResponder: Bool = false) {
        guard let field = lastFocusedFieldBeforeMenu else { return }
        lastFocusedFieldBeforeMenu = nil
        focusedField = field

        guard preferImmediateResponder else { return }
        focusCoordinator.requestFocus(for: field)
        DispatchQueue.main.async {
            focusCoordinator.requestFocus(for: field)
        }
    }

    private func clearChipValue(_ chip: TaskEditorRenderedChip) {
        switch (draftState.category, chip.menu) {
        case (.task, .time):
            draftState.taskTime = nil
            draftState.taskReminderOffset = nil
        default:
            break
        }
    }

    private func dismissActiveMenu() {
        restoreKeyboardFocusIfNeeded(preferImmediateResponder: true)
        withTransaction(ComposerMenuAnimation.dismissalTransaction) {
            activeMenu = nil
        }
    }

    @MainActor
    private func loadTemplates() async {
        guard let spaceID = appContext.sessionStore.currentSpace?.id else {
            taskTemplates = []
            return
        }

        isLoadingTemplates = true
        defer { isLoadingTemplates = false }

        do {
            taskTemplates = try await appContext.container.taskTemplateRepository.fetchTaskTemplates(spaceID: spaceID)
        } catch {
            taskTemplates = []
        }
    }

    private func applyTemplate(_ template: TaskTemplate) {
        draftState.apply(template: template, referenceDate: appContext.homeViewModel.selectedDate)
        dismissActiveMenu()
        displayedChips = makeRenderedChips(from: currentChipSnapshots, previous: displayedChips)
        focusedField = .title
        DispatchQueue.main.async {
            focusCoordinator.requestFocus(for: .title)
        }
    }

    @MainActor
    private func deleteTemplate(_ template: TaskTemplate) async {
        do {
            try await appContext.container.taskTemplateRepository.deleteTaskTemplate(templateID: template.id)
            taskTemplates.removeAll { $0.id == template.id }
        } catch {
            return
        }
    }

    @MainActor
    private func save() async {
        guard draftState.hasMeaningfulContent else { return }
        guard
            let spaceID = appContext.sessionStore.currentSpace?.id,
            let actorID = appContext.sessionStore.currentUser?.id
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            switch draftState.category {
            case .template:
                return
            case .task:
                let item = try await appContext.container.taskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: draftState.taskDraft()
                )
                await appContext.homeViewModel.reload(insertedItemIDs: [item.id])
            case .periodic:
                let draft = draftState.periodicTaskDraft()
                _ = try await appContext.container.periodicTaskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: draft
                )
                await appContext.routinesViewModel.load()
            case .project:
                let project = try await appContext.container.projectRepository.saveProject(
                    draftState.projectDraft(spaceID: spaceID)
                )
                for subtask in draftState.projectSubtasks {
                    _ = try await appContext.container.projectRepository.addSubtask(
                        projectID: project.id,
                        title: subtask.title,
                        isCompleted: subtask.isCompleted
                    )
                }
                await appContext.projectsViewModel.load()
            }

            focusedField = nil
            dismiss()
        } catch {
            isSaving = false
        }
    }
}

private enum ComposerCategory: Int, CaseIterable, Identifiable {
    case template
    case task
    case periodic
    case project

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .template:
            return "模板"
        case .task:
            return "任务"
        case .periodic:
            return "周期"
        case .project:
            return "项目"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .template:
            return "从模板创建"
        case .task:
            return "任务标题"
        case .periodic:
            return "事务标题"
        case .project:
            return "项目标题"
        }
    }
}

private struct ProjectSubtaskDraft: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

private struct ComposerSmartSuggestionBar: View {
    let title: String
    let currentTime: Date?
    let currentRepeatRule: ItemRepeatRule?
    let currentDate: Date
    let onSetTime: (Date) -> Void
    let onSetRepeatRule: (ItemRepeatRule) -> Void
    let onSetDate: (Date) -> Void

    @State private var appliedIDs: Set<String> = []

    private var suggestions: [SmartSuggestion] {
        guard !title.isEmpty else { return [] }
        var result: [SmartSuggestion] = []
        let text = title

        // Time detection
        if currentTime == nil {
            if let time = detectTime(in: text) {
                let formatted = time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                result.append(.setTime(time, display: "设为 \(formatted)"))
            }
        }

        // Repeat detection
        if currentRepeatRule == nil {
            if text.contains("每天") || text.contains("每日") {
                result.append(.setRepeat(.daily, display: "每天重复"))
            } else if text.contains("每周") {
                result.append(.setRepeat(.weekly, display: "每周重复"))
            } else if text.contains("每月") {
                result.append(.setRepeat(.monthly, display: "每月重复"))
            } else if text.contains("工作日") {
                result.append(.setRepeat(.weekdays, display: "工作日重复"))
            }
        }

        // Date detection — "周X" weekday references
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let isAlreadyToday = calendar.isDate(currentDate, inSameDayAs: today)

        let weekdayMap: [(String, Int)] = [
            ("周一", 2), ("周二", 3), ("周三", 4), ("周四", 5),
            ("周五", 6), ("周六", 7), ("周日", 1), ("周天", 1),
        ]
        for (keyword, targetWeekday) in weekdayMap {
            if text.contains(keyword) {
                if let date = nextDateForWeekday(targetWeekday) {
                    let label = Self.relativeLabel(for: date)
                    result.append(.setDate(date, display: "设为\(label)"))
                }
                break
            }
        }

        // "周末" → next Saturday
        if text.contains("周末") && !text.contains("周一") {
            if let date = nextDateForWeekday(7) { // Saturday
                let label = Self.relativeLabel(for: date)
                result.append(.setDate(date, display: "设为\(label)"))
            }
        }

        // Explicit relative dates
        if text.contains("明天") {
            if let d = calendar.date(byAdding: .day, value: 1, to: today), isAlreadyToday {
                result.append(.setDate(d, display: "设为明天"))
            }
        } else if text.contains("后天") {
            if let d = calendar.date(byAdding: .day, value: 2, to: today) {
                result.append(.setDate(d, display: "设为后天"))
            }
        } else if text.contains("下周") && !weekdayMap.contains(where: { text.contains($0.0) }) {
            if let d = calendar.date(byAdding: .weekOfYear, value: 1, to: today) {
                result.append(.setDate(d, display: "设为下周"))
            }
        }

        return result.filter { !appliedIDs.contains($0.id) }
    }

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            HomeInteractionFeedback.selection()
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                appliedIDs.insert(suggestion.id)
                            }
                            applySuggestion(suggestion)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: suggestion.icon)
                                    .font(AppTheme.typography.sized(11, weight: .semibold))
                                Text(suggestion.display)
                                    .font(AppTheme.typography.sized(13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.colors.coral)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppTheme.colors.coral.opacity(0.1))
                            )
                        }
                        .buttonStyle(TaskEditorChipButtonStyle())
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.85).combined(with: .opacity)
                            )
                        )
                    }
                }
            }
            .transition(.opacity.combined(with: .offset(y: 4)))
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: suggestions.map(\.id))
        }
    }

    private func applySuggestion(_ suggestion: SmartSuggestion) {
        switch suggestion {
        case .setTime(let time, _):
            onSetTime(time)
        case .setRepeat(let preset, _):
            onSetRepeatRule(preset.makeRule(anchorDate: currentDate))
        case .setDate(let date, _):
            onSetDate(date)
        }
    }

    private func nextDateForWeekday(_ weekday: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        var daysAhead = weekday - todayWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: today)
    }

    private static func relativeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 1: return "明天"
        case 2: return "后天"
        default:
            let weekday = calendar.component(.weekday, from: date)
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return "周\(names[weekday - 1])"
        }
    }

    private func detectTime(in text: String) -> Date? {
        let patterns: [(String, Int, Int)] = [
            ("上午(\\d{1,2})点", 0, 0),
            ("下午(\\d{1,2})点", 12, 0),
            ("晚上(\\d{1,2})点", 12, 0),
            ("早上(\\d{1,2})点", 0, 0),
            ("(\\d{1,2})点半", 0, 30),
            ("(\\d{1,2})点", 0, 0),
        ]

        for (pattern, hourOffset, minuteDefault) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let hourRange = Range(match.range(at: 1), in: text) {
                var hour = Int(text[hourRange]) ?? 0
                hour += hourOffset
                if hour > 23 { hour -= 12 }

                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minuteDefault
                return Calendar.current.date(from: components)
            }
        }

        return nil
    }

    enum SmartSuggestion: Identifiable {
        case setTime(Date, display: String)
        case setRepeat(TaskEditorRepeatPreset, display: String)
        case setDate(Date, display: String)

        var id: String {
            switch self {
            case .setTime(_, let d): return "time-\(d)"
            case .setRepeat(_, let d): return "repeat-\(d)"
            case .setDate(_, let d): return "date-\(d)"
            }
        }

        var display: String {
            switch self {
            case .setTime(_, let d), .setRepeat(_, let d), .setDate(_, let d): return d
            }
        }

        var icon: String {
            switch self {
            case .setTime: return "clock"
            case .setRepeat: return "arrow.triangle.2.circlepath"
            case .setDate: return "calendar"
            }
        }
    }
}

private struct ComposerDraftState: Hashable {
    var category: ComposerCategory
    var title = ""
    var notes = ""
    var linkedListID: UUID?
    var linkedProjectID: UUID?
    var assigneeMode: TaskAssigneeMode = .self
    var assignmentNote = ""
    var taskDate: Date
    var taskTime: Date?
    var projectTargetDate: Date?
    var isPinned = false
    var taskReminderOffset: TimeInterval?
    var repeatRule: ItemRepeatRule?
    var projectSubtasks: [ProjectSubtaskDraft] = []
    var projectSubtaskInput = ""
    var periodicCycle: PeriodicCycle = .monthly
    var periodicReminderRules: [PeriodicReminderRule] = []
    var periodicReminderEnabled: Bool { !periodicReminderRules.isEmpty }
    var periodicSubtasks: [ProjectSubtaskDraft] = []
    var periodicSubtaskInput = ""

    init(initialCategory: ComposerCategory, referenceDate: Date) {
        self.category = initialCategory
        let calendar = Calendar.current
        self.taskDate = calendar.startOfDay(for: referenceDate)
        self.repeatRule = nil
    }

    var hasMeaningfulContent: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var taskDateText: String {
        Self.localizedRelativeMonthDayText(taskDate)
    }

    var taskTimeText: String {
        guard let taskTime else { return "时间" }
        return taskTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var projectDateText: String {
        guard let projectTargetDate else { return "截止日期" }
        return Self.localizedRelativeMonthDayText(projectTargetDate)
    }

    var repeatSummaryText: String {
        repeatRule?.title(anchorDate: taskDate, calendar: .current) ?? "重复"
    }

    var projectSubtaskSummaryText: String {
        let total = projectSubtasks.count
        guard total > 0 else { return "子任务" }
        let completed = projectSubtasks.filter(\.isCompleted).count
        return "\(completed)/\(total)"
    }

    func reminderSummaryText(for category: ComposerCategory) -> String {
        let offset: TimeInterval?
        switch category {
        case .template:
            offset = nil
        case .task:
            offset = taskReminderOffset
        case .periodic:
            offset = nil
        case .project:
            offset = nil
        }

        guard let offset else { return "提醒" }
        return ReminderPreset.preset(for: offset)?.chipTitle ?? "提醒"
    }

    func taskDraft() -> TaskDraft {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch category {
        case .template:
            return TaskDraft(title: title)
        case .task:
            let mergedDate = taskTime.map { Self.merge(date: taskDate, timeSource: $0) }
            let fallbackDate = Calendar.current.startOfDay(for: taskDate)
            let dueAt = mergedDate ?? fallbackDate
            let reminderTarget = Self.reminderTargetDate(for: dueAt, hasExplicitTime: taskTime != nil)
            let remindAt = taskReminderOffset.map { reminderTarget.addingTimeInterval(-$0) }
            return TaskDraft(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                listID: linkedListID,
                projectID: linkedProjectID,
                dueAt: dueAt,
                hasExplicitTime: taskTime != nil,
                remindAt: remindAt,
                assigneeMode: assigneeMode,
                assignmentState: assigneeMode == .partner ? .pendingResponse : .active,
                assignmentNote: assignmentNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : assignmentNote.trimmingCharacters(in: .whitespacesAndNewlines),
                isPinned: isPinned,
                repeatRule: repeatRule
            )
        case .periodic:
            return TaskDraft(title: title)
        case .project:
            return TaskDraft(title: title, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        }
    }

    func projectDraft(spaceID: UUID) -> Project {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Project(
            id: UUID(),
            spaceID: spaceID,
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            colorToken: "graphite",
            status: .active,
            targetDate: projectTargetDate,
            remindAt: nil,
            taskCount: projectSubtasks.count,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil
        )
    }

    mutating func addProjectSubtask() {
        let trimmed = projectSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        projectSubtasks.append(ProjectSubtaskDraft(title: trimmed))
        projectSubtaskInput = ""
    }

    mutating func toggleProjectSubtask(_ id: UUID) {
        guard let index = projectSubtasks.firstIndex(where: { $0.id == id }) else { return }
        projectSubtasks[index].isCompleted.toggle()
    }

    mutating func removeProjectSubtask(_ id: UUID) {
        projectSubtasks.removeAll { $0.id == id }
    }

    // MARK: - Periodic Subtasks

    mutating func addPeriodicSubtask() {
        let trimmed = periodicSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        periodicSubtasks.append(ProjectSubtaskDraft(title: trimmed))
        periodicSubtaskInput = ""
    }

    mutating func togglePeriodicSubtask(_ id: UUID) {
        guard let index = periodicSubtasks.firstIndex(where: { $0.id == id }) else { return }
        periodicSubtasks[index].isCompleted.toggle()
    }

    mutating func removePeriodicSubtask(_ id: UUID) {
        periodicSubtasks.removeAll { $0.id == id }
    }

    var periodicReminderSummaryText: String {
        guard let rule = periodicReminderRules.first else { return "提醒" }
        switch rule.timing {
        case .dayOfPeriod(let day):
            return "第\(day)天"
        case .businessDayOfPeriod(let day):
            return "第\(day)工作日"
        case .daysBeforeEnd(let days):
            return "截止前\(days)天"
        }
    }

    var periodicSubtaskSummaryText: String {
        let total = periodicSubtasks.count
        guard total > 0 else { return "子任务" }
        return "\(total) 项"
    }

    func periodicTaskDraft() -> PeriodicTaskDraft {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return PeriodicTaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            cycle: periodicCycle,
            reminderRules: periodicReminderRules,
            subtasks: periodicSubtasks.map {
                PeriodicSubtask(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
            }
        )
    }

    mutating func apply(template: TaskTemplate, referenceDate: Date) {
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: referenceDate)

        title = template.title
        notes = template.notes ?? ""
        linkedListID = template.listID
        linkedProjectID = template.projectID
        isPinned = template.isPinned
        assigneeMode = .self
        assignmentNote = ""
        projectSubtasks = []
        projectSubtaskInput = ""
        projectTargetDate = nil
        category = .task
        taskDate = anchorDate
        taskTime = template.hasExplicitTime ? template.time?.date(on: anchorDate, calendar: calendar) : nil
        taskReminderOffset = template.reminderOffset
        repeatRule = template.repeatRule
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

    private static func reminderTargetDate(for dueAt: Date, hasExplicitTime: Bool) -> Date {
        guard hasExplicitTime == false else { return dueAt }
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
    }

    private static func localizedMonthDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func localizedRelativeMonthDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天"
        }
        return localizedMonthDayText(date)
    }
}

struct ComposerTemplatePickerSheet: View {
    let templates: [TaskTemplate]
    let isLoading: Bool
    let onSelect: (TaskTemplate) -> Void
    let onDelete: (TaskTemplate) async -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取模板…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if templates.isEmpty {
                ContentUnavailableView(
                    "还没有可用模板",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("先在任务详情里把常用任务保存为模板。")
                )
            } else {
                List {
                    ForEach(templates) { template in
                        Button {
                            ComposerButtonHaptics.selection()
                            onSelect(template)
                        } label: {
                            ComposerTemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await onDelete(template)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.colors.surface)
            }
        }
    }
}

struct ComposerTemplateRow: View {
    let template: TaskTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(template.title)
                .font(AppTheme.typography.sized(18, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let notes = template.notes, notes.isEmpty == false {
                Text(notes)
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                templateBadge(title: "任务", systemImage: "square.stack.3d.up")
                if let time = template.time {
                    templateBadge(
                        title: String(format: "%02d:%02d", time.hour, time.minute),
                        systemImage: "clock"
                    )
                }
                if let reminderOffset = template.reminderOffset,
                   let preset = TaskEditorReminderPreset.preset(for: reminderOffset) {
                    templateBadge(title: preset.chipTitle, systemImage: "bell")
                }
                if template.isPinned {
                    templateBadge(title: "置顶", systemImage: "pin")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.colors.pillSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.colors.pillOutline.opacity(0.88), lineWidth: 1)
        }
    }

    private func templateBadge(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(11, weight: .bold))
            Text(title)
                .font(AppTheme.typography.sized(12, weight: .semibold))
        }
        .foregroundStyle(AppTheme.colors.body.opacity(0.78))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(AppTheme.colors.outline.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct ComposerPage: View {
    let category: ComposerCategory
    @Binding var draftState: ComposerDraftState
    let isPairMode: Bool
    let templates: [TaskTemplate]
    let isLoadingTemplates: Bool
    let onTemplatePicked: (TaskTemplate) -> Void
    let onTemplateDeleted: (TaskTemplate) async -> Void
    @Binding var focusedField: ComposerField?
    let focusCoordinator: ComposerTextInputFocusCoordinator
    var isPeriodicSubtaskMode: Bool = false
    var isProjectSubtaskMode: Bool = false

    var body: some View {
        Group {
            if category == .template {
                ComposerTemplatePickerSheet(
                    templates: templates,
                    isLoading: isLoadingTemplates,
                    onSelect: onTemplatePicked,
                    onDelete: onTemplateDeleted
                )
            } else {
                editorPage
            }
        }
    }

    private var editorPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerFocusableTextView(
                text: $draftState.title,
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .title,
                placeholder: category.titlePlaceholder,
                font: AppTheme.typography.sizedUIFont(30, weight: .bold),
                textColor: UIColor(AppTheme.colors.title),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.62)),
                maximumNumberOfLines: 3
            )

            if category == .task {
                ComposerSmartSuggestionBar(
                    title: draftState.title,
                    currentTime: draftState.taskTime,
                    currentRepeatRule: draftState.repeatRule,
                    currentDate: draftState.taskDate,
                    onSetTime: { time in
                        draftState.taskTime = time
                    },
                    onSetRepeatRule: { rule in
                        draftState.repeatRule = rule
                    },
                    onSetDate: { date in
                        draftState.taskDate = date
                    }
                )
            }

            ComposerFocusableTextView(
                text: $draftState.notes,
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .notes,
                placeholder: "添加备注...",
                font: AppTheme.typography.sizedUIFont(16, weight: .medium),
                textColor: UIColor(AppTheme.colors.body.opacity(0.78)),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.74)),
                maximumNumberOfLines: 8
            )

            if isPairMode, category != .project, category != .periodic {
                composerAssignmentSection
                    .padding(.top, 10)
            }

            if category == .periodic && isPeriodicSubtaskMode {
                ComposerPeriodicSubtasksInline(draftState: $draftState)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if category == .project && isProjectSubtaskMode {
                ComposerProjectSubtasksInline(draftState: $draftState)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var composerAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("归属给")
                .font(AppTheme.typography.sized(14, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))

            Picker("归属给", selection: $draftState.assigneeMode) {
                Text("自己").tag(TaskAssigneeMode.`self`)
                Text("对方").tag(TaskAssigneeMode.partner)
                Text("一起").tag(TaskAssigneeMode.both)
            }
            .pickerStyle(.segmented)

            if draftState.assigneeMode == .partner {
                TextField("补一句说明或留言", text: $draftState.assignmentNote, axis: .vertical)
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
        }
    }
}

private struct ComposerFocusableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: ComposerField?
    let focusCoordinator: ComposerTextInputFocusCoordinator
    let field: ComposerField
    let placeholder: String
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let maximumNumberOfLines: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerTextViewContainer {
        let container = ComposerTextViewContainer()
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

    func updateUIView(_ uiView: ComposerTextViewContainer, context: Context) {
        context.coordinator.parent = self
        focusCoordinator.register(uiView.textView, for: field)
        update(uiView, coordinator: context.coordinator)
        context.coordinator.syncFirstResponder(in: uiView.textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextViewContainer, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else {
            return uiView.intrinsicContentSize
        }
        return uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    }

    private func update(_ container: ComposerTextViewContainer, coordinator: Coordinator) {
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
        var parent: ComposerFocusableTextView

        init(parent: ComposerFocusableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let updated = textView.text ?? ""
            if parent.text != updated {
                parent.text = updated
            }
            if let container = textView.superview as? ComposerTextViewContainer {
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

private final class ComposerTextViewContainer: UIView {
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

private struct ComposerRenderedChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let menu: ComposerMenu
    let showsTrailingClear: Bool
    let transitionDirection: ComposerChipTextTransitionDirection
    let semanticValue: ComposerChipSemanticValue
}

private struct ComposerChipSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let menu: ComposerMenu
    let semanticValue: ComposerChipSemanticValue
    var showsTrailingClear = false
}

private enum ComposerChipTextTransitionDirection {
    case up
    case down

    var outgoingOffset: CGFloat {
        switch self {
        case .up:
            return -16
        case .down:
            return 16
        }
    }

    var incomingStartOffset: CGFloat {
        -outgoingOffset
    }
}

private enum ComposerChipSemanticValue: Equatable {
    case date(Date)
    case optionalDate(Date?)
    case time(Date?)
    case reminder(TimeInterval?)
    case repeatRule(title: String, rank: Int)

    static func direction(from oldValue: Self, to newValue: Self) -> ComposerChipTextTransitionDirection {
        switch (oldValue, newValue) {
        case let (.date(oldDate), .date(newDate)):
            return newDate >= oldDate ? .up : .down
        case let (.optionalDate(oldDate), .optionalDate(newDate)):
            return compare(oldDate, newDate)
        case let (.time(oldTime), .time(newTime)):
            return compare(oldTime, newTime)
        case let (.reminder(oldOffset), .reminder(newOffset)):
            return (newOffset ?? -.infinity) >= (oldOffset ?? -.infinity) ? .up : .down
        case let (.repeatRule(oldTitle, oldRank), .repeatRule(newTitle, newRank)):
            if newRank != oldRank {
                return newRank >= oldRank ? .up : .down
            }
            return newTitle.localizedCompare(oldTitle) == .orderedDescending ? .up : .down
        default:
            return .up
        }
    }

    private static func compare(_ oldDate: Date?, _ newDate: Date?) -> ComposerChipTextTransitionDirection {
        switch (oldDate, newDate) {
        case let (.some(oldDate), .some(newDate)):
            return newDate >= oldDate ? .up : .down
        case (.none, .some):
            return .up
        case (.some, .none):
            return .down
        case (.none, .none):
            return .up
        }
    }
}

private struct ComposerChipTextSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case numeric
        case text
    }

    let id: String
    let text: String
    let kind: Kind

    static func empty(id: String, kind: Kind) -> Self {
        Self(id: id, text: "", kind: kind)
    }

    func measuredWidth(using font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

private struct ComposerChipTextLayout: Equatable {
    let segments: [ComposerChipTextSegment]

    init(text: String, semanticValue: ComposerChipSemanticValue) {
        switch semanticValue {
        case let .date(date):
            segments = Self.dateSegments(for: date)
        case let .optionalDate(date):
            if let date {
                segments = Self.dateSegments(for: date)
            } else {
                segments = [ComposerChipTextSegment(id: "main", text: text, kind: .text)]
            }
        case let .time(date):
            segments = Self.timeSegments(for: date, placeholder: text)
        case .reminder, .repeatRule:
            segments = [ComposerChipTextSegment(id: "main", text: text, kind: .text)]
        }
    }

    func segment(id: String) -> ComposerChipTextSegment? {
        segments.first { $0.id == id }
    }

    func measuredWidth(using font: UIFont) -> CGFloat {
        segments.reduce(0) { partialResult, segment in
            partialResult + segment.measuredWidth(using: font)
        }
    }

    private static func dateSegments(for date: Date) -> [ComposerChipTextSegment] {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return [
                ComposerChipTextSegment(id: "relative", text: "今天", kind: .text),
                .empty(id: "monthTens", kind: .numeric),
                .empty(id: "monthOnes", kind: .numeric),
                .empty(id: "monthSuffix", kind: .text),
                .empty(id: "dayTens", kind: .numeric),
                .empty(id: "dayOnes", kind: .numeric),
                .empty(id: "daySuffix", kind: .text)
            ]
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return [
                ComposerChipTextSegment(id: "relative", text: "明天", kind: .text),
                .empty(id: "monthTens", kind: .numeric),
                .empty(id: "monthOnes", kind: .numeric),
                .empty(id: "monthSuffix", kind: .text),
                .empty(id: "dayTens", kind: .numeric),
                .empty(id: "dayOnes", kind: .numeric),
                .empty(id: "daySuffix", kind: .text)
            ]
        }

        let monthSegments = numberSegments(
            prefix: "month",
            value: calendar.component(.month, from: date),
            digits: 2,
            blankLeadingZero: true
        )
        let daySegments = numberSegments(
            prefix: "day",
            value: calendar.component(.day, from: date),
            digits: 2,
            blankLeadingZero: true
        )
        return [
            .empty(id: "relative", kind: .text),
            monthSegments[0],
            monthSegments[1],
            ComposerChipTextSegment(id: "monthSuffix", text: "月", kind: .text),
            daySegments[0],
            daySegments[1],
            ComposerChipTextSegment(id: "daySuffix", text: "日", kind: .text)
        ]
    }

    private static func timeSegments(for date: Date?, placeholder: String) -> [ComposerChipTextSegment] {
        guard let date else {
            return [
                ComposerChipTextSegment(id: "placeholder", text: placeholder, kind: .text),
                .empty(id: "hourTens", kind: .numeric),
                .empty(id: "hourOnes", kind: .numeric),
                .empty(id: "separator", kind: .text),
                .empty(id: "minuteTens", kind: .numeric),
                .empty(id: "minuteOnes", kind: .numeric)
            ]
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        let formatted = formatter.string(from: date)
        let components = formatted.split(separator: ":").map(String.init)
        let hour = Int(components.indices.contains(0) ? components[0] : "") ?? 0
        let minute = Int(components.indices.contains(1) ? components[1] : "") ?? 0
        let hourSegments = numberSegments(prefix: "hour", value: hour, digits: 2, blankLeadingZero: false)
        let minuteSegments = numberSegments(prefix: "minute", value: minute, digits: 2, blankLeadingZero: false)

        return [
            .empty(id: "placeholder", kind: .text),
            hourSegments[0],
            hourSegments[1],
            ComposerChipTextSegment(id: "separator", text: ":", kind: .text),
            minuteSegments[0],
            minuteSegments[1]
        ]
    }

    private static func numberSegments(
        prefix: String,
        value: Int,
        digits: Int,
        blankLeadingZero: Bool
    ) -> [ComposerChipTextSegment] {
        let formatted = String(format: "%0\(digits)d", value)
        return formatted.enumerated().map { index, character in
            let isLeadingZero = blankLeadingZero && index == 0 && character == "0"
            return ComposerChipTextSegment(
                id: "\(prefix)\(index)",
                text: isLeadingZero ? "" : String(character),
                kind: .numeric
            )
        }
    }
}

private struct ComposerAnimatedChipTitle: View {
    let text: String
    let semanticValue: ComposerChipSemanticValue
    let direction: ComposerChipTextTransitionDirection
    let font: Font
    let uiFont: UIFont

    @State private var displayedText: String
    @State private var displayedWidth: CGFloat
    @State private var transitionToken = UUID()

    init(
        text: String,
        semanticValue: ComposerChipSemanticValue,
        direction: ComposerChipTextTransitionDirection,
        font: Font,
        uiFont: UIFont
    ) {
        self.text = text
        self.semanticValue = semanticValue
        self.direction = direction
        self.font = font
        self.uiFont = uiFont
        _displayedText = State(initialValue: text)
        _displayedWidth = State(
            initialValue: Self.measuredWidth(
                text: text,
                semanticValue: semanticValue,
                using: uiFont
            )
        )
    }

    var body: some View {
        token(displayedText)
        .frame(width: displayedWidth, height: 22, alignment: .center)
        .frame(height: 22, alignment: .center)
        .clipped()
        .onChange(of: text) { oldValue, newValue in
            guard oldValue != newValue else { return }
            syncTransition(to: newValue)
        }
    }

    private func syncTransition(to newText: String) {
        let targetWidth = Self.measuredWidth(
            text: newText,
            semanticValue: semanticValue,
            using: uiFont
        )
        let token = UUID()
        transitionToken = token

        if targetWidth > displayedWidth {
            withAnimation(ComposerChipAnimation.layoutSpring) {
                displayedWidth = targetWidth
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + ComposerChipAnimation.widthExpansionLead) {
                guard transitionToken == token else { return }
                withAnimation(ComposerChipAnimation.textSpring) {
                    displayedText = newText
                }
            }
        } else {
            withAnimation(ComposerChipAnimation.textSpring) {
                displayedText = newText
            }
            withAnimation(ComposerChipAnimation.layoutSpring) {
                displayedWidth = targetWidth
            }
        }
    }

    @ViewBuilder
    private func token(_ value: String) -> some View {
        if value.isEmpty {
            Text("")
                .font(font)
                .lineLimit(1)
        } else {
            switch contentTransitionStyle {
            case .numeric:
                Text(value)
                    .font(font)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: direction == .down))
                    .lineLimit(1)
            case .interpolated:
                Text(value)
                    .font(font)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
            case .none:
                Text(value)
                    .font(font)
                    .lineLimit(1)
            }
        }
    }

    private var contentTransitionStyle: ComposerChipContentTransitionStyle {
        switch semanticValue {
        case .date, .optionalDate, .time:
            return .numeric
        case .reminder:
            return .numeric
        case .repeatRule:
            return .interpolated
        }
    }

    private static func measure(text: String, using font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private static func measuredWidth(
        text: String,
        semanticValue: ComposerChipSemanticValue,
        using font: UIFont
    ) -> CGFloat {
        let measuredFont = measuredFont(for: semanticValue, baseFont: font)
        return measure(text: text, using: measuredFont) + measurementPadding(for: semanticValue)
    }

    private static func measuredFont(
        for semanticValue: ComposerChipSemanticValue,
        baseFont: UIFont
    ) -> UIFont {
        guard usesNumericTransition(for: semanticValue) else { return baseFont }
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    private static func measurementPadding(for semanticValue: ComposerChipSemanticValue) -> CGFloat {
        usesNumericTransition(for: semanticValue) ? 8 : 6
    }

    private static func usesNumericTransition(for semanticValue: ComposerChipSemanticValue) -> Bool {
        switch semanticValue {
        case .date, .optionalDate, .time:
            return true
        case .reminder:
            return true
        case .repeatRule:
            return false
        }
    }
}

private enum ComposerChipContentTransitionStyle {
    case numeric
    case interpolated
    case none
}

private enum ComposerMenu: String, Identifiable {
    case date
    case time
    case reminder
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(ComposerDateMenuDetent.self)]
        case .time:
            return [.custom(TaskEditorTaskMenuDetent.self)]
        case .reminder, .repeatRule:
            return [.custom(TaskEditorTaskMenuDetent.self)]
        }
    }
}

private struct ComposerDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            ComposerDatePickerSheet.preferredHeight + TaskEditorUnifiedMenuMetrics.topBarHeight,
            context.maxDetentValue * 0.72
        )
    }
}

private struct ComposerEditorMenuSheet: View {
    let context: TaskEditorMenuContext
    @Binding var activeMenu: TaskEditorMenu
    @Binding var draftState: ComposerDraftState
    let quickTimePresetMinutes: [Int]
    let templates: [TaskTemplate]
    let isLoadingTemplates: Bool
    let onTemplatePicked: (TaskTemplate) -> Void
    let onTemplateDeleted: (TaskTemplate) async -> Void
    let disabledMenus: Set<TaskEditorMenu>
    let onDismiss: () -> Void

    @State private var stagedSelectedDate: Date
    @State private var stagedSelectedTime: Date?
    @State private var stagedReminderOffset: TimeInterval?
    @State private var stagedRepeatRule: ItemRepeatRule?

    @State private var didEditDate = false
    @State private var didEditTime = false
    @State private var didEditReminder = false
    @State private var didEditRepeatRule = false

    init(
        context: TaskEditorMenuContext,
        activeMenu: Binding<TaskEditorMenu>,
        draftState: Binding<ComposerDraftState>,
        quickTimePresetMinutes: [Int],
        templates: [TaskTemplate],
        isLoadingTemplates: Bool,
        onTemplatePicked: @escaping (TaskTemplate) -> Void,
        onTemplateDeleted: @escaping (TaskTemplate) async -> Void,
        disabledMenus: Set<TaskEditorMenu>,
        onDismiss: @escaping () -> Void
    ) {
        self.context = context
        _activeMenu = activeMenu
        _draftState = draftState
        self.quickTimePresetMinutes = quickTimePresetMinutes
        self.templates = templates
        self.isLoadingTemplates = isLoadingTemplates
        self.onTemplatePicked = onTemplatePicked
        self.onTemplateDeleted = onTemplateDeleted
        self.disabledMenus = disabledMenus
        self.onDismiss = onDismiss

        let currentDraft = draftState.wrappedValue
        let initialDate: Date
        let initialTime: Date?
        let initialReminder: TimeInterval?

        switch currentDraft.category {
        case .template:
            initialDate = currentDraft.taskDate
            initialTime = nil
            initialReminder = nil
        case .task:
            initialDate = currentDraft.taskDate
            initialTime = currentDraft.taskTime
            initialReminder = currentDraft.taskReminderOffset
        case .periodic:
            initialDate = currentDraft.taskDate
            initialTime = nil
            initialReminder = nil
        case .project:
            initialDate = currentDraft.projectTargetDate ?? currentDraft.taskDate
            initialTime = nil
            initialReminder = nil
        }

        _stagedSelectedDate = State(initialValue: initialDate)
        _stagedSelectedTime = State(initialValue: initialTime)
        _stagedReminderOffset = State(initialValue: initialReminder)
        _stagedRepeatRule = State(initialValue: currentDraft.repeatRule)
    }

    var body: some View {
        TaskEditorUnifiedMenuSheet(
            context: context,
            activeMenu: $activeMenu,
            disabledMenus: stagedDisabledMenus,
            selectionFeedback: ComposerButtonHaptics.selection,
            headerTitle: context == .templates ? "选择模板" : nil,
            switcherPlacement: .bottom,
            onClose: onDismiss,
            onSave: context == .templates ? onDismiss : applyChangesAndDismiss
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
                selectionFeedback: ComposerButtonHaptics.selection,
                onDismiss: {},
                dismissesOnSelection: false
            )
        case .time:
            TaskEditorTimePickerSheet(
                selectedTime: stagedTimeBinding,
                anchorDate: stagedSelectedDate,
                quickPresetMinutes: quickTimePresetMinutes,
                savesOnQuickPresetSelection: false,
                showsPrimaryButton: false,
                selectionFeedback: ComposerButtonHaptics.selection,
                primaryFeedback: ComposerButtonHaptics.primary,
                onTimeSaved: nil,
                onDismiss: {}
            )
        case .reminder:
            TaskEditorReminderOptionList(
                selectedOffset: stagedReminderOffset,
                selectionFeedback: ComposerButtonHaptics.selection,
                onSelect: { offset in
                    setReminder(offset)
                }
            )
        case .repeatRule:
            TaskEditorOptionList(
                options: repeatRuleMenuOptions,
                selectionFeedback: ComposerButtonHaptics.selection
            )
        case .subtasks:
            if draftState.category == .periodic {
                ComposerPeriodicSubtasksPanel(draftState: $draftState)
            } else {
                ComposerProjectSubtasksPanel(draftState: $draftState)
            }
        case .periodicReminder:
            ComposerPeriodicReminderPanel(draftState: $draftState)
        case .periodicCycle:
            ComposerPeriodicCyclePanel(draftState: $draftState)
        case .template:
            ComposerTemplatePickerSheet(
                templates: templates,
                isLoading: isLoadingTemplates,
                onSelect: onTemplatePicked,
                onDelete: onTemplateDeleted
            )
        }
    }

    private func applyChangesAndDismiss() {
        if didEditDate {
            switch draftState.category {
            case .template, .periodic:
                break
            case .task:
                draftState.taskDate = stagedSelectedDate
            case .project:
                draftState.projectTargetDate = stagedSelectedDate
            }
        }

        if didEditTime {
            switch draftState.category {
            case .template, .periodic:
                break
            case .task:
                draftState.taskTime = stagedSelectedTime
            case .project:
                break
            }
        }

        if didEditReminder {
            switch draftState.category {
            case .template, .periodic:
                break
            case .task:
                draftState.taskReminderOffset = stagedReminderOffset
            case .project:
                break
            }
        }

        if didEditRepeatRule, draftState.category == .task {
            draftState.repeatRule = stagedRepeatRule
        }

        onDismiss()
    }

    private var stagedReminderContext: TaskEditorStagedReminderContext {
        TaskEditorStagedReminderContext(
            selectedDate: stagedSelectedDate,
            selectedTime: stagedSelectedTime,
            reminderOffset: stagedReminderOffset
        )
    }

    private var stagedDisabledMenus: Set<TaskEditorMenu> {
        guard context == .task else { return disabledMenus }
        return stagedReminderContext.isReminderMenuDisabled ? [.reminder] : []
    }

    private var stagedDateBinding: Binding<Date> {
        Binding(
            get: { stagedSelectedDate },
            set: { newValue in
                stagedSelectedDate = newValue
                didEditDate = true
            }
        )
    }

    private var stagedTimeBinding: Binding<Date?> {
        Binding(
            get: { stagedSelectedTime },
            set: { newValue in
                stagedSelectedTime = newValue
                didEditTime = true
            }
        )
    }

    private var reminderMenuOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不提醒", isSelected: stagedReminderOffset == nil) {
            setReminder(nil)
        }] + TaskEditorReminderPreset.allCases.map { preset in
            TaskEditorOptionRow(
                title: preset.title,
                isSelected: stagedReminderOffset == preset.secondsBeforeTarget,
                action: {
                    setReminder(preset.secondsBeforeTarget)
                }
            )
        }
    }

    private var repeatRuleMenuOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(
            title: "不重复",
            isSelected: stagedRepeatRule == nil,
            action: {
                stagedRepeatRule = nil
                didEditRepeatRule = true
            }
        )] + TaskEditorRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: stagedSelectedDate)
            return TaskEditorOptionRow(
                title: title,
                isSelected: title == stagedRepeatRule?.title(anchorDate: stagedSelectedDate, calendar: .current),
                action: {
                    stagedRepeatRule = preset.makeRule(anchorDate: stagedSelectedDate)
                    didEditRepeatRule = true
                }
            )
        }
    }

    private func setReminder(_ seconds: TimeInterval?) {
        stagedReminderOffset = seconds
        didEditReminder = true
    }
}

private struct ComposerProjectSubtasksPanel: View {
    @Binding var draftState: ComposerDraftState
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !draftState.projectSubtasks.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(draftState.projectSubtasks) { subtask in
                            HStack(spacing: 12) {
                                Button {
                                    ComposerButtonHaptics.selection()
                                    draftState.toggleProjectSubtask(subtask.id)
                                } label: {
                                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(AppTheme.typography.sized(20, weight: .semibold))
                                        .foregroundStyle(subtask.isCompleted ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.42))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)

                                Text(subtask.title)
                                    .font(AppTheme.typography.sized(16, weight: .semibold))
                                    .foregroundStyle(AppTheme.colors.title.opacity(subtask.isCompleted ? 0.46 : 1))
                                    .strikethrough(subtask.isCompleted, color: AppTheme.colors.body.opacity(0.36))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    ComposerButtonHaptics.selection()
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                        draftState.removeProjectSubtask(subtask.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(AppTheme.typography.sized(11, weight: .bold))
                                        .foregroundStyle(AppTheme.colors.body.opacity(0.66))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(TaskEditorMenuOptionGlassModifier())
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: draftState.projectSubtasks)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 12) {
                TextField("添加子任务", text: $draftState.projectSubtaskInput)
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($isInputFocused)
                    .onSubmit { addSubtask() }

                Button("添加") { addSubtask() }
                    .buttonStyle(.plain)
                    .font(AppTheme.typography.sized(15, weight: .bold))
                    .foregroundStyle(draftState.projectSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.colors.body.opacity(0.4) : AppTheme.colors.title)
                    .disabled(draftState.projectSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AppTheme.colors.pillSurface))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AppTheme.colors.pillOutline, lineWidth: 1))
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if draftState.projectSubtasks.isEmpty {
                DispatchQueue.main.async { isInputFocused = true }
            }
        }
    }

    private func addSubtask() {
        ComposerButtonHaptics.primary()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            draftState.addProjectSubtask()
        }
        if draftState.projectSubtaskInput.isEmpty {
            isInputFocused = true
        }
    }
}

// MARK: - Periodic Subtasks Panel

private struct ComposerPeriodicSubtasksPanel: View {
    @Binding var draftState: ComposerDraftState
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !draftState.periodicSubtasks.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(draftState.periodicSubtasks) { subtask in
                            subtaskRow(subtask)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                    removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: draftState.periodicSubtasks)
            }

            addInputRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func subtaskRow(_ subtask: ProjectSubtaskDraft) -> some View {
        HStack(spacing: 12) {
            Button {
                ComposerButtonHaptics.selection()
                draftState.togglePeriodicSubtask(subtask.id)
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.typography.sized(20, weight: .semibold))
                    .foregroundStyle(subtask.isCompleted ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.42))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(AppTheme.typography.sized(16, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title.opacity(subtask.isCompleted ? 0.46 : 1))
                .strikethrough(subtask.isCompleted, color: AppTheme.colors.body.opacity(0.36))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                ComposerButtonHaptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    draftState.removePeriodicSubtask(subtask.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.66))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TaskEditorMenuOptionGlassModifier())
    }

    private var addInputRow: some View {
        HStack(spacing: 12) {
            TextField("添加子任务", text: $draftState.periodicSubtaskInput)
                .font(AppTheme.typography.sized(16, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit { addSubtask() }

            Button("添加") { addSubtask() }
                .buttonStyle(.plain)
                .font(AppTheme.typography.sized(15, weight: .bold))
                .foregroundStyle(
                    draftState.periodicSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AppTheme.colors.body.opacity(0.4)
                        : AppTheme.colors.title
                )
                .disabled(draftState.periodicSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AppTheme.colors.pillSurface))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(AppTheme.colors.pillOutline, lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private func addSubtask() {
        ComposerButtonHaptics.primary()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            draftState.addPeriodicSubtask()
        }
        if draftState.periodicSubtaskInput.isEmpty {
            isInputFocused = true
        }
    }
}

// MARK: - Periodic Subtasks Inline (embedded in editor body)

private struct ComposerPeriodicSubtasksInline: View {
    @Binding var draftState: ComposerDraftState
    @FocusState private var isInputFocused: Bool
    @FocusState private var focusedSubtaskID: UUID?
    @State private var editingSubtaskID: UUID?
    @State private var subtaskDraft = ""

    var body: some View {
        VStack(spacing: 6) {
            ForEach(draftState.periodicSubtasks) { subtask in
                subtaskRow(subtask)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                    ))
            }

            addInputRow
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: draftState.periodicSubtasks)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { isInputFocused = true }
        .onChange(of: draftState.periodicSubtasks) { _, subtasks in
            if let editingSubtaskID, !subtasks.contains(where: { $0.id == editingSubtaskID }) {
                self.editingSubtaskID = nil
                subtaskDraft = ""
            }
        }
    }

    @ViewBuilder
    private func subtaskRow(_ subtask: ProjectSubtaskDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                ComposerButtonHaptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    draftState.togglePeriodicSubtask(subtask.id)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(subtask.isCompleted ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.42))
            }
            .buttonStyle(.plain)

            if editingSubtaskID == subtask.id {
                TextField("", text: subtaskBinding(for: subtask), prompt: Text(subtask.title))
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focusedSubtaskID, equals: subtask.id)
                    .onSubmit { commitSubtask(subtask) }
                    .onChange(of: focusedSubtaskID) { _, focusedID in
                        if focusedID != subtask.id, editingSubtaskID == subtask.id {
                            commitSubtask(subtask)
                        }
                    }
            } else {
                Button {
                    ComposerButtonHaptics.selection()
                    editingSubtaskID = subtask.id
                    subtaskDraft = subtask.title
                    focusedSubtaskID = subtask.id
                } label: {
                    Text(subtask.title)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.title.opacity(subtask.isCompleted ? 0.46 : 0.92))
                        .strikethrough(subtask.isCompleted, color: AppTheme.colors.body.opacity(0.32))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                ComposerButtonHaptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    draftState.removePeriodicSubtask(subtask.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(AppTheme.typography.sized(10, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.46))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func subtaskBinding(for subtask: ProjectSubtaskDraft) -> Binding<String> {
        Binding(
            get: { editingSubtaskID == subtask.id ? subtaskDraft : subtask.title },
            set: { subtaskDraft = $0 }
        )
    }

    private func commitSubtask(_ subtask: ProjectSubtaskDraft) {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            editingSubtaskID = nil
            subtaskDraft = ""
            focusedSubtaskID = nil
        }
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        if let index = draftState.periodicSubtasks.firstIndex(where: { $0.id == subtask.id }) {
            draftState.periodicSubtasks[index].title = trimmed
        }
    }

    private var addInputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(AppTheme.typography.sized(17, weight: .semibold))
                .foregroundStyle(AppTheme.colors.coral.opacity(
                    draftState.periodicSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1
                ))

            TextField("添加子任务", text: $draftState.periodicSubtaskInput)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit { addSubtask() }
        }
        .padding(.vertical, 6)
    }

    private func addSubtask() {
        ComposerButtonHaptics.primary()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            draftState.addPeriodicSubtask()
        }
        isInputFocused = true
    }
}

// MARK: - Project Subtasks Inline (embedded in editor body)

private struct ComposerProjectSubtasksInline: View {
    @Binding var draftState: ComposerDraftState
    @FocusState private var isInputFocused: Bool
    @FocusState private var focusedSubtaskID: UUID?
    @State private var editingSubtaskID: UUID?
    @State private var subtaskDraft = ""

    var body: some View {
        VStack(spacing: 6) {
            ForEach(draftState.projectSubtasks) { subtask in
                subtaskRow(subtask)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                    ))
            }

            addInputRow
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: draftState.projectSubtasks)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { isInputFocused = true }
        .onChange(of: draftState.projectSubtasks) { _, subtasks in
            if let editingSubtaskID, !subtasks.contains(where: { $0.id == editingSubtaskID }) {
                self.editingSubtaskID = nil
                subtaskDraft = ""
            }
        }
    }

    @ViewBuilder
    private func subtaskRow(_ subtask: ProjectSubtaskDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                ComposerButtonHaptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    draftState.toggleProjectSubtask(subtask.id)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(subtask.isCompleted ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.42))
            }
            .buttonStyle(.plain)

            if editingSubtaskID == subtask.id {
                TextField("", text: subtaskBinding(for: subtask), prompt: Text(subtask.title))
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focusedSubtaskID, equals: subtask.id)
                    .onSubmit { commitSubtask(subtask) }
                    .onChange(of: focusedSubtaskID) { _, focusedID in
                        if focusedID != subtask.id, editingSubtaskID == subtask.id {
                            commitSubtask(subtask)
                        }
                    }
            } else {
                Button {
                    ComposerButtonHaptics.selection()
                    editingSubtaskID = subtask.id
                    subtaskDraft = subtask.title
                    focusedSubtaskID = subtask.id
                } label: {
                    Text(subtask.title)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.title.opacity(subtask.isCompleted ? 0.46 : 0.92))
                        .strikethrough(subtask.isCompleted, color: AppTheme.colors.body.opacity(0.32))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                ComposerButtonHaptics.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    draftState.removeProjectSubtask(subtask.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(AppTheme.typography.sized(10, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.46))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func subtaskBinding(for subtask: ProjectSubtaskDraft) -> Binding<String> {
        Binding(
            get: { editingSubtaskID == subtask.id ? subtaskDraft : subtask.title },
            set: { subtaskDraft = $0 }
        )
    }

    private func commitSubtask(_ subtask: ProjectSubtaskDraft) {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            editingSubtaskID = nil
            subtaskDraft = ""
            focusedSubtaskID = nil
        }
        guard !trimmed.isEmpty, trimmed != subtask.title else { return }
        if let index = draftState.projectSubtasks.firstIndex(where: { $0.id == subtask.id }) {
            draftState.projectSubtasks[index].title = trimmed
        }
    }

    private var addInputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(AppTheme.typography.sized(17, weight: .semibold))
                .foregroundStyle(AppTheme.colors.coral.opacity(
                    draftState.projectSubtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1
                ))

            TextField("添加子任务", text: $draftState.projectSubtaskInput)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit { addSubtask() }
        }
        .padding(.vertical, 6)
    }

    private func addSubtask() {
        ComposerButtonHaptics.primary()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            draftState.addProjectSubtask()
        }
        isInputFocused = true
    }
}

// MARK: - Periodic Cycle Panel

private struct ComposerPeriodicCyclePanel: View {
    @Binding var draftState: ComposerDraftState

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                    Button {
                        ComposerButtonHaptics.selection()
                        draftState.periodicCycle = cycle
                    } label: {
                        HStack {
                            Text(cycle.title)
                                .font(AppTheme.typography.sized(17, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer(minLength: 0)
                            if draftState.periodicCycle == cycle {
                                Image(systemName: "checkmark")
                                    .font(AppTheme.typography.sized(14, weight: .bold))
                                    .foregroundStyle(AppTheme.colors.coral)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: TaskEditorMenuOptionMetrics.height)
                        .padding(.horizontal, 18)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(TaskEditorMenuOptionButtonStyle())
                    .modifier(TaskEditorMenuOptionGlassModifier())
                }
            }
            .padding(TaskEditorMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Periodic Reminder Panel

private struct ComposerPeriodicReminderPanel: View {
    @Binding var draftState: ComposerDraftState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(draftState.periodicReminderRules.indices, id: \.self) { index in
                    RoutinesReminderRulePicker(
                        rule: $draftState.periodicReminderRules[index],
                        cycle: draftState.periodicCycle
                    )
                    .padding(.horizontal, 20)

                    if index < draftState.periodicReminderRules.count - 1 {
                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if draftState.periodicReminderRules.isEmpty {
                draftState.periodicReminderRules = [defaultRule(for: draftState.periodicCycle)]
            }
        }
    }

    private func defaultRule(for cycle: PeriodicCycle) -> PeriodicReminderRule {
        switch cycle {
        case .weekly:  PeriodicReminderRule(timing: .dayOfPeriod(3))
        case .monthly: PeriodicReminderRule(timing: .dayOfPeriod(20))
        case .quarterly: PeriodicReminderRule(timing: .daysBeforeEnd(14))
        case .yearly:  PeriodicReminderRule(timing: .daysBeforeEnd(30))
        }
    }
}

private struct ComposerMenuSheet: View {
    let menu: ComposerMenu
    @Binding var draftState: ComposerDraftState
    let quickTimePresetMinutes: [Int]
    let onDismiss: () -> Void

    var body: some View {
        menuContent
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menu {
        case .date:
            ComposerDatePickerSheet(draftState: $draftState, onDismiss: onDismiss)
        case .time:
            ComposerTimePickerSheet(
                draftState: $draftState,
                quickPresetMinutes: quickTimePresetMinutes,
                onDismiss: onDismiss
            )
        case .reminder:
            TaskEditorReminderOptionList(
                selectedOffset: draftState.taskReminderOffset,
                selectionFeedback: ComposerButtonHaptics.selection,
                onSelect: { offset in
                    setReminder(offset)
                }
            )
        case .repeatRule:
            optionList(
                options: RepeatPreset.allCases.map { preset in
                    let title = preset.title(anchorDate: draftState.taskDate)
                    return ComposerOptionRow(
                        title: title,
                        isSelected: title == draftState.repeatSummaryText,
                        action: {
                            draftState.repeatRule = preset.makeRule(anchorDate: draftState.taskDate)
                            onDismiss()
                        }
                    )
                }
            )
        }
    }

    private var reminderMenuOptions: [ComposerOptionRow] {
        [ComposerOptionRow(title: "不提醒", isSelected: draftState.reminderSummaryText(for: draftState.category) == "提醒") {
            setReminder(nil)
        }] + ReminderPreset.allCases.map { preset in
            ComposerOptionRow(
                title: preset.title,
                isSelected: draftState.reminderSummaryText(for: draftState.category) == preset.title,
                action: {
                    setReminder(preset.secondsBeforeTarget)
                }
            )
        }
    }

    private func optionList(options: [ComposerOptionRow]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        ComposerButtonHaptics.selection()
                        option.action()
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(AppTheme.typography.sized(17, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer(minLength: 0)
                            if option.isSelected {
                                Image(systemName: "checkmark")
                                    .font(AppTheme.typography.sized(14, weight: .bold))
                                .foregroundStyle(AppTheme.colors.coral)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: ComposerMenuOptionMetrics.height)
                        .padding(.horizontal, 18)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: ComposerMenuOptionMetrics.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(ComposerMenuOptionButtonStyle())
                    .modifier(ComposerMenuOptionGlassModifier())
                }
            }
            .padding(ComposerMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }

    private func setReminder(_ seconds: TimeInterval?) {
        switch draftState.category {
        case .template:
            break
        case .task:
            draftState.taskReminderOffset = seconds
        case .periodic:
            break
        case .project:
            break
        }
        onDismiss()
    }
}

private struct ComposerDatePickerSheet: View {
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

    @Binding var draftState: ComposerDraftState
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: CalendarMonthTransitionDirection = .forward

    init(draftState: Binding<ComposerDraftState>, onDismiss: @escaping () -> Void) {
        _draftState = draftState
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let initialDate: Date
        switch draftState.wrappedValue.category {
        case .template:
            initialDate = draftState.wrappedValue.taskDate
        case .task:
            initialDate = draftState.wrappedValue.taskDate
        case .periodic:
            initialDate = draftState.wrappedValue.taskDate
        case .project:
            initialDate = draftState.wrappedValue.projectTargetDate ?? draftState.wrappedValue.taskDate
        }

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
                            ComposerButtonHaptics.selection()
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
                                ComposerButtonHaptics.selection()
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
        Array(
            repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing),
            count: 7
        )
    }

    private func headerHorizontalInset(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(availableWidth - (Self.horizontalPadding * 2), 0)
        let columnWidth = max((gridWidth - (Self.gridColumnSpacing * 6)) / 7, 0)
        let firstColumnCenterX = Self.horizontalPadding + (columnWidth / 2)
        let visualDayHalfWidth = min(widestDayLabelWidth, columnWidth) / 2

        // Keep the header aligned to the date glyph envelope rather than the raw
        // grid edge so month text and trailing controls track the first/last
        // visible day labels across device widths and font changes.
        return max(firstColumnCenterX - visualDayHalfWidth, Self.horizontalPadding)
    }

    private var selectedDate: Date {
        switch draftState.category {
        case .template:
            return draftState.taskDate
        case .task:
            return draftState.taskDate
        case .periodic:
            return draftState.taskDate
        case .project:
            return draftState.projectTargetDate ?? draftState.taskDate
        }
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

    private var calendarGridHeight: CGFloat {
        Self.calendarGridHeight
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

    private var monthCells: [CalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [CalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                CalendarDayCell(
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
        ComposerButtonHaptics.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        switch draftState.category {
        case .template:
            draftState.taskDate = normalized
        case .task:
            draftState.taskDate = normalized
        case .periodic:
            draftState.taskDate = normalized
        case .project:
            draftState.projectTargetDate = normalized
        }
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: CalendarDayCell) -> Color {
        if isSelected(cell.date) {
            return .white
        }
        if isToday(cell.date) {
            return AppTheme.colors.coral
        }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }

}

private struct ComposerTimePickerSheet: View {
    @Binding var draftState: ComposerDraftState
    let quickPresetMinutes: [Int]
    let onDismiss: () -> Void
    @State private var selectedTime: Date

    init(
        draftState: Binding<ComposerDraftState>,
        quickPresetMinutes: [Int],
        onDismiss: @escaping () -> Void
    ) {
        _draftState = draftState
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.onDismiss = onDismiss
        let baseTime = draftState.wrappedValue.taskTime
            ?? Self.roundedTimeSeed(for: draftState.wrappedValue.taskDate)
            ?? draftState.wrappedValue.taskDate
        _selectedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickPresetMinutes, id: \.self) { minutes in
                    Button {
                        ComposerButtonHaptics.selection()
                        applyQuickPreset(minutes)
                    } label: {
                        Text(relativePresetTitle(minutes))
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(ComposerMenuOptionButtonStyle())
                    .modifier(ComposerMenuOptionGlassModifier())
                }
            }
            .padding(.top, ComposerTimePickerMetrics.verticalInset)
            .padding(.horizontal, ComposerMenuOptionMetrics.outerInset)
            .padding(.bottom, ComposerTimePickerMetrics.contentSpacing)

            TaskEditorSingleColumnTimeWheel(
                selection: $selectedTime,
                minuteInterval: 5
            )
            .frame(maxWidth: .infinity)
            .frame(height: ComposerTimePickerMetrics.pickerHeight)
            .clipped()
            .padding(.bottom, ComposerTimePickerMetrics.contentSpacing)

            HStack {
                Button {
                    ComposerButtonHaptics.primary()
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
                    .frame(minHeight: ComposerMenuOptionMetrics.height)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: ComposerMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(ComposerMenuOptionButtonStyle())
                .modifier(ComposerMenuOptionGlassModifier())
            }
            .padding(.horizontal, ComposerMenuOptionMetrics.outerInset)
            .padding(.bottom, ComposerTimePickerMetrics.verticalInset)
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
        let presetTime = Self.offsetTimeSeed(minutesFromNow: minutes, for: draftState.taskDate)
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
        draftState.taskTime = value ?? selectedTime
        onDismiss()
    }
}

private struct ComposerMinuteIntervalWheelPicker: UIViewRepresentable {
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
        var parent: ComposerMinuteIntervalWheelPicker
        var hasAppeared = false

        init(_ parent: ComposerMinuteIntervalWheelPicker) {
            self.parent = parent
        }

        @objc func didChange(_ sender: UIDatePicker) {
            parent.selection = ComposerMinuteIntervalWheelPicker.rounded(
                sender.date,
                minuteInterval: parent.minuteInterval
            )
        }
    }
}

private struct ComposerOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private enum ReminderPreset: CaseIterable, Identifiable {
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

    static func preset(for secondsBeforeTarget: TimeInterval) -> ReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum RepeatPreset: CaseIterable, Identifiable {
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

private struct ComposerChipSurfaceModifier: ViewModifier {
    let animationID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .matchedGeometryEffect(
                        id: "composer.chip.\(animationID)",
                        in: namespace
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            }
    }
}

private struct ComposerMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: ComposerMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: ComposerMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ComposerMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct ComposerMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum ComposerMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

private enum ComposerTimePickerMetrics {
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 214
}

private enum ComposerField: Hashable {
    case title
    case notes
}

@MainActor
private enum ComposerButtonHaptics {
    private static let selectionGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let primaryGenerator = UIImpactFeedbackGenerator(style: .light)

    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.impactOccurred(intensity: 0.9)
    }

    static func primary() {
        primaryGenerator.prepare()
        primaryGenerator.impactOccurred(intensity: 0.96)
    }
}

private enum ComposerChipAnimation {
    static let textSpring = Animation.easeInOut(duration: 0.7)
    static let layoutSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let textDuration: TimeInterval = 0.72
    static let segmentDelayStep: TimeInterval = 0.14
    static let maximumSegmentDelay: TimeInterval = 0.56
    static let widthExpansionLead: TimeInterval = 0.12
}

private enum ComposerMenuAnimation {
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
private final class ComposerTextInputFocusCoordinator {
    weak var titleTextView: UITextView?
    weak var notesTextView: UITextView?
    private(set) var currentFocusedField: ComposerField?
    private var pendingFocusField: ComposerField?

    var isTransitioningFocus: Bool {
        pendingFocusField != nil
    }

    func register(_ textView: UITextView, for field: ComposerField) {
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

    func prepareFocusTransition(to field: ComposerField) {
        pendingFocusField = field
    }

    func markDidBeginEditing(_ field: ComposerField) {
        currentFocusedField = field
        pendingFocusField = nil
    }

    func markDidEndEditing(_ field: ComposerField) {
        if currentFocusedField == field {
            currentFocusedField = nil
        }
    }

    func requestFocus(for field: ComposerField) {
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

private struct CalendarDayCell: Identifiable {
    let id = UUID()
    let date: Date
    let isInDisplayedMonth: Bool
}

private enum CalendarMonthTransitionDirection {
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

private struct ComposerMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .presentationSizing(.page)
        } else {
            content
        }
    }
}
