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

    init(route: ComposerRoute, appContext: AppContext, initialTitle: String? = nil) {
        self.route = route
        self.appContext = appContext
        self.initialTitle = initialTitle
        let initialDraft = ComposerDraftState(
            initialCategory: route == .newProject ? .project : .task,
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
                    focusedField: $focusedField,
                    focusCoordinator: focusCoordinator
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
        .sheet(item: $activeMenu) { menu in
            ComposerEditorMenuSheet(
                menu: menu,
                draftState: $draftState,
                quickTimePresetMinutes: NotificationSettings.normalizedQuickTimePresetMinutes(
                    appContext.sessionStore.currentUser?.preferences.quickTimePresetMinutes
                    ?? NotificationSettings.defaultQuickTimePresetMinutes
                ),
                onDismiss: dismissActiveMenu
            )
            .presentationDetents(menu.detents)
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.enabled)
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
            .modifier(TaskEditorMenuPresentationSizingModifier())
            .onDisappear {
                restoreKeyboardFocusIfNeeded(preferImmediateResponder: true)
                playPendingChipUpdatesIfNeeded()
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
                HStack(alignment: .center, spacing: 12) {
                    chipRow(trailingInset: 0)
                }

                if draftState.hasMeaningfulContent {
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
            Task {
                await save()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))

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
        .scaleEffect(isSaving ? 0.98 : 1)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }

    private func chipRow(trailingInset: CGFloat) -> some View {
        TaskEditorChipRow(
            chips: chipsForCurrentCategory,
            namespace: chipRowNamespace,
            trailingInset: trailingInset,
            onChipTap: { menu in
                ComposerButtonHaptics.selection()
                openMenu(menu)
            },
            onClearTap: { chip in
                ComposerButtonHaptics.selection()
                clearChipValue(chip)
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
        case .periodic:
            return [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.repeatRule.rawValue,
                    title: draftState.repeatSummaryText,
                    systemImage: "arrow.triangle.2.circlepath",
                    menu: .repeatRule,
                    semanticValue: .repeatRule(
                        title: draftState.repeatSummaryText,
                        rank: draftState.repeatRule.animationRank
                    )
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.reminder.rawValue,
                    title: draftState.reminderSummaryText(for: .periodic),
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(draftState.periodicReminderOffset)
                )
            ]
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
                    id: TaskEditorMenu.priority.rawValue,
                    title: draftState.priority.title,
                    systemImage: "flag",
                    menu: .priority,
                    semanticValue: .priority(draftState.priority.animationRank)
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
                    id: TaskEditorMenu.reminder.rawValue,
                    title: draftState.reminderSummaryText(for: .project),
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(draftState.projectReminderOffset)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.priority.rawValue,
                    title: draftState.priority.title,
                    systemImage: "flag",
                    menu: .priority,
                    semanticValue: .priority(draftState.priority.animationRank)
                )
            ]
        }
    }

    private func playPendingChipUpdatesIfNeeded() {
        guard let pendingChipSnapshots else { return }
        applyRenderedChips(pendingChipSnapshots, animated: true)
        self.pendingChipSnapshots = nil
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
    private var addButtonTitle: String {
        draftState.category == .project ? "创建" : "添加"
    }

    private func openMenu(_ menu: TaskEditorMenu) {
        lastFocusedFieldBeforeMenu = focusedField
        focusCoordinator.resignCurrentResponder()
        focusedField = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withTransaction(ComposerMenuAnimation.presentationTransaction) {
                activeMenu = menu
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
            case .periodic, .task:
                _ = try await appContext.container.taskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: draftState.taskDraft()
                )
                await appContext.homeViewModel.reload()
            case .project:
                _ = try await appContext.container.projectRepository.saveProject(
                    draftState.projectDraft(spaceID: spaceID)
                )
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
    case periodic
    case task
    case project

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .periodic:
            return "周期性"
        case .task:
            return "任务"
        case .project:
            return "项目"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .periodic:
            return "周期性标题"
        case .task:
            return "任务标题"
        case .project:
            return "项目标题"
        }
    }
}

