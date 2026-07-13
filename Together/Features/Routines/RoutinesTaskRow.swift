import SwiftUI

enum RoutineInlineFocusTarget: Hashable {
    case title
    case notes
    case detail

    func anchorID(for taskID: UUID) -> String {
        switch self {
        case .title: "routine-inline-title-\(taskID.uuidString)"
        case .notes: "routine-inline-notes-\(taskID.uuidString)"
        case .detail: "routine-inline-detail-\(taskID.uuidString)"
        }
    }

    var scrollAnchor: UnitPoint {
        switch self {
        case .title: .center
        case .notes, .detail: .center
        }
    }
}

enum RoutineInlineLayoutMetrics {
    static let actionSlotWidth: CGFloat = 40
    static let titleGap: CGFloat = AppTheme.spacing.md
    static let titleLeadingInset = actionSlotWidth + titleGap
    static let rowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 32
    static let detailVerticalSpacing: CGFloat = 2
    static let attributeMinHeight: CGFloat = AdaptiveTaskAttributeToolbarLayout.rowHeight
    static let detailTopPadding: CGFloat = AppTheme.spacing.xxs
    static let detailBottomPadding: CGFloat = AppTheme.spacing.xxs

    static func estimatedDetailHeight(showsAddNote: Bool) -> CGFloat {
        let visibleRowCount = showsAddNote ? 2 : 1
        let rowHeights = attributeMinHeight + (showsAddNote ? compactRowMinHeight : 0)
        let spacings = CGFloat(max(visibleRowCount - 1, 0)) * detailVerticalSpacing
        return detailTopPadding + rowHeights + spacings + detailBottomPadding
    }
}

