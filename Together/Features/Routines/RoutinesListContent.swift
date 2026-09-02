import SwiftUI

enum HomeModeTaskTransitionTiming {
    static let revealDelay: Duration = .milliseconds(70)
    static let rowDuration: Double = 0.24
    static let rowDelay: Double = 0.05
    static let linearCascadeRowCount = 8
    static let maximumCascadeDelay: Double = 0.46

    private static let tailHalfDistance = 8.0

    static func delay(
        for index: Int,
        taskCount: Int,
        isPresented: Bool,
        reduceMotion: Bool
    ) -> Double {
        guard reduceMotion == false else { return 0 }
        let rowCount = max(taskCount, 1)
        let rowIndex = min(max(index, 0), rowCount - 1)
        let delayIndex = isPresented ? rowIndex : rowCount - rowIndex - 1
        return cascadingDelay(for: delayIndex)
    }

    private static func cascadingDelay(for index: Int) -> Double {
        let clampedIndex = max(index, 0)
        let linearEndIndex = linearCascadeRowCount - 1
        guard clampedIndex > linearEndIndex else {
            return Double(clampedIndex) * rowDelay
        }

        // Keep a readable cadence across a phoneful of rows, then compress the
        // offscreen tail so a large task collection never stalls the switch.
        let linearEndDelay = Double(linearEndIndex) * rowDelay
        let tailDistance = Double(clampedIndex - linearEndIndex)
        let tailProgress = tailDistance / (tailDistance + tailHalfDistance)
        return linearEndDelay
            + (maximumCascadeDelay - linearEndDelay) * tailProgress
    }
}

struct HomeModeTaskRevealKey: Hashable {
    let isPresented: Bool
    let reduceMotion: Bool
    let isContentReady: Bool
}

struct RoutineCycleTaskRevealKey: Hashable {
    let cycle: PeriodicCycle
    let isPresented: Bool
    let reduceMotion: Bool
    let isContentReady: Bool
}

struct HomeModeTaskWaveModifier: AnimatableModifier {
    var progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let values = TaskMorphCascadeValues.resolve(
            progress: progress,
            reduceMotion: reduceMotion
        )
        content
            .offset(x: values.offset.width, y: values.offset.height)
            .opacity(values.opacity)
            .allowsHitTesting(values.progress >= 0.999)
            .accessibilityHidden(values.progress < 0.999)
    }
}

extension View {
    func homeModeTaskWave(progress: CGFloat) -> some View {
        modifier(HomeModeTaskWaveModifier(progress: progress))
    }
}

