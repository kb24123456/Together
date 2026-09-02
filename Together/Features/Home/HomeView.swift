import SwiftUI

struct HomeModeTimelineWaveSequence: Equatable {
    let activeTaskIDs: [UUID]
    let completedTaskIDs: [UUID]
    let includesWeeklyCompletedSummary: Bool
    let includesDateHeader: Bool

    init(
        activeTaskIDs: [UUID],
        completedTaskIDs: [UUID],
        includesWeeklyCompletedSummary: Bool,
        includesDateHeader: Bool = true
    ) {
        self.activeTaskIDs = activeTaskIDs
        self.completedTaskIDs = completedTaskIDs
        self.includesWeeklyCompletedSummary = includesWeeklyCompletedSummary
        self.includesDateHeader = includesDateHeader
    }

    var dateHeaderIndex: Int? {
        includesDateHeader ? 0 : nil
    }

    private var leadingElementCount: Int {
        includesDateHeader ? 1 : 0
    }

    var todayCompletedHeaderIndex: Int? {
        completedTaskIDs.isEmpty ? nil : leadingElementCount + activeTaskIDs.count
    }

    var weeklyCompletedSummaryIndex: Int? {
        guard includesWeeklyCompletedSummary else { return nil }
        return leadingElementCount
            + activeTaskIDs.count
            + (completedTaskIDs.isEmpty ? 0 : 1)
            + completedTaskIDs.count
    }

    var elementCount: Int {
        leadingElementCount
            + activeTaskIDs.count
            + completedTaskIDs.count
            + (completedTaskIDs.isEmpty ? 0 : 1)
            + (includesWeeklyCompletedSummary ? 1 : 0)
    }

