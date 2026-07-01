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

private enum RoutineInlineLayoutMetrics {
    static let actionSlotWidth: CGFloat = 40
    static let titleGap: CGFloat = AppTheme.spacing.md
    static let titleLeadingInset = actionSlotWidth + titleGap
    static let rowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 34
    static let detailVerticalSpacing: CGFloat = AppTheme.spacing.xs
    static let attributeMinHeight: CGFloat = 40
    static let detailTopPadding: CGFloat = AppTheme.spacing.xxs
    static let detailBottomPadding: CGFloat = AppTheme.spacing.xxs
    static let estimatedDetailHeight: CGFloat = 126
}

struct RoutinesTaskRow: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let animationBatch: Int
    let onOpenDetail: () -> Void
    let onInlineFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTitleFocused: Bool
    @State private var titleDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
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
                    onFocus: onInlineFocus
                )
                .id(RoutineInlineFocusTarget.detail.anchorID(for: task.id))
            }
        }
        .animation(detailAnimation, value: isDetailPresented)
        .onAppear {
            titleDraft = draftTitle
        }
        .onChange(of: draftTitle) { _, title in
            guard isTitleFocused == false, isEditingTitle == false else { return }
            titleDraft = title
        }
        .onChange(of: isDetailExpanded) { _, expanded in
            guard expanded == false, isEditingTitle || isTitleFocused else { return }
            commitTitleAfterFocusUpdate()
        }
        .onChange(of: isCompleted) { _, completed in
            guard completed else { return }
            triggerCompletionAnimation()
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            completionButton

            Group {
                if isDetailPresented {
                    expandedTitleStack
                } else {
                    Button {
                        onOpenDetail()
                    } label: {
                        collapsedTitleStack
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            }
            Task {
                await viewModel.toggleCompletion(taskID: task.id)
            }
        } label: {
            completionBadge
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isCompleted ? "标记为未完成" : "完成例行任务")
    }

    private var collapsedTitleStack: some View {
        titleStack(title: task.title, includesNote: true)
    }

    @ViewBuilder
    private var expandedTitleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            if isEditingTitle {
                expandedTitleEditor
            } else {
                Button {
                    beginTitleEditing()
                } label: {
                    titleText(draftTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑例行任务标题")
            }

            Text(displayTargetText)
                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                .foregroundStyle(subtitleColor)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleStack(title: String, includesNote: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            titleText(title)

            Text(displayTargetText)
                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                .foregroundStyle(subtitleColor)
                .lineLimit(2)

            if includesNote, let note = RoutineTaskDisplayText.text(for: task).noteText {
                Text(note)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(isCompleted ? 0.34 : 0.5))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var displayTargetText: String {
        guard isDetailPresented, let draft = viewModel.detailDraft else {
            return RoutineTargetText.text(for: task)
        }
        guard let rule = draft.reminderRules.first else {
            return "未设置目标时间"
        }
        return RoutineTargetText.text(for: rule, cycle: draft.cycle)
    }

    private var subtitleColor: Color {
        if urgency == .pastReminder {
            return AppTheme.colors.coral.opacity(isCompleted ? 0.5 : 1)
        }
        if urgency == .approaching {
            return AppTheme.colors.warning.opacity(isCompleted ? 0.5 : 0.9)
        }
        return isCompleted ? AppTheme.colors.body.opacity(0.4) : AppTheme.colors.textTertiary
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
        switch urgency {
        case .pastReminder: return AppTheme.colors.coral.opacity(0.58)
        case .approaching: return AppTheme.colors.warning.opacity(0.58)
        default: return AppTheme.colors.body.opacity(0.44)
        }
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
    let onFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var notesFocused: Bool
    @State private var notesDraft = ""
    @State private var notesEditorRequested = false
    @State private var isCommittingNotes = false

    var body: some View {
        RoutineInlineCascadeStack(
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion,
            fallbackHeight: RoutineInlineLayoutMetrics.estimatedDetailHeight
        ) {
            VStack(alignment: .leading, spacing: RoutineInlineLayoutMetrics.detailVerticalSpacing) {
                notesEditor
                    .id(RoutineInlineFocusTarget.notes.anchorID(for: task.id))
                    .modifier(cascadeItem(index: 0))

                attributeToolbar
                    .modifier(cascadeItem(index: 1))
            }
            .padding(.top, RoutineInlineLayoutMetrics.detailTopPadding)
            .padding(.bottom, RoutineInlineLayoutMetrics.detailBottomPadding)
        }
        .onAppear {
            notesDraft = viewModel.detailDraft?.notes ?? task.notes ?? ""
            notesEditorRequested = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        .onChange(of: notesFocused) { _, focused in
            if focused {
                onFocus(.notes)
            } else if notesEditorRequested, isCommittingNotes == false {
                commitNotesAfterFocusUpdate()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded == false else { return }
            commitNotesAfterFocusUpdate()
        }
    }

    private func cascadeItem(index: Int) -> RoutineInlineCascadeItemModifier {
        RoutineInlineCascadeItemModifier(
            index: index,
            rowCount: 2,
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion
        )
    }

    @ViewBuilder
    private var notesEditor: some View {
        if showsNotesEditor {
            HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                TextField("添加备注", text: $notesDraft, axis: .vertical)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.74))
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($notesFocused)
                    .padding(.leading, RoutineInlineLayoutMetrics.titleLeadingInset)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RoutineInlineLayoutMetrics.compactRowMinHeight,
                        alignment: .leading
                    )

                Button {
                    commitNotesAfterFocusUpdate()
                } label: {
                    Label("保存", systemImage: "checkmark")
                        .font(AppTheme.typography.sized(12, weight: .bold))
                        .foregroundStyle(AppTheme.colors.sky)
                        .frame(minWidth: 54, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存例行任务备注")
            }
        } else {
            Button {
                HomeInteractionFeedback.selection()
                notesEditorRequested = true
                Task { @MainActor in
                    await Task.yield()
                    notesFocused = true
                }
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
    }

    private var showsNotesEditor: Bool {
        notesEditorRequested || notesFocused || notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func commitNotesAfterFocusUpdate() {
        guard isCommittingNotes == false else { return }
        guard notesEditorRequested || notesFocused else { return }
        let shouldReadFocusedInput = notesFocused
        isCommittingNotes = true
        Task { @MainActor in
            if shouldReadFocusedInput {
                notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
            }
            notesFocused = false
            await Task.yield()
            viewModel.updateDraftNotes(notesDraft)
            notesEditorRequested = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            isCommittingNotes = false
        }
    }

    private var attributeToolbar: some View {
        HStack(spacing: 0) {
            cycleMenu
                .frame(maxWidth: .infinity)
            targetDayControl
                .frame(maxWidth: .infinity)
            targetTimeControl
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var cycleMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                Button(cycle.title) {
                    viewModel.updateDraftCycle(cycle)
                }
            }
        } label: {
            settingLabel(
                icon: "arrow.triangle.2.circlepath",
                title: draftCycle.title,
                isConfigured: true
            )
        }
        .accessibilityLabel("例行任务维度，当前为\(draftCycle.title)")
    }

    @ViewBuilder
    private var targetDayControl: some View {
        if draftCycle == .daily {
            settingLabel(icon: "calendar", title: "每天", isConfigured: currentRule != nil)
        } else if let rule = currentRule {
            Menu {
                targetDayOptions(for: draftCycle, rule: rule)
            } label: {
                settingLabel(icon: "calendar", title: targetDayTitle(rule: rule), isConfigured: true)
            }
            .accessibilityLabel("目标日期，当前为\(targetDayTitle(rule: rule))")
        } else {
            Button {
                viewModel.updateDraftReminderRule(RoutinesViewModel.defaultRule(for: draftCycle))
            } label: {
                settingLabel(icon: "calendar", title: "目标日", isConfigured: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var targetTimeControl: some View {
        if let rule = currentRule {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title.opacity(0.74))

                DatePicker(
                    "目标时间",
                    selection: Binding(
                        get: { timeDate(for: rule) },
                        set: { updateDraftTime($0, rule: rule) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
            }
            .frame(maxWidth: .infinity, minHeight: RoutineInlineLayoutMetrics.attributeMinHeight)
        } else {
            Button {
                viewModel.updateDraftReminderRule(RoutinesViewModel.defaultRule(for: draftCycle))
            } label: {
                settingLabel(icon: "clock", title: "时间", isConfigured: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func settingLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .frame(width: 16)

            Text(title)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .foregroundStyle(isConfigured ? AppTheme.colors.title.opacity(0.74) : AppTheme.colors.body.opacity(0.42))
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: RoutineInlineLayoutMetrics.attributeMinHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func targetDayOptions(for cycle: PeriodicCycle, rule: PeriodicReminderRule) -> some View {
        switch cycle {
        case .daily:
            Button("每天") {
                updateRuleTiming(.dayOfPeriod(1), rule: rule)
            }
        case .weekly:
            ForEach(1...7, id: \.self) { day in
                Button(RoutineTargetText.weekdayText(for: day)) {
                    updateRuleTiming(.dayOfPeriod(day), rule: rule)
                }
            }
        case .monthly:
            ForEach([1, 5, 10, 15, 20, 25, 31], id: \.self) { day in
                Button(day == 31 ? "最后一天" : "\(day) 号") {
                    updateRuleTiming(.dayOfPeriod(day), rule: rule)
                }
            }
        case .quarterly:
            Button("第 1 天") { updateRuleTiming(.dayOfPeriod(1), rule: rule) }
            Button("第 30 天") { updateRuleTiming(.dayOfPeriod(30), rule: rule) }
            Button("结束前 14 天") { updateRuleTiming(.daysBeforeEnd(14), rule: rule) }
        case .yearly:
            Button("第 1 天") { updateRuleTiming(.dayOfPeriod(1), rule: rule) }
            Button("第 180 天") { updateRuleTiming(.dayOfPeriod(180), rule: rule) }
            Button("结束前 30 天") { updateRuleTiming(.daysBeforeEnd(30), rule: rule) }
        }
    }

    private var draftCycle: PeriodicCycle {
        viewModel.detailDraft?.cycle ?? task.cycle
    }

    private var currentRule: PeriodicReminderRule? {
        viewModel.detailDraft?.reminderRules.first
    }

    private func targetDayTitle(rule: PeriodicReminderRule) -> String {
        switch draftCycle {
        case .daily:
            return "每天"
        case .weekly:
            if case .dayOfPeriod(let day) = rule.timing {
                return RoutineTargetText.weekdayText(for: day)
            }
            return "目标日"
        case .monthly:
            switch rule.timing {
            case .dayOfPeriod(let day) where day >= 31: return "最后一天"
            case .dayOfPeriod(let day): return "\(day)号"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        case .quarterly, .yearly:
            switch rule.timing {
            case .dayOfPeriod(let day): return "第\(day)天"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        }
    }

    private func updateRuleTiming(_ timing: PeriodicReminderRule.Timing, rule: PeriodicReminderRule) {
        viewModel.updateDraftReminderRule(
            PeriodicReminderRule(timing: timing, hour: rule.hour, minute: rule.minute)
        )
    }

    private func timeDate(for rule: PeriodicReminderRule) -> Date {
        Calendar.current.date(from: DateComponents(hour: rule.hour, minute: rule.minute)) ?? .now
    }

    private func updateDraftTime(_ date: Date, rule: PeriodicReminderRule) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        viewModel.updateDraftReminderRule(
            PeriodicReminderRule(
                timing: rule.timing,
                hour: components.hour ?? rule.hour,
                minute: components.minute ?? rule.minute
            )
        )
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