struct RoutinesTaskRow: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let animationBatch: Int
    let onOpenDetail: () -> Void
    let onToggleCompletion: () -> Void
    let onInlineFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
    @State private var isEditingNotes = false
    @State private var isCommittingNotes = false
    @State private var isAnimatingCompletion = false
    @State private var completionAnimationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var badgeFillScale: CGFloat = 1
    @State private var badgeFillOpacity: CGFloat = 0

    private var isCompleted: Bool {
        viewModel.isCompleted(task)
    }

    private var urgency: PeriodicTaskUrgency {
        viewModel.urgencyState(task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            if isDetailPresented {
                RoutinesInlineDetailView(
                    task: task,
                    viewModel: viewModel,
                    isExpanded: isDetailExpanded,
                    animationBatch: animationBatch,
                    showsAddNote: visibleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isEditingNotes == false,
                    onAddNote: beginNotesEditing,
                    onFocus: onInlineFocus
                )
                .id(RoutineInlineFocusTarget.detail.anchorID(for: task.id))
            }
        }
        .animation(detailAnimation, value: isDetailPresented)
        .onAppear {
            titleDraft = draftTitle
            notesDraft = visibleNotes
        }
        .onChange(of: draftTitle) { _, title in
            guard isTitleFocused == false, isEditingTitle == false else { return }
            titleDraft = title
        }
        .onChange(of: visibleNotes) { _, notes in
            guard isNotesFocused == false, isEditingNotes == false else { return }
            notesDraft = notes
        }
        .onChange(of: isDetailExpanded) { _, expanded in
            guard expanded == false else { return }
            if isEditingTitle || isTitleFocused {
                commitTitleAfterFocusUpdate()
            }
            if isEditingNotes || isNotesFocused {
                commitNotesAfterFocusUpdate()
            }
        }
        .onChange(of: isCompleted) { _, completed in
            guard completed else { return }
            triggerCompletionAnimation()
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            completionButton

            ZStack(alignment: .topLeading) {
                stableTitleStack

                if isDetailPresented == false {
                    Button {
                        onOpenDetail()
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("展开例行任务")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionButton: some View {
        Button {
            if isCompleted {
                HomeInteractionFeedback.selection()
            } else {
                HomeInteractionFeedback.completion()
                if isDetailPresented {
                    triggerCompletionAnimation()
                }
            }
            onToggleCompletion()
        } label: {
            completionBadge
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isCompleted ? "标记为未完成" : "完成例行任务")
    }

    @ViewBuilder
    private var stableTitleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            if isDetailPresented, isEditingTitle {
                expandedTitleEditor
            } else {
                Button {
                    if isDetailPresented {
                        beginTitleEditing()
                    } else {
                        onOpenDetail()
                    }
                } label: {
                    titleText(isDetailPresented ? draftTitle : task.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isDetailPresented)
                .accessibilityHidden(isDetailPresented == false)
                .accessibilityLabel("编辑例行任务标题")
            }

            if isDetailPresented {
                subtitleContent
            } else {
                subtitleText(rowDisplayText.primarySubtitle)
            }

            if let propertyText = rowDisplayText.propertyText {
                subtitleText(propertyText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var subtitleContent: some View {
        if isEditingNotes {
            HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                TextField("添加备注", text: $notesDraft, axis: .vertical)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($isNotesFocused)
                    .id(RoutineInlineFocusTarget.notes.anchorID(for: task.id))
                    .onChange(of: isNotesFocused) { _, focused in
                        if focused {
                            onInlineFocus(.notes)
                        } else if isEditingNotes, isCommittingNotes == false {
                            commitNotesAfterFocusUpdate()
                        }
                    }

                inlineSaveButton(accessibilityLabel: "保存例行任务备注") {
                    commitNotesAfterFocusUpdate()
                }
            }
        } else if visibleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Button(action: beginNotesEditing) {
                subtitleText(rowDisplayText.primarySubtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑例行任务备注")
        } else {
            subtitleText(rowDisplayText.primarySubtitle)
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.typography.sized(15, weight: .medium))
            .foregroundStyle(subtitleColor)
            .lineLimit(2)
    }

    private var rowDisplayText: RoutineTaskDisplayText {
        let trimmedNotes = visibleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNotes.isEmpty ? nil : trimmedNotes
        let target = visibleTargetText
        return RoutineTaskDisplayText(
            primarySubtitle: note ?? (target.isEmpty ? (isCompleted ? "已完成" : "进行中") : target),
            propertyText: note != nil && target.isEmpty == false ? target : nil
        )
    }

    private var visibleNotes: String {
        isDetailPresented ? (viewModel.detailDraft?.notes ?? "") : (task.notes ?? "")
    }

    private var visibleTargetText: String {
        guard isDetailPresented, let draft = viewModel.detailDraft else {
            return RoutineTaskPropertyText.text(for: task)
        }
        guard let rule = draft.reminderRules.first else { return "" }
        return RoutineTaskPropertyText.text(for: rule, cycle: draft.cycle)
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.typography.sized(19, weight: .bold))
            .foregroundStyle(isCompleted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .allowsTightening(true)
    }

    private var expandedTitleEditor: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            TextField("例行任务标题", text: $titleDraft)
                .font(AppTheme.typography.sized(19, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .focused($isTitleFocused)
                .onSubmit {
                    commitTitleAfterFocusUpdate()
                }
                .id(RoutineInlineFocusTarget.title.anchorID(for: task.id))
                .onChange(of: isTitleFocused) { _, focused in
                    if focused {
                        onInlineFocus(.title)
                    } else if isEditingTitle, isCommittingTitle == false {
                        commitTitleAfterFocusUpdate()
                    }
                }

            inlineSaveButton(accessibilityLabel: "保存例行任务标题") {
                commitTitleAfterFocusUpdate()
            }
        }
    }

    private func beginTitleEditing() {
        titleDraft = draftTitle
        isEditingTitle = true
        onInlineFocus(.title)
        Task { @MainActor in
            await Task.yield()
            isTitleFocused = true
        }
    }

    private func commitTitleAfterFocusUpdate() {
        guard isEditingTitle || isTitleFocused else { return }
        isCommittingTitle = true
        Task { @MainActor in
            titleDraft = TextInputSnapshotReader.resolvedText(fallback: titleDraft)
            isTitleFocused = false
            await Task.yield()
            let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                viewModel.updateDraftTitle(trimmed)
                titleDraft = trimmed
            } else {
                titleDraft = draftTitle
            }
            isEditingTitle = false
            isCommittingTitle = false
        }
    }

    private func beginNotesEditing() {
        notesDraft = visibleNotes
        isEditingNotes = true
        onInlineFocus(.notes)
        Task { @MainActor in
            await Task.yield()
            isNotesFocused = true
        }
    }

    private func commitNotesAfterFocusUpdate() {
        guard isEditingNotes || isNotesFocused else { return }
        guard isCommittingNotes == false else { return }
        isCommittingNotes = true
        Task { @MainActor in
            notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
            isNotesFocused = false
            await Task.yield()
            viewModel.updateDraftNotes(notesDraft)
            isEditingNotes = false
            isCommittingNotes = false
        }
    }

    private func inlineSaveButton(
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label("保存", systemImage: "checkmark")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(minWidth: 54, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var draftTitle: String {
        isDetailPresented ? (viewModel.detailDraft?.title ?? task.title) : task.title
    }

    private var subtitleColor: Color {
        AppTheme.colors.body.opacity(isCompleted ? 0.4 : 0.74)
    }

    private var detailAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .snappy(duration: 0.28, extraBounce: 0.02)
    }

    // MARK: - Completion badge

    private var completionBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(isCompleted ? 0 : badgeFillOpacity)

            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: isAnimatingCompletion ? 1.8 : 1.6, dash: [3.6, 4.4])
                )
                .opacity(isCompleted ? 0 : 1)

            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(17, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.15), value: completionAnimationCount)
                .opacity(isCompleted ? 1 : 0)
                .offset(
                    x: AppTheme.metrics.checkmarkVisualOffset.width,
                    y: AppTheme.metrics.checkmarkVisualOffset.height
                )
        }
        .scaleEffect(isAnimatingCompletion ? badgeScale : 1)
        .shadow(
            color: AppTheme.colors.coral.opacity(isAnimatingCompletion ? 0.2 : 0),
            radius: isAnimatingCompletion ? 12 : 0,
            y: isAnimatingCompletion ? 5 : 0
        )
    }

    private var ringColor: Color {
        if isAnimatingCompletion {
            return AppTheme.colors.body.opacity(0.32)
        }
        return AppTheme.colors.body.opacity(0.44)
    }

    private func triggerCompletionAnimation() {
        completionAnimationCount += 1
        isAnimatingCompletion = true
        badgeScale = 1
        badgeFillScale = 1
        badgeFillOpacity = 0

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.16)) {
                badgeFillOpacity = 0
            }
            isAnimatingCompletion = false
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            badgeScale = 1.22
            badgeFillScale = 1.4
            badgeFillOpacity = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                badgeScale = 1
                badgeFillOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(350))
            isAnimatingCompletion = false
            badgeFillScale = 1
        }
    }
}