    func taskIndex(for taskID: UUID) -> Int? {
        if let index = activeTaskIDs.firstIndex(of: taskID) {
            return leadingElementCount + index
        }
        guard let index = completedTaskIDs.firstIndex(of: taskID) else {
            return nil
        }
        return leadingElementCount + activeTaskIDs.count + 1 + index
    }
}

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: HomeViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let isRoutinesModePresented: Bool
    var isRootSurfaceVisible = true
    let onCreateTaskTapped: () -> Void
    let taskDetailTransition: Namespace.ID
    let onOpenTaskDetail: (TaskDetailRoute) -> Void
    let onCompletedHistoryTapped: (CompletedHistoryFilter) -> Void
    @State private var isCompletedVisibilityButtonCompressed = false
    @State private var isCompletedSectionVisible = true
    @State private var highlightedTaskID: UUID?
    @State private var isTimelineReorderingActive = false
    @State private var hasHandledInitialSelectedDateTask = false
    @State private var pendingFocusTaskID: UUID?
    @State private var timelineDateBarSelection = HomeTimelineDateBarSelection()
    @State private var timelineDateBarBoundaryMaxY: CGFloat = 0
    @State private var modeTaskRowsPresented = true
    @State private var deletingTaskIDs: Set<UUID> = []

    private let timelineRowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let timelineRowVerticalInset = TaskMorphListSpacing.compactExternalInset
    private let timelineBottomInset: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            backgroundView

            contentCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .font(AppTheme.typography.body)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.performDeferredMaintenanceIfNeeded()
        }
        .task(
            id: HomeModeTaskRevealKey(
                isPresented: isRoutinesModePresented == false,
                reduceMotion: reduceMotion,
                isContentReady: true
            )
        ) {
            await updateModeTaskRowsPresentation()
        }
        .task(id: viewModel.selectedDateKey) {
            guard hasHandledInitialSelectedDateTask else {
                hasHandledInitialSelectedDateTask = true
                return
            }
            await viewModel.reload(reason: .dateChange)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isOverdueSheetPresented },
                set: { if !$0 { viewModel.dismissOverdueSheet() } }
            )
        ) {
            HomeOverdueSummarySheet(viewModel: viewModel)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isWeeklyCompletedSheetPresented },
                set: { if !$0 { viewModel.dismissWeeklyCompletedSheet() } }
            )
        ) {
            WeeklyCompletedSheet(
                items: viewModel.weeklyCompletedSheetItems,
                count: viewModel.weeklyCompletedEntryCount,
                isLoading: viewModel.isWeeklyCompletedSheetLoading,
                didFailLoading: viewModel.didFailLoadingWeeklyCompletedSheet,
                weekdayLabel: { viewModel.weekdayLabel(for: $0) },
                onOpenFullHistory: {
                    viewModel.dismissWeeklyCompletedSheet()
                    onCompletedHistoryTapped(.week)
                },
                onRefresh: {
                    await viewModel.loadWeeklyCompletedSheet()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            isCompletedSectionVisible = true
        }
        .onChange(of: appContext.startupRestorePresentationState) { oldValue, newValue in
            guard oldValue.isVisible, newValue == .idle else { return }
            Task {
                await viewModel.reload(reason: .startupRestore)
            }
        }
    }

    private var backgroundView: some View {
        GradientGridBackground(
            showsAmbientParticles: true,
            ambientParticlesEnabled: appContext.ambientBackgroundSettings.isEnabled,
            isParticleMotionSuppressed: isAmbientParticleMotionSuppressed,
            isSurfaceVisible: isRootSurfaceVisible
        )
    }

    private var isAmbientParticleMotionSuppressed: Bool {
        viewModel.isOverdueSheetPresented
            || viewModel.isWeeklyCompletedSheetPresented
    }

    private var showsStartupRestoreStatus: Bool {
        appContext.startupRestorePresentationState.isVisible
            && appContext.sessionStore.activeMode == .single
            && !isOverlayModeActive
    }

    private var showsStartupRestorePlaceholder: Bool {
        guard showsStartupRestoreStatus else { return false }
        if case .restoring = appContext.startupRestorePresentationState {
            return true
        }
        return false
    }

    private var startupRestorePlaceholder: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Image("EmptyCalendar")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.spacing.xs) {
                Text(startupRestorePlaceholderTitle)
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.66))
                    .multilineTextAlignment(.center)

                Text(startupRestorePlaceholderMessage)
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.42))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var startupRestorePlaceholderTitle: String {
        switch appContext.startupRestorePresentationState {
        case .failed:
            return "网络暂时不可用"
        case .idle, .restoring:
            return "正在恢复你的数据"
        }
    }

    private var startupRestorePlaceholderMessage: String {
        switch appContext.startupRestorePresentationState {
        case .failed:
            return "稍后会自动重试"
        case .restoring(let isSlow):
            return isSlow ? "仍在同步，请稍候" : "通常只需要几秒钟"
        case .idle:
            return ""
        }
    }

    private var restoreTransitionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : AppTheme.motion.smooth
    }

    private var contentCard: some View {
        ZStack(alignment: .top) {
            tasksContent
                .opacity(isOverlayModeActive ? 0 : 1)
                .offset(y: routinesTaskSurfaceOffset)
                .scaleEffect(routinesTaskSurfaceScale, anchor: .top)
                .blur(radius: routinesTaskSurfaceBlur)
                .allowsHitTesting(!isOverlayModeActive)
                .accessibilityHidden(isOverlayModeActive)
                .animation(taskSurfaceModeAnimation, value: isRoutinesModePresented)

            if isRoutinesModePresented {
                routinesModeContent
                    .transition(.opacity.combined(with: .offset(y: 12)))
                    .allowsHitTesting(true)
            }
        }
    }

    private var tasksContent: some View {
        ZStack(alignment: .top) {
            if showsStartupRestorePlaceholder {
                ScrollView {
                    startupRestorePlaceholder
                        .padding(.horizontal, AppTheme.spacing.xl)
                        .padding(.top, 52)
                        .padding(.bottom, AppTheme.spacing.lg)
                }
                .id("startup-restore-\(viewModel.selectedDateKey)")
                .scrollIndicators(.hidden)
                .scrollDisabled(isOverlayModeActive)
                .applySoftScrollEdgeTransition()
                .transition(timelineTransition)
            } else if viewModel.items.isEmpty,
                      viewModel.loadState == .loading || viewModel.loadState == .idle {
                homeLoadingState
            } else if viewModel.items.isEmpty,
                      case .failed = viewModel.loadState {
                homeLoadFailureState
            } else if hasDisplayedTimelineEntries == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.md) { // normalized 14→16
                        timelineSection
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, AppTheme.spacing.md) // normalized 14→16
                    .padding(.bottom, AppTheme.spacing.lg)
                }
                .id("empty-\(viewModel.selectedDateKey)")
                .scrollIndicators(.hidden)
                .scrollDisabled(isOverlayModeActive)
                .applySoftScrollEdgeTransition()
                .transition(timelineTransition)
            } else {
                ScrollViewReader { scrollProxy in
                    timelineList(scrollProxy: scrollProxy)
                        .id("timeline-\(viewModel.selectedDateKey)")
                        .transition(timelineTransition)
                        .onReceive(NotificationCenter.default.publisher(for: .openTaskFromNudge)) { notif in
                            guard let id = notif.userInfo?["task_id"] as? UUID else { return }
                            _ = appContext.consumePendingHighlightTaskID()
                            requestExternalFocus(id, via: scrollProxy)
                        }
                        .task {
                            // Cold-launch path: openTaskFromNotification fires before this
                            // ScrollViewReader is alive, so onReceive never fires. Drain the
                            // pending highlight stored on AppContext and apply it now.
                            guard let id = appContext.consumePendingHighlightTaskID() else { return }
                            requestExternalFocus(id, via: scrollProxy)
                        }
                }
            }

            if let statusMessage = nonBlockingStatusMessage {
                homeStatusBanner(
                    message: statusMessage,
                    retriesLoad: hasNonBlockingLoadFailure,
                    retriesExternalRoute: viewModel.failedExternalRouteTaskID != nil
                )
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, AppTheme.spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: viewModel.selectedDateKey)
        .animation(restoreTransitionAnimation, value: appContext.startupRestorePresentationState)
    }

    private var hasNonBlockingLoadFailure: Bool {
        guard viewModel.items.isEmpty == false else { return false }
        if case .failed = viewModel.loadState { return true }
        return false
    }

    private var nonBlockingStatusMessage: String? {
        if let externalRouteErrorMessage = viewModel.externalRouteErrorMessage {
            return externalRouteErrorMessage
        }
        if hasNonBlockingLoadFailure, case let .failed(message) = viewModel.loadState {
            return message
        }
        return viewModel.operationErrorMessage
    }

    private var homeLoadingState: some View {
        VStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text("正在加载任务")
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.64))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .accessibilityElement(children: .combine)
    }

    private var homeLoadFailureState: some View {
        VStack(spacing: AppTheme.spacing.md) {
            EmptyStateCard(
                title: "任务加载失败",
                message: "本地数据仍然保留，点击重试后会重新读取。",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                usesNeutralBackground: true
            )

            Button("重试") {
                Task { await viewModel.reload() }
            }
            .font(AppTheme.typography.sized(15, weight: .semibold))
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, 52)
    }

    private func homeStatusBanner(
        message: String,
        retriesLoad: Bool,
        retriesExternalRoute: Bool
    ) -> some View {
        HStack(spacing: AppTheme.spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))

            Text(message)
                .font(AppTheme.typography.sized(13, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)

            if retriesLoad || retriesExternalRoute {
                Button("重试") {
                    if retriesLoad {
                        Task { await viewModel.reload() }
                    } else {
                        viewModel.retryExternalTaskRoute()
                    }
                }
                .font(AppTheme.typography.sized(13, weight: .semibold))
            } else {
                Button {
                    if viewModel.externalRouteErrorMessage != nil {
                        viewModel.clearExternalRouteFailure()
                    } else {
                        viewModel.dismissOperationError()
                    }
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

    /// Scroll to and briefly highlight a task row. Called from both the hot path
    /// (onReceive) and the cold-launch path (.task drain on ScrollViewReader).
    private func highlight(_ id: UUID, via proxy: ScrollViewProxy) {
        highlightedTaskID = id
        let presentationID = viewModel.timelineEntry(for: id)?.presentationID
        withAnimation {
            if let presentationID {
                proxy.scrollTo(presentationID, anchor: .center)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            highlightedTaskID = nil
        }
    }

    private func requestExternalFocus(_ id: UUID, via proxy: ScrollViewProxy) {
        pendingFocusTaskID = id
        highlight(id, via: proxy)
        openPendingExternalFocusIfPossible()
    }

    private func openPendingExternalFocusIfPossible() {
        guard let itemID = pendingFocusTaskID,
              let entry = viewModel.timelineEntry(for: itemID)
        else { return }
        guard entry.isCompleted == false else {
            pendingFocusTaskID = nil
            return
        }
        onOpenTaskDetail(.todo(entry.itemID))
        pendingFocusTaskID = nil
    }

    private func completeTimelineEntry(_ entry: HomeTimelineEntry) {
        Task { @MainActor in
            await viewModel.completeItem(entry.itemID)
        }
    }

    private var routinesModeContent: some View {
        RoutinesListContent(
            viewModel: routinesViewModel,
            isPresented: isRoutinesModePresented,
            contentTopPadding: 0,
            contentBottomPadding: 104,
            showsCanvasBackground: false,
            taskDetailTransition: taskDetailTransition,
            onOpenTaskDetail: onOpenTaskDetail
        )
    }

    private func timelineList(scrollProxy: ScrollViewProxy) -> some View {
        standardTimelineList(scrollProxy: scrollProxy)
    }

    private func standardTimelineList(scrollProxy: ScrollViewProxy) -> some View {
        standardTimelineForeground(scrollProxy: scrollProxy)
    }

    private func standardTimelineForeground(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if #unavailable(iOS 26.0), viewModel.showsOverdueCapsule {
                overdueSummaryButton
                    .zIndex(2)
            }

            ZStack(alignment: .topLeading) {
                if #available(iOS 26.0, *) {
                    timelineScrollView(
                        scrollProxy: scrollProxy,
                        usesDateBar: true
                    )
                        .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                            VStack(spacing: 0) {
                                if viewModel.showsOverdueCapsule {
                                    overdueSummaryButton
                                }
                                if let section = displayedTimelineDateBarSection {
                                    timelineDateBar(section)
                                }
                            }
                        }
                        .applySoftScrollEdgeTransition()
                } else {
                    timelineScrollView(
                        scrollProxy: scrollProxy,
                        usesDateBar: false
                    )
                        .applySoftScrollEdgeTransition()
                }
            }
            .coordinateSpace(name: HomeTimelineFocusCoordinateSpace.name)
            .onChange(of: displayedActiveSections.map(\.id), initial: true) { _, sectionIDs in
                var selection = timelineDateBarSelection
                selection.reconcile(sectionIDs: sectionIDs)
                guard selection != timelineDateBarSelection else { return }
                timelineDateBarSelection = selection
            }
        }
    }

    private var overdueSummaryButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            viewModel.presentOverdueSheet()
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                Text("当前已逾期")
                    .font(AppTheme.typography.scaled(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.86))

                Text(verbatim: String(viewModel.overdueEntryCount))
                    .font(AppTheme.typography.scaled(13, weight: .bold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.colors.overdueAccent)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeOverdueSummaryButtonStyle())
        .animation(timelineDateBarContentAnimation, value: viewModel.overdueEntryCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前已逾期 \(viewModel.overdueEntryCount) 项")
        .accessibilityHint("打开逾期任务列表")
    }

    private func timelineScrollView(
        scrollProxy: ScrollViewProxy,
        usesDateBar: Bool
    ) -> some View {
        let waveSequence = homeModeTimelineWaveSequence
        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 0,
                pinnedViews: usesDateBar ? [] : [.sectionHeaders]
            ) {
                ForEach(displayedActiveSections) { section in
                    Section {
                        timelineRows(
                            section.entries,
                            section: section,
                            rowTransition: activeRowTransition,
                            scrollProxy: scrollProxy
                        )
                    } header: {
                        timelineSectionHeader(section, usesDateBar: usesDateBar)
                    }
                }

                if displayedCompletedEntries.isEmpty == false {
                    todayCompletedHeader
                        .padding(
                            EdgeInsets(
                                top: 12,
                                leading: timelineRowHorizontalInset,
                                bottom: 10,
                                trailing: timelineRowHorizontalInset
                            )
                        )
                        .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
                        .animation(
                            modeTaskRowAnimation(
                                index: waveSequence.todayCompletedHeaderIndex ?? 0,
                                taskCount: waveSequence.elementCount
                            ),
                            value: modeTaskRowsPresented
                        )

                    completedTimelineSection(scrollProxy: scrollProxy)
                }

                if displayedHasWeeklyCompletedEntries {
                    completedVisibilityButton
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(
                            EdgeInsets(
                                top: displayedCompletedEntries.isEmpty ? 12 : 4,
                                leading: timelineRowHorizontalInset,
                                bottom: timelineBottomInset,
                                trailing: timelineRowHorizontalInset
                            )
                        )
                        .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
                        .animation(
                            modeTaskRowAnimation(
                                index: waveSequence.weeklyCompletedSummaryIndex ?? 0,
                                taskCount: waveSequence.elementCount
                            ),
                            value: modeTaskRowsPresented
                        )
                } else if displayedCompletedEntries.isEmpty {
                    Color.clear
                        .frame(height: max(64, timelineBottomInset))
                }
            }
        }
        .defaultScrollAnchor(.top, for: .alignment)
        .scrollIndicators(.hidden)
        .scrollDisabled(isOverlayModeActive)
        .safeAreaPadding(.top, 0)
        .safeAreaPadding(.bottom, 0)
    }

    @ViewBuilder
    private func timelineSectionHeader(
        _ section: HomeTimelineSection,
        usesDateBar: Bool
    ) -> some View {
        if usesDateBar, section.id == displayedActiveSections.first?.id {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        } else if usesDateBar {
            timelineSectionHeaderLayout(section)
                .opacity(timelineDateBarSelection.activeSectionID == section.id ? 0 : 1)
                .accessibilityHidden(timelineDateBarSelection.activeSectionID == section.id)
                .onGeometryChange(for: Bool.self) { proxy in
                    guard timelineDateBarBoundaryMaxY > 0 else { return false }
                    return proxy.frame(in: .global).maxY <= timelineDateBarBoundaryMaxY + 0.5
                } action: { hasCrossedDateBar in
                    var selection = timelineDateBarSelection
                    selection.setCrossed(
                        hasCrossedDateBar,
                        sectionID: section.id,
                        sectionIDs: displayedActiveSections.map(\.id)
                    )
                    guard selection != timelineDateBarSelection else { return }
                    timelineDateBarSelection = selection
                }
        } else {
            timelineSectionHeader(section)
        }
    }

    private func timelineDateBar(_ section: HomeTimelineSection) -> some View {
        let waveSequence = homeModeTimelineWaveSequence
        return ZStack(alignment: .leading) {
            timelineSectionHeaderLayout(section)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(timelineDateBarContentAnimation, value: section.id)
                .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
                .animation(
                    modeTaskRowAnimation(
                        index: waveSequence.dateHeaderIndex ?? 0,
                        taskCount: waveSequence.elementCount
                    ),
                    value: modeTaskRowsPresented
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { maxY in
            guard abs(maxY - timelineDateBarBoundaryMaxY) > 0.5 else { return }
            timelineDateBarBoundaryMaxY = maxY
        }
    }

    @ViewBuilder
    private func timelineSectionHeader(_ section: HomeTimelineSection) -> some View {
        if section.id == displayedActiveSections.first?.id {
            let waveSequence = homeModeTimelineWaveSequence
            timelineSectionHeaderLayout(section)
                .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
                .animation(
                    modeTaskRowAnimation(
                        index: waveSequence.dateHeaderIndex ?? 0,
                        taskCount: waveSequence.elementCount
                    ),
                    value: modeTaskRowsPresented
                )
        } else {
            timelineSectionHeaderLayout(section)
        }
    }

    private var timelineDateBarContentAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.14)
            : .smooth(duration: 0.26, extraBounce: 0)
    }

    private func timelineSectionHeaderLayout(_ section: HomeTimelineSection) -> some View {
        HomeTimelineDateSectionHeader(section: section)
            .padding(.horizontal, timelineRowHorizontalInset)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    private var timelineReorderingControl: some View {
        Button {
            HomeInteractionFeedback.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isTimelineReorderingActive = false
            }
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "line.3.horizontal")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                Text("完成排序")
                    .font(AppTheme.typography.sized(13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.sky)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.sky.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("退出任务排序模式")
    }

    @ViewBuilder
    private func completedTimelineSection(scrollProxy: ScrollViewProxy) -> some View {
        timelineRows(
            displayedCompletedEntries,
            rowTransition: completedRowTransition,
            sectionVisibility: CompletedSectionVisibility(
                isVisible: isCompletedSectionVisible,
                count: displayedCompletedEntries.count
            ),
            scrollProxy: scrollProxy
        )
    }

    private var displayedActiveSections: [HomeTimelineSection] {
        viewModel.activeTimelineSections
    }

    private var displayedTimelineDateBarSection: HomeTimelineSection? {
        guard let activeSectionID = timelineDateBarSelection.activeSectionID else {
            return displayedActiveSections.first
        }
        return displayedActiveSections.first(where: { $0.id == activeSectionID })
            ?? displayedActiveSections.first
    }

    private var displayedCompletedEntries: [HomeTimelineEntry] {
        viewModel.completedTimelineEntries
    }

    private var homeModeTimelineWaveSequence: HomeModeTimelineWaveSequence {
        HomeModeTimelineWaveSequence(
            activeTaskIDs: displayedActiveSections.flatMap { section in
                section.entries.map(\.itemID)
            },
            completedTaskIDs: displayedCompletedEntries.map(\.itemID),
            includesWeeklyCompletedSummary: displayedHasWeeklyCompletedEntries,
            includesDateHeader: displayedTimelineDateBarSection != nil
        )
    }

    private var hasDisplayedTimelineEntries: Bool {
        displayedActiveSections.contains { $0.entries.isEmpty == false }
            || displayedCompletedEntries.isEmpty == false
            || viewModel.showsOverdueCapsule
    }

    private var displayedHasWeeklyCompletedEntries: Bool {
        viewModel.hasWeeklyCompletedEntries
    }

    private var displayedWeeklyCompletedEntryCount: Int {
        viewModel.weeklyCompletedEntryCount
    }

    private var todayCompletedHeader: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Text("今天已完成")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.58))

            Text("\(displayedCompletedEntries.count)")
                .font(AppTheme.typography.sized(11, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.46))
                .frame(minWidth: 20, minHeight: 20)
                .background(
                    Circle()
                        .fill(AppTheme.colors.surfaceElevated.opacity(0.86))
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func timelineRows(
        _ entries: [HomeTimelineEntry],
        section: HomeTimelineSection? = nil,
        rowTransition: AnyTransition? = nil,
        sectionVisibility: CompletedSectionVisibility? = nil,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let waveSequence = homeModeTimelineWaveSequence
        ForEach(entries, id: \.presentationID) { entry in
            let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
            timelineRow(
                entry: entry,
                isDetailPresented: false,
                isDetailExpanded: false,
                motion: .compact,
                scrollProxy: scrollProxy
            )
            .modifier(
                TimelineSwipeActionsModifier(
                    isEnabled: entry.isCompleted == false,
                    canDelete: viewModel.canDeleteItem(entry.itemID),
                    snoozeTitle: viewModel.primarySnoozeTitle,
                    onSnooze: {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.snoozeItem(entry.itemID) }
                    },
                    onDelete: {
                        requestTaskDeletion(entry.itemID)
                    }
                )
            )
            .contextMenu {
                if entry.isCompleted == false {
                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.snoozeItemToTomorrow(entry.itemID) }
                    } label: {
                        Label("推迟到明天", systemImage: "calendar.badge.clock")
                    }

                    if viewModel.isFriday {
                        Button {
                            HomeInteractionFeedback.selection()
                            Task { await viewModel.snoozeItemToNextMonday(entry.itemID) }
                        } label: {
                            Label("推迟到下周一", systemImage: "calendar.badge.clock")
                        }
                    }

                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.convertItemToPeriodicTask(entry.itemID) }
                    } label: {
                        Label("转为定期任务", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if viewModel.canDeleteItem(entry.itemID) {
                        Button(role: .destructive) {
                            requestTaskDeletion(entry.itemID)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .id(entry.presentationID)
            .padding(
                EdgeInsets(
                    top: timelineRowVerticalInset,
                    leading: timelineRowHorizontalInset,
                    bottom: timelineRowVerticalInset,
                    trailing: timelineRowHorizontalInset
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .insertedListItemMotion(
                isInserted: viewModel.isAnimatingInsertion(for: entry.itemID),
                onAnimationCompleted: {
                    viewModel.completeInsertionAnimation(for: entry.itemID)
                }
            )
            .applyTransition(
                rowTransition,
                removal: deletingTaskIDs.contains(entry.itemID)
                    ? taskRemovalTransition
                    : .opacity
            )
            .applyCompletedSectionVisibility(
                sectionVisibility.map { $0.rowVisibility(for: index) }
            )
            .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
            .animation(
                modeTaskRowAnimation(
                    index: waveSequence.taskIndex(for: entry.itemID) ?? index,
                    taskCount: waveSequence.elementCount
                ),
                value: modeTaskRowsPresented
            )
        }
    }

    private func timelineRow(
        entry: HomeTimelineEntry,
        isDetailPresented: Bool,
        isDetailExpanded: Bool,
        motion: TaskExpansionMotion,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        HomeTimelineRow(
            entry: entry,
            isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.itemID, on: viewModel.selectedDate),
            isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.itemID, on: viewModel.selectedDate),
            isDetailPresented: isDetailPresented,
            isDetailExpanded: isDetailExpanded,
            isUrgent: isDetailPresented ? (viewModel.inlineDetailDraft?.isUrgent ?? entry.isUrgent) : entry.isUrgent,
            isFollowed: viewModel.item(for: entry.itemID)?.isFollowed == true,
            expandedTitle: isDetailPresented ? (viewModel.inlineDetailDraft?.title ?? entry.title) : entry.title,
            expandedNotes: isDetailPresented ? (viewModel.inlineDetailDraft?.notes ?? entry.notes) : entry.notes,
            isEditingNotes: false,
            motion: motion,
            requestsInitialTitleFocus: false,
            taskDetailTransition: taskDetailTransition,
            onToggleCompletion: {
                entry.isCompleted
                    ? HomeInteractionFeedback.selection()
                    : HomeInteractionFeedback.completion()
                completeTimelineEntry(entry)
            },
            onOpenDetail: {
                onOpenTaskDetail(.todo(entry.itemID))
            },
            onUpdateTitle: viewModel.updateDraftTitle,
            onUpdateNotes: viewModel.updateDraftNotes,
            onBeginNoteEditing: {},
            onEndNoteEditing: {},
            onInlineFocus: { _ in }
        )
    }

    private func requestTaskDeletion(_ itemID: UUID) {
        guard deletingTaskIDs.insert(itemID).inserted else { return }
        HomeInteractionFeedback.delete()
        Task { @MainActor in
            defer { deletingTaskIDs.remove(itemID) }
            await viewModel.deleteItem(
                itemID,
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

    private var timelineSection: some View {
        let waveSequence = homeModeTimelineWaveSequence
        return ZStack {
            if hasDisplayedTimelineEntries == false {
                VStack(spacing: AppTheme.spacing.xl) {
                    VStack(spacing: AppTheme.spacing.md) {
                        Image("EmptyCalendar")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .accessibilityHidden(true)

                        Text("还没有任务")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                        Text("添加一个新任务，或用 OCR 导入纸面清单")
                            .font(AppTheme.typography.sized(14, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.38))
                    }

                    Button {
                        HomeInteractionFeedback.selection()
                        onCreateTaskTapped()
                    } label: {
                        HStack(spacing: AppTheme.spacing.xs) {
                            Image(systemName: "plus")
                                .font(AppTheme.typography.sized(14, weight: .semibold))

                            Text("新建任务")
                                .font(AppTheme.typography.sized(15, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.colors.title)
                        .padding(.horizontal, AppTheme.spacing.lg)
                        .padding(.vertical, AppTheme.spacing.md)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)

                    if displayedHasWeeklyCompletedEntries {
                        Button {
                            HomeInteractionFeedback.selection()
                            isCompletedVisibilityButtonCompressed = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(110))
                                isCompletedVisibilityButtonCompressed = false
                            }
                            Task {
                                await viewModel.presentWeeklyCompletedSheet()
                            }
                        } label: {
                            Text("本周已完成 \(displayedWeeklyCompletedEntryCount) 项")
                                .font(AppTheme.typography.sized(13, weight: .medium))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .homeModeTaskWave(progress: modeTaskRowsPresented ? 1 : 0)
                        .animation(
                            modeTaskRowAnimation(
                                index: waveSequence.weeklyCompletedSummaryIndex ?? 0,
                                taskCount: waveSequence.elementCount
                            ),
                            value: modeTaskRowsPresented
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                EmptyView()
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: viewModel.selectedDateKey)
        .animation(.smooth(duration: 0.26, extraBounce: 0), value: viewModel.timelineEntryIDs)
        .animation(.smooth(duration: 0.22, extraBounce: 0), value: viewModel.hasCompletedEntries)
    }

    private var completedVisibilityButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            isCompletedVisibilityButtonCompressed = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                isCompletedVisibilityButtonCompressed = false
            }
            Task {
                await viewModel.presentWeeklyCompletedSheet()
            }
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                Text(viewModel.completedVisibilityButtonTitle)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.76))

                Text("\(viewModel.weeklyCompletedEntryCount)")
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(
                        Circle()
                            .fill(AppTheme.colors.background.opacity(0.8))
                    )
            }
            .padding(.leading, AppTheme.spacing.md) // normalized 14→16
            .padding(.trailing, AppTheme.spacing.sm)
            .padding(.vertical, AppTheme.spacing.xs) // normalized 7→6
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(
            x: isCompletedVisibilityButtonCompressed ? 0.92 : 1,
            y: isCompletedVisibilityButtonCompressed ? 0.88 : 1,
            anchor: .center
        )
        .animation(.bouncy(duration: 0.54, extraBounce: 0.28), value: isCompletedVisibilityButtonCompressed)
    }

    private var modeFadeAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .easeOut(duration: 0.16)
    }

    private var taskSurfaceModeAnimation: Animation {
        guard reduceMotion == false else { return .easeInOut(duration: 0.18) }
        return isRoutinesModePresented
            ? .smooth(duration: 0.24, extraBounce: 0)
            : .smooth(duration: 0.34, extraBounce: 0).delay(0.06)
    }

    private func modeTaskRowAnimation(index: Int, taskCount: Int) -> Animation {
        let delay = HomeModeTaskTransitionTiming.delay(
            for: index,
            taskCount: taskCount,
            isPresented: modeTaskRowsPresented,
            reduceMotion: reduceMotion
        )
        return reduceMotion
            ? .easeInOut(duration: 0.18)
            : .linear(duration: HomeModeTaskTransitionTiming.rowDuration).delay(delay)
    }

    private func updateModeTaskRowsPresentation() async {
        let shouldPresent = isRoutinesModePresented == false
        guard shouldPresent else {
            modeTaskRowsPresented = false
            return
        }
        guard reduceMotion == false else {
            modeTaskRowsPresented = true
            return
        }
        guard modeTaskRowsPresented == false else { return }

        try? await Task.sleep(for: HomeModeTaskTransitionTiming.revealDelay)
        guard Task.isCancelled == false else { return }
        modeTaskRowsPresented = true
    }

    private var routinesTaskSurfaceOffset: CGFloat {
        guard reduceMotion == false, isRoutinesModePresented else { return 0 }
        return -8
    }

    private var routinesTaskSurfaceScale: CGFloat {
        guard reduceMotion == false, isRoutinesModePresented else { return 1 }
        return 0.985
    }

    private var routinesTaskSurfaceBlur: CGFloat {
        guard reduceMotion == false, isRoutinesModePresented else { return 0 }
        return 2
    }

    private var isOverlayModeActive: Bool {
        isRoutinesModePresented
    }

    private var timelineTransition: AnyTransition {
        .opacity
    }

    private var activeRowTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: VerticalMotionModifier(offsetY: -34, scale: 0.985, opacity: 0),
                identity: VerticalMotionModifier(offsetY: 0, scale: 1, opacity: 1)
            ),
            removal: .opacity
        )
    }

    private var completedRowTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: VerticalMotionModifier(offsetY: -8, scale: 1, opacity: 0),
                identity: VerticalMotionModifier(offsetY: 0, scale: 1, opacity: 1)
            ),
            removal: .opacity
        )
    }

}

