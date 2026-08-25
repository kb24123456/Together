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
    static let actionSlotWidth: CGFloat = 28
    static let titleGap: CGFloat = AppTheme.spacing.sm
    static let titleLeadingInset = actionSlotWidth + titleGap
    static let attributeLeadingInset = HomeInlineTaskLayoutMetrics.expandedAttributeLeadingInset
    static let rowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 32
    static let detailVerticalSpacing: CGFloat = 0
    static let attributeMinHeight: CGFloat = TaskAttributeToolbarMetrics.rowHeight
    static let detailTitleOverlap: CGFloat = HomeInlineTaskLayoutMetrics.detailTitleOverlap
    static let detailTopPadding: CGFloat = HomeInlineTaskLayoutMetrics.detailTopPadding
    static let attributeTopOverlap: CGFloat = HomeInlineTaskLayoutMetrics.attributeTopOverlap
    static let detailBottomPadding: CGFloat = 0

    static func estimatedDetailHeight(showsAddNote: Bool) -> CGFloat {
        let visibleRowCount = showsAddNote ? 2 : 1
        let rowHeights = attributeMinHeight + (showsAddNote ? compactRowMinHeight : 0)
        let spacings = CGFloat(max(visibleRowCount - 1, 0)) * detailVerticalSpacing
        let overlap = showsAddNote ? attributeTopOverlap : 0
        return detailTopPadding + rowHeights + spacings - overlap + detailBottomPadding
    }
}

