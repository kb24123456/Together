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
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    let showsCanvasBackground: Bool

    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cycleIndicatorNamespace
    @State private var visualFocusTaskID: UUID?
    @State private var collapsingTaskID: UUID?
    @State private var detailAnimationBatch = 0
    @State private var cycleTransitionDirection = 1
    @State private var focusedRowFrame: CGRect?

    private let rowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let rowTopInset: CGFloat = 24
    private let rowBottomInset: CGFloat = 4
    private let listTopAnchor = "routines-list-top"
    private let taskScrollCoordinateSpace = "routines-task-scroll"

    private var currentTasks: [PeriodicTask] {
        viewModel.currentTasks
    }

    var body: some View {
        VStack(spacing: 0) {
            fixedDimensionHeader

            ScrollViewReader { scrollProxy in
                taskScrollView(scrollProxy: scrollProxy)
                    .onChange(of: viewModel.selectedCycle) { _, cycle in
                        appContext.router.pendingPeriodicCycle = cycle
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
        .sheet(isPresented: $viewModel.isEditorPresented) {
            RoutinesEditorSheet(viewModel: viewModel, initialCycle: viewModel.editorDefaultCycle)
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
            await viewModel.loadIfNeeded()
            guard isPresented else { return }
            appContext.router.pendingPeriodicCycle = viewModel.selectedCycle
            selectPendingRouterCycleIfNeeded()
        }
        .onChange(of: viewModel.expandedTaskID) { _, taskID in
            guard taskID == nil else { return }
            visualFocusTaskID = nil
            collapsingTaskID = nil
            focusedRowFrame = nil
        }
        .onChange(of: isPresented) { _, newValue in
            guard newValue == false else { return }
            Task { @MainActor in
                if viewModel.expandedTaskID != nil {
                    _ = await viewModel.collapseInlineDetail()
                }
                viewModel.clearTemporaryCycleIfNeeded()
            }
        }
        .onDisappear {
            Task { @MainActor in
                if viewModel.expandedTaskID != nil {
                    _ = await viewModel.collapseInlineDetail()
                }
                viewModel.clearTemporaryCycleIfNeeded()
            }
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
        .saturation(fixedHeaderSaturation)
        .brightness(fixedHeaderBrightness)
        .blur(radius: fixedHeaderBlurRadius)
        .scaleEffect(fixedHeaderScale, anchor: .top)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 10))
        .opacity(isPresented ? fixedHeaderOpacity : 0)
        .animation(focusAnimation, value: visualFocusTaskID)
        .animation(modeHeaderAnimation, value: isPresented)
        .overlay {
            if visualFocusTaskID != nil {
                Button {
                    collapseVisualFocusIfNeeded()
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起例行任务详情")
            }
        }
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
        let isSelected = viewModel.selectedCycle == cycle
        return Button {
            guard visualFocusTaskID == nil else {
                collapseVisualFocusIfNeeded()
                return
            }
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
        .accessibilityLabel("管理例行任务维度")
    }

    private func updateCycleVisibility(_ cycle: PeriodicCycle, isVisible: Bool) {
        guard visualFocusTaskID == nil else { return }
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
        let summary = viewModel.summary(for: viewModel.selectedCycle)
        return HStack(alignment: .center, spacing: AppTheme.spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(viewModel.selectedCycle.currentPeriodPrefix)
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
            .accessibilityLabel("\(viewModel.selectedCycle.title)完成进度")
            .accessibilityValue("已完成 \(summary.completedCount) 项，共 \(summary.totalCount) 项")
        }
        .contentTransition(.numericText())
    }

    private func daysRemainingText(_ summary: RoutineDimensionSummary) -> String {
        if viewModel.selectedCycle == .daily {
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

                    taskStream(scrollProxy: scrollProxy)
                        .id(viewModel.selectedCycle)
                        .transition(cycleContentTransition)

                    Color.clear.frame(height: contentBottomPadding)
                }
                .padding(.bottom, AppTheme.spacing.md)
            }
            .scrollIndicators(.hidden)
            .applyScrollEdgeProtection()
            .coordinateSpace(name: taskScrollCoordinateSpace)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard visualFocusTaskID != nil,
                              RoutineFocusTapPolicy.shouldCollapse(
                                  tapLocation: value.location,
                                  focusedRowFrame: focusedRowFrame
                              )
                        else { return }
                        collapseVisualFocusIfNeeded()
                    }
            )
        }
        .animation(cycleAnimation, value: viewModel.selectedCycle)
    }

    @ViewBuilder
    private func taskStream(scrollProxy: ScrollViewProxy) -> some View {
        if viewModel.tasks.isEmpty && viewModel.loadState == .loaded {
            routinesEmptyState
        } else if currentTasks.isEmpty {
            emptyTabState
        } else {
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

    private func routineRow(
        _ task: PeriodicTask,
        index: Int,
        taskCount: Int,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let isDetailPresented = isInlineDetailPresented(for: task.id)
        let isDetailExpanded = isInlineDetailVisuallyExpanded(for: task.id)
        return RoutinesTaskRow(
            task: task,
            viewModel: viewModel,
            isDetailPresented: isDetailPresented,
            isDetailExpanded: isDetailExpanded,
            animationBatch: detailAnimationBatch,
            onOpenDetail: {
                toggleInlineDetail(task.id, scrollProxy: scrollProxy)
            },
            onToggleCompletion: {
                completeRoutineTask(task, isDetailPresented: isDetailPresented)
            },
            onInlineFocus: { target in
                scrollToInlineFocus(target, taskID: task.id, scrollProxy: scrollProxy)
            }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(
            RoutinesInlineFocusChromeModifier(
                isFocused: visualFocusTaskID == task.id && isDetailPresented,
                reduceMotion: reduceMotion
            )
        )
        .saturation(rowFocusSaturation(taskID: task.id))
        .brightness(rowFocusBrightness(taskID: task.id))
        .blur(radius: rowFocusBlurRadius(taskID: task.id))
        .scaleEffect(rowFocusScale(taskID: task.id), anchor: .center)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 12))
        .opacity(isPresented ? rowFocusOpacity(taskID: task.id) : 0)
        .zIndex(visualFocusTaskID == task.id ? 3 : 0)
        .animation(focusAnimation, value: visualFocusTaskID)
        .animation(
            modeRowAnimation(index: index, taskCount: taskCount),
            value: isPresented
        )
        .onGeometryChange(for: CGRect?.self) { proxy in
            visualFocusTaskID == task.id
                ? proxy.frame(in: .named(taskScrollCoordinateSpace))
                : nil
        } action: { frame in
            guard let frame else { return }
            focusedRowFrame = frame
        }
        .contextMenu {
            if visualFocusTaskID == nil || visualFocusTaskID == task.id {
                if viewModel.canEditPeriodicTask(task) {
                    Button {
                        if isDetailPresented {
                            beginInlineDetailCollapse(taskID: task.id)
                        } else {
                            toggleInlineDetail(task.id, scrollProxy: scrollProxy)
                        }
                    } label: {
                        Label(
                            isDetailPresented ? "收起" : "编辑",
                            systemImage: isDetailPresented ? "chevron.up" : "pencil"
                        )
                    }
                }

                if viewModel.canDeletePeriodicTask(task) {
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

    // MARK: - Inline focus lifecycle

    private func toggleInlineDetail(_ taskID: UUID, scrollProxy: ScrollViewProxy) {
        HomeInteractionFeedback.soft()
        Task { @MainActor in
            if let focusedTaskID = visualFocusTaskID, focusedTaskID != taskID {
                beginInlineDetailCollapse(taskID: focusedTaskID)
                return
            }

            if viewModel.expandedTaskID == taskID {
                beginInlineDetailCollapse(taskID: taskID)
                return
            }

            if let expandedTaskID = viewModel.expandedTaskID, expandedTaskID != taskID {
                beginInlineDetailCollapse(taskID: expandedTaskID)
                return
            }

            collapsingTaskID = nil
            visualFocusTaskID = nil
            focusedRowFrame = nil
            await viewModel.toggleInlineDetail(taskID)
            detailAnimationBatch += 1
            guard viewModel.expandedTaskID == taskID else { return }

            withAnimation(focusAnimation) {
                visualFocusTaskID = taskID
            }

            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) {
                scrollProxy.scrollTo(
                    RoutineInlineFocusTarget.detail.anchorID(for: taskID),
                    anchor: .center
                )
            }
        }
    }

    private func beginInlineDetailCollapse(taskID: UUID) {
        guard collapsingTaskID != taskID else { return }

        withAnimation(focusAnimation) {
            visualFocusTaskID = nil
        }

        Task { @MainActor in
            collapsingTaskID = taskID
            detailAnimationBatch += 1
            if reduceMotion == false {
                try? await Task.sleep(for: .milliseconds(360))
            }
            guard collapsingTaskID == taskID else { return }
            let didCollapse = await viewModel.collapseInlineDetail()
            collapsingTaskID = nil
            guard didCollapse == false else { return }

            detailAnimationBatch += 1
            withAnimation(focusAnimation) {
                visualFocusTaskID = taskID
            }
        }
    }

    private func completeRoutineTask(_ task: PeriodicTask, isDetailPresented: Bool) {
        Task { @MainActor in
            guard isDetailPresented else {
                await viewModel.toggleCompletion(taskID: task.id)
                return
            }

            guard await viewModel.prepareExpandedCompletion(taskID: task.id) else { return }
            try? await Task.sleep(for: .milliseconds(300))

            collapsingTaskID = task.id
            detailAnimationBatch += 1
            if reduceMotion == false {
                try? await Task.sleep(for: .milliseconds(360))
            }
            guard collapsingTaskID == task.id else { return }
            let didCollapse = await viewModel.collapseInlineDetail()
            guard didCollapse else {
                collapsingTaskID = nil
                return
            }
            withAnimation(focusAnimation) {
                visualFocusTaskID = nil
            }
            collapsingTaskID = nil
            viewModel.finishExpandedCompletion(taskID: task.id)
        }
    }

    private func collapseVisualFocusIfNeeded() {
        guard let taskID = visualFocusTaskID else { return }
        HomeInteractionFeedback.soft()
        beginInlineDetailCollapse(taskID: taskID)
    }

    private func isInlineDetailPresented(for taskID: UUID) -> Bool {
        viewModel.expandedTaskID == taskID || collapsingTaskID == taskID
    }

    private func isInlineDetailVisuallyExpanded(for taskID: UUID) -> Bool {
        viewModel.expandedTaskID == taskID && collapsingTaskID != taskID
    }

    private func scrollToInlineFocus(
        _ target: RoutineInlineFocusTarget,
        taskID: UUID,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            scrollProxy.scrollTo(target.anchorID(for: taskID), anchor: target.scrollAnchor)
        }
    }

    // MARK: - Empty states

    private var routinesEmptyState: some View {
        emptyState(
            title: "还没有例行任务",
            subtitle: "先从每天、每周或每月的节奏开始",
            buttonTitle: "新建例行任务"
        )
    }

    private var emptyTabState: some View {
        emptyState(
            title: "暂无\(viewModel.selectedCycle.title)任务",
            subtitle: "给这个维度添加一个固定节奏",
            buttonTitle: "新建\(viewModel.selectedCycle.title)任务"
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

    private var focusAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0)
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

    private func rowFocusOpacity(taskID: UUID) -> Double {
        guard let visualFocusTaskID else { return 1 }
        return visualFocusTaskID == taskID ? 1 : 0.12
    }

    private func rowFocusSaturation(taskID: UUID) -> Double {
        guard let visualFocusTaskID else { return 1 }
        return visualFocusTaskID == taskID ? 1.1 : 0.03
    }

    private func rowFocusBrightness(taskID: UUID) -> Double {
        guard let visualFocusTaskID else { return 0 }
        return visualFocusTaskID == taskID ? 0.045 : -0.125
    }

    private func rowFocusBlurRadius(taskID: UUID) -> CGFloat {
        guard reduceMotion == false, let visualFocusTaskID else { return 0 }
        return visualFocusTaskID == taskID ? 0 : 3.05
    }

    private func rowFocusScale(taskID: UUID) -> CGFloat {
        guard reduceMotion == false, let visualFocusTaskID else { return 1 }
        return visualFocusTaskID == taskID ? 1.02 : 0.986
    }

    private var fixedHeaderOpacity: Double {
        visualFocusTaskID == nil ? 1 : 0.34
    }

    private var fixedHeaderSaturation: Double {
        visualFocusTaskID == nil ? 1 : 0.82
    }

    private var fixedHeaderBrightness: Double {
        visualFocusTaskID == nil ? 0 : 0.02
    }

    private var fixedHeaderBlurRadius: CGFloat {
        guard reduceMotion == false, visualFocusTaskID != nil else { return 0 }
        return 2.4
    }

    private var fixedHeaderScale: CGFloat {
        guard reduceMotion == false, visualFocusTaskID != nil else { return 1 }
        return 0.99
    }
}

enum RoutineFocusTapPolicy {
    private static let focusTolerance: CGFloat = 6
    private static let focusBottomOverflow: CGFloat = 16

    static func shouldCollapse(tapLocation: CGPoint, focusedRowFrame: CGRect?) -> Bool {
        guard var hitFrame = focusedRowFrame else { return false }
        hitFrame = hitFrame.insetBy(dx: -focusTolerance, dy: -focusTolerance)
        hitFrame.size.height += focusBottomOverflow
        return hitFrame.contains(tapLocation) == false
    }
}

private struct RoutinesInlineFocusChromeModifier: ViewModifier {
    let isFocused: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(AppTheme.colors.surface.opacity(isFocused ? 1 : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .strokeBorder(AppTheme.colors.surface.opacity(isFocused ? 1 : 0), lineWidth: 0.8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 0)
                    .padding(.bottom, -16)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadowColor.opacity(isFocused ? shadowOpacity : 0),
                radius: isFocused ? (reduceMotion ? 14 : 28) : 0,
                x: 0,
                y: isFocused ? 14 : 0
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black : AppTheme.colors.title
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.08
    }
}