#if DEBUG
#Preview("Home Default") {
    makeHomePreview()
}

#Preview("Home No Overdue Capsule") {
    makeHomePreview(selectedDateOffset: 1)
}

#Preview("Home Empty State") {
    makeHomePreview(selectedDateOffset: 14)
}

@MainActor
private func makeHomePreview(selectedDateOffset: Int? = nil) -> some View {
    let context = AppContext.makeBootstrappedContext()
    if let selectedDateOffset {
        context.homeViewModel.selectDate(
            Calendar.current.date(byAdding: .day, value: selectedDateOffset, to: MockDataFactory.now) ?? MockDataFactory.now
        )
    }

    return HomePreviewContainer(context: context)
}

private struct HomePreviewContainer: View {
    let context: AppContext
    @Namespace private var taskDetailTransition

    var body: some View {
        HomeView(
            viewModel: context.homeViewModel,
            routinesViewModel: context.routinesViewModel,
            isRoutinesModePresented: false,
            onCreateTaskTapped: {},
            taskDetailTransition: taskDetailTransition,
            onOpenTaskDetail: { _ in },
            onCompletedHistoryTapped: { _ in }
        )
    }
}
#endif

enum HomeInlineTaskLayoutMetrics {
    static let actionSlotWidth: CGFloat = 40
    static let checkboxSize: CGFloat = 28
    static let titleGap: CGFloat = AppTheme.spacing.md
    static let titleLeadingInset: CGFloat = actionSlotWidth + titleGap
    static let rowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 32
    static let detailVerticalSpacing: CGFloat = 0
    static let subtaskSpacing: CGFloat = 3
    static let taskTitleLeadingInset: CGFloat = checkboxSize + AppTheme.spacing.sm
    static let attributeLeadingInset: CGFloat = taskTitleLeadingInset
    /// The 20pt subtask mark is centered inside a 28pt action slot, so its
    /// visible left edge begins 4pt inside the detail content.
    static let expandedAttributeLeadingInset: CGFloat = 4
    static let attributeSpacing: CGFloat = 18
    static let attributeMinHeight: CGFloat = TaskAttributeToolbarMetrics.rowHeight
    static let attributeHorizontalPadding: CGFloat = 2
    static let attributeIconSize: CGFloat = 14
    static let attributeIconWidth: CGFloat = 16
    static let attributeTextSize: CGFloat = 14
    /// The shared title identity rests 12pt above its compact origin. Pull the
    /// disclosure upward far enough to preserve the compact stack's 4pt visual
    /// gap between the expanded title and the first detail row.
    static let detailTitleOverlap: CGFloat = 20
    static let detailTopPadding: CGFloat = 0
    static let attributeTopOverlap: CGFloat = 6
    static let detailBottomPadding: CGFloat = 0
    static let lifecycleInlineHeight: CGFloat = 28
    static let creationActionHeight: CGFloat = 44