struct RoutinesTaskRow: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isAnimatingCompletion: Bool
    let isAnimatingReopening: Bool
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let isDetailCollapsing: Bool
    let expansionMotion: TaskExpansionMotion
    let cascadeRowCount: Int
    var isCreationDraft = false
    var deletionVisualState: TaskDeletionVisualState? = nil
    var creationFocusRequestRevision: UInt = 0
    var creationFocusDismissalRevision: UInt = 0
    var creationCommitRequestRevision: UInt = 0
    var creationValidationMessage: String? = nil
    var onSubmitCreation: () -> Void = {}
    var onCreationTitleChanged: (String) -> Void = { _ in }
    let onOpenDetail: () -> Void
    let onToggleCompletion: () -> Void
    let onDismissDetail: () -> Void
    let onInlineFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @AccessibilityFocusState private var isTitleAccessibilityFocused: Bool
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
    @State private var isEditingNotes = false
    @State private var isCommittingNotes = false
    @State private var completionAnimationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var badgeOutlineOpacity = 1.0
    @State private var badgeFillScale: CGFloat = 0.5
    @State private var badgeFillOpacity = 0.0
    @State private var badgeAuraScale: CGFloat = 0.86
    @State private var badgeAuraOpacity = 0.0
    @State private var completionCheckmarkScale: CGFloat = 1
    @State private var completionCheckmarkOpacity = 1.0
    @State private var rowScale: CGFloat = 1
    @State private var rowVerticalOffset: CGFloat = 0
    @State private var rowOpacity = 1.0
    @State private var reopeningCheckmarkOpacity = 1.0
    @State private var validationNudgeProgress: CGFloat = 1

    private var isCompleted: Bool {
        viewModel.isCompleted(task)
    }

    private var urgency: PeriodicTaskUrgency {
        viewModel.urgencyState(task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            TaskMorphDisclosure(
                progress: isDetailPresented ? expansionMotion.layoutProgress : 0,
                isInteractive: isDetailExpanded
            ) {
                RoutinesInlineDetailView(
                    task: task,
                    viewModel: viewModel,
                    isExpanded: isDetailExpanded,
                    isCollapsing: isDetailCollapsing,
                    cascadeElapsed: expansionMotion.cascadeElapsed(
                        isCollapsing: isDetailCollapsing
                    ),
                    cascadeRowCount: cascadeRowCount,
                    creationFocusDismissalRevision: creationFocusDismissalRevision,
                    creationCommitRequestRevision: creationCommitRequestRevision,
                    onDismiss: onDismissDetail,
                    onFocus: onInlineFocus
                )
                .id(RoutineInlineFocusTarget.detail.anchorID(for: task.id))
            }
            .padding(.top, -RoutineInlineLayoutMetrics.detailTitleOverlap)
        }
        .scaleEffect(rowScale, anchor: .center)
        .offset(y: rowVerticalOffset)
        .opacity(rowOpacity)
        .accessibilityHidden(deletionVisualState != nil)
        .onAppear {
            titleDraft = draftTitle
            notesDraft = visibleNotes
            if isCreationDraft {
                isEditingTitle = true
                if creationFocusRequestRevision > 0 {
                    beginTitleEditing()
                }
            }
            guard shouldPlayCompletionAnimation else { return }
            startCompletionAnimation()
        }
        .onChange(of: creationFocusRequestRevision) { _, revision in
            guard isCreationDraft, revision > 0 else { return }
            beginTitleEditing()
        }
        .onChange(of: creationFocusDismissalRevision) { _, revision in
            guard isCreationDraft, revision > 0 else { return }
            commitTitleAfterFocusUpdate()
            commitNotesAfterFocusUpdate()
        }
        .onChange(of: creationCommitRequestRevision) { _, revision in
            guard isCreationDraft, revision > 0 else { return }
            flushCreationTitleForCommit()
        }
        .onChange(of: creationValidationMessage) { _, message in
            guard isCreationDraft, message != nil else { return }
            playCreationValidationFeedback()
        }
        .onChange(of: isAnimatingCompletion) { _, newValue in
            guard newValue, shouldPlayCompletionAnimation else { return }
            startCompletionAnimation()
        }
        .onChange(of: isAnimatingReopening) { _, newValue in
            guard newValue else { return }

            if reduceMotion {
                withAnimation(.easeOut(duration: 0.12)) {
                    reopeningCheckmarkOpacity = 0
                    badgeOutlineOpacity = 1
                }
                return
            }

            reopeningCheckmarkOpacity = 1
            badgeOutlineOpacity = 0.14
            completionCheckmarkScale = 1

            withAnimation(.easeOut(duration: 0.18)) {
                reopeningCheckmarkOpacity = 0
                badgeOutlineOpacity = 1
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    rowScale = 1
                    rowVerticalOffset = 0
                    rowOpacity = 1
                }
            }
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
        .onChange(of: isDetailPresented) { wasPresented, isPresented in
            guard wasPresented, isPresented == false else { return }
            Task { @MainActor in
                await Task.yield()
                isTitleAccessibilityFocused = true
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .taskTitleCenter, spacing: AppTheme.spacing.sm) {
            completionButton
                .padding(.horizontal, -8)
                .padding(.vertical, -10)
                .scaleEffect(resolvedDeletionVisualState.controlScale)
                .opacity(resolvedDeletionVisualState.controlOpacity)
                .alignmentGuide(.taskTitleCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }

            ZStack(alignment: .topLeading) {
                stableTitleStack
                    .taskDeletionTypographyEffect(resolvedDeletionVisualState)

                if isDetailPresented == false, isCompleted == false {
                    Button {
                        onOpenDetail()
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityFocused($isTitleAccessibilityFocused)
                    .accessibilityLabel("展开定期任务")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(expansionMotion.identityScale, anchor: .topLeading)
        .offset(
            x: expansionMotion.identityOffsetX,
            y: expansionMotion.identityOffsetY
        )
    }

    private var resolvedDeletionVisualState: TaskDeletionVisualState {
        deletionVisualState ?? .idle(taskID: task.id)
    }

    private var completionButton: some View {
        Button {
            if isCompleted {
                HomeInteractionFeedback.selection()
            } else {
                HomeInteractionFeedback.completion()
            }
            onToggleCompletion()
        } label: {
                completionBadge
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isCreationDraft)
        .accessibilityHidden(isCreationDraft)
        .accessibilityLabel(isCompleted ? "标记为未完成" : "完成定期任务")
    }

    @ViewBuilder
    private var stableTitleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Group {
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
                        Group {
                            if isDetailPresented {
                                TaskMorphInterpolatedHeightRegion(
                                    progress: expansionMotion.layoutProgress,
                                    compact: { titleText(draftTitle, lineLimit: 2) },
                                    expanded: { titleText(draftTitle, lineLimit: nil) },
                                    visible: { titleText(draftTitle, lineLimit: nil) }
                                )
                            } else {
                                titleText(task.title, lineLimit: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(isDetailPresented)
                    .accessibilityHidden(isDetailPresented == false)
                    .accessibilityLabel("编辑定期任务标题")
                }
            }
            if isCreationDraft, let creationValidationMessage {
                Text(creationValidationMessage)
                    .font(AppTheme.typography.scaled(12, weight: .medium, relativeTo: .caption1))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if isDetailPresented {
                TaskMorphMeasuredRegion(
                    progress: expansionMotion.compactHeightProgress,
                    isInteractive: false
                ) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                        subtitleText(rowDisplayText.primarySubtitle)
                        if let propertyText = rowDisplayText.propertyText {
                            subtitleText(propertyText)
                        }
                    }
                    .opacity(expansionMotion.collapsedOpacity)
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    subtitleText(rowDisplayText.primarySubtitle)
                    if let propertyText = rowDisplayText.propertyText {
                        subtitleText(propertyText)
                    }
                }
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

                inlineSaveButton(accessibilityLabel: "保存定期任务备注") {
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
            .accessibilityLabel("编辑定期任务备注")
        } else {
            subtitleText(rowDisplayText.primarySubtitle)
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
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
        isDetailPresented ? (viewModel.activeEditorDraft?.notes ?? "") : (task.notes ?? "")
    }

    private var visibleTargetText: String {
        guard isDetailPresented, let draft = viewModel.activeEditorDraft else {
            return RoutineTaskPropertyText.text(for: task)
        }
        guard let rule = draft.reminderRules.first else { return "" }
        return RoutineTaskPropertyText.text(for: rule, cycle: draft.cycle)
    }

    private func titleText(_ title: String, lineLimit: Int?) -> some View {
        Text(title)
            .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(titleColor)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.taskTitleCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }
    }

    private var expandedTitleEditor: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            TextField(
                "定期任务标题",
                text: $titleDraft,
                axis: isCreationDraft ? .horizontal : .vertical
            )
                .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(titleColor)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .lineLimit(isCreationDraft ? 1...1 : 1...4)
                .focused($isTitleFocused)
                .onChange(of: titleDraft) { _, title in
                    guard isCreationDraft else { return }
                    viewModel.updateDraftTitle(title)
                    onCreationTitleChanged(title)
                }
                .onSubmit {
                    commitTitleAfterFocusUpdate(
                        then: isCreationDraft ? onSubmitCreation : nil
                    )
                }
                .id(RoutineInlineFocusTarget.title.anchorID(for: task.id))
                .onChange(of: isTitleFocused) { _, focused in
                    if focused {
                        onInlineFocus(.title)
                    } else if isEditingTitle, isCommittingTitle == false {
                        commitTitleAfterFocusUpdate()
                    }
                }

            if isCreationDraft == false {
                inlineSaveButton(accessibilityLabel: "保存定期任务标题") {
                    commitTitleAfterFocusUpdate()
                }
            }
        }
        .modifier(
            TaskCreationValidationNudge(
                progress: reduceMotion ? 1 : validationNudgeProgress
            )
        )
    }

    private func playCreationValidationFeedback() {
        HomeInteractionFeedback.validation()
        guard reduceMotion == false else {
            beginTitleEditing()
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            validationNudgeProgress = 0
        }
        withAnimation(.linear(duration: 0.16)) {
            validationNudgeProgress = 1
        }
        beginTitleEditing()
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

    private func commitTitleAfterFocusUpdate(then action: (() -> Void)? = nil) {
        guard isEditingTitle || isTitleFocused else {
            action?()
            return
        }
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
            action?()
        }
    }

    private func flushCreationTitleForCommit() {
        titleDraft = TextInputSnapshotReader.resolvedText(fallback: titleDraft)
        isCommittingTitle = true
        isTitleFocused = false
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.updateDraftTitle(trimmed)
        onCreationTitleChanged(trimmed)
        titleDraft = trimmed
        isEditingTitle = false
        isCommittingTitle = false
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
        isDetailPresented ? (viewModel.activeEditorDraft?.title ?? task.title) : task.title
    }

    private var subtitleColor: Color {
        if isDetailPresented, colorScheme == .light, isCompleted == false {
            return AppTheme.colors.taskFocusBody
        }
        return AppTheme.colors.body.opacity(isCompleted ? 0.4 : 0.74)
    }

    private var titleColor: Color {
        if isDetailPresented, colorScheme == .light, isCompleted == false {
            return AppTheme.colors.taskFocusTitle
        }
        return isCompleted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title
    }

    // MARK: - Completion badge

    private var shouldPlayCompletionAnimation: Bool {
        isAnimatingCompletion && isCompleted == false
    }

    private var completionBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppTheme.colors.coral.opacity(0.34), lineWidth: 2)
                .scaleEffect(badgeAuraScale)
                .opacity(badgeAuraOpacity)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(shouldPlayCompletionAnimation ? badgeFillOpacity : (isCompleted ? 0 : badgeFillOpacity))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    ringColor,
                    lineWidth: shouldPlayCompletionAnimation ? 1.4 : 1.2
                )
                .opacity(outlineOpacity)

            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(17, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.15), value: completionAnimationCount)
                .opacity(checkmarkOpacity)
                .scaleEffect(completionCheckmarkScale)
                .offset(
                    x: AppTheme.metrics.checkmarkVisualOffset.width,
                    y: AppTheme.metrics.checkmarkVisualOffset.height
                )
        }
        .scaleEffect(badgeScale)
        .shadow(
            color: AppTheme.colors.coral.opacity(badgeAuraOpacity * 0.42),
            radius: badgeAuraOpacity > 0 ? 12 : 0,
            y: badgeAuraOpacity > 0 ? 5 : 0
        )
    }

    private var ringColor: Color {
        if isAnimatingReopening {
            return AppTheme.colors.body.opacity(0.30)
        }

        if isCompleted {
            return .clear
        }

        if shouldPlayCompletionAnimation {
            return AppTheme.colors.body.opacity(0.32)
        }

        return AppTheme.colors.body.opacity(isDetailPresented ? 0.38 : 0.30)
    }

    private var outlineOpacity: Double {
        if isAnimatingReopening { return badgeOutlineOpacity }
        if isCompleted { return 0 }
        if shouldPlayCompletionAnimation { return badgeOutlineOpacity }
        return 1
    }

    private var checkmarkOpacity: Double {
        guard isCompleted || shouldPlayCompletionAnimation || isAnimatingReopening else { return 0 }
        return (isAnimatingReopening ? reopeningCheckmarkOpacity : 1) * completionCheckmarkOpacity
    }

    private func startCompletionAnimation() {
        completionAnimationCount += 1
        badgeOutlineOpacity = 1
        badgeFillScale = reduceMotion ? 0.96 : 0.68
        badgeFillOpacity = reduceMotion ? 0.1 : 0.18
        badgeAuraScale = 0.86
        badgeAuraOpacity = 0
        badgeScale = reduceMotion ? 1 : 0.92
        completionCheckmarkScale = reduceMotion ? 1 : 0.72
        completionCheckmarkOpacity = reduceMotion ? 1 : 0
        rowScale = reduceMotion ? 1 : 0.992
        rowVerticalOffset = 0

        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.08)) {
            badgeOutlineOpacity = reduceMotion ? 0.16 : 0.12
        }

        Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.16)) {
                    badgeFillScale = 1
                    badgeFillOpacity = 0
                    badgeAuraOpacity = 0
                    completionCheckmarkOpacity = 1
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(36))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                badgeScale = 1.08
                badgeFillScale = 1.04
                badgeAuraScale = 1.08
                completionCheckmarkScale = 1.08
                rowScale = 0.986
                rowVerticalOffset = -1
            }
            withAnimation(.easeOut(duration: 0.12)) {
                badgeFillOpacity = 0.24
                badgeAuraOpacity = 0.28
                completionCheckmarkOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(112))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                badgeScale = 1
                completionCheckmarkScale = 1
                rowScale = 1
                rowVerticalOffset = 1
            }
            withAnimation(.easeOut(duration: 0.22)) {
                badgeFillScale = 1.42
                badgeFillOpacity = 0
                badgeAuraScale = 1.48
                badgeAuraOpacity = 0
                badgeOutlineOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(96))
            withAnimation(.easeOut(duration: 0.12)) {
                rowVerticalOffset = 0
                rowScale = 1
            }
        }
    }
}