private struct ComposerDraftState: Hashable {
    var category: ComposerCategory
    var title = ""
    var notes = ""
    var taskDate: Date
    var taskTime: Date?
    var periodicAnchorDate: Date
    var projectTargetDate: Date?
    var priority: ItemPriority = .normal
    var periodicReminderOffset: TimeInterval?
    var taskReminderOffset: TimeInterval?
    var projectReminderOffset: TimeInterval?
    var repeatRule: ItemRepeatRule

    init(initialCategory: ComposerCategory, referenceDate: Date) {
        self.category = initialCategory
        let calendar = Calendar.current
        self.taskDate = calendar.startOfDay(for: referenceDate)
        self.periodicAnchorDate = calendar.startOfDay(for: referenceDate)
        self.repeatRule = ItemRepeatRule(frequency: .daily)
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
        repeatRule.title(anchorDate: periodicAnchorDate, calendar: .current)
    }

    func reminderSummaryText(for category: ComposerCategory) -> String {
        let offset: TimeInterval?
        switch category {
        case .periodic:
            offset = periodicReminderOffset
        case .task:
            offset = taskReminderOffset
        case .project:
            offset = projectReminderOffset
        }

        guard let offset else { return "提醒" }
        return ReminderPreset.preset(for: offset)?.chipTitle ?? "提醒"
    }

    func taskDraft() -> TaskDraft {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch category {
        case .periodic:
            let anchorTime = Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: periodicAnchorDate
            ) ?? periodicAnchorDate
            let remindAt = periodicReminderOffset.map { anchorTime.addingTimeInterval(-$0) }
            return TaskDraft(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueAt: anchorTime,
                hasExplicitTime: false,
                remindAt: remindAt,
                priority: priority,
                repeatRule: repeatRule
            )
        case .task:
            let mergedDate = taskTime.map { Self.merge(date: taskDate, timeSource: $0) }
            let fallbackDate = Calendar.current.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: taskDate
            ) ?? taskDate
            let dueAt = mergedDate ?? fallbackDate
            let remindAt = taskReminderOffset.map { dueAt.addingTimeInterval(-$0) }
            return TaskDraft(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueAt: dueAt,
                hasExplicitTime: taskTime != nil,
                remindAt: remindAt,
                priority: priority
            )
        case .project:
            return TaskDraft(title: title, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        }
    }

    func projectDraft(spaceID: UUID) -> Project {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDate = projectTargetDate
        let remindAt = projectReminderOffset.flatMap { offset in
            targetDate?.addingTimeInterval(-offset)
        }

        return Project(
            id: UUID(),
            spaceID: spaceID,
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            colorToken: "graphite",
            status: .active,
            targetDate: targetDate,
            remindAt: remindAt,
            priority: priority,
            taskCount: 0,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil
        )
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

private struct ComposerPage: View {
    let category: ComposerCategory
    @Binding var draftState: ComposerDraftState
    @Binding var focusedField: ComposerField?
    let focusCoordinator: ComposerTextInputFocusCoordinator

    var body: some View {
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    case priority(Int)
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
        case let (.priority(oldRank), .priority(newRank)):
            return newRank >= oldRank ? .up : .down
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
        case .reminder, .priority, .repeatRule:
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
        case .priority, .repeatRule:
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
        case .priority, .repeatRule:
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
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(ComposerDateMenuDetent.self)]
        case .time:
            return [.fraction(0.5)]
        case .reminder, .priority, .repeatRule:
            return [.fraction(0.46)]
        }
    }
}

private struct ComposerDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            ComposerDatePickerSheet.preferredHeight + 12,
            context.maxDetentValue * 0.72
        )
    }
}