    static func estimatedDetailHeight(
        subtaskCount: Int,
        showsAddNote: Bool = true,
        note: String? = nil,
        includesCreationActions: Bool = false
    ) -> CGFloat {
        let leadingRowCount = showsAddNote ? 1 : 0
        let rowCount = max(subtaskCount + leadingRowCount + 2, 1)
        let compactRows = CGFloat(leadingRowCount + 1) * compactRowMinHeight
        let subtaskRows = CGFloat(subtaskCount) * rowMinHeight
        let noteHeight: CGFloat = if let note, note.isEmpty == false {
            estimatedNoteHeight(note)
        } else {
            0
        }
        let rowHeights = compactRows + subtaskRows + attributeMinHeight + noteHeight
        let spacings = CGFloat(max(rowCount - 1, 0)) * detailVerticalSpacing
        let subtaskSpacings = CGFloat(max(subtaskCount - 1, 0)) * subtaskSpacing
        return detailTopPadding
            + rowHeights
            + spacings
            + subtaskSpacings
            - attributeTopOverlap
            + lifecycleInlineHeight
            + (includesCreationActions ? creationActionHeight + AppTheme.spacing.sm : 0)
            + detailVerticalSpacing
            + detailBottomPadding
    }

    private static func estimatedNoteHeight(_ note: String) -> CGFloat {
        let explicitLines = max(1, note.split(separator: "\n", omittingEmptySubsequences: false).count)
        let wrappedLines = max(1, Int(ceil(Double(note.count) / 24)))
        return min(CGFloat(max(explicitLines, wrappedLines)) * 20, 260)
    }
}

