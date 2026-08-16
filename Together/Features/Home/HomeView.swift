import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: HomeViewModel
    @Bindable var morphSession: HomeMorphSession
    @Bindable var projectsViewModel: ProjectsViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let isProjectModePresented: Bool
    let isRoutinesModePresented: Bool
    let onCreateTaskTapped: () -> Void
    let onCompletedHistoryTapped: (CompletedHistoryFilter) -> Void
    @State private var isCompletedVisibilityButtonCompressed = false
    @State private var isCompletedSectionVisible = true
    @State private var highlightedTaskID: UUID?
    @State private var isTimelineReorderingActive = false
    @State private var hasHandledInitialSelectedDateTask = false
    @State private var frozenActiveSections: [HomeTimelineSection]?
    @State private var frozenCompletedEntries: [HomeTimelineEntry]?
    @State private var frozenHasWeeklyCompletedEntries: Bool?
    @State private var frozenWeeklyCompletedEntryCount: Int?
    @State private var pendingFocusTaskID: UUID?
    @State private var editingNoteTaskID: UUID?
    @State private var timelineMorphViewport = TaskMorphViewportCoordinator()
    @State private var timelineDateBarSelection = HomeTimelineDateBarSelection()
    @State private var timelineDateBarBoundaryMaxY: CGFloat = 0

    private let timelineRowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let timelineRowVerticalInset: CGFloat = 8
    private let timelineBottomInset: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            backgroundView
                .brightness(morphSession.isFocusDepthActive ? backgroundDimBrightness : 0)

            contentCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .font(AppTheme.typography.body)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.performDeferredMaintenanceIfNeeded()
        }
        .task(id: viewModel.selectedDateKey) {
            guard morphSession.isActive == false else { return }
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
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active,
                  morphSession.phase == .heroEntering,
                  let token = morphSession.currentToken()
            else { return }
            morphSession.finishHero(using: token)
        }
        .onChange(of: morphSession.phase) { _, phase in
            switch phase {
            case .heroEntering, .active, .saving, .collapsing:
                if frozenActiveSections == nil {
                    frozenActiveSections = viewModel.activeTimelineSections
                    frozenCompletedEntries = viewModel.completedTimelineEntries
                    frozenHasWeeklyCompletedEntries = viewModel.hasWeeklyCompletedEntries
                    frozenWeeklyCompletedEntryCount = viewModel.weeklyCompletedEntryCount
                }
            case .relocating, .idle:
                frozenActiveSections = nil
                frozenCompletedEntries = nil
                frozenHasWeeklyCompletedEntries = nil
                frozenWeeklyCompletedEntryCount = nil
            }

            if phase == .idle {
                timelineMorphViewport.reset()
            }
        }
        .onChange(of: morphSession.visualState) { oldState, newState in
            guard case .persisted(.todo, let itemID) = morphSession.subject else { return }
            if oldState == .expanded, newState == .compact {
                timelineMorphViewport.beginCollapse(for: itemID)
            } else if oldState == .compact, newState == .expanded {
                timelineMorphViewport.resumeExpansion(for: itemID)
            }
        }
        .onChange(of: viewModel.items.map(\.id)) { _, itemIDs in
            guard case .persisted(.todo, let itemID) = morphSession.subject,
                  itemIDs.contains(itemID) == false
            else { return }
            viewModel.dismissItemDetail()
            morphSession.recover()
        }
        .accessibilityAction(.escape) {
            morphSession.requestDismissal()
        }
    }

    private var backgroundView: some View {
        GradientGridBackground()
    }

    private var backgroundDimBrightness: Double {
        colorScheme == .dark ? -0.06 : -0.10
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
                .animation(modeFadeAnimation, value: isProjectModePresented)

            if isProjectModePresented {
                projectsModeContent
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .allowsHitTesting(true)
            }

            if isRoutinesModePresented {
                routinesModeContent
                    .transition(.opacity.combined(with: .offset(y: 12)))
                    .allowsHitTesting(true)
            }
        }
        .animation(projectModeAnimation, value: isProjectModePresented)
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
                .applyHomeScrollEdgeTransition()
                .transition(timelineTransition)
            } else if morphSession.isActive == false,
                      viewModel.items.isEmpty,
                      viewModel.loadState == .loading || viewModel.loadState == .idle {
                homeLoadingState
            } else if morphSession.isActive == false,
                      viewModel.items.isEmpty,
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
                .applyHomeScrollEdgeTransition()
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
                        .task(id: morphSession.phase) {
                            guard morphSession.phase == .relocating,
                                  morphSession.isCreationFlow,
                                  case .persisted(.todo, _) = morphSession.subject,
                                  let presentationID = morphSession.placement?.presentationID,
                                  let token = morphSession.currentToken()
                            else { return }
                            await Task.yield()
                            var transaction = Transaction()
                            transaction.animation = nil
                            withTransaction(transaction) {
                                scrollProxy.scrollTo(presentationID, anchor: .center)
                            }
                            await Task.yield()
                            morphSession.enableCreationListReveal(using: token)
                        }
                        .onChange(of: morphSession.phase) { _, phase in
                            guard phase == .idle, let itemID = pendingFocusTaskID else { return }
                            requestExternalFocus(itemID, via: scrollProxy)
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
        guard morphSession.isActive == false else { return }
        highlight(id, via: proxy)
        openPendingExternalFocusIfPossible()
    }

    private func openPendingExternalFocusIfPossible() {
        guard morphSession.isActive == false,
              let itemID = pendingFocusTaskID,
              let entry = viewModel.timelineEntry(for: itemID),
              openInlineTaskDetail(entry)
        else { return }
        pendingFocusTaskID = nil
    }

    private func completeTimelineEntry(_ entry: HomeTimelineEntry) {
        Task { @MainActor in
            await viewModel.completeItem(entry.itemID)
        }
    }

    @discardableResult
    private func openInlineTaskDetail(_ entry: HomeTimelineEntry) -> Bool {
        if morphSession.isActive {
            var reversedCollapse = false
            withAnimation(morphGeometryAnimation) {
                reversedCollapse = morphSession.reverseDetailCollapse(
                    domain: .todo,
                    id: entry.itemID
                ) != nil
            }
            if reversedCollapse { return true }
            morphSession.requestDismissal()
            return false
        }
        HomeInteractionFeedback.soft()
        guard let placement = viewModel.morphPlacement(for: entry.itemID) else { return false }
        timelineMorphViewport.beginExpansion(
            for: entry.itemID,
            estimatedHeightDelta: estimatedExpansionHeight(for: entry)
        )
        var expansionToken: HomeMorphSessionToken?
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            viewModel.presentItemDetail(entry.itemID)
            viewModel.markDetailForExpandedEditing()
            expansionToken = morphSession.prepareExpansion(
                domain: .todo,
                id: entry.itemID,
                placement: placement
            )
        }
        guard let expansionToken else {
            timelineMorphViewport.cancelExpansion(for: entry.itemID)
            viewModel.dismissItemDetail()
            return false
        }
        Task { @MainActor in
            // Let SwiftUI commit the active compact surface and its pre-mounted,
            // zero-height disclosure before starting the reversible morph.
            await Task.yield()
            await Task.yield()
            guard morphSession.isCurrent(expansionToken) else { return }
            withAnimation(morphGeometryAnimation) {
                _ = morphSession.activatePreparedExpansion(using: expansionToken)
            }
        }
        return true
    }

    private func estimatedExpansionHeight(for entry: HomeTimelineEntry) -> CGFloat {
        let expandedTextAllowance: CGFloat = {
            let titleAllowance: CGFloat = entry.title.count > 18 ? 28 : 0
            let noteAllowance: CGFloat = entry.notes?.isEmpty == false ? 24 : 0
            return titleAllowance + noteAllowance
        }()
        return estimatedDetailDisclosureHeight(for: entry) + expandedTextAllowance
    }

    private func estimatedDetailDisclosureHeight(for entry: HomeTimelineEntry) -> CGFloat {
        // The disclosure contains two compact action rows and one 36pt row for
        // each subtask. Measured geometry replaces this estimate as soon as it
        // is available, including after Dynamic Type changes.
        80 + 40 * CGFloat(entry.subtasks.count)
    }

    private var morphGeometryAnimation: Animation {
        TaskMorphBloomMotion.geometryAnimation(reduceMotion: reduceMotion)
    }

    private var projectsModeContent: some View {
        ProjectsListContent(
            viewModel: projectsViewModel,
            style: .screen,
            showsHeader: false,
            isPresented: isProjectModePresented,
            contentTopPadding: 14,
            contentBottomPadding: 104
        )
    }

    private var routinesModeContent: some View {
        RoutinesListContent(
            viewModel: routinesViewModel,
            morphSession: morphSession,
            isPresented: isRoutinesModePresented,
            contentTopPadding: 0,
            contentBottomPadding: 104,
            showsCanvasBackground: false
        )
    }

    private func timelineList(scrollProxy: ScrollViewProxy) -> some View {
        standardTimelineList(scrollProxy: scrollProxy)
    }

    private func standardTimelineList(scrollProxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            if #available(iOS 26.0, *) {
                timelineScrollView(scrollProxy: scrollProxy, usesDateBar: true)
                    .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                        if let section = displayedTimelineDateBarSection {
                            timelineDateBar(section)
                        }
                    }
                    .applyHomeScrollEdgeTransition()
            } else {
                timelineScrollView(scrollProxy: scrollProxy, usesDateBar: false)
                    .applyHomeScrollEdgeTransition()
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

    private func timelineScrollView(
        scrollProxy: ScrollViewProxy,
        usesDateBar: Bool
    ) -> some View {
        ScrollView {
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
                } else if displayedCompletedEntries.isEmpty {
                    Color.clear
                        .frame(height: max(64, timelineBottomInset))
                }
            }
            .taskMorphScrollViewport(coordinator: timelineMorphViewport)
        }
        .onScrollGeometryChange(for: TaskMorphScrollSnapshot.self) { geometry in
            TaskMorphScrollSnapshot(geometry)
        } action: { _, snapshot in
            timelineMorphViewport.recordScrollSnapshot(snapshot)
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            timelineMorphViewport.recordViewportFrame(frame)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isOverlayModeActive)
        .transaction { transaction in
            if morphSession.phase == .relocating, morphSession.isCreationFlow == false {
                // The real destination row is established atomically under
                // the lifted surface. It must not run the timeline's normal
                // insertion/reordering animation at the same time.
                transaction.animation = nil
            }
        }
        .safeAreaPadding(.top, 0)
        .refreshable {
            await viewModel.reload()
        }
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
                .taskMorphBackgroundDepth(
                    isDeemphasized: morphSession.isFocusDepthActive,
                    anchor: .leading,
                    onDismiss: morphSession.requestDismissal
                )
        } else {
            timelineSectionHeader(section)
        }
    }

    private func timelineDateBar(_ section: HomeTimelineSection) -> some View {
        timelineSectionHeaderLayout(section)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(timelineDateBarContentAnimation, value: section.id)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxY
            } action: { maxY in
                guard abs(maxY - timelineDateBarBoundaryMaxY) > 0.5 else { return }
                timelineDateBarBoundaryMaxY = maxY
            }
            .taskMorphBackgroundDepth(
                isDeemphasized: morphSession.isFocusDepthActive,
                anchor: .leading,
                onDismiss: morphSession.requestDismissal
            )
    }

    private var timelineDateBarContentAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.14)
            : .smooth(duration: 0.26, extraBounce: 0)
    }

    private func timelineSectionHeader(_ section: HomeTimelineSection) -> some View {
        timelineSectionHeaderLayout(section)
            .taskMorphBackgroundDepth(
                isDeemphasized: morphSession.isFocusDepthActive,
                anchor: .leading,
                onDismiss: morphSession.requestDismissal
            )
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
        frozenActiveSections ?? viewModel.activeTimelineSections
    }

    private var displayedTimelineDateBarSection: HomeTimelineSection? {
        guard let activeSectionID = timelineDateBarSelection.activeSectionID else {
            return displayedActiveSections.first
        }
        return displayedActiveSections.first(where: { $0.id == activeSectionID })
            ?? displayedActiveSections.first
    }

    private var displayedCompletedEntries: [HomeTimelineEntry] {
        frozenCompletedEntries ?? viewModel.completedTimelineEntries
    }

    private var hasDisplayedTimelineEntries: Bool {
        displayedActiveSections.contains { $0.entries.isEmpty == false }
            || displayedCompletedEntries.isEmpty == false
    }

    private var displayedHasWeeklyCompletedEntries: Bool {
        frozenHasWeeklyCompletedEntries ?? viewModel.hasWeeklyCompletedEntries
    }

    private var displayedWeeklyCompletedEntryCount: Int {
        frozenWeeklyCompletedEntryCount ?? viewModel.weeklyCompletedEntryCount
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
        .taskMorphBackgroundDepth(
            isDeemphasized: morphSession.isFocusDepthActive,
            onDismiss: morphSession.requestDismissal
        )
    }

    @ViewBuilder
    private func timelineRows(
        _ entries: [HomeTimelineEntry],
        section: HomeTimelineSection? = nil,
        rowTransition: AnyTransition? = nil,
        sectionVisibility: CompletedSectionVisibility? = nil,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ForEach(entries, id: \.presentationID) { entry in
            let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
            let isActiveMorph = morphSession.isActive(.todo, id: entry.itemID)
            let isCreationRevealTarget = morphSession.isCreationListRevealTarget(.todo, id: entry.itemID)
            TaskMorphContainer(
                state: isActiveMorph ? morphSession.visualState : .compact,
                isActive: isActiveMorph,
                hidesRealSurfaceForHero: false,
                isBackgroundDeemphasized: morphSession.isFocusDepthActive
                    && morphSession.isCreationFlow == false
                    && isActiveMorph == false,
                isBackgroundDimmed: morphSession.isFocusDepthActive
                    && morphSession.isCreationFlow
                    && isActiveMorph == false
            ) {
                let isExpanded = isActiveMorph && morphSession.visualState == .expanded
                VStack(alignment: .leading, spacing: 0) {
                    timelineRow(
                        entry: entry,
                        isDetailPresented: isExpanded,
                        isDetailExpanded: isExpanded
                    )

                    HomeTaskCompactSummary(entry: entry, isExpanded: isExpanded)
                        .padding(.leading, HomeInlineTaskLayoutMetrics.attributeLeadingInset)

                    TaskMorphDisclosure(
                        isExpanded: isExpanded,
                        estimatedHeight: estimatedDetailDisclosureHeight(for: entry),
                        onMeasuredHeight: { height in
                            timelineMorphViewport.recordExpansionHeight(height, for: entry.itemID)
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            HomeInlineTaskDetailCard(
                                entry: entry,
                                viewModel: viewModel,
                                isExpanded: isExpanded,
                                showsAddNote: viewModel.inlineDetailDraft?.notes?
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty != false
                                    && editingNoteTaskID != entry.itemID,
                                onAddNote: { editingNoteTaskID = entry.itemID }
                            )

                            HomeTaskAttributeFooter(
                                entry: entry,
                                viewModel: viewModel,
                                isExpanded: isExpanded
                            )

                            if let error = morphSession.errorMessage {
                                Label(error, systemImage: "exclamationmark.circle.fill")
                                    .font(AppTheme.typography.sized(13, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding(.leading, HomeInlineTaskLayoutMetrics.attributeLeadingInset)
                                    .padding(.top, AppTheme.spacing.sm)
                            }
                        }
                    }
                }
            }
            .modifier(
                TimelineSwipeActionsModifier(
                    isEnabled: entry.isCompleted == false && morphSession.isActive == false,
                    canDelete: viewModel.canDeleteItem(entry.itemID),
                    onSnooze: {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.snoozeItem(entry.itemID) }
                    },
                    onDelete: {
                        HomeInteractionFeedback.delete()
                        Task { await viewModel.deleteItem(entry.itemID) }
                    }
                )
            )
            .contextMenu {
                if entry.isCompleted == false, morphSession.isActive == false {
                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.snoozeItem(entry.itemID) }
                    } label: {
                        Label("推迟到明天", systemImage: "calendar.badge.clock")
                    }

                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await viewModel.convertItemToPeriodicTask(entry.itemID) }
                    } label: {
                        Label("转为定期任务", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if viewModel.canDeleteItem(entry.itemID) {
                        Button(role: .destructive) {
                            HomeInteractionFeedback.delete()
                            Task { await viewModel.deleteItem(entry.itemID) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .id(entry.presentationID)
            .taskMorphListPlacement(
                state: isActiveMorph ? morphSession.visualState : .compact,
                isActive: isActiveMorph,
                compactInsets: EdgeInsets(
                    top: timelineRowVerticalInset,
                    leading: timelineRowHorizontalInset,
                    bottom: timelineRowVerticalInset,
                    trailing: timelineRowHorizontalInset
                )
            )
            .taskCreationListReveal(
                isTarget: isCreationRevealTarget,
                isEnabled: morphSession.isCreationListRevealEnabled,
                onCompleted: {
                    guard let subject = morphSession.subject,
                          let token = morphSession.currentToken()
                    else { return }
                    morphSession.requestCreationRevealCompletion(subject, using: token)
                }
            )
            .taskMorphViewportProgress(
                isActiveMorph && morphSession.visualState == .expanded ? 1 : 0,
                id: entry.itemID,
                coordinator: timelineMorphViewport
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                timelineMorphViewport.recordRowFrame(frame, for: entry.itemID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .insertedListItemMotion(
                isInserted: isCreationRevealTarget == false && viewModel.isAnimatingInsertion(for: entry.itemID),
                onAnimationCompleted: {
                    viewModel.completeInsertionAnimation(for: entry.itemID)
                }
            )
            .applyTransition(rowTransition)
            .applyCompletedSectionVisibility(
                sectionVisibility.map { $0.rowVisibility(for: index) }
            )
            .taskEdgeFlow(
                intensity: morphSession.isFocusDepthActive ? 0 : 1,
                isBaseHidden: isCreationRevealTarget
            )
            .zIndex(isActiveMorph ? 1 : 0)
        }
    }

    private func timelineRow(
        entry: HomeTimelineEntry,
        isDetailPresented: Bool,
        isDetailExpanded: Bool
    ) -> some View {
        HomeTimelineRow(
            entry: entry,
            isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.itemID, on: viewModel.selectedDate),
            isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.itemID, on: viewModel.selectedDate),
            isDetailPresented: isDetailPresented,
            isDetailExpanded: isDetailExpanded,
            isUrgent: isDetailPresented ? (viewModel.inlineDetailDraft?.isUrgent ?? entry.isUrgent) : entry.isUrgent,
            expandedTitle: isDetailPresented ? (viewModel.inlineDetailDraft?.title ?? entry.title) : entry.title,
            expandedNotes: isDetailPresented ? (viewModel.inlineDetailDraft?.notes ?? entry.notes) : entry.notes,
            isEditingNotes: editingNoteTaskID == entry.itemID,
            onToggleCompletion: {
                if isDetailPresented {
                    morphSession.requestCompletion()
                } else {
                    guard morphSession.isActive == false else { return }
                    entry.isCompleted
                        ? HomeInteractionFeedback.selection()
                        : HomeInteractionFeedback.completion()
                    completeTimelineEntry(entry)
                }
            },
            onOpenDetail: { openInlineTaskDetail(entry) },
            onUpdateTitle: viewModel.updateDraftTitle,
            onUpdateNotes: viewModel.updateDraftNotes,
            onBeginNoteEditing: { editingNoteTaskID = entry.itemID },
            onEndNoteEditing: {
                if editingNoteTaskID == entry.itemID {
                    editingNoteTaskID = nil
                }
            },
            onInlineFocus: { _ in }
        )
    }

    private var timelineSection: some View {
        ZStack {
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

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }

    private var isOverlayModeActive: Bool {
        isProjectModePresented || isRoutinesModePresented
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

    return HomeView(
        viewModel: context.homeViewModel,
        morphSession: HomeMorphSession(),
        projectsViewModel: context.projectsViewModel,
        routinesViewModel: context.routinesViewModel,
        isProjectModePresented: false,
        isRoutinesModePresented: false,
        onCreateTaskTapped: {},
        onCompletedHistoryTapped: { _ in }
    )
}
#endif

enum HomeInlineTaskLayoutMetrics {
    static let actionSlotWidth: CGFloat = 40
    static let checkboxSize: CGFloat = 28
    static let titleGap: CGFloat = AppTheme.spacing.md
    static let titleLeadingInset: CGFloat = actionSlotWidth + titleGap
    static let rowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 32
    static let detailVerticalSpacing: CGFloat = AppTheme.spacing.xxs
    static let taskTitleLeadingInset: CGFloat = checkboxSize + AppTheme.spacing.sm
    static let attributeLeadingInset: CGFloat = taskTitleLeadingInset
    static let attributeSpacing: CGFloat = 18
    static let attributeMinHeight: CGFloat = 34
    static let attributeHorizontalPadding: CGFloat = 2
    static let attributeIconSize: CGFloat = 14
    static let attributeIconWidth: CGFloat = 16
    static let attributeTextSize: CGFloat = 14
    static let detailTopPadding: CGFloat = AppTheme.spacing.xxs
    static let detailBottomPadding: CGFloat = AppTheme.spacing.xxs

    static func estimatedDetailHeight(
        subtaskCount: Int,
        showsAddNote: Bool = true,
        note: String? = nil
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
        return detailTopPadding + rowHeights + spacings + detailBottomPadding
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

        return HomeTimelineRowDisplayText(
            primarySubtitle: noteText ?? "",
            propertyText: nil
        )
    }
}

struct TaskSharedElementVisual: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let element: TaskSharedElement
    let content: TaskSharedIdentityContent
    var titleLineLimit: Int? = 2
    var noteLineLimit: Int? = nil
    var noteFontSize: CGFloat = 15

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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        AppTheme.colors.body.opacity(content.isMuted ? 0.4 : 0.74)
    }

    private var titleColor: Color {
        content.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title
    }
}

struct TaskSharedAttributeBand: View {
    let content: TaskSharedIdentityContent
    var elements: [TaskSharedElement] = [.time, .reminder, .progress, .urgent]

    var body: some View {
        TaskSharedAttributeBandLayout(horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(visibleElements, id: \.self) { element in
                TaskSharedElementVisual(element: element, content: content)
            }
        }
    }

    private var visibleElements: [TaskSharedElement] {
        elements.filter { content.visibleElements.contains($0) }
    }
}

private struct TaskSharedAttributeBandLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let rows = rows(for: subviews, width: width)
        let height = rows.enumerated().reduce(CGFloat.zero) { partial, row in
            partial + (row.element.map(\.height).max() ?? 0) + (row.offset == 0 ? 0 : verticalSpacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            let rowHeight = row.map(\.height).max() ?? 0
            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.width, height: item.height)
                )
                x += item.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [[Item]] {
        var rows: [[Item]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let required = rows[rows.count - 1].isEmpty ? size.width : horizontalSpacing + size.width
            if currentWidth + required > width, rows.count < 2, rows[rows.count - 1].isEmpty == false {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(Item(subview: subview, width: size.width, height: size.height))
            currentWidth += (rows[rows.count - 1].count == 1 ? 0 : horizontalSpacing) + size.width
        }
        return rows
    }

    private struct Item {
        let subview: LayoutSubview
        let width: CGFloat
        let height: CGFloat
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

private struct TaskTitleCenterAlignment: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
        dimensions[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let taskTitleCenter = VerticalAlignment(TaskTitleCenterAlignment.self)
}

struct HomeTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let isAnimatingReopening: Bool
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let isUrgent: Bool
    let expandedTitle: String
    let expandedNotes: String?
    let isEditingNotes: Bool
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    let onUpdateTitle: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onBeginNoteEditing: () -> Void
    let onEndNoteEditing: () -> Void
    let onInlineFocus: (HomeInlineFocusTarget) -> Void
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
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
    @State private var rowOpacity: Double = 1
    @State private var reopeningCheckmarkOpacity: Double = 1
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false
    @State private var isCommittingNotes = false

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
        }
        .scaleEffect(rowScale, anchor: .center)
        .offset(y: rowVerticalOffset)
        .opacity(rowOpacity)
        .onAppear {
            titleDraft = expandedTitle
            notesDraft = expandedNotes ?? ""
            guard shouldPlayCompletionAnimation else { return }
            startCompletionAnimation()
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
        }
    }

    private var shouldPlayCompletionAnimation: Bool {
        isAnimatingCompletion && entry.isCompleted == false
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
                .accessibilityLabel(isDetailPresented ? "编辑任务标题" : "展开任务")
            }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Group {
                if isEditingTitle {
                    expandedTitleEditor
                } else {
                    sourceTitleVisual
                }
            }
            .alignmentGuide(.taskTitleCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }

            if showsSubtitle {
                subtitleContent
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private var sourceTitleVisual: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.sm) {
            TaskSharedElementVisual(
                element: .title,
                content: sharedIdentityContent,
                titleLineLimit: isDetailPresented ? nil : 2
            )

            if isUrgent, isDetailPresented == false, entry.isCompleted == false {
                Image(systemName: "flag.fill")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .accessibilityLabel("紧急")
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

                inlineSaveButton {
                    commitNotesAfterFocusUpdate()
                }
            }
        } else if visibleNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Button {
                guard isDetailPresented else { return }
                onBeginNoteEditing()
            } label: {
                subtitleText(displaySubtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isDetailPresented)
            .accessibilityLabel("编辑备注")
        } else {
            subtitleText(displaySubtitle)
        }
    }

    private func subtitleText(_ text: String) -> some View {
        TaskSharedElementVisual(
            element: .note,
            content: sharedIdentityContent,
            noteLineLimit: isDetailPresented ? nil : 1,
            noteFontSize: 14
        )
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
            .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .lineLimit(1...4)
            .focused($isTitleFocused)
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

            inlineSaveButton {
                commitTitleAfterFocusUpdate()
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
        AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.74)
    }

    @ViewBuilder
    private var timelineSymbol: some View {
        checkmarkBadge
            .frame(width: 24, height: 24)
    }

    private var checkmarkBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppTheme.colors.coral.opacity(0.34), lineWidth: 2)
                .scaleEffect(badgeAuraScale)
                .opacity(badgeAuraOpacity)

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

        if entry.isCompleted {
            return .clear
        }

        if shouldPlayCompletionAnimation {
            return AppTheme.colors.body.opacity(0.32)
        }

        return AppTheme.colors.body.opacity(0.30)
    }

    private var outlineOpacity: Double {
        if isAnimatingReopening { return badgeOutlineOpacity }
        if entry.isCompleted { return 0 }
        if shouldPlayCompletionAnimation { return badgeOutlineOpacity }
        return 1
    }

    private var checkmarkOpacity: Double {
        guard entry.isCompleted || shouldPlayCompletionAnimation || isAnimatingReopening else { return 0 }
        return (isAnimatingReopening ? reopeningCheckmarkOpacity : 1) * completionCheckmarkOpacity
    }
}

