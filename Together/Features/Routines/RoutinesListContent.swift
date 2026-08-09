import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum RoutineModeTransitionTiming {
    static let maximumCascadingRows = 5
    static let rowDelay: Double = 0.02

    static func delay(
        for index: Int,
        taskCount: Int,
        isPresented: Bool,
        reduceMotion: Bool
    ) -> Double {
        guard reduceMotion == false else { return 0 }
        let visibleCount = min(max(taskCount, 1), maximumCascadingRows)
        let visibleIndex = min(max(index, 0), visibleCount - 1)
        let delayIndex = isPresented ? visibleIndex : visibleCount - visibleIndex - 1
        return Double(delayIndex) * rowDelay
    }
}

private struct RoutinesListLoadKey: Hashable {
    let spaceID: UUID?
    let isPresented: Bool
}

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    @Bindable var morphSession: HomeMorphSession
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let showsCanvasBackground: Bool

    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cycleIndicatorNamespace
    @State private var cycleTransitionDirection = 1
    @State private var frozenTasks: [PeriodicTask]?
    @State private var frozenTaskStreamPresentation: RoutinesViewModel.TaskStreamPresentation?
    @State private var frozenSummary: RoutineDimensionSummary?
    @State private var frozenStatusMessage: String?
    @State private var frozenSelectedCycle: PeriodicCycle?
    @State private var pendingDraftFrame: CGRect?
    @State private var heroTargetCaptureID: UUID?
    @State private var taskMorphViewport = TaskMorphViewportCoordinator()

    private let rowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let rowTopInset: CGFloat = 24
    private let rowBottomInset: CGFloat = 4
    private let listTopAnchor = "routines-list-top"

    private var currentTasks: [PeriodicTask] {
        let tasks = frozenTasks ?? viewModel.currentTasks
        guard let draftID = activePeriodicDraftID else { return tasks }
        return tasks.filter { $0.id != draftID }
    }

    private var activePeriodicDraftID: UUID? {
        guard case .draft(.periodic, let id) = morphSession.subject else {
            if case .persisted(.periodic, let id) = morphSession.subject,
               viewModel.creationSession?.id == id {
                return id
            }
            return nil
        }
        return id
    }

    private var displayedCycle: PeriodicCycle {
        frozenSelectedCycle ?? viewModel.selectedCycle
    }

    var body: some View {
        VStack(spacing: 0) {
            fixedDimensionHeader

            ScrollViewReader { scrollProxy in
                taskScrollView(scrollProxy: scrollProxy)
                    .onChange(of: viewModel.selectedCycle) { _, cycle in
                        appContext.router.pendingPeriodicCycle = cycle
                        guard morphSession.isActive == false else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                            scrollProxy.scrollTo(listTopAnchor, anchor: .top)
                        }
                    }
            }
        }
        .background {
            if showsCanvasBackground {
                GradientGridBackground()
            }
        }
        .alert("无法使用原生闹钟", isPresented: $viewModel.showsAlarmAuthorizationDeniedAlert) {
            Button("取消", role: .cancel) {}
            Button("打开设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("请在系统设置中允许 Together 使用闹钟；当前提醒方式保持不变。")
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
        .onChange(of: morphSession.phase) { _, phase in
            switch phase {
            case .heroEntering, .active, .saving, .collapsing:
                if frozenTasks == nil {
                    frozenTasks = viewModel.currentTasks
                    frozenTaskStreamPresentation = viewModel.taskStreamPresentation
                    frozenSummary = viewModel.summary(for: viewModel.selectedCycle)
                    frozenStatusMessage = nonBlockingStatusMessage
                    frozenSelectedCycle = viewModel.selectedCycle
                }
            case .relocating, .idle:
                frozenTasks = nil
                frozenTaskStreamPresentation = nil
                frozenSummary = nil
                frozenStatusMessage = nil
                frozenSelectedCycle = nil
            }

            if phase == .idle {
                taskMorphViewport.reset()
            }
        }
        .onChange(of: morphSession.visualState) { oldState, newState in
            guard oldState == .expanded,
                  newState == .compact,
                  case .persisted(.periodic, let taskID) = morphSession.subject
            else { return }
            taskMorphViewport.beginCollapse(for: taskID)
        }
        .onChange(of: viewModel.tasks.map(\.id)) { _, taskIDs in
            guard case .persisted(.periodic, let taskID) = morphSession.subject,
                  taskIDs.contains(taskID) == false
            else { return }
            viewModel.finishMorphDetail()
            morphSession.recover()
        }
        .accessibilityAction(.escape) {
            morphSession.requestDismissal()
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
            guard morphSession.isActive == false else { return }
            HomeInteractionFeedback.selection()
            updateCycleTransitionDirection(to: cycle)
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
        guard morphSession.isActive == false else { return }
        HomeInteractionFeedback.selection()
        if isVisible == false, viewModel.selectedCycle == cycle,
           let fallback = PeriodicCycle.allCases.first(where: {
               $0 != cycle && viewModel.persistedVisibleCycles.contains($0)
           }) {
            updateCycleTransitionDirection(to: fallback)
        }
        withAnimation(cycleAnimation) {
            viewModel.setCycle(cycle, isVisible: isVisible)
        }
    }

    private var periodHeader: some View {
        let summary = frozenSummary ?? viewModel.summary(for: displayedCycle)
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
        ZStack {
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

                    Color.clear.frame(height: contentBottomPadding)
                }
                .padding(.bottom, AppTheme.spacing.md)
                .taskMorphScrollViewport(coordinator: taskMorphViewport)
            }
            .onScrollGeometryChange(for: TaskMorphScrollSnapshot.self) { geometry in
                TaskMorphScrollSnapshot(geometry)
            } action: { _, snapshot in
                taskMorphViewport.recordScrollSnapshot(snapshot)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                taskMorphViewport.recordViewportFrame(frame)
            }
            .scrollIndicators(.hidden)
            .applyScrollEdgeProtection()
            .transaction { transaction in
                if morphSession.phase == .relocating {
                    // Cycle changes and the destination row are prepared behind
                    // the focus surface without a second SwiftUI transition.
                    transaction.animation = nil
                }
            }
        }
        .animation(morphSession.isActive ? nil : cycleAnimation, value: displayedCycle)
    }

    @ViewBuilder
    private func taskStream(scrollProxy: ScrollViewProxy) -> some View {
        if activePeriodicDraftID != nil {
            periodicDraftSlot(scrollProxy: scrollProxy)
        }

        switch frozenTaskStreamPresentation ?? viewModel.taskStreamPresentation {
        case .loading:
            routinesLoadingState
        case .failure:
            routinesFailureState
        case .allEmpty:
            if activePeriodicDraftID == nil { routinesEmptyState }
        case .cycleEmpty:
            if activePeriodicDraftID == nil { emptyTabState }
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
        frozenTasks == nil ? nonBlockingStatusMessage : frozenStatusMessage
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
        let isActiveMorph = morphSession.isActive(.periodic, id: task.id)
        return TaskMorphContainer(
            state: isActiveMorph ? morphSession.visualState : .compact,
            isActive: isActiveMorph,
            hidesRealSurfaceForHero: false
        ) {
            let isExpanded = isActiveMorph && morphSession.visualState == .expanded
            VStack(alignment: .leading, spacing: 0) {
                routineTaskRow(
                    task,
                    isDetailPresented: isExpanded,
                    isDetailExpanded: isExpanded,
                    scrollProxy: scrollProxy
                )
                TaskMorphDisclosure(
                    isExpanded: isExpanded,
                    onMeasuredHeight: { height in
                        taskMorphViewport.recordExpansionHeight(
                            height,
                            for: task.id,
                            component: .footer
                        )
                    }
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = morphSession.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(AppTheme.typography.sized(13, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.leading, 52)
                                .padding(.top, AppTheme.spacing.sm)
                        }
                        HStack {
                            Spacer(minLength: 0)
                            Button {
                                morphSession.requestDismissal()
                            } label: {
                                Label("收起", systemImage: "chevron.up")
                                    .font(AppTheme.typography.sized(13, weight: .semibold))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(morphSession.phase != .active)
                            .accessibilityHint("保存更改并收起定期任务详情")
                        }
                        .padding(.leading, 52)
                    }
                }
            }
        }
        .id(task.id)
        .taskMorphListPlacement(
            state: isActiveMorph ? morphSession.visualState : .compact,
            isActive: isActiveMorph,
            compactInsets: EdgeInsets(
                top: rowTopInset,
                leading: rowHorizontalInset,
                bottom: rowBottomInset,
                trailing: rowHorizontalInset
            )
        )
        .taskMorphViewportProgress(
            isActiveMorph && morphSession.visualState == .expanded ? 1 : 0,
            id: task.id,
            coordinator: taskMorphViewport
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            taskMorphViewport.recordRowFrame(frame, for: task.id)
        }
        .modifier(
            RoutineSwipeActionsModifier(
                isEnabled: morphSession.isActive == false,
                canDelete: viewModel.canDeletePeriodicTask(task),
                onDefer: {
                    HomeInteractionFeedback.selection()
                    Task {
                        await viewModel.deferTaskUntilTomorrow(taskID: task.id)
                    }
                },
                onDelete: {
                    HomeInteractionFeedback.delete()
                    Task {
                        await viewModel.deleteTask(taskID: task.id)
                    }
                }
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 12))
        .opacity(isPresented ? 1 : 0)
        .animation(
            modeRowAnimation(index: index, taskCount: taskCount),
            value: isPresented
        )
        .contextMenu {
            if morphSession.isActive == false {
                if viewModel.canEditPeriodicTask(task) {
                    Button {
                        toggleInlineDetail(task.id, scrollProxy: scrollProxy)
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
                        HomeInteractionFeedback.delete()
                        Task {
                            await viewModel.deleteTask(taskID: task.id)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func routineTaskRow(
        _ task: PeriodicTask,
        isDetailPresented: Bool,
        isDetailExpanded: Bool,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        RoutinesTaskRow(
            task: task,
            viewModel: viewModel,
            isAnimatingCompletion: viewModel.isAnimatingCompletion(taskID: task.id),
            isAnimatingReopening: viewModel.isAnimatingReopening(taskID: task.id),
            isDetailPresented: isDetailPresented,
            isDetailExpanded: isDetailExpanded,
            animationBatch: 0,
            onOpenDetail: {
                toggleInlineDetail(task.id, scrollProxy: scrollProxy)
            },
            onToggleCompletion: {
                if isDetailPresented {
                    morphSession.requestCompletion()
                } else {
                    guard morphSession.isActive == false else { return }
                    Task { await viewModel.toggleCompletion(taskID: task.id) }
                }
            },
            onInlineFocus: { focus in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)) {
                    scrollProxy.scrollTo(focus.anchorID(for: task.id), anchor: focus.scrollAnchor)
                }
            },
            onDetailHeightChange: { height in
                taskMorphViewport.recordExpansionHeight(
                    height,
                    for: task.id,
                    component: .primary
                )
            }
        )
    }

    @ViewBuilder
    private func periodicDraftSlot(scrollProxy: ScrollViewProxy) -> some View {
        if let session = viewModel.creationSession,
           activePeriodicDraftID == session.id,
           let placement = morphSession.placement {
            TaskMorphContainer(
                state: morphSession.visualState,
                isActive: true,
                hidesRealSurfaceForHero: morphSession.phase == .heroEntering
            ) {
                switch morphSession.visualState {
                case .compact, .expanded:
                    periodicDraftCompactContent(session: session, scrollProxy: scrollProxy)
                case .editing:
                    PeriodicTaskCreationCard(
                        viewModel: viewModel,
                        session: session,
                        isInteractive: morphSession.isInteractive,
                        onDiscard: { morphSession.requestDismissal() },
                        onCommit: { morphSession.requestCommit() }
                    )
                }
            }
            .id(placement.presentationID)
            .taskMorphListPlacement(
                state: morphSession.visualState,
                isActive: true,
                compactInsets: EdgeInsets(
                    top: rowTopInset,
                    leading: rowHorizontalInset,
                    bottom: rowBottomInset,
                    trailing: rowHorizontalInset
                )
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                pendingDraftFrame = frame
                guard heroTargetCaptureID == session.id else { return }
                morphSession.recordHeroTargetFrame(frame)
            }
            .task(id: session.id) {
                guard morphSession.phase == .heroEntering else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    scrollProxy.scrollTo(placement.presentationID, anchor: .center)
                }
                await Task.yield()
                await Task.yield()
                heroTargetCaptureID = session.id
                if let pendingDraftFrame {
                    morphSession.recordHeroTargetFrame(pendingDraftFrame)
                }
            }
        }
    }

    @ViewBuilder
    private func periodicDraftCompactContent(
        session: PeriodicTaskCreationSession,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        if session.phase == .committed,
           let task = viewModel.tasks.first(where: { $0.id == session.id }) {
            routineTaskRow(task, isDetailPresented: false, isDetailExpanded: false, scrollProxy: scrollProxy)
        } else {
            HStack(alignment: .top, spacing: AppTheme.spacing.md) {
                RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                    .strokeBorder(
                        AppTheme.colors.body.opacity(0.38),
                        style: StrokeStyle(lineWidth: 1.6, dash: [3.6, 4.4])
                    )
                    .frame(width: 40, height: 40)
                Text(session.draft.title.isEmpty ? "新定期任务" : session.draft.title)
                    .font(AppTheme.typography.sized(19, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
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

    // MARK: - Inline focus lifecycle

    private func toggleInlineDetail(_ taskID: UUID, scrollProxy: ScrollViewProxy) {
        _ = scrollProxy
        if morphSession.isActive {
            morphSession.requestDismissal()
            return
        }
        HomeInteractionFeedback.soft()
        guard let placement = viewModel.morphPlacement(for: taskID),
              let task = viewModel.tasks.first(where: { $0.id == taskID })
        else { return }
        let showsAddNote = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        taskMorphViewport.beginExpansion(
            for: taskID,
            estimatedHeightDelta: RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: showsAddNote) + 44,
            protectedTopInset: 12
        )
        var expansionToken: HomeMorphSessionToken?
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            guard viewModel.presentDetailForMorph(taskID) else { return }
            expansionToken = morphSession.prepareExpansion(
                domain: .periodic,
                id: taskID,
                placement: placement
            )
        }
        guard let expansionToken else {
            taskMorphViewport.cancelExpansion(for: taskID)
            viewModel.finishMorphDetail()
            return
        }
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard morphSession.isCurrent(expansionToken) else { return }
            withAnimation(morphGeometryAnimation) {
                _ = morphSession.activatePreparedExpansion(using: expansionToken)
            }
        }
    }

    private var morphGeometryAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.9)
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
                appContext.router.activeComposer = .newPeriodicTask
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
            updateCycleTransitionDirection(to: pendingCycle)
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
            updateCycleTransitionDirection(to: firstAttention.0)
            withAnimation(cycleAnimation) {
                if viewModel.persistedVisibleCycles.contains(firstAttention.0) {
                    viewModel.selectCycle(firstAttention.0)
                } else {
                    viewModel.selectCycleTemporarily(firstAttention.0)
                }
            }
        }
    }

    private func updateCycleTransitionDirection(to cycle: PeriodicCycle) {
        guard let currentIndex = PeriodicCycle.allCases.firstIndex(of: viewModel.selectedCycle),
              let targetIndex = PeriodicCycle.allCases.firstIndex(of: cycle)
        else {
            cycleTransitionDirection = 1
            return
        }
        cycleTransitionDirection = targetIndex >= currentIndex ? 1 : -1
    }

    private var cycleAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.26, extraBounce: 0)
    }

    private var cycleContentTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        let insertionEdge: Edge = cycleTransitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = cycleTransitionDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var modeHeaderAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.32, extraBounce: 0).delay(isPresented ? 0.04 : 0)
    }

    private func modeRowAnimation(index: Int, taskCount: Int) -> Animation {
        let delay = RoutineModeTransitionTiming.delay(
            for: index,
            taskCount: taskCount,
            isPresented: isPresented,
            reduceMotion: reduceMotion
        )
        return reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.3, extraBounce: 0).delay(delay)
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