enum HomeInlineFocusTarget: Hashable {
    case title
    case notes
    case newSubtask
    case subtask(UUID)

    func anchorID(for itemID: UUID) -> String {
        switch self {
        case .title:
            return "inline-title-\(itemID.uuidString)"
        case .notes:
            return "inline-notes-\(itemID.uuidString)"
        case .newSubtask:
            return "inline-new-subtask-\(itemID.uuidString)"
        case .subtask(let subtaskID):
            return "inline-subtask-\(itemID.uuidString)-\(subtaskID.uuidString)"
        }
    }

    var scrollAnchor: UnitPoint {
        .center
    }
}

enum HomeTimelineSubtitleText {
    static func propertyText(for entry: HomeTimelineEntry) -> String {
        var components: [String] = []
        if entry.timeText.isEmpty == false {
            components.append(entry.timeText)
        }

        if entry.reminderText.isEmpty == false {
            components.append(entry.reminderText)
        }

        if entry.subtasks.isEmpty == false {
            components.append("子任务 \(entry.subtaskCompletedCount)/\(entry.subtasks.count)")
        }

        return components.joined(separator: " · ")
    }

    static func text(for entry: HomeTimelineEntry) -> String {
        let properties = propertyText(for: entry)
        return properties
    }
}

struct HomeTimelineRowDisplayText: Equatable {
    let primarySubtitle: String
    let propertyText: String?

    static func text(for entry: HomeTimelineEntry) -> HomeTimelineRowDisplayText {
        text(for: entry, notes: entry.notes)
    }

    static func text(for entry: HomeTimelineEntry, notes: String?) -> HomeTimelineRowDisplayText {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText: String? = if let trimmedNotes, trimmedNotes.isEmpty == false {
            trimmedNotes
        } else {
            nil
        }

        let propertyText = HomeTimelineSubtitleText.propertyText(for: entry)
        return HomeTimelineRowDisplayText(
            primarySubtitle: noteText ?? propertyText,
            propertyText: noteText != nil && propertyText.isEmpty == false ? propertyText : nil
        )
    }
}

struct TaskSharedElementVisual: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let element: TaskSharedElement
    let content: TaskSharedIdentityContent
    var titleLineLimit: Int? = 2
    var noteLineLimit: Int? = nil
    var noteFontSize: CGFloat = 15
    var usesTaskFocusText = false
    var fillsAvailableWidth = true

    @ViewBuilder
    var body: some View {
        switch element {
        case .completion:
            completionMark
        case .title:
            Text(content.title)
                .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(titleColor)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
        case .note:
            if let note = content.note {
                Text(note)
                    .font(AppTheme.typography.scaled(noteFontSize, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(noteLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .progress:
            if content.totalSubtaskCount > 0 {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .strokeBorder(AppTheme.colors.body.opacity(0.16), lineWidth: 2.2)
                        Circle()
                            .inset(by: 1.1)
                            .trim(from: 0, to: progressFraction)
                            .stroke(
                                AppTheme.colors.sky,
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 17, height: 17)

                    Text("\(content.completedSubtaskCount)/\(content.totalSubtaskCount)")
                        .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                        .fontDesign(.rounded)
                }
                .foregroundStyle(subtitleColor)
                .fixedSize()
            }
        case .time:
            if let timeSummary = content.timeSummary {
                attributeToken(icon: "clock", text: timeSummary, color: subtitleColor)
            }
        case .reminder:
            if let reminderSummary = content.reminderSummary {
                attributeToken(icon: "bell", text: reminderSummary, color: subtitleColor)
            }
        case .urgent:
            if content.isUrgent, content.isCompleted == false {
                attributeToken(icon: "flag.fill", text: "", color: AppTheme.colors.coral)
            }
        }
    }

    private var completionMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    content.isCompleted ? Color.clear : AppTheme.colors.body.opacity(0.30),
                    lineWidth: 1.2
                )
            if content.isCompleted {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .offset(
                        x: AppTheme.metrics.checkmarkVisualOffset.width,
                        y: AppTheme.metrics.checkmarkVisualOffset.height
                    )
            }
        }
        .frame(width: 24, height: 24)
    }

    private func attributeToken(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                .frame(width: 16)
            if text.isEmpty == false {
                Text(text)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .fontDesign(.rounded)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(color)
        .fixedSize()
    }

    private var progressFraction: CGFloat {
        guard content.totalSubtaskCount > 0 else { return 0 }
        return CGFloat(content.completedSubtaskCount) / CGFloat(content.totalSubtaskCount)
    }

    private var subtitleColor: Color {
        if usesTaskFocusText, colorScheme == .light, content.isMuted == false {
            return AppTheme.colors.taskFocusBody
        }
        return AppTheme.colors.body.opacity(content.isMuted ? 0.4 : 0.74)
    }

    private var titleColor: Color {
        if usesTaskFocusText, colorScheme == .light, content.isMuted == false {
            return AppTheme.colors.taskFocusTitle
        }
        return content.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title
    }
}

struct HomeTimelineDateBarSelection: Equatable {
    private(set) var crossedSectionIDs: Set<String> = []
    private(set) var activeSectionID: String?

    mutating func reconcile(sectionIDs: [String]) {
        crossedSectionIDs.formIntersection(sectionIDs)
        activeSectionID = sectionIDs.last(where: crossedSectionIDs.contains)
            ?? sectionIDs.first
    }

    mutating func setCrossed(
        _ hasCrossed: Bool,
        sectionID: String,
        sectionIDs: [String]
    ) {
        guard sectionIDs.contains(sectionID) else { return }
        if hasCrossed {
            crossedSectionIDs.insert(sectionID)
        } else {
            crossedSectionIDs.remove(sectionID)
        }
        reconcile(sectionIDs: sectionIDs)
    }
}

private struct HomeTimelineDateSectionHeader: View {
    let section: HomeTimelineSection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(section.title)
                .font(AppTheme.typography.scaled(22, weight: .semibold, relativeTo: .title2))
                .fontDesign(.rounded)
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(section.context)·")

                Text(verbatim: "\(section.count)")
                    .contentTransition(.numericText(value: Double(section.count)))
                    .animation(.snappy(duration: 0.22), value: section.count)

                Text("项")
            }
            .font(AppTheme.typography.scaled(12, weight: .medium, relativeTo: .caption1))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.colors.textTertiary)
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum HomeTimelineFocusCoordinateSpace {
    static let name = "home-timeline-focus"
}

private struct HomeTimelineRowShell<Symbol: View, Content: View>: View {
    let symbol: Symbol
    let content: Content