private struct TimelineSwipeActionsModifier: ViewModifier {
    let isEnabled: Bool
    let canDelete: Bool
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
            .navigationTitle("本周已完成")
            .navigationSubtitle("不含今天，共 \(count) 项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
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
    @Bindable var viewModel: HomeViewModel
    @State private var displayedEntries: [HomeOverdueEntry] = []
    @State private var animatingCompletionIDs: Set<UUID> = []
    @State private var reschedulingIDs: Set<UUID> = []

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
            syncDisplayedEntries(with: newValue)
            dismissIfFinished()
        }
        .onChange(of: viewModel.overdueEntryCount) { _, newValue in
            guard newValue == 0 else { return }
            dismissIfFinished()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .presentationCornerRadius(nil)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                Text("逾期任务")
                    .font(AppTheme.typography.sized(24, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)

                Text("统一在这里处理所有已逾期任务")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.62))

                Text("共 \(entries.count) 项")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral.opacity(0.84))
            }
            Spacer(minLength: 0)
        }
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
                        subtasks: [],
                        subtaskCompletedCount: 0
                    ),
                    isAnimatingCompletion: animatingCompletionIDs.contains(entry.id),
                    isAnimatingReopening: false,
                    isDetailPresented: false,
                    isDetailExpanded: false,
                    isUrgent: false,
                    expandedTitle: entry.title,
                    expandedNotes: entry.detailText,
                    isEditingNotes: false,
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
        .disabled(reschedulingIDs.contains(entry.id))
        .accessibilityLabel("将逾期任务改到今天")
    }

    private func handleCompletion(for itemID: UUID) async {
        guard animatingCompletionIDs.insert(itemID).inserted else { return }

        async let completionTask: Void = viewModel.completeItem(itemID)

        try? await Task.sleep(for: .milliseconds(520))

        withAnimation(.bouncy(duration: 0.54, extraBounce: 0.08)) {
            displayedEntries.removeAll { $0.id == itemID }
        }

        _ = await completionTask
        animatingCompletionIDs.remove(itemID)
        dismissIfFinished()
    }

    private func handleRescheduleToToday(for itemID: UUID) async {
        guard reschedulingIDs.insert(itemID).inserted else { return }

        await viewModel.rescheduleOverdueItemToToday(itemID)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            displayedEntries.removeAll { $0.id == itemID }
        }

        reschedulingIDs.remove(itemID)
        dismissIfFinished()
    }

    private func syncDisplayedEntries(with sourceEntries: [HomeOverdueEntry]) {
        var remainingEntries = Dictionary(uniqueKeysWithValues: sourceEntries.map { ($0.id, $0) })
        var nextEntries: [HomeOverdueEntry] = []

        for entry in displayedEntries {
            if let updatedEntry = remainingEntries.removeValue(forKey: entry.id) {
                nextEntries.append(updatedEntry)
            } else if animatingCompletionIDs.contains(entry.id) {
                nextEntries.append(entry)
            }
        }

        for entry in sourceEntries where remainingEntries[entry.id] != nil {
            nextEntries.append(entry)
            remainingEntries.removeValue(forKey: entry.id)
        }

        displayedEntries = nextEntries
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
    func applyTransition(_ transition: AnyTransition?) -> some View {
        if let transition {
            self.transition(.asymmetric(insertion: transition, removal: .opacity))
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