private struct ComposerEditorMenuSheet: View {
    let menu: TaskEditorMenu
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
            TaskEditorDatePickerSheet(
                selectedDate: selectedDateBinding,
                selectionFeedback: ComposerButtonHaptics.selection,
                onDismiss: onDismiss
            )
        case .time:
            TaskEditorTimePickerSheet(
                selectedTime: $draftState.taskTime,
                anchorDate: draftState.taskDate,
                quickPresetMinutes: quickTimePresetMinutes,
                selectionFeedback: ComposerButtonHaptics.selection,
                primaryFeedback: ComposerButtonHaptics.primary,
                onDismiss: onDismiss
            )
        case .reminder:
            TaskEditorOptionList(
                options: reminderMenuOptions,
                selectionFeedback: ComposerButtonHaptics.selection
            )
        case .priority:
            TaskEditorOptionList(
                options: ItemPriority.allCases.map { priority in
                    TaskEditorOptionRow(
                        title: priority.title,
                        isSelected: draftState.priority == priority,
                        action: {
                            draftState.priority = priority
                            onDismiss()
                        }
                    )
                },
                selectionFeedback: ComposerButtonHaptics.selection
            )
        case .repeatRule:
            TaskEditorOptionList(
                options: TaskEditorRepeatPreset.allCases.map { preset in
                    let title = preset.title(anchorDate: draftState.periodicAnchorDate)
                    return TaskEditorOptionRow(
                        title: title,
                        isSelected: title == draftState.repeatSummaryText,
                        action: {
                            draftState.repeatRule = preset.makeRule(anchorDate: draftState.periodicAnchorDate)
                            onDismiss()
                        }
                    )
                },
                selectionFeedback: ComposerButtonHaptics.selection
            )
        }
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: {
                switch draftState.category {
                case .periodic:
                    return draftState.periodicAnchorDate
                case .task:
                    return draftState.taskDate
                case .project:
                    return draftState.projectTargetDate ?? draftState.taskDate
                }
            },
            set: { newValue in
                switch draftState.category {
                case .periodic:
                    draftState.periodicAnchorDate = newValue
                case .task:
                    draftState.taskDate = newValue
                case .project:
                    draftState.projectTargetDate = newValue
                }
            }
        )
    }

    private var reminderMenuOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不提醒", isSelected: draftState.reminderSummaryText(for: draftState.category) == "提醒") {
            setReminder(nil)
        }] + TaskEditorReminderPreset.allCases.map { preset in
            TaskEditorOptionRow(
                title: preset.title,
                isSelected: draftState.reminderSummaryText(for: draftState.category) == preset.title,
                action: {
                    setReminder(preset.secondsBeforeTarget)
                }
            )
        }
    }

    private func setReminder(_ seconds: TimeInterval?) {
        switch draftState.category {
        case .periodic:
            draftState.periodicReminderOffset = seconds
        case .task:
            draftState.taskReminderOffset = seconds
        case .project:
            draftState.projectReminderOffset = seconds
        }
        onDismiss()
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
            optionList(
                options: reminderMenuOptions
            )
        case .priority:
            optionList(
                options: ItemPriority.allCases.map { priority in
                    ComposerOptionRow(
                        title: priority.title,
                        isSelected: draftState.priority == priority,
                        action: {
                            draftState.priority = priority
                            onDismiss()
                        }
                    )
                }
            )
        case .repeatRule:
            optionList(
                options: RepeatPreset.allCases.map { preset in
                    let title = preset.title(anchorDate: draftState.periodicAnchorDate)
                    return ComposerOptionRow(
                        title: title,
                        isSelected: title == draftState.repeatSummaryText,
                        action: {
                            draftState.repeatRule = preset.makeRule(anchorDate: draftState.periodicAnchorDate)
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
        case .periodic:
            draftState.periodicReminderOffset = seconds
        case .task:
            draftState.taskReminderOffset = seconds
        case .project:
            draftState.projectReminderOffset = seconds
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
        case .periodic:
            initialDate = draftState.wrappedValue.periodicAnchorDate
        case .task:
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
        case .periodic:
            return draftState.periodicAnchorDate
        case .task:
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
        case .periodic:
            draftState.periodicAnchorDate = normalized
        case .task:
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