    init(
        @ViewBuilder symbol: () -> Symbol,
        @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol()
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .taskTitleCenter, spacing: AppTheme.spacing.sm) {
            symbol
                .alignmentGuide(.taskTitleCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.taskMorphBackgroundTextOpacity) private var backgroundTextOpacity
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let isAnimatingReopening: Bool
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let isUrgent: Bool
    let isFollowed: Bool
    let expandedTitle: String
    let expandedNotes: String?
    let isEditingNotes: Bool
    let motion: TaskExpansionMotion
    let requestsInitialTitleFocus: Bool
    let taskDetailTransition: Namespace.ID?
    let inputCommitRequestRevision: UInt
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    let onUpdateTitle: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onBeginNoteEditing: () -> Void
    let onEndNoteEditing: () -> Void
    let onInlineFocus: (HomeInlineFocusTarget) -> Void
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @AccessibilityFocusState private var isTitleAccessibilityFocused: Bool
    @State private var badgeOutlineOpacity = 1.0
    @State private var badgeFillScale: CGFloat = 0.5
    @State private var badgeFillOpacity = 0.0
    @State private var isCompletionCheckmarkPresented = false
    @State private var reopeningCheckmarkOpacity: Double = 1
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
    @State private var isCommittingNotes = false
    @State private var didRequestInitialTitleFocus = false

    init(
        entry: HomeTimelineEntry,
        isAnimatingCompletion: Bool,
        isAnimatingReopening: Bool,
        isDetailPresented: Bool,
        isDetailExpanded: Bool,
        isUrgent: Bool,
        isFollowed: Bool,
        expandedTitle: String,
        expandedNotes: String?,
        isEditingNotes: Bool,
        motion: TaskExpansionMotion,
        requestsInitialTitleFocus: Bool,
        taskDetailTransition: Namespace.ID? = nil,
        inputCommitRequestRevision: UInt = 0,
        onToggleCompletion: @escaping () -> Void,
        onOpenDetail: @escaping () -> Void,
        onUpdateTitle: @escaping (String) -> Void,
        onUpdateNotes: @escaping (String) -> Void,
        onBeginNoteEditing: @escaping () -> Void,
        onEndNoteEditing: @escaping () -> Void,
        onInlineFocus: @escaping (HomeInlineFocusTarget) -> Void
    ) {
        self.entry = entry
        self.isAnimatingCompletion = isAnimatingCompletion
        self.isAnimatingReopening = isAnimatingReopening
        self.isDetailPresented = isDetailPresented
        self.isDetailExpanded = isDetailExpanded
        self.isUrgent = isUrgent
        self.isFollowed = isFollowed
        self.expandedTitle = expandedTitle
        self.expandedNotes = expandedNotes
        self.isEditingNotes = isEditingNotes
        self.motion = motion
        self.requestsInitialTitleFocus = requestsInitialTitleFocus
        self.taskDetailTransition = taskDetailTransition
        self.inputCommitRequestRevision = inputCommitRequestRevision
        self.onToggleCompletion = onToggleCompletion
        self.onOpenDetail = onOpenDetail
        self.onUpdateTitle = onUpdateTitle
        self.onUpdateNotes = onUpdateNotes
        self.onBeginNoteEditing = onBeginNoteEditing
        self.onEndNoteEditing = onEndNoteEditing
        self.onInlineFocus = onInlineFocus
        _titleDraft = State(initialValue: expandedTitle)
        _notesDraft = State(initialValue: expandedNotes ?? "")
        _isEditingTitle = State(
            initialValue: requestsInitialTitleFocus && isDetailPresented
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeTimelineRowShell {
                Button(action: onToggleCompletion) {
                    timelineSymbol
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, -8)
                .padding(.vertical, -10)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } content: {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    titleContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scaleEffect(motion.identityScale, anchor: .topLeading)
            .offset(x: motion.identityOffsetX, y: motion.identityOffsetY)
        }
        .onAppear {
            titleDraft = expandedTitle
            notesDraft = expandedNotes ?? ""
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
            } else if entry.isCompleted == false {
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
        .onChange(of: expandedTitle) { _, title in
            guard isTitleFocused == false, isEditingTitle == false else { return }
            titleDraft = title
        }
        .onChange(of: expandedNotes) { _, notes in
            guard isNotesFocused == false, isEditingNotes == false else { return }
            notesDraft = notes ?? ""
        }
        .onChange(of: isEditingNotes) { _, isEditing in
            if isEditing {
                notesDraft = expandedNotes ?? ""
                onInlineFocus(.notes)
                Task { @MainActor in
                    await Task.yield()
                    isNotesFocused = true
                }
            } else {
                isNotesFocused = false
            }
        }
        .onChange(of: isDetailExpanded) { _, isExpanded in
            guard isExpanded == false, isEditingNotes || isNotesFocused else { return }
            commitNotesAfterFocusUpdate()
        }
        .onChange(of: isDetailPresented) { _, isPresented in
            guard isPresented == false else { return }
            isEditingTitle = false
            isCommittingTitle = false
            isTitleFocused = false
            isCommittingNotes = false
            isNotesFocused = false
            onEndNoteEditing()
            Task { @MainActor in
                await Task.yield()
                isTitleAccessibilityFocused = true
            }
        }
    }

    private var shouldPlayCompletionAnimation: Bool {
        isAnimatingCompletion && entry.isCompleted == false
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

    private var displaySubtitle: String {
        rowDisplayText.primarySubtitle
    }

    private var displayPropertyText: String? {
        rowDisplayText.propertyText
    }

    private var rowDisplayText: HomeTimelineRowDisplayText {
        HomeTimelineRowDisplayText.text(for: entry, notes: visibleNotes)
    }

    private var visibleNotes: String? {
        isDetailPresented ? expandedNotes : entry.notes
    }

    private var showsSubtitle: Bool {
        displaySubtitle.isEmpty == false || (isDetailPresented && isEditingNotes)
    }

    private var titleContent: some View {
        titleStack
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay {
                if entry.isCompleted == false {
                    Button {
                        if isDetailPresented {
                            beginTitleEditing()
                        } else {
                            onOpenDetail()
                        }
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(isEditingTitle == false && isEditingNotes == false)
                    .accessibilityFocused($isTitleAccessibilityFocused)
                    .accessibilityLabel(isDetailPresented ? "编辑任务标题" : "展开任务")
                }
            }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Group {
                if isEditingTitle {
                    expandedTitleEditor
                } else if isDetailPresented {
                    TaskMorphInterpolatedHeightRegion(
                        progress: motion.layoutProgress,
                        compact: { sourceTitleVisual(lineLimit: 2) },
                        expanded: { sourceTitleVisual(lineLimit: nil) },
                        visible: { sourceTitleVisual(lineLimit: nil) }
                    )
                } else {
                    sourceTitleVisual(lineLimit: 2)
                }
            }
            .alignmentGuide(.taskTitleCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }

            if hasCompactContent {
                if isDetailPresented {
                    TaskMorphMeasuredRegion(
                        progress: motion.compactHeightProgress,
                        isInteractive: false
                    ) {
                        compactContent
                            .opacity(motion.collapsedOpacity)
                    }
                } else {
                    compactContent
                }
            }

        }
        .frame(maxWidth: isDetailPresented ? .infinity : nil, alignment: .leading)
        .opacity(backgroundTextOpacity)
        .taskDetailMatchedTransitionSource(
            .todo(entry.itemID),
            in: taskDetailTransition,
            isEnabled: isDetailPresented == false
        )
    }

    private var hasCompactContent: Bool {
        showsSubtitle || displayPropertyText != nil
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            if showsSubtitle {
                subtitleContent
            }

            if let displayPropertyText {
                propertySubtitleText(displayPropertyText)
            }
        }
        .frame(maxWidth: isDetailPresented ? .infinity : nil, alignment: .leading)
    }

    private var sharedIdentityContent: TaskSharedIdentityContent {
        TaskSharedIdentityContent.make(
            entry: entry,
            title: isDetailPresented ? expandedTitle : entry.title,
            notes: visibleNotes
        )
    }

    private var sharedAttributeAccessibilityLabel: String {
        var labels: [String] = []
        if sharedIdentityContent.totalSubtaskCount > 0 {
            labels.append("子任务 \(sharedIdentityContent.completedSubtaskCount) / \(sharedIdentityContent.totalSubtaskCount)")
        }
        if let time = sharedIdentityContent.timeSummary { labels.append(time) }
        if let reminder = sharedIdentityContent.reminderSummary { labels.append("提醒 \(reminder)") }
        if sharedIdentityContent.isUrgent { labels.append("紧急") }
        return labels.joined(separator: "，")
    }

    @ViewBuilder
    private func sourceTitleVisual(lineLimit: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.sm) {
            TaskSharedElementVisual(
                element: .title,
                content: sharedIdentityContent,
                titleLineLimit: lineLimit,
                usesTaskFocusText: isDetailPresented,
                fillsAvailableWidth: isDetailPresented
            )

            if isDetailPresented == false,
               entry.isCompleted == false,
               isUrgent || isFollowed {
                HStack(spacing: AppTheme.spacing.xs) {
                    if isUrgent {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(AppTheme.colors.coral)
                            .accessibilityLabel("紧急")
                    }

                    if isFollowed {
                        Image(systemName: "scope")
                            .foregroundStyle(AppTheme.colors.sky)
                            .accessibilityLabel("已关注")
                    }
                }
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var subtitleContent: some View {
        if isDetailPresented, isEditingNotes {
            HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                TextField("添加备注", text: $notesDraft, axis: .vertical)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($isNotesFocused)
                    .id(HomeInlineFocusTarget.notes.anchorID(for: entry.itemID))
                    .onSubmit {
                        commitNotesAfterFocusUpdate()
                    }
                    .onChange(of: isNotesFocused) { _, focused in
                        if focused {
                            onInlineFocus(.notes)
                        } else if isEditingNotes, isCommittingNotes == false {
                            commitNotesAfterFocusUpdate()
                        }
                    }

                if requestsInitialTitleFocus == false {
                    inlineSaveButton {
                        commitNotesAfterFocusUpdate()
                    }
                }
            }
        } else if visibleNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Button {
                guard isDetailPresented else { return }
                onBeginNoteEditing()
            } label: {
                subtitleText(displaySubtitle)
                    .frame(
                        maxWidth: isDetailPresented ? .infinity : nil,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isDetailPresented)
            .accessibilityLabel("编辑备注")
        } else {
            propertySubtitleText(displaySubtitle)
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(subtitleColor)
            .lineLimit(isDetailPresented ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: isDetailPresented ? .infinity : nil, alignment: .leading)
    }

    private func propertySubtitleText(_ text: String) -> some View {
        var attributedText = AttributedString(text)
        if let labelRange = attributedText.range(of: "子任务 ") {
            attributedText[labelRange].foregroundColor = subtitleColor.opacity(0.72)
        }

        return Text(attributedText)
            .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(subtitleColor)
            .lineLimit(isDetailPresented ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: isDetailPresented ? .infinity : nil, alignment: .leading)
    }

    private func beginTitleEditing() {
        titleDraft = expandedTitle
        isEditingTitle = true
        onInlineFocus(.title)

        Task { @MainActor in
            await Task.yield()
            isTitleFocused = true
        }
    }

    private var expandedTitleEditor: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            TextField(
                "任务标题",
                text: $titleDraft,
                axis: .vertical
            )
            .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(expandedTitleColor)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .lineLimit(1...4)
            .focused($isTitleFocused)
            .onChange(of: titleDraft) { _, title in
                guard isDetailPresented else { return }
                onUpdateTitle(title)
            }
            .onSubmit {
                commitTitleAfterFocusUpdate()
            }
            .id(HomeInlineFocusTarget.title.anchorID(for: entry.itemID))
            .onAppear {
                titleDraft = expandedTitle
            }
            .onChange(of: isTitleFocused) { _, isFocused in
                if isFocused {
                    isEditingTitle = true
                    titleDraft = expandedTitle
                    onInlineFocus(.title)
                } else if isCommittingTitle == false, isEditingTitle {
                    commitTitleAfterFocusUpdate()
                }
            }

            if requestsInitialTitleFocus == false {
                inlineSaveButton {
                    commitTitleAfterFocusUpdate()
                }
            }
        }
    }

    private func inlineSaveButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("确认", systemImage: "checkmark")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(AppTheme.colors.sky)
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 54, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("确认文本")
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
            commitTitle()
            isEditingTitle = false
            isCommittingTitle = false
            action?()
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != expandedTitle else { return }
        onUpdateTitle(trimmed)
    }

    private func commitNotesAfterFocusUpdate() {
        guard isEditingNotes || isNotesFocused else { return }
        guard isCommittingNotes == false else { return }
        isCommittingNotes = true
        Task { @MainActor in
            notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
            isNotesFocused = false
            await Task.yield()
            onUpdateNotes(notesDraft)
            onEndNoteEditing()
            isCommittingNotes = false
        }
    }

    private var subtitleColor: Color {
        if isDetailPresented, colorScheme == .light, entry.isMuted == false {
            return AppTheme.colors.taskFocusBody
        }
        return AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.74)
    }

    private var expandedTitleColor: Color {
        if isDetailPresented, colorScheme == .light, entry.isMuted == false {
            return AppTheme.colors.taskFocusTitle
        }
        return entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title
    }

    @ViewBuilder
    private var timelineSymbol: some View {
        checkmarkBadge
            .frame(width: 24, height: 24)
    }

    private var checkmarkBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(shouldPlayCompletionAnimation ? badgeFillOpacity : (entry.isCompleted ? 0 : badgeFillOpacity))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    ringColor,
                    lineWidth: shouldPlayCompletionAnimation ? 1.4 : 1.2
                )
                .opacity(outlineOpacity)