private struct RoutinesListLoadKey: Hashable {
    let spaceID: UUID?
    let isPresented: Bool
}

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let showsCanvasBackground: Bool
    let taskDetailTransition: Namespace.ID
    let onOpenTaskDetail: (TaskDetailRoute) -> Void

    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cycleIndicatorNamespace
    @State private var modePeriodHeaderPresented = false
    @State private var modeTaskRowsPresented = false
    @State private var revealedTaskCycle: PeriodicCycle?
    @State private var taskWaveLeadingElementCount = 1
    @State private var deletingTaskIDs: Set<UUID> = []

    private let rowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let rowTopInset = TaskMorphListSpacing.compactExternalInset
    private let rowBottomInset = TaskMorphListSpacing.compactExternalInset
    private let listTopAnchor = "routines-list-top"

    private var currentTasks: [PeriodicTask] {
        viewModel.currentTasks
    }

    private var displayedCycle: PeriodicCycle {
        viewModel.selectedCycle
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            taskScrollView(scrollProxy: scrollProxy)
                .onChange(of: viewModel.selectedCycle) { _, cycle in
                    appContext.router.pendingPeriodicCycle = cycle
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(listTopAnchor, anchor: .top)
                    }
                }
        }
        .background {
            if showsCanvasBackground {
                GradientGridBackground()
            }
        }
        .task(
            id: RoutinesListLoadKey(
                spaceID: appContext.sessionStore.currentSpace?.id,
                isPresented: isPresented
            )
        ) {
            guard isPresented else { return }
            await viewModel.loadIfNeeded()
            appContext.router.pendingPeriodicCycle = viewModel.selectedCycle
            selectPendingRouterCycleIfNeeded()
        }
        .task(
            id: HomeModeTaskRevealKey(
                isPresented: isPresented,
                reduceMotion: reduceMotion,
                isContentReady: true
            )
        ) {
            await updateModePeriodHeaderPresentation()
        }
        .task(
            id: HomeModeTaskRevealKey(
                isPresented: isPresented,
                reduceMotion: reduceMotion,
                isContentReady: isModeTaskContentReady
            )
        ) {
            await updateModeTaskRowsPresentation()
        }
        .task(
            id: RoutineCycleTaskRevealKey(
                cycle: displayedCycle,
                isPresented: isPresented,
                reduceMotion: reduceMotion,
                isContentReady: isModeTaskContentReady
            )
        ) {
            await updateCycleTaskRowsPresentation()
        }
        .task(id: viewModel.nextDeferredTaskResumeDate) {
            await refreshWhenNextDeferredTaskResumes()
        }
        .onChange(of: isPresented) { _, newValue in
            guard newValue == false else { return }
            viewModel.clearTemporaryCycleIfNeeded()
        }
        .onDisappear {
            viewModel.clearTemporaryCycleIfNeeded()
        }
    }

    // MARK: - Fixed dimension header

    private var fixedDimensionHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            cycleRail
            periodHeader
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, contentTopPadding + AppTheme.spacing.xs)
        .padding(.bottom, AppTheme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 10))
        .opacity(isPresented ? 1 : 0)
        .animation(modeHeaderAnimation, value: isPresented)
    }

    private var cycleRail: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(viewModel.visibleCycles, id: \.self) { cycle in
                cycleButton(cycle)
                    .frame(maxWidth: .infinity)
            }

            dimensionManagementMenu
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func cycleButton(_ cycle: PeriodicCycle) -> some View {
        let isSelected = displayedCycle == cycle
        return Button {
            HomeInteractionFeedback.selection()
            withAnimation(cycleAnimation) {
                viewModel.selectCycle(cycle)
            }
        } label: {
            VStack(spacing: AppTheme.spacing.xs) {
                Text(cycle.title)
                    .font(AppTheme.typography.sized(15, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.48))

                ZStack {
                    Color.clear.frame(height: 3)
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(AppTheme.colors.sky)
                            .frame(width: 24, height: 3)
                            .matchedGeometryEffect(id: "routine-cycle-indicator", in: cycleIndicatorNamespace)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dimensionManagementMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                let isVisible = viewModel.persistedVisibleCycles.contains(cycle)
                Toggle(
                    cycle.title,
                    isOn: Binding(
                        get: { viewModel.persistedVisibleCycles.contains(cycle) },
                        set: { updateCycleVisibility(cycle, isVisible: $0) }
                    )
                )
                .disabled(isVisible && viewModel.canHideCycle(cycle) == false)
            }
        } label: {
            VStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "ellipsis")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.48))

                Color.clear.frame(height: 3)
            }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("管理定期任务维度")
    }

    private func updateCycleVisibility(_ cycle: PeriodicCycle, isVisible: Bool) {
        HomeInteractionFeedback.selection()
        withAnimation(cycleAnimation) {
            viewModel.setCycle(cycle, isVisible: isVisible)
        }
    }

    private var periodHeader: some View {
        let summary = viewModel.summary(for: displayedCycle)
        return HStack(alignment: .center, spacing: AppTheme.spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(displayedCycle.currentPeriodPrefix)
                    .font(AppTheme.typography.sized(19, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title.opacity(0.78))

                HStack(spacing: AppTheme.spacing.sm) {
                    Text("\(summary.pendingCount) 项未完成")
                        .foregroundStyle(AppTheme.colors.body.opacity(0.52))

                    Text(daysRemainingText(summary))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                }
                .font(AppTheme.typography.sized(13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeModeTaskWave(progress: modePeriodHeaderPresented ? 1 : 0)
            .animation(
                taskWaveAnimation(
                    index: 0,
                    elementCount: max(currentTasks.count + 1, 1),
                    isPresented: modePeriodHeaderPresented
                ),
                value: modePeriodHeaderPresented
            )

            Gauge(value: summary.completionProgress, in: 0...1) {
                Text("完成进度")
            } currentValueLabel: {
                Text("\(summary.completedCount)/\(summary.totalCount)")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(AppTheme.colors.sky)
            .frame(width: 52, height: 52)
            .accessibilityLabel("\(displayedCycle.title)完成进度")
            .accessibilityValue("已完成 \(summary.completedCount) 项，共 \(summary.totalCount) 项")
        }
        .contentTransition(.numericText())
    }

    private func daysRemainingText(_ summary: RoutineDimensionSummary) -> String {
        if displayedCycle == .daily {
            return "今天"
        }
        return "还剩 \(summary.daysRemaining) 天"
    }

    // MARK: - Task stream

    private func taskScrollView(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            fixedDimensionHeader

            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: 1)
                            .id(listTopAnchor)

                        if let statusMessage = displayedStatusMessage {
                            routinesStatusBanner(
                                message: statusMessage,
                                retriesLoad: hasNonBlockingLoadFailure
                            )
                            .padding(.horizontal, AppTheme.spacing.xl)
                            .padding(.top, AppTheme.spacing.sm)
                        }

                        taskStream(scrollProxy: scrollProxy)
                            .id(displayedCycle)
                            .transition(cycleContentTransition)

                        Color.clear
                            .frame(height: contentBottomPadding)
                            .allowsHitTesting(false)
                    }
                    .padding(.bottom, AppTheme.spacing.md)
                    .frame(
                        minHeight: viewport.size.height,
                        alignment: .top
                    )
                }
                .safeAreaPadding(.bottom, 0)
                .scrollIndicators(.hidden)
                .applySoftScrollEdgeTransition()
            }
        }
        .animation(cycleAnimation, value: displayedCycle)
    }

    @ViewBuilder
    private func taskStream(scrollProxy: ScrollViewProxy) -> some View {
        switch displayedTaskStreamPresentation {
        case .loading:
            routinesLoadingState
        case .failure:
            routinesFailureState
        case .allEmpty:
            routinesEmptyState
        case .cycleEmpty:
            emptyTabState
        case .content:
            ForEach(Array(currentTasks.enumerated()), id: \.element.id) { index, task in
                routineRow(
                    task,
                    index: index,
                    taskCount: currentTasks.count,
                    scrollProxy: scrollProxy
                )
            }
        }
    }

    private var displayedTaskStreamPresentation: RoutinesViewModel.TaskStreamPresentation {
        viewModel.taskStreamPresentation
    }

    private var hasNonBlockingLoadFailure: Bool {
        guard viewModel.tasks.isEmpty == false else { return false }
        if case .failed = viewModel.loadState { return true }
        return false
    }

    private var nonBlockingStatusMessage: String? {
        if hasNonBlockingLoadFailure, case let .failed(message) = viewModel.loadState {
            return message
        }
        return viewModel.operationErrorMessage
    }

    private var displayedStatusMessage: String? {
        nonBlockingStatusMessage
    }

    private var routinesLoadingState: some View {
        VStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text("正在加载定期任务")
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.64))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .accessibilityElement(children: .combine)
    }

    private var routinesFailureState: some View {
        VStack(spacing: AppTheme.spacing.md) {
            EmptyStateCard(
                title: "定期任务加载失败",
                message: "已有数据不会被清空，点击重试后会重新读取。",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                usesNeutralBackground: true
            )

            Button("重试") {
                Task { await viewModel.reload(showsLoading: true) }
            }
            .font(AppTheme.typography.sized(15, weight: .semibold))
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, 52)
    }

    private func routinesStatusBanner(message: String, retriesLoad: Bool) -> some View {
        HStack(spacing: AppTheme.spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))

            Text(message)
                .font(AppTheme.typography.sized(13, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)

            if retriesLoad {
                Button("重试") {
                    Task { await viewModel.reload() }
                }
                .font(AppTheme.typography.sized(13, weight: .semibold))
            } else {
                Button {
                    viewModel.dismissOperationError()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭错误提示")
            }
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.sm)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        )
    }

    private func routineRow(
        _ task: PeriodicTask,
        index: Int,
        taskCount: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        routineTaskRow(
            task,
            isDetailPresented: false,
            isDetailExpanded: false,
            isDetailCollapsing: false,
            motion: .compact,
            cascadeRowCount: 2,
            scrollProxy: scrollProxy
        )
        .id(task.id)
        .padding(
            EdgeInsets(
                top: rowTopInset,
                leading: rowHorizontalInset,
                bottom: rowBottomInset,
                trailing: rowHorizontalInset
            )
        )
        .modifier(
            RoutineSwipeActionsModifier(
                isEnabled: true,
                canDelete: viewModel.canDeletePeriodicTask(task),
                onDefer: {
                    HomeInteractionFeedback.selection()
                    Task {
                        await viewModel.deferTaskUntilTomorrow(taskID: task.id)
                    }
                },
                onDelete: {
                    requestTaskDeletion(task.id)
                }
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeModeTaskWave(progress: taskRowsPresented ? 1 : 0)
        .animation(
            taskWaveAnimation(
                index: index + taskWaveLeadingElementCount,
                elementCount: taskCount + taskWaveLeadingElementCount,
                isPresented: taskRowsPresented
            ),
            value: taskRowsPresented
        )
        .contextMenu {
            if viewModel.isCompleted(task) == false,
               viewModel.canEditPeriodicTask(task) {
                Button {
                    onOpenTaskDetail(.periodic(task.id))
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }

            if viewModel.canDeletePeriodicTask(task) {
                Button {
                    HomeInteractionFeedback.selection()
                    Task {
                        await viewModel.deferTaskUntilTomorrow(taskID: task.id)
                    }
                } label: {
                    Label("推迟到明天", systemImage: "calendar.badge.clock")
                }

                Button(role: .destructive) {
                    requestTaskDeletion(task.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .applyTaskRemovalTransition(
            isDeleting: deletingTaskIDs.contains(task.id),
            transition: taskRemovalTransition
        )
        .insertedListItemMotion(
            isInserted: viewModel.isAnimatingInsertion(taskID: task.id),
            onAnimationCompleted: {
                viewModel.completeInsertionAnimation(taskID: task.id)
            }
        )
    }

    private func routineTaskRow(
        _ task: PeriodicTask,
        isDetailPresented: Bool,
        isDetailExpanded: Bool,
        isDetailCollapsing: Bool,
        motion: TaskExpansionMotion,
        cascadeRowCount: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        RoutinesTaskRow(
            task: task,
            viewModel: viewModel,
            isAnimatingCompletion: viewModel.isAnimatingCompletion(taskID: task.id),
            isAnimatingReopening: viewModel.isAnimatingReopening(taskID: task.id),
            isDetailPresented: isDetailPresented,
            isDetailExpanded: isDetailExpanded,
            isDetailCollapsing: isDetailCollapsing,
            expansionMotion: motion,
            cascadeRowCount: cascadeRowCount,
            requestsInitialTitleFocus: false,
            taskDetailTransition: taskDetailTransition,
            onOpenDetail: {
                onOpenTaskDetail(.periodic(task.id))
            },
            onToggleCompletion: {
                Task { await viewModel.toggleCompletion(taskID: task.id) }
            },
            onDismissDetail: {},
            onInlineFocus: { focus in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)) {
                    scrollProxy.scrollTo(focus.anchorID(for: task.id), anchor: focus.scrollAnchor)
                }
            }
        )
    }

    private func requestTaskDeletion(_ taskID: UUID) {
        guard deletingTaskIDs.insert(taskID).inserted else { return }
        HomeInteractionFeedback.delete()
        Task { @MainActor in
            defer { deletingTaskIDs.remove(taskID) }
            await viewModel.deleteTask(
                taskID: taskID,
                removalAnimation: taskRemovalAnimation
            )
        }
    }

    private var taskRemovalAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .smooth(duration: 0.20, extraBounce: 0)
    }

    private var taskRemovalTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private func refreshWhenNextDeferredTaskResumes() async {
        guard let resumeDate = viewModel.nextDeferredTaskResumeDate else { return }
        let delay = max(0, resumeDate.timeIntervalSinceNow)
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }
        guard Task.isCancelled == false else { return }
        viewModel.refreshReferenceDate()
    }

    // MARK: - Empty states

    private var routinesEmptyState: some View {
        emptyState(
            title: "还没有定期任务",
            subtitle: "先从每天、每周或每月的节奏开始",
            buttonTitle: "新建定期任务"
        )
    }

    private var emptyTabState: some View {
        emptyState(
            title: "暂无\(displayedCycle.title)任务",
            subtitle: "给这个维度添加一个固定节奏",
            buttonTitle: "新建\(displayedCycle.title)任务"
        )
    }

    private func emptyState(title: String, subtitle: String, buttonTitle: String) -> some View {
        VStack(spacing: AppTheme.spacing.xl) {
            VStack(spacing: AppTheme.spacing.md) {
                Image("EmptyRoutines")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)

                VStack(spacing: AppTheme.spacing.xs) {
                    Text(title)
                        .font(AppTheme.typography.sized(17, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                    Text(subtitle)
                        .font(AppTheme.typography.sized(14, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.38))
                }
            }

            Button {
                HomeInteractionFeedback.selection()
                appContext.router.pendingPeriodicCycle = viewModel.selectedCycle
                appContext.router.requestComposer(.newPeriodicTask)
            } label: {
                Label(buttonTitle, systemImage: "plus")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.colors.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, 72)
    }

    // MARK: - Routing and presentation helpers

    private func selectPendingRouterCycleIfNeeded() {
        if let pendingCycle = appContext.router.pendingPeriodicCycle {
            if viewModel.persistedVisibleCycles.contains(pendingCycle) {
                viewModel.selectCycle(pendingCycle)
            } else {
                viewModel.selectCycleTemporarily(pendingCycle)
            }
        }

        guard appContext.router.shouldAutoSelectPendingCycle else { return }
        appContext.router.shouldAutoSelectPendingCycle = false

        let attention = viewModel.attentionSummary(referenceDate: viewModel.referenceDate)
        if let firstAttention = attention.first {
            withAnimation(cycleAnimation) {
                if viewModel.persistedVisibleCycles.contains(firstAttention.0) {
                    viewModel.selectCycle(firstAttention.0)
                } else {
                    viewModel.selectCycleTemporarily(firstAttention.0)
                }
            }
        }
    }

    private var cycleAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.26, extraBounce: 0)
    }

    private var cycleContentTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .asymmetric(
            insertion: .identity,
            removal: .opacity
        )
    }

    private var modeHeaderAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.32, extraBounce: 0).delay(isPresented ? 0.04 : 0)
    }

    private func taskWaveAnimation(
        index: Int,
        elementCount: Int,
        isPresented: Bool
    ) -> Animation {
        let delay = HomeModeTaskTransitionTiming.delay(
            for: index,
            taskCount: elementCount,
            isPresented: isPresented,
            reduceMotion: reduceMotion
        )
        return reduceMotion
            ? .easeInOut(duration: 0.18)
            : .linear(duration: HomeModeTaskTransitionTiming.rowDuration).delay(delay)
    }

    private func updateModePeriodHeaderPresentation() async {
        guard isPresented else {
            modePeriodHeaderPresented = false
            return
        }
        guard reduceMotion == false else {
            modePeriodHeaderPresented = true
            return
        }

        modePeriodHeaderPresented = false
        try? await Task.sleep(for: HomeModeTaskTransitionTiming.revealDelay)
        guard Task.isCancelled == false else { return }
        modePeriodHeaderPresented = true
    }

    private func updateModeTaskRowsPresentation() async {
        guard isPresented else {
            modeTaskRowsPresented = false
            return
        }
        guard isModeTaskContentReady else {
            modeTaskRowsPresented = false
            return
        }
        guard reduceMotion == false else {
            taskWaveLeadingElementCount = 1
            modeTaskRowsPresented = true
            return
        }

        taskWaveLeadingElementCount = 1
        modeTaskRowsPresented = false
        try? await Task.sleep(for: HomeModeTaskTransitionTiming.revealDelay)
        guard Task.isCancelled == false else { return }
        modeTaskRowsPresented = true
    }

    private func updateCycleTaskRowsPresentation() async {
        guard isPresented, isModeTaskContentReady else {
            revealedTaskCycle = nil
            return
        }
        guard modeTaskRowsPresented else {
            revealedTaskCycle = displayedCycle
            return
        }
        guard reduceMotion == false else {
            revealedTaskCycle = displayedCycle
            return
        }

        let targetCycle = displayedCycle
        taskWaveLeadingElementCount = 0
        revealedTaskCycle = nil
        try? await Task.sleep(for: HomeModeTaskTransitionTiming.revealDelay)
        guard Task.isCancelled == false, displayedCycle == targetCycle else { return }
        revealedTaskCycle = targetCycle
    }

    private var taskRowsPresented: Bool {
        modeTaskRowsPresented && revealedTaskCycle == displayedCycle
    }

    private var isModeTaskContentReady: Bool {
        switch viewModel.taskStreamPresentation {
        case .loading:
            false
        case .failure, .allEmpty, .cycleEmpty, .content:
            true
        }
    }

}

private struct RoutineSwipeActionsModifier: ViewModifier {
    let isEnabled: Bool
    let canDelete: Bool
    let onDefer: () -> Void
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onDefer()
                    } label: {
                        Label("推迟到明天", systemImage: "calendar.badge.clock")
                    }
                    .tint(AppTheme.colors.sky)

                    if canDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func applyTaskRemovalTransition(
        isDeleting: Bool,
        transition: AnyTransition
    ) -> some View {
        if isDeleting {
            self.transition(transition)
        } else {
            self
        }
    }
}
