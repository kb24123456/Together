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
    let requestsInitialTitleFocus: Bool
    let showsAttributeToolbar: Bool
    let taskDetailTransition: Namespace.ID?
    let inputCommitRequestRevision: UInt
    let onOpenDetail: () -> Void
    let onToggleCompletion: () -> Void
    let onDismissDetail: () -> Void
    let onInlineFocus: (RoutineInlineFocusTarget) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.taskMorphBackgroundTextOpacity) private var backgroundTextOpacity
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @AccessibilityFocusState private var isTitleAccessibilityFocused: Bool
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
    @State private var isEditingNotes = false
    @State private var isCommittingNotes = false
    @State private var didRequestInitialTitleFocus = false
    @State private var badgeOutlineOpacity = 1.0
    @State private var badgeFillScale: CGFloat = 0.5
    @State private var badgeFillOpacity = 0.0
    @State private var isCompletionCheckmarkPresented = false
    @State private var reopeningCheckmarkOpacity = 1.0

    init(
        task: PeriodicTask,
        viewModel: RoutinesViewModel,
        isAnimatingCompletion: Bool,
        isAnimatingReopening: Bool,
        isDetailPresented: Bool,
        isDetailExpanded: Bool,
        isDetailCollapsing: Bool,
        expansionMotion: TaskExpansionMotion,
        cascadeRowCount: Int,
        requestsInitialTitleFocus: Bool,
        showsAttributeToolbar: Bool = true,
        taskDetailTransition: Namespace.ID? = nil,
        inputCommitRequestRevision: UInt = 0,
        onOpenDetail: @escaping () -> Void,
        onToggleCompletion: @escaping () -> Void,
        onDismissDetail: @escaping () -> Void,
        onInlineFocus: @escaping (RoutineInlineFocusTarget) -> Void
    ) {
        self.task = task
        _viewModel = Bindable(wrappedValue: viewModel)
        self.isAnimatingCompletion = isAnimatingCompletion
        self.isAnimatingReopening = isAnimatingReopening
        self.isDetailPresented = isDetailPresented
        self.isDetailExpanded = isDetailExpanded
        self.isDetailCollapsing = isDetailCollapsing
        self.expansionMotion = expansionMotion
        self.cascadeRowCount = cascadeRowCount
        self.requestsInitialTitleFocus = requestsInitialTitleFocus
        self.showsAttributeToolbar = showsAttributeToolbar
        self.taskDetailTransition = taskDetailTransition
        self.inputCommitRequestRevision = inputCommitRequestRevision
        self.onOpenDetail = onOpenDetail
        self.onToggleCompletion = onToggleCompletion
        self.onDismissDetail = onDismissDetail
        self.onInlineFocus = onInlineFocus

        let initialTitle = isDetailPresented
            ? (viewModel.activeEditorDraft?.title ?? task.title)
            : task.title
        let initialNotes = isDetailPresented
            ? (viewModel.activeEditorDraft?.notes ?? "")
            : (task.notes ?? "")
        _titleDraft = State(initialValue: initialTitle)
        _notesDraft = State(initialValue: initialNotes)
        _isEditingTitle = State(
            initialValue: requestsInitialTitleFocus && isDetailPresented
        )
    }

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
                    usesGlobalConfirmation: requestsInitialTitleFocus,
                    showsAttributeToolbar: showsAttributeToolbar,
                    onDismiss: onDismissDetail,
                    onFocus: onInlineFocus
                )
                .id(RoutineInlineFocusTarget.detail.anchorID(for: task.id))
            }
            .padding(
                .top,
                expansionMotion == .navigationDetail
                    ? AppTheme.spacing.sm
                    : -RoutineInlineLayoutMetrics.detailTitleOverlap
            )
        }
        .onAppear {
            titleDraft = draftTitle
            notesDraft = visibleNotes
            guard shouldPlayCompletionAnimation else { return }
            startCompletionAnimation()
        }
        .task {
            guard requestsInitialTitleFocus,
                  didRequestInitialTitleFocus == false
            else { return }
            didRequestInitialTitleFocus = true
            await Task.yield()
            guard Task.isCancelled == false, isDetailPresented else { return }
            onInlineFocus(.title)
            isTitleFocused = true
        }
        .onChange(of: inputCommitRequestRevision) { _, revision in
            guard revision > 0 else { return }
            commitTitleAfterFocusUpdate()
            commitNotesAfterFocusUpdate()
        }
        .onChange(of: isAnimatingCompletion) { _, newValue in
            if newValue, shouldPlayCompletionAnimation {
                startCompletionAnimation()
            } else if isCompleted == false {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    isCompletionCheckmarkPresented = false
                }
            }
        }
        .onChange(of: isAnimatingReopening) { _, newValue in
            guard newValue else { return }

            isCompletionCheckmarkPresented = false

            if reduceMotion {
                withAnimation(.easeOut(duration: 0.12)) {
                    reopeningCheckmarkOpacity = 0
                    badgeOutlineOpacity = 1
                }
                return
            }

            reopeningCheckmarkOpacity = 1
            badgeOutlineOpacity = 0.14

            withAnimation(.easeOut(duration: 0.18)) {
                reopeningCheckmarkOpacity = 0
                badgeOutlineOpacity = 1
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
                .alignmentGuide(.taskTitleCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }

            ZStack(alignment: .topLeading) {
                stableTitleStack

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
        .accessibilityLabel(isCompleted ? "标记为未完成" : "完成定期任务")
    }

    @ViewBuilder
    private var stableTitleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
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
                        .frame(
                            maxWidth: isDetailPresented ? .infinity : nil,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(isDetailPresented)
                    .accessibilityHidden(isDetailPresented == false)
                    .accessibilityLabel("编辑定期任务标题")
                }
            }
            if isDetailPresented {
                TaskMorphMeasuredRegion(
                    progress: expansionMotion.compactHeightProgress,
                    isInteractive: false
                ) {
                    VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
                        subtitleText(rowDisplayText.primarySubtitle)
                        if let propertyText = rowDisplayText.propertyText {
                            subtitleText(propertyText)
                        }
                    }
                    .opacity(expansionMotion.collapsedOpacity)
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
                    subtitleText(rowDisplayText.primarySubtitle)
                    if let propertyText = rowDisplayText.propertyText {
                        subtitleText(propertyText)
                    }
                }
            }
        }
        .frame(maxWidth: isDetailPresented ? .infinity : nil, alignment: .leading)
        .opacity(backgroundTextOpacity)
        .taskDetailMatchedTransitionSource(
            .periodic(task.id),
            in: taskDetailTransition,
            isEnabled: isDetailPresented == false
        )
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

                if requestsInitialTitleFocus == false {
                    inlineSaveButton(accessibilityLabel: "保存定期任务备注") {
                        commitNotesAfterFocusUpdate()
                    }
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
            .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
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
            .font(AppTheme.typography.hierarchy(.primary, weight: .semibold))
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
                axis: .vertical
            )
                .font(AppTheme.typography.hierarchy(.primary, weight: .semibold))
                .foregroundStyle(titleColor)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .lineLimit(1...4)
                .focused($isTitleFocused)
                .onChange(of: titleDraft) { _, title in
                    guard isDetailPresented else { return }
                    viewModel.updateDraftTitle(title)
                }
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

            if requestsInitialTitleFocus == false {
                inlineSaveButton(accessibilityLabel: "保存定期任务标题") {
                    commitTitleAfterFocusUpdate()
                }
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
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(shouldPlayCompletionAnimation ? badgeFillOpacity : (isCompleted ? 0 : badgeFillOpacity))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    ringColor,
                    lineWidth: shouldPlayCompletionAnimation ? 1.4 : 1.2
                )
                .opacity(outlineOpacity)

            if isCompleted || isCompletionCheckmarkPresented || isAnimatingReopening {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .transition(.symbolEffect(.drawOn))
                    .opacity(isAnimatingReopening ? reopeningCheckmarkOpacity : 1)
                    .offset(
                        x: AppTheme.metrics.checkmarkVisualOffset.width,
                        y: AppTheme.metrics.checkmarkVisualOffset.height
                    )
            }
        }
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

    private func startCompletionAnimation() {
        badgeOutlineOpacity = 1
        badgeFillScale = reduceMotion ? 0.96 : 0.76
        badgeFillOpacity = reduceMotion ? 0.1 : 0.16
        isCompletionCheckmarkPresented = false

        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.08)) {
            badgeOutlineOpacity = reduceMotion ? 0.16 : 0.12
        }

        Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.16)) {
                    badgeFillScale = 1
                    badgeFillOpacity = 0
                    isCompletionCheckmarkPresented = true
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(36))
            withAnimation(.smooth(duration: 0.20, extraBounce: 0)) {
                badgeFillScale = 1.08
                isCompletionCheckmarkPresented = true
            }
            withAnimation(.easeOut(duration: 0.12)) {
                badgeFillOpacity = 0.20
            }

            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.22)) {
                badgeFillScale = 1.28
                badgeFillOpacity = 0
                badgeOutlineOpacity = 0
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
    let usesGlobalConfirmation: Bool
    let showsAttributeToolbar: Bool
    let onDismiss: () -> Void
    let onFocus: (RoutineInlineFocusTarget) -> Void

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
            if showsAttributeToolbar {
                attributeToolbar
                    .padding(.top, -RoutineInlineLayoutMetrics.attributeTopOverlap)
                    .taskMorphCascade(
                        elapsed: cascadeElapsed,
                        index: 1,
                        rowCount: cascadeRowCount,
                        isCollapsing: isCollapsing
                    )
            }
        }
        .padding(.top, RoutineInlineLayoutMetrics.detailTopPadding)
        .padding(.bottom, RoutineInlineLayoutMetrics.detailBottomPadding)
        .onAppear { notesDraft = viewModel.activeEditorDraft?.notes ?? task.notes ?? "" }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded == false, isEditingNotes else { return }
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

                if usesGlobalConfirmation == false {
                    Button("确认", action: commitNotes)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.sky)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.vertical, -6)
                        .buttonStyle(.plain)
                }
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

    private var attributeToolbar: some View {
        TaskAttributeAdaptiveRail {
            attributeToolbarControls
        }
        .padding(.leading, RoutineInlineLayoutMetrics.attributeLeadingInset)
    }

    @ViewBuilder
    private var attributeToolbarControls: some View {
        cycleMenu
        targetDayControl
        targetTimeControl
        reminderMenu
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
            reminderOption("准时", minutes: 0)
            reminderOption("提前 5 分钟", minutes: 5)
            reminderOption("提前 15 分钟", minutes: 15)
            reminderOption("提前 30 分钟", minutes: 30)
            reminderOption("提前 1 小时", minutes: 60)
            reminderOption("提前 1 天", minutes: 1_440)

        } label: {
            settingMenuLabel(
                icon: "bell",
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
            fillsAvailableWidth: false,
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
            fillsAvailableWidth: false
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
            fillsAvailableWidth: false
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

    private var reminderTitle: String {
        guard let rule = currentRule, rule.hasReminder else { return "提醒" }
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

struct PeriodicTaskAttributeFooter: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    let isExpanded: Bool
    let allowsZoomTransition: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var attributeTransition
    @State private var attributeSheetPresentation: TaskAttributeEditorTransitionPresentation?
    @State private var initialAttributeRule: PeriodicReminderRule?
    @State private var timeIconEffectTrigger = 0
    @State private var reminderIconEffectTrigger = 0

    var body: some View {
        expandedControls
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .allowsHitTesting(isExpanded)
            .sheet(item: $attributeSheetPresentation, onDismiss: triggerAttributeIconEffects) { presentation in
                PeriodicTaskAttributeSheet(task: task, viewModel: viewModel)
                    .taskAttributeEditorNavigationTransition(
                        from: presentation.source,
                        in: attributeTransition,
                        reduceMotion: reduceMotion,
                        allowsZoomTransition: presentation.allowsZoomTransition
                    )
            }
    }

    private var expandedControls: some View {
        TaskAttributeAdaptiveRail {
            attributeControls(fillsAvailableWidth: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, RoutineInlineLayoutMetrics.attributeLeadingInset)
    }

    @ViewBuilder
    private func attributeControls(fillsAvailableWidth: Bool) -> some View {
        attributeButton(
            title: cycle.title,
            systemImage: "arrow.triangle.2.circlepath",
            isConfigured: true,
            fillsAvailableWidth: fillsAvailableWidth,
            transitionSource: .periodicCycle,
            accessibilityLabel: "周期，当前为\(cycle.title)"
        )
        attributeButton(
            title: PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule),
            systemImage: "calendar",
            isConfigured: cycle == .daily || rule?.hasTargetDay == true,
            fillsAvailableWidth: fillsAvailableWidth,
            transitionSource: .periodicTargetDay,
            accessibilityLabel: "目标日，当前为\(PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule))"
        )
        attributeButton(
            title: PeriodicTaskAttributeText.targetTimeTitle(rule: rule),
            systemImage: "clock",
            isConfigured: rule?.hasTargetTime == true,
            fillsAvailableWidth: fillsAvailableWidth,
            transitionSource: .periodicTargetTime,
            accessibilityLabel: "目标时间，当前为\(PeriodicTaskAttributeText.targetTimeTitle(rule: rule))",
            iconEffect: .rotate,
            iconEffectTrigger: timeIconEffectTrigger
        )
        attributeButton(
            title: PeriodicTaskAttributeText.reminderTitle(rule: rule),
            systemImage: "bell",
            isConfigured: rule?.hasReminder == true,
            fillsAvailableWidth: fillsAvailableWidth,
            transitionSource: .periodicReminder,
            accessibilityLabel: "提醒，当前为\(PeriodicTaskAttributeText.reminderTitle(rule: rule))",
            iconEffect: .wiggle,
            iconEffectTrigger: reminderIconEffectTrigger
        )
    }

    private func attributeButton(
        title: String,
        systemImage: String,
        isConfigured: Bool,
        fillsAvailableWidth: Bool,
        transitionSource: TaskAttributeEditorTransitionSource,
        accessibilityLabel: String,
        iconEffect: TaskAttributeIconEffect = .none,
        iconEffectTrigger: Int = 0
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            initialAttributeRule = rule
            attributeSheetPresentation = TaskAttributeEditorTransitionPresentation(
                source: transitionSource,
                allowsZoomTransition: allowsZoomTransition
            )
        } label: {
            TaskAttributeLabel(
                icon: systemImage,
                title: title,
                isConfigured: isConfigured,
                usesContinuousCapsule: true,
                alignsToCardCorner: true,
                horizontalPadding: 8,
                isFocusForeground: true,
                fillsAvailableWidth: fillsAvailableWidth,
                usesLightweightBackground: true,
                animatesTitleChanges: true,
                iconEffect: iconEffect,
                iconEffectTrigger: iconEffectTrigger,
                transitionSource: transitionSource,
                transitionNamespace: attributeTransition
            )
        }
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        .buttonStyle(TaskMorphAttributeButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("轻点编辑定期任务属性")
    }

    private var cycle: PeriodicCycle {
        viewModel.activeEditorDraft?.cycle ?? task.cycle
    }

    private var rule: PeriodicReminderRule? {
        viewModel.activeEditorDraft?.reminderRules.first ?? task.reminderRules.first
    }

    private func triggerAttributeIconEffects() {
        let updatedRule = rule
        if initialAttributeRule?.hour != updatedRule?.hour
            || initialAttributeRule?.minute != updatedRule?.minute {
            timeIconEffectTrigger += 1
        }
        if initialAttributeRule?.reminderLeadMinutes != updatedRule?.reminderLeadMinutes {
            reminderIconEffectTrigger += 1
        }
        initialAttributeRule = nil
    }

}

private struct PeriodicTaskAttributeSheet: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    sheetContent
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                sheetContent
            }
        }
        .background(AppTheme.colors.surface)
        .accessibilityAction(.escape) {
            dismiss()
        }
        .presentationContentInteraction(.scrolls)
        .presentationDetents([sheetDetent])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.colors.surface)
    }

    private var sheetDetent: PresentationDetent {
        guard dynamicTypeSize.isAccessibilitySize == false else { return .large }

        let standardRowCount = 4
        let visibleRowCount = usesMonthlyWeekdayRule ? standardRowCount + 1 : standardRowCount
        let rowsHeight = CGFloat(standardRowCount) * PeriodicTaskAttributeSheetLayout.rowHeight
            + (usesMonthlyWeekdayRule ? PeriodicTaskAttributeSheetLayout.stackedRowHeight : 0)
        let spacingHeight = CGFloat(visibleRowCount - 1)
            * PeriodicTaskAttributeSheetLayout.rowSpacing
        return .height(rowsHeight + spacingHeight + AppTheme.spacing.md * 2)
    }

    private var sheetContent: some View {
        VStack(spacing: PeriodicTaskAttributeSheetLayout.rowSpacing) {
            cycleRow
            targetDayRow

            if usesMonthlyWeekdayRule {
                monthlyWeekdayRuleRow
                    .transition(
                        .blurReplace
                            .combined(with: .scale(0.96, anchor: .trailing))
                            .combined(with: .opacity)
                    )
            }

            targetTimeRow
            reminderRow
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.vertical, AppTheme.spacing.md)
        .frame(maxWidth: .infinity)
    }

    private var cycleRow: some View {
        PeriodicTaskAttributeSettingRow(
            icon: "arrow.triangle.2.circlepath",
            title: "周期"
        ) {
            Picker(selection: cycleBinding) {
                ForEach(PeriodicCycle.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                valueLabel(cycle.title)
            }
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("周期")
            .accessibilityValue(cycle.title)
        }
    }

    @ViewBuilder
    private var targetDayRow: some View {
        PeriodicTaskAttributeSettingRow(icon: "calendar", title: "目标日") {
            if cycle == .daily {
                Text("每天")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.colors.body)
                    .frame(minHeight: 44)
                    .accessibilityLabel("目标日")
                    .accessibilityValue("每天")
            } else {
                Picker(selection: targetDayChoiceBinding) {
                    ForEach(targetDayOptions) { option in
                        Text(option.title).tag(option.choice)
                    }
                } label: {
                    valueLabel(
                        PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule)
                    )
                }
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("目标日")
                .accessibilityValue(
                    PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule)
                )
            }
        }
    }

    private var monthlyWeekdayRuleRow: some View {
        PeriodicTaskAttributeSettingRow(
            icon: "calendar.badge.clock",
            title: "重复方式",
            layout: .stacked
        ) {
            HStack(spacing: AppTheme.spacing.xs) {
                Picker(selection: monthlyOrdinalBinding) {
                    ForEach(PeriodicMonthWeekOrdinal.allCases, id: \.self) { ordinal in
                        Text(ordinal.title).tag(ordinal)
                    }
                } label: {
                    compactSelectorLabel(monthlyOrdinal.title)
                }
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("每月第几个星期")
                .accessibilityValue(monthlyOrdinal.title)

                Picker(selection: monthlyWeekdayBinding) {
                    ForEach(Self.monthlyWeekdays, id: \.self) { weekday in
                        Text(RoutineTargetText.absoluteWeekdayText(for: weekday)).tag(weekday)
                    }
                } label: {
                    compactSelectorLabel(
                        RoutineTargetText.absoluteWeekdayText(for: monthlyWeekday)
                    )
                }
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("星期")
                .accessibilityValue(
                    RoutineTargetText.absoluteWeekdayText(for: monthlyWeekday)
                )
            }
        }
    }

    private var targetTimeRow: some View {
        PeriodicTaskAttributeSettingRow(icon: "clock", title: "目标时间") {
            HStack(spacing: AppTheme.spacing.xs) {
                if rule?.hasTargetTime == true {
                    DatePicker(
                        "目标时间",
                        selection: targetTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(AppTheme.colors.coral)
                    .frame(minHeight: 44)
                    .contentTransition(.numericText())
                    .transition(
                        .blurReplace
                            .combined(with: .scale(0.94, anchor: .trailing))
                    )
                    .accessibilityValue(
                        PeriodicTaskAttributeText.targetTimeTitle(rule: rule)
                    )

                    Button {
                        HomeInteractionFeedback.selection()
                        performTimeControlStateChange {
                            viewModel.clearDraftTargetTime()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.colors.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .blurReplace
                            .combined(with: .offset(x: -14))
                            .combined(with: .scale(0.68, anchor: .leading))
                            .combined(with: .opacity)
                    )
                    .accessibilityLabel("清除目标时间")
                    .accessibilityHint("同时清除提醒")
                } else {
                    Button {
                        HomeInteractionFeedback.selection()
                        performTimeControlStateChange {
                            updateTargetTime(.now)
                        }
                    } label: {
                        HStack(spacing: AppTheme.spacing.xs) {
                            Text("添加时间")
                                .font(.callout.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(AppTheme.colors.body)
                        .padding(.horizontal, AppTheme.spacing.sm)
                        .frame(minHeight: 36)
                        .background(AppTheme.colors.pillSurface, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .transition(
                        .blurReplace
                            .combined(with: .scale(0.94, anchor: .trailing))
                    )
                    .accessibilityHint("添加后可使用系统时间选择器修改")
                }
            }
        }
    }

    private var reminderRow: some View {
        PeriodicTaskAttributeSettingRow(
            icon: "bell",
            title: "提醒"
        ) {
            Picker(selection: reminderLeadBinding) {
                Text("无提醒").tag(nil as Int?)
                ForEach(Self.reminderOptions) { option in
                    Text(option.title).tag(Optional(option.minutes))
                }
            } label: {
                reminderValueLabel
            }
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(canConfigureReminder == false)
            .accessibilityLabel("提醒")
            .accessibilityValue(
                canConfigureReminder ? reminderValueTitle : "需先设置目标"
            )
            .accessibilityHint(
                canConfigureReminder
                    ? "轻点选择提醒时间"
                    : "需要先设置完整目标"
            )
        }
    }

    @ViewBuilder
    private var reminderValueLabel: some View {
        if canConfigureReminder {
            valueLabel(reminderValueTitle)
                .transition(
                    .blurReplace
                        .combined(with: .scale(0.94, anchor: .trailing))
                )
        } else {
            valueLabel("需先设置目标", isEnabled: false)
                .transition(
                    .blurReplace
                        .combined(with: .scale(0.94, anchor: .trailing))
                )
        }
    }

    private func compactSelectorLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(AppTheme.colors.body)
        .padding(.horizontal, AppTheme.spacing.sm)
        .frame(minHeight: 36)
        .background(AppTheme.colors.pillSurface, in: Capsule(style: .continuous))
    }

    private func valueLabel(_ title: String, isEnabled: Bool = true) -> some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(
                    isEnabled ? AppTheme.colors.body : AppTheme.colors.textTertiary
                )
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var cycleBinding: Binding<PeriodicCycle> {
        Binding(
            get: { cycle },
            set: { newCycle in
                guard newCycle != cycle else { return }
                HomeInteractionFeedback.selection()
                performContentStateChange {
                    viewModel.updateDraftCycle(newCycle)
                }
            }
        )
    }

    private var targetDayChoiceBinding: Binding<PeriodicTargetDayChoice> {
        Binding(
            get: { targetDayChoice },
            set: { choice in
                guard choice != targetDayChoice else { return }
                HomeInteractionFeedback.selection()
                performContentStateChange {
                    switch choice {
                    case .none:
                        viewModel.clearDraftTargetDay()
                    case .timing(let timing):
                        viewModel.updateDraftTargetDay(timing)
                    case .monthlyWeekday:
                        viewModel.updateDraftTargetDay(
                            .weekdayOfMonth(ordinal: .first, weekday: 2)
                        )
                    }
                }
            }
        )
    }

    private var monthlyOrdinalBinding: Binding<PeriodicMonthWeekOrdinal> {
        Binding(
            get: { monthlyOrdinal },
            set: { ordinal in
                guard ordinal != monthlyOrdinal else { return }
                HomeInteractionFeedback.selection()
                performContentStateChange {
                    viewModel.updateDraftTargetDay(
                        .weekdayOfMonth(ordinal: ordinal, weekday: monthlyWeekday)
                    )
                }
            }
        )
    }

    private var monthlyWeekdayBinding: Binding<Int> {
        Binding(
            get: { monthlyWeekday },
            set: { weekday in
                guard weekday != monthlyWeekday else { return }
                HomeInteractionFeedback.selection()
                performContentStateChange {
                    viewModel.updateDraftTargetDay(
                        .weekdayOfMonth(ordinal: monthlyOrdinal, weekday: weekday)
                    )
                }
            }
        )
    }

    private var reminderLeadBinding: Binding<Int?> {
        Binding(
            get: { rule?.reminderLeadMinutes },
            set: { minutes in
                guard minutes != rule?.reminderLeadMinutes else { return }
                HomeInteractionFeedback.selection()
                performContentStateChange {
                    viewModel.updateDraftReminder(leadMinutes: minutes)
                }
            }
        )
    }

    private var targetTimeBinding: Binding<Date> {
        Binding(
            get: { targetTimeDate },
            set: updateTargetTime
        )
    }

    private func updateTargetTime(_ date: Date) {
        let rounded = ExistingTaskScheduleEditorPolicy.roundedTime(date, on: date)
        let components = Calendar.current.dateComponents([.hour, .minute], from: rounded)
        guard let hour = components.hour, let minute = components.minute else { return }
        viewModel.updateDraftTargetTime(hour: hour, minute: minute)
    }

    private func performContentStateChange(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(.smooth(duration: 0.22), update)
        }
    }

    private func performTimeControlStateChange(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(.spring(duration: 0.42, bounce: 0.04), update)
        }
    }

    private var targetTimeDate: Date {
        Calendar.current.date(
            from: DateComponents(hour: rule?.hour, minute: rule?.minute)
        ) ?? .now
    }

    private var cycle: PeriodicCycle {
        viewModel.activeEditorDraft?.cycle ?? task.cycle
    }

    private var rule: PeriodicReminderRule? {
        viewModel.activeEditorDraft?.reminderRules.first ?? task.reminderRules.first
    }

    private var canConfigureReminder: Bool {
        rule?.hasCompleteTarget(for: cycle) == true
    }

    private var reminderValueTitle: String {
        guard rule?.hasReminder == true else { return "无提醒" }
        return PeriodicTaskAttributeText.reminderTitle(rule: rule)
    }

    private var targetDayChoice: PeriodicTargetDayChoice {
        guard let timing = rule?.timing else { return .none }
        if cycle == .monthly {
            switch timing {
            case .weekdayOfMonth:
                return .monthlyWeekday
            case .dayOfPeriod(let day) where day >= 31:
                return .timing(.daysBeforeEnd(1))
            default:
                break
            }
        }
        return .timing(timing)
    }

    private var targetDayOptions: [PeriodicTargetDayOption] {
        var options: [PeriodicTargetDayOption] = [
            PeriodicTargetDayOption(title: "不设置目标日", choice: .none)
        ]
        switch cycle {
        case .daily:
            break
        case .weekly:
            options += (1...7).map { day in
                PeriodicTargetDayOption(
                    title: RoutineTargetText.weekdayText(for: day),
                    choice: .timing(.dayOfPeriod(day))
                )
            }
        case .monthly:
            options += [
                PeriodicTargetDayOption(title: "每月 1 号", choice: .timing(.dayOfPeriod(1))),
                PeriodicTargetDayOption(title: "每月 15 号", choice: .timing(.dayOfPeriod(15))),
                PeriodicTargetDayOption(title: "每月最后一天", choice: .timing(.daysBeforeEnd(1))),
                PeriodicTargetDayOption(title: "每月首个工作日", choice: .timing(.businessDayOfPeriod(1))),
                PeriodicTargetDayOption(title: "每月最后一个工作日", choice: .timing(.lastBusinessDay)),
                PeriodicTargetDayOption(
                    title: targetDayChoice == .monthlyWeekday
                        ? PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule)
                        : "按周次与周几…",
                    choice: .monthlyWeekday
                )
            ]
        case .quarterly:
            options += [
                PeriodicTargetDayOption(title: "季度第 1 天", choice: .timing(.dayOfPeriod(1))),
                PeriodicTargetDayOption(title: "季度第 45 天", choice: .timing(.dayOfPeriod(45))),
                PeriodicTargetDayOption(title: "季度最后一天", choice: .timing(.daysBeforeEnd(1))),
                PeriodicTargetDayOption(title: "季度首个工作日", choice: .timing(.businessDayOfPeriod(1))),
                PeriodicTargetDayOption(title: "季度最后一个工作日", choice: .timing(.lastBusinessDay)),
                PeriodicTargetDayOption(title: "季度结束前 14 天", choice: .timing(.daysBeforeEnd(14)))
            ]
        case .yearly:
            options += [
                PeriodicTargetDayOption(title: "年度第 1 天", choice: .timing(.dayOfPeriod(1))),
                PeriodicTargetDayOption(title: "年度第 183 天", choice: .timing(.dayOfPeriod(183))),
                PeriodicTargetDayOption(title: "年度最后一天", choice: .timing(.daysBeforeEnd(1))),
                PeriodicTargetDayOption(title: "年度首个工作日", choice: .timing(.businessDayOfPeriod(1))),
                PeriodicTargetDayOption(title: "年度最后一个工作日", choice: .timing(.lastBusinessDay)),
                PeriodicTargetDayOption(title: "年度结束前 30 天", choice: .timing(.daysBeforeEnd(30)))
            ]
        }

        if options.contains(where: { $0.choice == targetDayChoice }) == false,
           targetDayChoice != .none {
            options.append(
                PeriodicTargetDayOption(
                    title: PeriodicTaskAttributeText.targetDayTitle(cycle: cycle, rule: rule),
                    choice: targetDayChoice
                )
            )
        }
        return options
    }

    private var usesMonthlyWeekdayRule: Bool {
        guard cycle == .monthly, case .weekdayOfMonth = rule?.timing else { return false }
        return true
    }

    private var monthlyOrdinal: PeriodicMonthWeekOrdinal {
        guard case .weekdayOfMonth(let ordinal, _) = rule?.timing else { return .first }
        return ordinal
    }

    private var monthlyWeekday: Int {
        guard case .weekdayOfMonth(_, let weekday) = rule?.timing else { return 2 }
        return weekday
    }

    private static let monthlyWeekdays = [2, 3, 4, 5, 6, 7, 1]

    private static let reminderOptions = [
        PeriodicReminderOption(title: "准时", minutes: 0),
        PeriodicReminderOption(title: "提前 5 分钟", minutes: 5),
        PeriodicReminderOption(title: "提前 15 分钟", minutes: 15),
        PeriodicReminderOption(title: "提前 30 分钟", minutes: 30),
        PeriodicReminderOption(title: "提前 1 小时", minutes: 60),
        PeriodicReminderOption(title: "提前 1 天", minutes: 1_440)
    ]
}

private enum PeriodicTargetDayChoice: Hashable {
    case none
    case timing(PeriodicReminderRule.Timing)
    case monthlyWeekday
}

private struct PeriodicTargetDayOption: Identifiable {
    let title: String
    let choice: PeriodicTargetDayChoice

    var id: PeriodicTargetDayChoice { choice }
}

private enum PeriodicTaskAttributeSheetLayout {
    static let rowHeight: CGFloat = 52
    static let stackedRowHeight: CGFloat = 72
    static let rowSpacing: CGFloat = 2
}

private enum PeriodicTaskAttributeRowLayout: Equatable {
    case adaptive
    case stacked
}

private struct PeriodicReminderOption: Identifiable {
    let title: String
    let minutes: Int

    var id: Int { minutes }
}

private struct PeriodicTaskAttributeSettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let layout: PeriodicTaskAttributeRowLayout
    let trailing: Trailing

    init(
        icon: String,
        title: String,
        layout: PeriodicTaskAttributeRowLayout = .adaptive,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.layout = layout
        self.trailing = trailing()
    }

    var body: some View {
        rowContent
            .frame(
                maxWidth: .infinity,
                minHeight: layout == .stacked
                    ? PeriodicTaskAttributeSheetLayout.stackedRowHeight
                    : PeriodicTaskAttributeSheetLayout.rowHeight
            )
    }

    @ViewBuilder
    private var rowContent: some View {
        switch layout {
        case .adaptive:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.spacing.md) {
                    leadingLabel
                    Spacer(minLength: AppTheme.spacing.md)
                    trailing
                        .layoutPriority(1)
                }

                stackedContent
            }
        case .stacked:
            stackedContent
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            leadingLabel
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var leadingLabel: some View {
        HStack(spacing: AppTheme.spacing.sm) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.colors.title)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private enum PeriodicTaskAttributeText {
    static func targetDayTitle(
        cycle: PeriodicCycle,
        rule: PeriodicReminderRule?
    ) -> String {
        guard let timing = rule?.timing else {
            return cycle == .daily ? "每天" : "目标日"
        }
        switch cycle {
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

    static func targetTimeTitle(rule: PeriodicReminderRule?) -> String {
        guard let hour = rule?.hour, let minute = rule?.minute else { return "时间" }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func reminderTitle(rule: PeriodicReminderRule?) -> String {
        guard let rule, rule.hasReminder else { return "提醒" }
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
}