private struct RoutinesInlineDetailView: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isExpanded: Bool
    let animationBatch: Int
    let showsAddNote: Bool
    let onAddNote: () -> Void
    let onFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAttributeEditor: InlineAttributeEditor?

    var body: some View {
        RoutineInlineCascadeStack(
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion,
            fallbackHeight: RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: showsAddNote)
        ) {
            VStack(alignment: .leading, spacing: RoutineInlineLayoutMetrics.detailVerticalSpacing) {
                if showsAddNote {
                    notesPlaceholderButton
                        .modifier(cascadeItem(index: 0))
                }

                attributeToolbar
                    .modifier(cascadeItem(index: showsAddNote ? 1 : 0))

            }
            .padding(.top, RoutineInlineLayoutMetrics.detailTopPadding)
            .padding(.bottom, RoutineInlineLayoutMetrics.detailBottomPadding)
        }
    }

    private func cascadeItem(index: Int) -> RoutineInlineCascadeItemModifier {
        RoutineInlineCascadeItemModifier(
            index: index,
            rowCount: showsAddNote ? 2 : 1,
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion
        )
    }

    private var notesPlaceholderButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            onAddNote()
        } label: {
            HStack(spacing: RoutineInlineLayoutMetrics.titleGap) {
                Image(systemName: "plus")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.34))
                    .frame(
                        width: RoutineInlineLayoutMetrics.actionSlotWidth,
                        height: RoutineInlineLayoutMetrics.compactRowMinHeight,
                        alignment: .trailing
                    )

                Text("添加备注")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.34))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: RoutineInlineLayoutMetrics.compactRowMinHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加备注")
    }

    private var attributeToolbar: some View {
        AdaptiveTaskAttributeToolbarLayout() {
            cycleMenu
                .frame(maxWidth: .infinity)
            targetDayControl
                .frame(maxWidth: .infinity)
            targetTimeControl
                .frame(maxWidth: .infinity)
            reminderMenu
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $activeAttributeEditor) { editor in
            inlineAttributeEditor(editor)
        }
    }

    private var reminderMenu: some View {
        Menu {
            Button {
                viewModel.updateDraftReminder(leadMinutes: nil)
            } label: {
                if currentRule?.hasReminder == true {
                    Text("关闭提醒")
                } else {
                    Label("关闭提醒", systemImage: "checkmark")
                }
            }

            Divider()
            reminderOption("目标时刻", minutes: 0)
            reminderOption("提前 5 分钟", minutes: 5)
            reminderOption("提前 15 分钟", minutes: 15)
            reminderOption("提前 30 分钟", minutes: 30)
            reminderOption("提前 1 小时", minutes: 60)
            reminderOption("提前 1 天", minutes: 1_440)

            if currentRule?.hasReminder == true {
                Divider()
                Button {
                    Task { await viewModel.updateDraftReminderDelivery(.notification) }
                } label: {
                    Label("普通通知", systemImage: currentRule?.reminderDelivery == .alarm ? "bell" : "checkmark")
                }
                if #available(iOS 26.0, *) {
                    Button {
                        Task { await viewModel.updateDraftReminderDelivery(.alarm) }
                    } label: {
                        Label("原生闹钟", systemImage: currentRule?.reminderDelivery == .alarm ? "checkmark" : "alarm")
                    }
                }
            }
        } label: {
            settingMenuLabel(
                icon: currentRule?.reminderDelivery == .alarm ? "alarm" : "bell",
                title: reminderTitle,
                isConfigured: currentRule?.hasReminder == true
            )
        }
        .buttonStyle(.plain)
        .disabled(currentRule?.hasCompleteTarget(for: draftCycle) != true)
        .accessibilityLabel("例行任务提醒，当前为\(reminderTitle)")
    }

    private func reminderOption(_ title: String, minutes: Int) -> some View {
        Button {
            viewModel.updateDraftReminder(leadMinutes: minutes)
        } label: {
            if currentRule?.reminderLeadMinutes == minutes {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var cycleMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                Button {
                    viewModel.updateDraftCycle(cycle)
                } label: {
                    if draftCycle == cycle {
                        Label(cycle.title, systemImage: "checkmark")
                    } else {
                        Text(cycle.title)
                    }
                }
            }
        } label: {
            settingMenuLabel(
                icon: "arrow.triangle.2.circlepath",
                title: draftCycle.title,
                isConfigured: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("例行任务维度，当前为\(draftCycle.title)")
    }

    @ViewBuilder
    private var targetDayControl: some View {
        if draftCycle == .daily {
            settingLabel(icon: "calendar", title: "每天", isConfigured: true)
        } else {
            Menu {
                targetDayOptions(for: draftCycle)
                if currentRule?.hasTargetDay == true {
                    Divider()
                    Button("清除目标日", role: .destructive) {
                        viewModel.clearDraftTargetDay()
                    }
                }
            } label: {
                settingMenuLabel(
                    icon: "calendar",
                    title: targetDayTitle,
                    isConfigured: currentRule?.hasTargetDay == true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("目标日期，当前为\(targetDayTitle)")
        }
    }

    @ViewBuilder
    private var targetTimeControl: some View {
        TaskAttributeButton(
            icon: "clock",
            title: currentRule?.hasTargetTime == true ? TaskAttributeValueText.time(timeDate) : "时间",
            isConfigured: currentRule?.hasTargetTime == true
        ) {
            toggleAttributeEditor(.time)
        }
    }

    private func settingLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured
        )
    }

    private func settingMenuLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured,
            fillsAvailableWidth: false
        )
    }

    private func toggleAttributeEditor(_ editor: InlineAttributeEditor) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.14) : .snappy(duration: 0.28, extraBounce: 0.01)) {
            activeAttributeEditor = activeAttributeEditor == editor ? nil : editor
        }
    }

    private func inlineAttributeEditor(_ editor: InlineAttributeEditor) -> some View {
        InlineDateTimePickerPanel(
            editor: editor,
            title: "选择目标时间",
            initialSelection: currentRule?.hasTargetTime == true ? timeDate : nil,
            fallbackSelection: .now,
            supportsClearing: currentRule?.hasTargetTime == true,
            onCommit: { value in
                if let value {
                    updateDraftTime(value)
                } else {
                    viewModel.clearDraftTargetTime()
                }
            }
        )
    }

    @ViewBuilder
    private func targetDayOptions(for cycle: PeriodicCycle) -> some View {
        switch cycle {
        case .daily:
            targetDayOption("每天", timing: .dayOfPeriod(1))
        case .weekly:
            ForEach(1...7, id: \.self) { day in
                targetDayOption(
                    RoutineTargetText.weekdayText(for: day),
                    timing: .dayOfPeriod(day)
                )
            }
        case .monthly:
            ForEach([1, 5, 10, 15, 20, 25, 31], id: \.self) { day in
                targetDayOption(
                    day == 31 ? "最后一天" : "\(day) 号",
                    timing: .dayOfPeriod(day)
                )
            }
        case .quarterly:
            targetDayOption("第 1 天", timing: .dayOfPeriod(1))
            targetDayOption("第 30 天", timing: .dayOfPeriod(30))
            targetDayOption("结束前 14 天", timing: .daysBeforeEnd(14))
        case .yearly:
            targetDayOption("第 1 天", timing: .dayOfPeriod(1))
            targetDayOption("第 180 天", timing: .dayOfPeriod(180))
            targetDayOption("结束前 30 天", timing: .daysBeforeEnd(30))
        }
    }

    private func targetDayOption(
        _ title: String,
        timing: PeriodicReminderRule.Timing
    ) -> some View {
        Button {
            viewModel.updateDraftTargetDay(timing)
        } label: {
            if currentRule?.timing == timing {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var draftCycle: PeriodicCycle {
        viewModel.detailDraft?.cycle ?? task.cycle
    }

    private var currentRule: PeriodicReminderRule? {
        viewModel.detailDraft?.reminderRules.first
    }

    private var targetDayTitle: String {
        guard let timing = currentRule?.timing else { return "目标日" }
        switch draftCycle {
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
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        case .quarterly, .yearly:
            switch timing {
            case .dayOfPeriod(let day): return "第\(day)天"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        }
    }

    private var reminderTitle: String {
        guard let rule = currentRule, rule.hasReminder else { return "提醒" }
        if rule.reminderDelivery == .alarm { return "闹钟" }
        guard let minutes = rule.reminderLeadMinutes else { return "提醒" }
        switch minutes {
        case 0: return "准时"
        case 5: return "提前5分"
        case 15: return "提前15分"
        case 30: return "提前30分"
        case 60: return "提前1时"
        case 1_440: return "提前1天"
        default: return "提醒"
        }
    }

    private var timeDate: Date {
        Calendar.current.date(
            from: DateComponents(hour: currentRule?.hour, minute: currentRule?.minute)
        ) ?? .now
    }

    private func updateDraftTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        viewModel.updateDraftTargetTime(hour: hour, minute: minute)
    }
}

private struct RoutineInlineCascadeStack<Content: View>: View {
    let isExpanded: Bool
    let animationBatch: Int
    let reduceMotion: Bool
    let fallbackHeight: CGFloat
    @ViewBuilder let content: Content

    @State private var measuredHeight: CGFloat = 0
    @State private var heightProgress: CGFloat = 0
    @State private var heightTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: RoutineInlineDetailHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
        }
        .frame(height: targetHeight * heightProgress, alignment: .top)
        .clipped()
        .onAppear {
            updateHeightProgress(isExpanded, animated: isExpanded)
        }
        .onDisappear {
            heightTask?.cancel()
            heightTask = nil
        }
        .onPreferenceChange(RoutineInlineDetailHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            if isExpanded && heightProgress > 0 {
                withAnimation(heightAnimation) {
                    measuredHeight = height
                }
            } else {
                measuredHeight = height
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            updateHeightProgress(expanded, animated: true)
        }
        .onChange(of: animationBatch) { _, _ in
            updateHeightProgress(isExpanded, animated: true)
        }
    }

    private var targetHeight: CGFloat {
        measuredHeight > 0 ? measuredHeight : fallbackHeight
    }

    private func updateHeightProgress(_ expanded: Bool, animated: Bool) {
        heightTask?.cancel()
        if expanded {
            heightProgress = 0
            heightTask = Task { @MainActor in
                await Task.yield()
                guard Task.isCancelled == false else { return }
                if animated {
                    withAnimation(heightAnimation) {
                        heightProgress = 1
                    }
                } else {
                    heightProgress = 1
                }
            }
        } else if animated {
            withAnimation(heightAnimation) {
                heightProgress = 0
            }
        } else {
            heightProgress = 0
        }
    }

    private var heightAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .snappy(duration: 0.34, extraBounce: 0.02)
    }
}

private struct RoutineInlineDetailHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RoutineInlineCascadeItemModifier: ViewModifier {
    let index: Int
    let rowCount: Int
    let isExpanded: Bool
    let animationBatch: Int
    let reduceMotion: Bool

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 14))
            .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.985), anchor: .top)
            .onAppear {
                isVisible = false
                guard isExpanded else { return }
                Task { @MainActor in
                    await Task.yield()
                    updateVisibility(true)
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                updateVisibility(expanded)
            }
            .onChange(of: animationBatch) { _, _ in
                updateVisibility(isExpanded)
            }
    }

    private func updateVisibility(_ visible: Bool) {
        withAnimation(rowAnimation(expanding: visible)) {
            isVisible = visible
        }
    }

    private func rowAnimation(expanding: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.14)
        }
        let delay = expanding
            ? Double(index) * 0.045
            : Double(max(rowCount - index - 1, 0)) * 0.032
        return .snappy(duration: 0.28, extraBounce: 0.02).delay(delay)
    }
}