            if entry.isCompleted || isCompletionCheckmarkPresented || isAnimatingReopening {
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

        if entry.isCompleted {
            return .clear
        }

        if shouldPlayCompletionAnimation {
            return AppTheme.colors.body.opacity(0.32)
        }

        return AppTheme.colors.body.opacity(isDetailPresented ? 0.38 : 0.30)
    }

    private var outlineOpacity: Double {
        if isAnimatingReopening { return badgeOutlineOpacity }
        if entry.isCompleted { return 0 }
        if shouldPlayCompletionAnimation { return badgeOutlineOpacity }
        return 1
    }

}

private struct TimelineSwipeActionsModifier: ViewModifier {
    let isEnabled: Bool
    let canDelete: Bool
    let snoozeTitle: String
    let onSnooze: () -> Void
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onSnooze()
                    } label: {
                        Label(snoozeTitle, systemImage: "calendar.badge.clock")
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

private struct WeeklyCompletedSheet: View {
    let items: [Item]
    let count: Int
    let isLoading: Bool
    let didFailLoading: Bool
    let weekdayLabel: (Date) -> String
    let onOpenFullHistory: () -> Void
    let onRefresh: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    emptyRow
                } else {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                            .listRowInsets(
                                EdgeInsets(
                                    top: AppTheme.spacing.md,
                                    leading: AppTheme.spacing.xl,
                                    bottom: AppTheme.spacing.xs,
                                    trailing: AppTheme.spacing.xl
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        ForEach(section.items) { item in
                            CompletedTaskRow(
                                item: item,
                                subtitle: subtitle(for: item),
                                trailingText: item.completedAt.map(weekdayLabel) ?? "",
                                showsArchivedDate: false,
                                archivedDateText: ""
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: AppTheme.spacing.sm,
                                    leading: AppTheme.spacing.xl,
                                    bottom: AppTheme.spacing.md,
                                    trailing: AppTheme.spacing.xl
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await onRefresh()
            }
            .applySoftScrollEdgeTransition()
            .navigationTitle("本周已完成")
            .navigationSubtitle("不含今天，共 \(count) 项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    weeklyCompletedToolbar
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    weeklyCompletedToolbar
                }
            }
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
    }

    @ToolbarContentBuilder
    private var weeklyCompletedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HomeInteractionFeedback.selection()
                onOpenFullHistory()
            } label: {
                Text("查看全部")
            }
            .font(.body)
            .foregroundStyle(AppTheme.colors.sky)
            .frame(minHeight: 44)
        }
    }

    private var emptyRow: some View {
        VStack(spacing: AppTheme.spacing.sm) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: emptySystemImage)
                    .font(AppTheme.typography.sized(24, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.36))
            }

            Text(emptyMessage)
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.xl)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptySystemImage: String {
        didFailLoading && count > 0 ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var emptyMessage: String {
        if isLoading {
            return "正在加载"
        }
        if didFailLoading && count > 0 {
            return "历史列表暂时无法加载，下拉刷新重试"
        }
        return "本周还没有历史完成任务"
    }

    private var sections: [WeeklyCompletedSection] {
        let grouped = Dictionary(grouping: items) { item in
            weekdaySortKey(for: item.completedAt ?? .distantPast)
        }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let items = grouped[key] else { return nil }
            let sorted = items.sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return WeeklyCompletedSection(
                id: key,
                title: weekdayTitle(forSortKey: key),
                items: sorted
            )
        }
    }

    private func subtitle(for item: Item) -> String {
        if item.subtasks.isEmpty == false {
            return "\(item.subtasks.filter(\.isCompleted).count)/\(item.subtasks.count) 子任务"
        }
        if let notes = item.notes, notes.isEmpty == false {
            return notes
        }
        return "已完成"
    }

    private func weekdaySortKey(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let order: Int
        switch weekday {
        case 6: order = 5
        case 5: order = 4
        case 4: order = 3
        case 3: order = 2
        case 2: order = 1
        default: order = 0
        }
        return order.formatted(.number.precision(.integerLength(2)))
    }

    private func weekdayTitle(forSortKey key: String) -> String {
        switch Int(key) ?? 0 {
        case 5: return "周五"
        case 4: return "周四"
        case 3: return "周三"
        case 2: return "周二"
        case 1: return "周一"
        default: return "其他"
        }
    }
}

private struct WeeklyCompletedSection: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}