private struct RoutinesInlineDetailView: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isExpanded: Bool
    let isCollapsing: Bool
    let cascadeElapsed: TimeInterval
    let cascadeRowCount: Int
    let creationFocusDismissalRevision: UInt
    let creationCommitRequestRevision: UInt
    let onDismiss: () -> Void
    let onFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var notesDraft = ""
    @State private var isEditingNotes = false
    @State private var isCommittingNotes = false
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RoutineInlineLayoutMetrics.detailVerticalSpacing) {
            notesControl
                .taskMorphCascade(
                    elapsed: cascadeElapsed,
                    index: 0,
                    rowCount: cascadeRowCount,
                    isCollapsing: isCollapsing
                )
            attributeToolbar
                .padding(.top, -RoutineInlineLayoutMetrics.attributeTopOverlap)
                .taskMorphCascade(
                    elapsed: cascadeElapsed,
                    index: 1,
                    rowCount: cascadeRowCount,
                    isCollapsing: isCollapsing
                )
        }
        .padding(.top, RoutineInlineLayoutMetrics.detailTopPadding)
        .padding(.bottom, RoutineInlineLayoutMetrics.detailBottomPadding)
        .onAppear { notesDraft = viewModel.activeEditorDraft?.notes ?? task.notes ?? "" }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded == false, isEditingNotes else { return }
            commitNotes()
        }
        .onChange(of: creationFocusDismissalRevision) { _, revision in
            guard revision > 0 else { return }
            commitNotes()
        }
        .onChange(of: creationCommitRequestRevision) { _, revision in
            guard revision > 0 else { return }
            commitNotes()
        }
        .accessibilityAction(named: "收起定期任务详情") {
            onDismiss()
        }
    }

    @ViewBuilder
    private var notesControl: some View {
        HStack(spacing: RoutineInlineLayoutMetrics.titleGap) {
            Image(systemName: notesIcon)
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(notesTitle == "添加备注" ? 0.68 : 0.76))
                .frame(
                    width: RoutineInlineLayoutMetrics.actionSlotWidth,
                    height: RoutineInlineLayoutMetrics.compactRowMinHeight
                )

            if isEditingNotes {
                TextField("添加备注", text: $notesDraft, axis: .vertical)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(taskFocusBodyColor)
                    .lineLimit(1...4)
                    .focused($isNotesFocused)
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
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    notesDraft = viewModel.activeEditorDraft?.notes ?? task.notes ?? ""
                    isEditingNotes = true
                    onFocus(.notes)
                    Task { @MainActor in
                        await Task.yield()
                        isNotesFocused = true
                    }
                } label: {
                    Text(notesTitle)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(notesTextColor)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .frame(minHeight: 44)
                .padding(.vertical, -6)
                .buttonStyle(.plain)
                .accessibilityLabel(notesTitle == "添加备注" ? "添加备注" : "编辑备注")
            }
        }
        .frame(maxWidth: .infinity, minHeight: RoutineInlineLayoutMetrics.compactRowMinHeight)
    }

    private var notesTitle: String {
        let notes = viewModel.activeEditorDraft?.notes ?? task.notes ?? ""
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "添加备注" : trimmed
    }

    private var notesIcon: String {
        notesTitle == "添加备注" ? "plus" : "note.text"
    }

    private var taskFocusBodyColor: Color {
        colorScheme == .light ? AppTheme.colors.taskFocusBody : AppTheme.colors.title
    }

    private var notesTextColor: Color {
        guard colorScheme == .light else {
            return AppTheme.colors.body.opacity(notesTitle == "添加备注" ? 0.72 : 0.82)
        }
        return notesTitle == "添加备注"
            ? AppTheme.colors.taskFocusPlaceholder
            : AppTheme.colors.taskFocusBody
    }

    private func commitNotes() {
        guard isEditingNotes, isCommittingNotes == false else { return }
        isCommittingNotes = true
        notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
        isNotesFocused = false
        viewModel.updateDraftNotes(notesDraft)
        isEditingNotes = false
        isCommittingNotes = false
    }

    @ViewBuilder
    private var attributeToolbar: some View {
        if usesEqualWidthAttributeToolbar {
            HStack(spacing: TaskAttributeToolbarMetrics.horizontalSpacing) {
                attributeToolbarControls
            }
            .frame(
                maxWidth: .infinity,
                minHeight: TaskAttributeToolbarMetrics.rowHeight
            )
            .padding(.leading, RoutineInlineLayoutMetrics.attributeLeadingInset)
        } else {
            TaskAttributeToolbarRail {
                attributeToolbarControls
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, RoutineInlineLayoutMetrics.attributeLeadingInset)
        }
    }

    @ViewBuilder
    private var attributeToolbarControls: some View {
        cycleMenu
            .frame(maxWidth: usesEqualWidthAttributeToolbar ? .infinity : nil)
        targetDayControl
            .frame(maxWidth: usesEqualWidthAttributeToolbar ? .infinity : nil)
        targetTimeControl
            .frame(maxWidth: usesEqualWidthAttributeToolbar ? .infinity : nil)
        reminderMenu
            .frame(maxWidth: usesEqualWidthAttributeToolbar ? .infinity : nil)
    }

    private var usesEqualWidthAttributeToolbar: Bool {
        dynamicTypeSize.isAccessibilitySize == false
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
        .accessibilityLabel("定期任务提醒，当前为\(reminderTitle)")
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
        .accessibilityLabel("定期任务维度，当前为\(draftCycle.title)")
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
        InlineTimePickerControl(
            selection: currentRule?.hasTargetTime == true ? timeDate : nil,
            fallbackSelection: .now,
            fillsAvailableWidth: usesEqualWidthAttributeToolbar,
            onCommit: { value in
                if let value {
                    updateDraftTime(value)
                } else {
                    viewModel.clearDraftTargetTime()
                }
            }
        )
    }

    private func settingLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured,
            usesContinuousCapsule: true,
            horizontalPadding: 8,
            isFocusForeground: true,
            fillsAvailableWidth: usesEqualWidthAttributeToolbar
        )
    }

    private func settingMenuLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured,
            usesContinuousCapsule: true,
            horizontalPadding: 8,
            isFocusForeground: true,
            fillsAvailableWidth: usesEqualWidthAttributeToolbar
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
        viewModel.activeEditorDraft?.cycle ?? task.cycle
    }

    private var currentRule: PeriodicReminderRule? {
        viewModel.activeEditorDraft?.reminderRules.first
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