private struct HomeOverdueSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: HomeViewModel
    @State private var displayedEntries: [HomeOverdueEntry] = []
    @State private var animatingCompletionIDs: Set<UUID> = []
    @State private var reschedulingIDs: Set<UUID> = []
    @State private var isReschedulingAll = false
    @State private var batchFailureCount = 0
    @State private var batchProgressCompleted = 0
    @State private var batchProgressTotal = 0

    private var entries: [HomeOverdueEntry] {
        viewModel.overdueSummaryEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.lg) // normalized 22→20
                .padding(.bottom, AppTheme.spacing.sm)

            overdueList
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.bottom, AppTheme.spacing.xs) // normalized 8→6
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            syncDisplayedEntries(with: entries)
        }
        .onChange(of: entries) { _, newValue in
            guard isReschedulingAll == false else { return }
            syncDisplayedEntries(with: newValue)
            dismissIfFinished()
        }
        .onChange(of: viewModel.overdueEntryCount) { _, newValue in
            guard isReschedulingAll == false else { return }
            guard newValue == 0 else { return }
            dismissIfFinished()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .presentationCornerRadius(nil)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.spacing.md) {
                headerSummary
                Spacer(minLength: AppTheme.spacing.md)
                rescheduleAllButton
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                headerSummary
                rescheduleAllButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Text("逾期任务")
                .font(AppTheme.typography.sized(24, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            Text("统一在这里处理所有已逾期任务")
                .font(AppTheme.typography.sized(13, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))

            Text(batchFailureCount > 0 ? "\(batchFailureCount) 项失败，可重试" : "共 \(displayedEntries.count) 项")
                .font(AppTheme.typography.sized(12, weight: .semibold))
                .foregroundStyle(AppTheme.colors.coral.opacity(0.84))
        }
    }

    private var rescheduleAllButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            Task {
                await handleRescheduleAllToToday()
            }
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                if isReschedulingAll {
                    ProgressView(
                        value: Double(batchProgressCompleted),
                        total: Double(max(batchProgressTotal, 1))
                    )
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                Text("全部改到今天")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.colors.sky)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .disabled(isReschedulingAll || displayedEntries.isEmpty)
        .accessibilityLabel(isReschedulingAll ? "正在全部改到今天" : "全部改到今天")
        .accessibilityValue(
            isReschedulingAll
                ? "已处理 \(batchProgressCompleted) 项，共 \(batchProgressTotal) 项"
                : ""
        )
        .accessibilityHint("将当前所有逾期任务迁移到今天")
    }

    private var overdueList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.spacing.md) {
                overdueRows
            }
            .padding(.top, 2) // specific visual offset, not a tier
            .padding(.bottom, AppTheme.spacing.sm)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var overdueRows: some View {
        ForEach(displayedEntries) { entry in
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                HomeTimelineRow(
                    entry: HomeTimelineEntry(
                        id: entry.id,
                        presentationID: "overdue-\(entry.id.uuidString)",
                        title: entry.title,
                        notes: entry.detailText,
                        timeText: entry.timeText,
                        reminderText: "",
                        statusText: "已逾期",
                        isUrgent: false,
                        isMuted: false,
                        isCompleted: false,
                        timingUrgency: .overdue,
                        relationText: nil,
                        primaryAvatar: nil,
                        secondaryAvatar: nil,
                        lastActionAt: nil,
                        createdAt: entry.createdAt,
                        subtasks: [],
                        subtaskCompletedCount: 0
                    ),
                    isAnimatingCompletion: animatingCompletionIDs.contains(entry.id),
                    isAnimatingReopening: false,
                    isDetailPresented: false,
                    isDetailExpanded: false,
                    isUrgent: false,
                    isFollowed: false,
                    expandedTitle: entry.title,
                    expandedNotes: entry.detailText,
                    isEditingNotes: false,
                    motion: .compact,
                    requestsInitialTitleFocus: false,
                    onToggleCompletion: {
                        HomeInteractionFeedback.completion()
                        Task {
                            await handleCompletion(for: entry.id)
                        }
                    },
                    onOpenDetail: {
                        HomeInteractionFeedback.selection()
                    },
                    onUpdateTitle: { _ in },
                    onUpdateNotes: { _ in },
                    onBeginNoteEditing: {},
                    onEndNoteEditing: {},
                    onInlineFocus: { _ in }
                )

                overdueRescheduleButton(for: entry)
                    .padding(.leading, HomeInlineTaskLayoutMetrics.actionSlotWidth + AppTheme.spacing.md)
            }
            .padding(.vertical, AppTheme.spacing.sm)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .top))
            )
            .allowsHitTesting(isReschedulingAll == false)
        }
    }

    private func overdueRescheduleButton(for entry: HomeOverdueEntry) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            Task {
                await handleRescheduleToToday(for: entry.id)
            }
        } label: {
            Label("改到今天", systemImage: "calendar")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title.opacity(reschedulingIDs.contains(entry.id) ? 0.32 : 0.68))
                .padding(.horizontal, AppTheme.spacing.sm)
                .frame(minHeight: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill).opacity(0.62))
                )
        }
        .buttonStyle(.plain)
        .disabled(reschedulingIDs.contains(entry.id) || isReschedulingAll)
        .accessibilityLabel("将逾期任务改到今天")
    }

    private func handleCompletion(for itemID: UUID) async {
        guard animatingCompletionIDs.insert(itemID).inserted else { return }

        async let completionTask: Void = viewModel.completeItem(itemID)

        try? await Task.sleep(for: .milliseconds(520))

        withAnimation(.bouncy(duration: 0.54, extraBounce: 0.08)) {
            displayedEntries.removeAll { $0.id == itemID }
        }
        if batchFailureCount > 0 {
            batchFailureCount = displayedEntries.count
        }

        _ = await completionTask
        animatingCompletionIDs.remove(itemID)
        dismissIfFinished()
    }

    private func handleRescheduleToToday(for itemID: UUID) async {
        guard reschedulingIDs.insert(itemID).inserted else { return }

        let didSucceed = await viewModel.rescheduleOverdueItemToToday(itemID)
        guard didSucceed else {
            reschedulingIDs.remove(itemID)
            return
        }

        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.26)) {
            displayedEntries.removeAll { $0.id == itemID }
        }
        if batchFailureCount > 0 {
            batchFailureCount = displayedEntries.count
        }

        reschedulingIDs.remove(itemID)
        dismissIfFinished()
    }

    private func handleRescheduleAllToToday() async {
        guard isReschedulingAll == false, displayedEntries.isEmpty == false else { return }
        isReschedulingAll = true
        batchFailureCount = 0
        batchProgressCompleted = 0
        batchProgressTotal = displayedEntries.count

        let result = await viewModel.rescheduleAllOverdueItemsToToday { completedCount, totalCount in
            batchProgressCompleted = completedCount
            batchProgressTotal = totalCount
        }
        let succeededIDs = Set(result.succeededIDs)
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.28)) {
            displayedEntries.removeAll { succeededIDs.contains($0.id) }
        }

        if result.succeededIDs.isEmpty == false, reduceMotion == false {
            try? await Task.sleep(for: .milliseconds(220))
        }

        batchFailureCount = result.failedIDs.count
        isReschedulingAll = false
        batchProgressCompleted = 0
        batchProgressTotal = 0
        syncDisplayedEntries(with: entries)
        if result.isCompleteSuccess {
            dismissIfFinished()
        }
    }

    private func syncDisplayedEntries(with sourceEntries: [HomeOverdueEntry]) {
        var remainingEntries = Dictionary(uniqueKeysWithValues: sourceEntries.map { ($0.id, $0) })
        var nextEntries: [HomeOverdueEntry] = []

        for entry in displayedEntries {
            if let updatedEntry = remainingEntries.removeValue(forKey: entry.id) {
                nextEntries.append(updatedEntry)
            } else if animatingCompletionIDs.contains(entry.id)
                || reschedulingIDs.contains(entry.id) {
                nextEntries.append(entry)
            }
        }

        for entry in sourceEntries where remainingEntries[entry.id] != nil {
            nextEntries.append(entry)
            remainingEntries.removeValue(forKey: entry.id)
        }

        displayedEntries = nextEntries
        if batchFailureCount > displayedEntries.count {
            batchFailureCount = displayedEntries.count
        }
    }

    private func dismissIfFinished() {
        guard displayedEntries.isEmpty, viewModel.overdueEntryCount == 0 else { return }
        dismiss()
    }
}

private struct VerticalMotionModifier: ViewModifier {
    let offsetY: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
    }
}

private struct CompletedSectionVisibility {
    let isVisible: Bool
    let count: Int

    func rowVisibility(for index: Int) -> CompletedRowVisibility {
        CompletedRowVisibility(
            isVisible: isVisible,
            index: index,
            count: count
        )
    }
}

private struct CompletedSectionMotionModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: isVisible ? 0 : 102)
            .scaleEffect(x: isVisible ? 1 : 1.016, y: isVisible ? 1 : 0.958, anchor: .center)
            .opacity(isVisible ? 1 : 0)
    }
}

private struct HomeOverdueSummaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.64 : 1)
    }
}

private struct CompletedRowVisibility {
    let isVisible: Bool
    let index: Int
    let count: Int
}

private struct CompletedRowCascadeModifier: ViewModifier {
    let visibility: CompletedRowVisibility

    private var animation: Animation {
        let delayIndex = visibility.isVisible ? visibility.index : max(visibility.count - visibility.index - 1, 0)
        return .smooth(duration: visibility.isVisible ? 0.24 : 0.18, extraBounce: 0)
            .delay(Double(delayIndex) * 0.018)
    }

    func body(content: Content) -> some View {
        content
            .offset(y: visibility.isVisible ? 0 : 12)
            .scaleEffect(
                x: 1,
                y: visibility.isVisible ? 1 : 0.982,
                anchor: .center
            )
            .opacity(visibility.isVisible ? 1 : 0)
            .animation(animation, value: visibility.isVisible)
    }
}

private extension View {
    @ViewBuilder
    func applyTransition(
        _ transition: AnyTransition?,
        removal: AnyTransition = .opacity
    ) -> some View {
        if let transition {
            self.transition(.asymmetric(insertion: transition, removal: removal))
        } else {
            self
        }
    }

    @ViewBuilder
    func applyCompletedSectionVisibility(_ visibility: CompletedRowVisibility?) -> some View {
        switch visibility {
        case let visibility?:
            self
                .modifier(CompletedRowCascadeModifier(visibility: visibility))
                .allowsHitTesting(visibility.isVisible)
        case nil:
            self
        }
    }
}
