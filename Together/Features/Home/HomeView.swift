import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: HomeViewModel
    @Bindable var projectsViewModel: ProjectsViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let isProjectModePresented: Bool
    let isRoutinesModePresented: Bool
    let onProfileTapped: () -> Void
    let onCreateTaskTapped: () -> Void
    let onCompletedHistoryTapped: (CompletedHistoryFilter) -> Void
    @State private var weekPagerOffset: CGFloat = 0
    @State private var isRequestStackExpanded = false
    @State private var isWeekPagerSettling = false
    @State private var isTodayJumpButtonVisible = false
    @State private var todayJumpRevealTask: Task<Void, Never>?
    @State private var isCompletedVisibilityButtonCompressed = false
    @State private var isCompletedSectionVisible = true
    @State private var monthPagerOffset: CGFloat = 0
    @State private var isMonthPagerSettling = false
    @State private var highlightedTaskID: UUID?
    @State private var isTimelineReorderingActive = false
    @State private var activeInlineDetailMenu: TaskEditorMenu?
    @State private var visualFocusItemID: UUID?
    @State private var collapsingInlineDetailID: UUID?
    @State private var inlineDetailAnimationBatch = 0

    private let weekPageBreathingGap: CGFloat = 0
    private let calendarColumnSpacing: CGFloat = AppTheme.spacing.sm
    private let calendarGridHorizontalInset: CGFloat = 4
    private let calendarWeekdayHeight: CGFloat = 20
    private let weekMiddleIndex = 3
    private let contentCardCornerRadius: CGFloat = 40
    private let timelineRowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let timelineRowVerticalInset: CGFloat = 14
    private let timelineBottomInset: CGFloat = 24
    private let monthGridSpacing: CGFloat = 8
    private let monthCompressedGridSpacing: CGFloat = 4
    private let monthDayCellHeight: CGFloat = 46
    private let monthCompressedDayCellHeight: CGFloat = 37
    private let monthDayCircleSize: CGFloat = 34
    private let monthCompressedDayCircleSize: CGFloat = 28
    private let monthIndicatorSize: CGFloat = 4
    private let monthIndicatorSpacing: CGFloat = 6
    private let monthCompressedTopPadding: CGFloat = 6
    private let monthDayTextVerticalOffset: CGFloat = 0
    private let calendarTopSpacing: CGFloat = 10
    private let homeCanvasColor = AppTheme.colors.background

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundView

                contentCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, contentTopInset(safeAreaTop: proxy.safeAreaInsets.top))
                    .offset(y: contentCardVerticalOffset)
                    .scaleEffect(contentCardScale, anchor: .top)

            }
        }
        .font(AppTheme.typography.body)
        .task {
            await viewModel.loadIfNeeded()
            updateTodayJumpButtonVisibility()
            await viewModel.performDeferredMaintenanceIfNeeded()
        }
        .task(id: viewModel.selectedDateKey) {
            visualFocusItemID = nil
            collapsingInlineDetailID = nil
            await viewModel.reload(reason: .dateChange)
            updateTodayJumpButtonVisibility()
        }
        .onChange(of: viewModel.expandedDetailItemID) { _, expandedItemID in
            guard expandedItemID == nil else { return }
            visualFocusItemID = nil
            collapsingInlineDetailID = nil
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
        .sheet(
            isPresented: Binding(
                get: { activeInlineDetailMenu != nil },
                set: { isPresented in
                    if isPresented == false {
                        activeInlineDetailMenu = nil
                    }
                }
            )
        ) {
            if let menuBinding = activeInlineDetailMenuBinding {
                HomeDetailMenuSheet(
                    context: .taskInline,
                    activeMenu: menuBinding,
                    viewModel: viewModel,
                    templates: [],
                    isLoadingTemplates: false,
                    onTemplatePicked: { _ in },
                    onTemplateDeleted: { _ in },
                    disabledMenus: inlineDetailDisabledMenus,
                    onDismiss: {
                        activeInlineDetailMenu = nil
                    }
                )
                .presentationDetents(TaskEditorMenuContext.taskInline.detents)
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
                .modifier(TaskEditorMenuPresentationSizingModifier())
            }
        }
        .onAppear {
            isCompletedSectionVisible = true
        }
        .onDisappear {
            todayJumpRevealTask?.cancel()
        }
        .onChange(of: appContext.startupRestorePresentationState) { oldValue, newValue in
            guard oldValue.isVisible, newValue == .idle else { return }
            Task {
                await viewModel.reload(reason: .startupRestore)
                updateTodayJumpButtonVisibility()
            }
        }
    }

    private var backgroundView: some View {
        GradientGridBackground()
    }

    private var activeInlineDetailMenuBinding: Binding<TaskEditorMenu>? {
        guard let activeInlineDetailMenu else { return nil }
        return Binding(
            get: { self.activeInlineDetailMenu ?? activeInlineDetailMenu },
            set: { self.activeInlineDetailMenu = $0 }
        )
    }

    private var inlineDetailDisabledMenus: Set<TaskEditorMenu> {
        viewModel.inlineDetailDraft?.hasExplicitTime == true ? [] : [.reminder]
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

    private var startupRestoreStatusPill: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            restoreStatusGlyph

            Text(startupRestoreStatusText)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated.opacity(0.92))
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(AppTheme.colors.outline.opacity(0.62), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var restoreStatusGlyph: some View {
        switch appContext.startupRestorePresentationState {
        case .failed:
            Image(systemName: "wifi.exclamationmark")
                .font(AppTheme.typography.sized(12, weight: .semibold))
                .foregroundStyle(AppTheme.colors.warning)
        case .restoring:
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.colors.body.opacity(0.62))
        case .idle:
            EmptyView()
        }
    }

    private var startupRestoreStatusText: String {
        switch appContext.startupRestorePresentationState {
        case .idle:
            return ""
        case .restoring(let isSlow):
            return isSlow ? "仍在同步，请稍候" : "正在恢复你的任务"
        case .failed:
            return "网络暂时不可用，稍后会自动重试"
        }
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

    private func topChrome(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, horizontalContentPadding)
                    .padding(.top, headerTopPadding(safeAreaTop: safeAreaTop))
                    .offset(y: headerVerticalOffset)

                weekCalendarContainer
                    .padding(.horizontal, horizontalContentPadding)
                    .padding(.top, calendarTopSpacing)

                if showsStartupRestoreStatus {
                    startupRestoreStatusPill
                        .padding(.horizontal, horizontalContentPadding)
                        .padding(.top, AppTheme.spacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, isOverlayModeActive ? 4 : 0)
            .background(homeCanvasColor)
            .animation(restoreTransitionAnimation, value: appContext.startupRestorePresentationState)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                HStack(alignment: .center, spacing: AppTheme.spacing.xs) { // normalized 8→6
                    headerTitle(compact: isOverlayModeActive)

                    if !isOverlayModeActive, isTodayJumpButtonVisible {
                        todayJumpButton
                            .transition(todayJumpTransition)
                    }
                }

                if !isOverlayModeActive {
                    spaceModeLine
                }

                if isProjectModePresented {
                    projectModeHeaderMeta
                }

                if isRoutinesModePresented {
                    routinesModeHeaderMeta
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            headerAvatarButton(compact: isOverlayModeActive)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.selectedDateKey)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.isViewingToday)
    }

    private var spaceModeLine: some View {
        HStack(spacing: AppTheme.spacing.xs) { // normalized 8→6
            ModeIndicator(label: currentViewLabel)

            Text(viewModel.spaceDisplayName)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)

        }
    }

    private func headerTopRow(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            headerTitle(compact: compact)

            if !compact, isTodayJumpButtonVisible {
                todayJumpButton
                    .transition(todayJumpTransition)
            }

            Spacer(minLength: 0)

            headerAvatarButton(compact: compact)
        }
        .frame(minHeight: compact ? 40 : 52, alignment: .center)
    }

    private var projectModeHeaderMeta: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            projectModeIndicator
                .layoutPriority(2)

            Text(projectModeProjectsSummary)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isProjectModePresented ? 1 : 0)
        .offset(y: isProjectModePresented ? 0 : projectModeContentTransitionOffset)
        .allowsHitTesting(false)
        .animation(projectModeAnimation, value: isProjectModePresented)
    }

    private var projectModeIndicator: some View {
        ModeIndicator(label: "项目视图")
    }

    private var routinesModeHeaderMeta: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            ModeIndicator(label: "例行任务")
            .layoutPriority(2)

            Text(routinesModeSummary)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isRoutinesModePresented ? 1 : 0)
        .offset(y: isRoutinesModePresented ? 0 : projectModeContentTransitionOffset)
        .allowsHitTesting(false)
        .animation(projectModeAnimation, value: isRoutinesModePresented)
    }

    private var routinesModeSummary: String {
        let summary = routinesViewModel.pendingSummary(referenceDate: routinesViewModel.referenceDate)
        let totalPending = summary.reduce(0) { $0 + $1.1 }
        if totalPending > 0 {
            return "还有 \(totalPending) 项待完成"
        }
        return "全部完成"
    }

    private var currentViewLabel: String {
        if isProjectModePresented {
            return "项目视图"
        }

        if isRoutinesModePresented {
            return "例行任务"
        }

        if viewModel.isMonthMode {
            return "日历视图"
        }

        return "今日视图"
    }

    private func headerTitle(compact: Bool) -> some View {
        Text(viewModel.headerDateText)
            .font(AppTheme.typography.sized(36, weight: .bold))
            .tracking(-0.9)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .foregroundStyle(headerPrimaryColor)
            .contentTransition(.numericText())
            .scaleEffect(compact ? 0.78 : 1, anchor: .leading)
            .frame(height: 44, alignment: .leading)
            .compositingGroup()
    }

    private func headerAvatarButton(compact: Bool) -> some View {
        HomeAvatarToggleButton(
            avatar: viewModel.headerAvatar,
            foregroundColor: headerPrimaryColor,
            secondaryForegroundColor: headerSecondaryColor,
            compact: compact,
            showsRestorePlaceholder: showsStartupRestorePlaceholder,
            action: {
                HomeInteractionFeedback.selection()
                onProfileTapped()
            }
        )
        .padding(.top, compact ? 0 : 2)
        .id(appContext.sessionStore.userProfileRevision)
        .compositingGroup()
        .accessibilityLabel("打开个人页")
        .accessibilityHint("查看个人资料和设置")
    }

    private var contentCard: some View {
        ZStack(alignment: .top) {
            tasksContent
                .opacity(isOverlayModeActive ? 0 : 1)
                .allowsHitTesting(!isOverlayModeActive)
                .animation(modeFadeAnimation, value: isOverlayModeActive)

            if isProjectModePresented {
                projectsModeContent
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .allowsHitTesting(true)
            }

            if isRoutinesModePresented {
                routinesModeContent
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .allowsHitTesting(true)
            }
        }
        .animation(projectModeAnimation, value: isProjectModePresented)
        .animation(projectModeAnimation, value: isRoutinesModePresented)
    }

    private var tasksContent: some View {
        ZStack {
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
                .applyScrollEdgeProtection()
                .transition(timelineTransition)
            } else if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.md) { // normalized 14→16
                        if appContext.sessionStore.activeMode == .single,
                           appContext.routinesViewModel.hasPendingTasks {
                            RoutinesSummaryCard(
                                viewModel: appContext.routinesViewModel,
                                onNavigateToRoutines: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                                        viewModel.setCalendarDisplayMode(.week)
                                        appContext.router.shouldAutoSelectPendingCycle = true
                                        appContext.router.currentSurface = .routines
                                    }
                                }
                            )
                        }

                        timelineSection
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, AppTheme.spacing.md) // normalized 14→16
                    .padding(.bottom, AppTheme.spacing.lg)
                }
                .id("empty-\(viewModel.selectedDateKey)")
                .scrollIndicators(.hidden)
                .scrollDisabled(isOverlayModeActive)
                .applyScrollEdgeProtection()
                .transition(timelineTransition)
            } else {
                ScrollViewReader { scrollProxy in
                    timelineList(scrollProxy: scrollProxy)
                        .id("timeline-\(viewModel.selectedDateKey)")
                        .transition(timelineTransition)
                        .onReceive(NotificationCenter.default.publisher(for: .openTaskFromNudge)) { notif in
                            guard let id = notif.userInfo?["task_id"] as? UUID else { return }
                            _ = appContext.consumePendingHighlightTaskID()
                            highlight(id, via: scrollProxy)
                        }
                        .task {
                            // Cold-launch path: openTaskFromNotification fires before this
                            // ScrollViewReader is alive, so onReceive never fires. Drain the
                            // pending highlight stored on AppContext and apply it now.
                            guard let id = appContext.consumePendingHighlightTaskID() else { return }
                            highlight(id, via: scrollProxy)
                        }
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: viewModel.selectedDateKey)
        .animation(restoreTransitionAnimation, value: appContext.startupRestorePresentationState)
    }

    /// Scroll to and briefly highlight a task row. Called from both the hot path
    /// (onReceive) and the cold-launch path (.task drain on ScrollViewReader).
    private func highlight(_ id: UUID, via proxy: ScrollViewProxy) {
        highlightedTaskID = id
        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            highlightedTaskID = nil
        }
    }

    private func toggleInlineDetail(_ itemID: UUID, scrollProxy: ScrollViewProxy) {
        HomeInteractionFeedback.soft()
        Task { @MainActor in
            if let focusedItemID = visualFocusItemID, focusedItemID != itemID {
                beginInlineDetailCollapse(itemID: focusedItemID)
                return
            }

            if viewModel.expandedDetailItemID == itemID {
                beginInlineDetailCollapse(itemID: itemID)
                return
            }

            if let expandedItemID = viewModel.expandedDetailItemID, expandedItemID != itemID {
                beginInlineDetailCollapse(itemID: expandedItemID)
                return
            }

            collapsingInlineDetailID = nil
            visualFocusItemID = nil
            await viewModel.toggleInlineDetail(itemID)
            inlineDetailAnimationBatch += 1
            guard viewModel.expandedDetailItemID == itemID else { return }
            withAnimation(timelineFocusAnimation) {
                visualFocusItemID = itemID
            }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                scrollProxy.scrollTo(inlineDetailAnchorID(for: itemID), anchor: .center)
            }
        }
    }

    private func beginInlineDetailCollapse(itemID: UUID) {
        guard collapsingInlineDetailID != itemID else { return }

        withAnimation(timelineFocusAnimation) {
            visualFocusItemID = nil
        }

        Task { @MainActor in
            collapsingInlineDetailID = itemID
            inlineDetailAnimationBatch += 1
            try? await Task.sleep(for: .milliseconds(inlineCollapseDelayMilliseconds))
            guard collapsingInlineDetailID == itemID else { return }
            await viewModel.collapseInlineDetail()
            collapsingInlineDetailID = nil
        }
    }

    private func collapseVisualFocusIfNeeded() {
        guard let focusedItemID = visualFocusItemID else { return }
        HomeInteractionFeedback.soft()
        beginInlineDetailCollapse(itemID: focusedItemID)
    }

    private func isInlineDetailPresented(for itemID: UUID) -> Bool {
        viewModel.expandedDetailItemID == itemID || collapsingInlineDetailID == itemID
    }

    private func isInlineDetailVisuallyExpanded(for itemID: UUID) -> Bool {
        viewModel.expandedDetailItemID == itemID && collapsingInlineDetailID != itemID
    }

    private var inlineCollapseDelayMilliseconds: UInt64 {
        360
    }

    private func inlineDetailAnchorID(for itemID: UUID) -> String {
        "inline-detail-\(itemID.uuidString)"
    }

    private func scrollToInlineFocus(
        _ target: HomeInlineFocusTarget,
        itemID: UUID,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            scrollProxy.scrollTo(target.anchorID(for: itemID), anchor: target.scrollAnchor)
        }
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
            isPresented: isRoutinesModePresented,
            contentTopPadding: 0,
            contentBottomPadding: 104
        )
    }

    private var weekCalendarContainer: some View {
        calendarSection
            .frame(height: isOverlayModeActive ? 0 : calendarContainerHeight, alignment: .top)
            .offset(y: weekSectionVerticalOffset)
            .opacity(isOverlayModeActive ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isOverlayModeActive)
            .animation(projectModeAnimation, value: isOverlayModeActive)
            .animation(calendarModeAnimation, value: viewModel.calendarDisplayMode)
    }

    private func timelineList(scrollProxy: ScrollViewProxy) -> some View {
        standardTimelineList(scrollProxy: scrollProxy)
    }

    private func standardTimelineList(scrollProxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if viewModel.showsOverdueCapsule {
                    overdueReminderCapsule
                        .padding(
                            EdgeInsets(
                                top: 10,
                                leading: timelineRowHorizontalInset,
                                bottom: 8,
                                trailing: timelineRowHorizontalInset
                            )
                        )
                }

                if appContext.sessionStore.activeMode == .single,
                   appContext.routinesViewModel.hasPendingTasks {
                    RoutinesSummaryCard(
                        viewModel: appContext.routinesViewModel,
                        onNavigateToRoutines: {
                            appContext.router.shouldAutoSelectPendingCycle = true
                            appContext.router.currentSurface = .routines
                        }
                    )
                    .padding(
                        EdgeInsets(
                            top: 6,
                            leading: timelineRowHorizontalInset,
                            bottom: 8,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                }

                ForEach(viewModel.activeTimelineSections) { section in
                    Section {
                        timelineRows(
                            section.entries,
                            rowTransition: activeRowTransition,
                            scrollProxy: scrollProxy
                        )
                    } header: {
                        HomeTimelineDateSectionHeader(section: section)
                            .padding(.horizontal, timelineRowHorizontalInset)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.colors.homeBackground.opacity(0.96))
                    }
                }

                if viewModel.hasCompletedEntries {
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

                if viewModel.hasWeeklyCompletedEntries {
                    completedVisibilityButton
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(
                            EdgeInsets(
                                top: viewModel.hasCompletedEntries ? 4 : 12,
                                leading: timelineRowHorizontalInset,
                                bottom: timelineBottomInset,
                                trailing: timelineRowHorizontalInset
                            )
                        )
                } else if viewModel.hasCompletedEntries == false {
                    Color.clear.frame(height: timelineBottomInset)
                }
            }
            .background {
                timelineFocusDismissBackground
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isOverlayModeActive)
        .safeAreaPadding(.top, 0)
        .applyScrollEdgeProtection()
        .refreshable {
            await viewModel.reload()
        }
    }

    private var timelineFocusDismissBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                collapseVisualFocusIfNeeded()
            }
    }

    private var todayJumpButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                isTodayJumpButtonVisible = false
                viewModel.returnToToday()
            }
            HomeInteractionFeedback.selection()
        } label: {
            Text("今天")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .padding(.horizontal, AppTheme.spacing.sm)
                .padding(.vertical, AppTheme.spacing.xxs)
        }
        .foregroundStyle(AppTheme.colors.title)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Capsule(style: .continuous))
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
        .buttonStyle(.plain)
        .accessibilityLabel("返回今天")
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

    private var todayJumpTransition: some Transition {
        .blurReplace
    }

    private func updateTodayJumpButtonVisibility() {
        todayJumpRevealTask?.cancel()

        guard shouldShowTodayJumpButton else {
            withAnimation(.smooth(duration: 0.18)) {
                isTodayJumpButtonVisible = false
            }
            return
        }

        guard isTodayJumpButtonVisible == false else { return }

        todayJumpRevealTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard shouldShowTodayJumpButton else { return }
                withAnimation(.smooth(duration: 0.22)) {
                    isTodayJumpButtonVisible = true
                }
            }
        }
    }

    private var shouldShowTodayJumpButton: Bool {
        guard !viewModel.isViewingToday, !isOverlayModeActive else {
            return false
        }

        var calendar = Calendar.current
        calendar.firstWeekday = 1  // 与 HomeViewModel 周日首日约定对齐
        return !calendar.isDate(viewModel.selectedDate, equalTo: .now, toGranularity: .weekOfYear)
    }

    @ViewBuilder
    private func completedTimelineSection(scrollProxy: ScrollViewProxy) -> some View {
        timelineRows(
            viewModel.completedTimelineEntries,
            rowTransition: completedRowTransition,
            sectionVisibility: CompletedSectionVisibility(
                isVisible: isCompletedSectionVisible,
                count: viewModel.completedTimelineEntries.count
            ),
            scrollProxy: scrollProxy
        )
    }

    private var todayCompletedHeader: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Text("今天已完成")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.58))

            Text("\(viewModel.todayCompletedEntryCount)")
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
        rowTransition: AnyTransition? = nil,
        sectionVisibility: CompletedSectionVisibility? = nil,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ForEach(entries, id: \.presentationID) { entry in
            let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
            let isDetailPresented = isInlineDetailPresented(for: entry.itemID)
            let isDetailExpanded = isInlineDetailVisuallyExpanded(for: entry.itemID)
            VStack(alignment: .leading, spacing: 0) {
                if entry.isCompleted {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.itemID, on: viewModel.selectedDate),
                        isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.itemID, on: viewModel.selectedDate),
                        titleLineLimit: 1,
                        titleMinimumScaleFactor: 0.68,
                        isDetailPresented: isDetailPresented,
                        isDetailExpanded: isDetailExpanded,
                        expandedTitle: viewModel.inlineDetailDraft?.title ?? entry.title,
                        onToggleCompletion: {
                            if entry.isCompleted {
                                HomeInteractionFeedback.selection()
                            } else {
                                HomeInteractionFeedback.completion()
                            }
                            Task {
                                await viewModel.completeItem(entry.itemID)
                            }
                        },
                        onOpenDetail: {
                            toggleInlineDetail(entry.itemID, scrollProxy: scrollProxy)
                        },
                        onUpdateTitle: { title in
                            viewModel.updateDraftTitle(title)
                        },
                        onInlineFocus: { target in
                            scrollToInlineFocus(target, itemID: entry.itemID, scrollProxy: scrollProxy)
                        }
                    )
                } else {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.itemID, on: viewModel.selectedDate),
                        isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.itemID, on: viewModel.selectedDate),
                        titleLineLimit: 1,
                        titleMinimumScaleFactor: 0.68,
                        isDetailPresented: isDetailPresented,
                        isDetailExpanded: isDetailExpanded,
                        expandedTitle: viewModel.inlineDetailDraft?.title ?? entry.title,
                        onToggleCompletion: {
                            if entry.isCompleted {
                                HomeInteractionFeedback.selection()
                            } else {
                                HomeInteractionFeedback.completion()
                            }
                            Task {
                                await viewModel.completeItem(entry.itemID)
                            }
                        },
                        onOpenDetail: {
                            toggleInlineDetail(entry.itemID, scrollProxy: scrollProxy)
                        },
                        onUpdateTitle: { title in
                            viewModel.updateDraftTitle(title)
                        },
                        onInlineFocus: { target in
                            scrollToInlineFocus(target, itemID: entry.itemID, scrollProxy: scrollProxy)
                        }
                    )
                    .modifier(
                        TimelineSwipeActionsModifier(
                            isEnabled: false,
                            canDelete: viewModel.canDeleteItem(entry.itemID),
                            onSnooze: {
                                HomeInteractionFeedback.selection()
                                Task {
                                    await viewModel.snoozeItem(entry.itemID)
                                }
                            },
                            onDelete: {
                                HomeInteractionFeedback.delete()
                                Task {
                                    await viewModel.deleteItem(entry.itemID)
                                }
                            }
                        )
                    )
                    .contextMenu {
                        Button {
                            HomeInteractionFeedback.selection()
                            Task {
                                await viewModel.snoozeItem(entry.itemID)
                            }
                        } label: {
                            Label("推迟到明天", systemImage: "calendar.badge.clock")
                        }

                        Button {
                            HomeInteractionFeedback.selection()
                            Task {
                                _ = await viewModel.saveItemAsTemplateResult(entry.itemID)
                            }
                        } label: {
                            Label("存为模板", systemImage: "bookmark")
                        }

                        Button {
                            HomeInteractionFeedback.selection()
                            Task {
                                await viewModel.convertItemToPeriodicTask(entry.itemID)
                            }
                        } label: {
                            Label("转为例行任务", systemImage: "arrow.triangle.2.circlepath")
                        }

                        if viewModel.canDeleteItem(entry.itemID) {
                            Button(role: .destructive) {
                                HomeInteractionFeedback.delete()
                                Task {
                                    await viewModel.deleteItem(entry.itemID)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }

                if isDetailPresented {
                    HomeInlineTaskDetailView(
                        entry: entry,
                        viewModel: viewModel,
                        isExpanded: isDetailExpanded,
                        animationBatch: inlineDetailAnimationBatch,
                        onOpenMenu: { menu in
                            activeInlineDetailMenu = menu
                        },
                        onFocus: { target in
                            scrollToInlineFocus(target, itemID: entry.itemID, scrollProxy: scrollProxy)
                        }
                    )
                    .id(inlineDetailAnchorID(for: entry.itemID))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
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
            .modifier(
                HomeInlineFocusChromeModifier(
                    isFocused: visualFocusItemID == entry.itemID && isDetailPresented,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(timelineFocusOpacity(for: entry))
            .saturation(timelineFocusSaturation(for: entry))
            .brightness(timelineFocusBrightness(for: entry))
            .blur(radius: timelineFocusBlurRadius(for: entry))
            .scaleEffect(timelineFocusScale(for: entry), anchor: .center)
            .zIndex(timelineFocusZIndex(for: entry))
            .animation(timelineFocusAnimation, value: visualFocusItemID)
            .insertedListItemMotion(
                isInserted: viewModel.isAnimatingInsertion(for: entry.itemID),
                onAnimationCompleted: {
                    viewModel.completeInsertionAnimation(for: entry.itemID)
                }
            )
            .applyTransition(rowTransition)
            .applyCompletedSectionVisibility(
                sectionVisibility.map { $0.rowVisibility(for: index) }
            )
        }
    }

    private func timelineFocusOpacity(for entry: HomeTimelineEntry) -> Double {
        guard let focusedItemID = visualFocusItemID else { return 1 }
        guard focusedItemID != entry.itemID else { return 1 }
        return entry.isCompleted ? 0.08 : 0.12
    }

    private func timelineFocusSaturation(for entry: HomeTimelineEntry) -> Double {
        guard let focusedItemID = visualFocusItemID else { return 1 }
        return focusedItemID == entry.itemID ? 1.1 : 0.03
    }

    private func timelineFocusBrightness(for entry: HomeTimelineEntry) -> Double {
        guard let focusedItemID = visualFocusItemID else { return 0 }
        return focusedItemID == entry.itemID ? 0.045 : -0.125
    }

    private func timelineFocusBlurRadius(for entry: HomeTimelineEntry) -> CGFloat {
        guard reduceMotion == false, let focusedItemID = visualFocusItemID else { return 0 }
        return focusedItemID == entry.itemID ? 0 : 3.05
    }

    private func timelineFocusScale(for entry: HomeTimelineEntry) -> CGFloat {
        guard reduceMotion == false, let focusedItemID = visualFocusItemID else { return 1 }
        return focusedItemID == entry.itemID ? 1.02 : 0.986
    }

    private func timelineFocusZIndex(for entry: HomeTimelineEntry) -> Double {
        guard let focusedItemID = visualFocusItemID else { return 0 }
        return focusedItemID == entry.itemID ? 3 : 0
    }

    private var timelineFocusAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0)
    }

    private var timelineSection: some View {
        ZStack {
            if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
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

                    if viewModel.hasWeeklyCompletedEntries {
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
                            Text("本周已完成 \(viewModel.weeklyCompletedEntryCount) 项")
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

    private var overdueReminderCapsule: some View {
        Button {
            HomeInteractionFeedback.selection()
            viewModel.presentOverdueSheet()
        } label: {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(16, weight: .semibold))

                Text(viewModel.overdueCapsuleTitle)
                    .font(AppTheme.typography.sized(14, weight: .semibold))

                Spacer(minLength: 0)

                Text("查看全部")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral.opacity(0.8))
            }
            .foregroundStyle(AppTheme.colors.coral)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.coral.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.overdueCapsuleTitle)
    }

    private var headerPrimaryColor: Color { AppTheme.colors.title }

    private var headerSecondaryColor: Color { AppTheme.colors.body.opacity(0.62) }

    private var headerVerticalOffset: CGFloat {
        isOverlayModeActive ? -6 : 0
    }

    private var weekSectionVerticalOffset: CGFloat {
        if isOverlayModeActive {
            return 0
        }

        return viewModel.isMonthMode ? 2 : 0
    }

    private var contentCardVerticalOffset: CGFloat {
        0
    }

    private var projectModeContentTransitionOffset: CGFloat {
        30
    }

    private var contentCardScale: CGFloat {
        1
    }

    private var modeFadeAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .easeOut(duration: 0.16)
    }

    private var calendarModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }

    private var isOverlayModeActive: Bool {
        isProjectModePresented || isRoutinesModePresented
    }

    private func headerTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + (isOverlayModeActive ? 16 : AppTheme.spacing.sm)
    }

    private var horizontalContentPadding: CGFloat {
        AppTheme.spacing.xl
    }

    private func contentTopInset(safeAreaTop: CGFloat) -> CGFloat {
        0
    }

    private var topChromeReservedHeight: CGFloat {
        if isOverlayModeActive {
            return 86
        }

        return 90
    }

    private var visibleCalendarContainerHeight: CGFloat {
        isOverlayModeActive ? 0 : calendarContainerHeight
    }

    private var startupRestoreStatusReservedHeight: CGFloat {
        showsStartupRestoreStatus ? 40 : 0
    }

    private var calendarContainerHeight: CGFloat {
        viewModel.isMonthMode ? monthCalendarExpandedHeight : 76
    }

    private var monthCalendarExpandedHeight: CGFloat {
        20 + monthGridContainerHeight
    }

    private var monthGridContainerHeight: CGFloat {
        (5 * monthDayCellHeight) + (4 * monthGridSpacing)
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            calendarWeekdayHeader
                .padding(.bottom, AppTheme.spacing.xs)

            if viewModel.isMonthMode {
                monthCalendarGrid
                    .transition(monthCalendarTransition)
            } else {
                weekCalendarSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var weekCalendarSection: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)

            HStack(spacing: 0) {
                ForEach([-1, 0, 1], id: \.self) { offset in
                    weekPage(for: offset)
                        .frame(width: pageWidth - weekPageBreathingGap)
                        .frame(width: pageWidth)
                        .opacity(weekPageOpacity(for: offset, pageWidth: pageWidth))
                }
            }
            .frame(width: pageWidth * 3, alignment: .leading)
            .offset(x: -pageWidth + weekPagerOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(weekPagerDragGesture(pageWidth: pageWidth))
        }
        .frame(height: 76)
        .clipped()
    }

    private func weekPage(for offset: Int) -> some View {
        let dates = viewModel.weekDates(shiftedByWeeks: offset)

        return LazyVGrid(columns: calendarColumns, spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                let isSelected = weekDateIsSelected(date, index: index)
                Button {
                    guard !isWeekPagerInteracting else { return }
                    guard !isSelected else { return }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                        viewModel.selectDate(date)
                    }
                    triggerSoftDateFeedback()
                } label: {
                    VStack(spacing: 0) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(
                                AppTheme.typography.sized(
                                    isOverlayModeActive ? 18 : 22,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.title
                                : AppTheme.colors.textTertiary
                            )
                    }
                    .scaleEffect(isSelected ? 1.16 : 1.0)
                    .scaleEffect(isOverlayModeActive ? 0.92 : 1, anchor: .center)
                    .frame(maxWidth: .infinity)
                    .frame(height: isOverlayModeActive ? 40 : 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, calendarGridHorizontalInset)
    }

    private var calendarWeekdayHeader: some View {
        let symbols = viewModel.weekdaySymbols

        return LazyVGrid(columns: calendarColumns, spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(headerSecondaryColor)
                    .frame(maxWidth: .infinity, minHeight: calendarWeekdayHeight)
            }
        }
        .padding(.horizontal, calendarGridHorizontalInset)
    }

    private var monthCalendarGrid: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)

            HStack(spacing: 0) {
                ForEach([-1, 0, 1], id: \.self) { offset in
                    monthPage(for: offset)
                        .frame(width: pageWidth)
                        .overlay(alignment: .trailing) {
                            monthPageDividerOverlay
                        }
                        .opacity(monthPageOpacity(for: offset, pageWidth: pageWidth))
                }
            }
            .frame(width: pageWidth * 3, alignment: .leading)
            .offset(x: -pageWidth + monthPagerOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(monthPagerDragGesture(pageWidth: pageWidth))
        }
        .frame(height: monthGridContainerHeight)
        .clipped()
    }

    private func monthPage(for offset: Int) -> some View {
        let days = viewModel.monthDays(shiftedByMonths: offset)
        let rowCount = viewModel.monthRowCount(shiftedByMonths: offset)
        let layout = monthLayoutMetrics(for: rowCount)

        return LazyVGrid(
            columns: calendarColumns,
            spacing: layout.rowSpacing
        ) {
            ForEach(days) { day in
                monthDayButton(day, metrics: layout)
            }
        }
        .padding(.horizontal, calendarGridHorizontalInset)
        .padding(.top, layout.topPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func monthDayButton(_ day: HomeMonthDay, metrics: MonthLayoutMetrics) -> some View {
        let isSelected = viewModel.isSelectedDate(day.date)
        let isToday = Calendar.current.isDateInToday(day.date)
        let hasIndicator = viewModel.hasNonRecurringItems(on: day.date)
        let showsSelectedRing = isSelected && !isToday
        let showsIndicator = hasIndicator && !isSelected
        let textColor = monthDayForegroundColor(day, isSelected: isSelected)
        let dayNumber = "\(Calendar.current.component(.day, from: day.date))"

        return Button {
            guard !isMonthPagerInteracting else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                viewModel.selectDate(day.date)
            }
            triggerSoftDateFeedback()
        } label: {
            VStack(spacing: monthIndicatorSpacing) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(AppTheme.colors.coral)
                            .frame(width: metrics.circleSize, height: metrics.circleSize)
                    }

                    if showsSelectedRing {
                        Circle()
                            .stroke(AppTheme.colors.coral, lineWidth: 1.6)
                            .frame(width: metrics.circleSize, height: metrics.circleSize)
                            .blurReplaceTransition(value: showsSelectedRing)
                    }

                    monthDayNumberLabel(
                        dayNumber,
                        isToday: isToday,
                        isSelected: isSelected,
                        metrics: metrics,
                        textColor: textColor
                    )
                }
                .compositingGroup()
                .frame(width: metrics.circleSize, height: metrics.circleSize)
                .frame(maxWidth: .infinity)

                if showsIndicator {
                    Circle()
                        .fill(AppTheme.colors.coral.opacity(0.8))
                        .frame(width: monthIndicatorSize, height: monthIndicatorSize)
                        .transition(.opacity)
                } else {
                    Color.clear
                        .frame(width: monthIndicatorSize, height: monthIndicatorSize)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(.dateTime.year().month().day().weekday()))
    }

    private func monthDayNumberLabel(
        _ dayNumber: String,
        isToday: Bool,
        isSelected: Bool,
        metrics: MonthLayoutMetrics,
        textColor: Color
    ) -> some View {
        if isToday {
            return AnyView(
                todayMonthDayNumberLabel(
                    dayNumber,
                    metrics: metrics,
                    textColor: textColor
                )
            )
        }

        return AnyView(
            Text(dayNumber)
                .font(AppTheme.typography.sized(metrics.fontSize, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(textColor)
                .frame(width: metrics.circleSize, height: metrics.circleSize, alignment: .center)
                .offset(y: monthDayTextVerticalOffset)
        )
    }

    private func todayMonthDayNumberLabel(
        _ dayNumber: String,
        metrics: MonthLayoutMetrics,
        textColor: Color
    ) -> some View {
        Text(dayNumber)
            .font(AppTheme.typography.sized(metrics.fontSize - 1, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(textColor)
            .frame(width: metrics.circleSize, height: metrics.circleSize, alignment: .center)
            .offset(y: monthDayTextVerticalOffset)
    }

    private func monthDayForegroundColor(_ day: HomeMonthDay, isSelected: Bool) -> Color {
        if Calendar.current.isDateInToday(day.date) {
            return .white
        }

        if isSelected {
            return AppTheme.colors.title
        }

        if day.isInDisplayedMonth {
            return AppTheme.colors.title.opacity(Calendar.current.isDateInToday(day.date) ? 0.94 : 0.84)
        }

        return AppTheme.colors.textTertiary.opacity(0.5)
    }

    private var monthPageDividerOverlay: some View {
        Rectangle()
            .fill(homeCanvasColor.opacity(0.14))
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(homeCanvasColor.opacity(0.08))
                    .frame(width: 3)
                    .blur(radius: 1.4)
            }
        .allowsHitTesting(false)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: calendarColumnSpacing), count: 7)
    }

    private var projectModeDateLine: String {
        viewModel.selectedWeekdayAndDateText.replacingOccurrences(of: "\n", with: " · ")
    }

    private var projectModeProjectsSummary: String {
        "当前 \(projectsViewModel.activeProjects.count) 条项目进行中"
    }

    private func triggerSoftDateFeedback() {
        HomeInteractionFeedback.soft()
    }

    private var timelineTransition: AnyTransition {
        if viewModel.isMonthMode {
            return .asymmetric(
                insertion: .offset(y: 14).combined(with: .opacity),
                removal: .offset(y: -12).combined(with: .opacity)
            )
        }

        let direction: CGFloat = viewModel.selectedDateTransitionEdge == .trailing ? 1 : -1

        switch viewModel.selectedDateTransitionStyle {
        case .sameWeek:
            return .asymmetric(
                insertion: .offset(x: 12 * direction).combined(with: .opacity),
                removal: .offset(x: -10 * direction).combined(with: .opacity)
            )
        case .crossWeek:
            return .asymmetric(
                insertion: .offset(x: 18 * direction).combined(with: .opacity),
                removal: .offset(x: -14 * direction).combined(with: .opacity)
            )
        }
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

    private var monthCalendarTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TopRevealMotionModifier(scaleY: 0.84, opacity: 0),
                identity: TopRevealMotionModifier(scaleY: 1, opacity: 1)
            ),
            removal: .opacity
        )
    }

    private func monthPagerDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard viewModel.isMonthMode else { return }
                guard !isMonthPagerSettling else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                monthPagerOffset = resistedMonthPagerOffset(for: value.translation.width, pageWidth: pageWidth)
            }
            .onEnded { value in
                guard viewModel.isMonthMode else { return }
                guard !isMonthPagerSettling else { return }
                let horizontalTravel = value.translation.width
                guard abs(horizontalTravel) > abs(value.translation.height) else {
                    settleMonthPager(to: 0, pageWidth: pageWidth)
                    return
                }

                let projectedTravel = value.predictedEndTranslation.width
                let targetDirection = monthPagerTargetDirection(
                    translation: horizontalTravel,
                    predictedTranslation: projectedTravel,
                    pageWidth: pageWidth
                )

                settleMonthPager(to: targetDirection, pageWidth: pageWidth)
            }
    }

    private func monthPagerTargetDirection(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        pageWidth: CGFloat
    ) -> Int {
        let distanceThreshold = pageWidth * 0.16
        let projectedThreshold = pageWidth * 0.3

        if translation <= -distanceThreshold || predictedTranslation <= -projectedThreshold {
            return -1
        }

        if translation >= distanceThreshold || predictedTranslation >= projectedThreshold {
            return 1
        }

        return 0
    }

    private func settleMonthPager(to direction: Int, pageWidth: CGFloat) {
        isMonthPagerSettling = true

        withAnimation(calendarModeAnimation) {
            monthPagerOffset = CGFloat(direction) * pageWidth
        }

        let settleDelay = direction == 0 ? 0.2 : 0.28
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(settleDelay))

            if direction != 0 {
                var resetTransaction = Transaction()
                resetTransaction.animation = nil
                withTransaction(resetTransaction) {
                    viewModel.shiftDisplayedMonth(by: -direction)
                    monthPagerOffset = 0
                    isMonthPagerSettling = false
                }
                triggerSoftDateFeedback()
                return
            }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                monthPagerOffset = 0
                isMonthPagerSettling = false
            }
        }
    }

    private func monthPageOpacity(for offset: Int, pageWidth: CGFloat) -> Double {
        let distance = monthPageDistance(for: offset, pageWidth: pageWidth)
        return 1 - (distance * 0.06)
    }

    private func monthPageDistance(for offset: Int, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        let relativeOffset = (CGFloat(offset) * pageWidth + monthPagerOffset) / pageWidth
        return min(abs(relativeOffset), 1)
    }

    private var isMonthPagerInteracting: Bool {
        isMonthPagerSettling || abs(monthPagerOffset) > 0.5
    }

    private func resistedMonthPagerOffset(for translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let limit = pageWidth * 0.92
        guard abs(translation) > limit else { return translation }

        let overflow = abs(translation) - limit
        let resistedOverflow = overflow * 0.24
        return translation.sign == .minus
            ? -(limit + resistedOverflow)
            : limit + resistedOverflow
    }

    private func monthLayoutMetrics(for rowCount: Int) -> MonthLayoutMetrics {
        if rowCount >= 6 {
            return MonthLayoutMetrics(
                cellHeight: monthCompressedDayCellHeight,
                rowSpacing: monthCompressedGridSpacing,
                fontSize: 17,
                circleSize: monthCompressedDayCircleSize,
                topPadding: monthCompressedTopPadding
            )
        }

        return MonthLayoutMetrics(
            cellHeight: monthDayCellHeight,
            rowSpacing: monthGridSpacing,
            fontSize: 19,
            circleSize: monthDayCircleSize,
            topPadding: 0
        )
    }

    private func weekPagerDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isWeekPagerSettling else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                weekPagerOffset = resistedWeekPagerOffset(
                    for: value.translation.width,
                    pageWidth: pageWidth
                )
            }
            .onEnded { value in
                guard !isWeekPagerSettling else { return }

                let horizontalTravel = value.translation.width
                guard abs(horizontalTravel) > abs(value.translation.height) else {
                    settleWeekPager(to: 0, pageWidth: pageWidth)
                    return
                }

                let projectedTravel = value.predictedEndTranslation.width
                let targetDirection = weekPagerTargetDirection(
                    translation: horizontalTravel,
                    predictedTranslation: projectedTravel,
                    pageWidth: pageWidth
                )

                settleWeekPager(to: targetDirection, pageWidth: pageWidth)
            }
    }

    private func weekPagerTargetDirection(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        pageWidth: CGFloat
    ) -> Int {
        let distanceThreshold = pageWidth * 0.24
        let projectedDistanceThreshold = pageWidth * 0.42

        if translation <= -distanceThreshold || predictedTranslation <= -projectedDistanceThreshold {
            return -1
        }

        if translation >= distanceThreshold || predictedTranslation >= projectedDistanceThreshold {
            return 1
        }

        return 0
    }

    private func settleWeekPager(to direction: Int, pageWidth: CGFloat) {
        isWeekPagerSettling = true

        let targetOffset = CGFloat(direction) * pageWidth
        let animation = direction == 0
            ? Animation.spring(response: 0.34, dampingFraction: 0.88)
            : Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)

        withAnimation(animation) {
            weekPagerOffset = targetOffset
        }

        let settleDelay = direction == 0 ? 0.22 : 0.30
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            if direction != 0 {
                viewModel.shiftSelectedWeek(by: -direction)
                triggerSoftDateFeedback()
            }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                weekPagerOffset = 0
                isWeekPagerSettling = false
            }
        }
    }

    private func resistedWeekPagerOffset(for translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let limit = pageWidth * 0.92
        guard abs(translation) > limit else { return translation }

        let overflow = abs(translation) - limit
        let resistedOverflow = overflow * 0.24
        return translation.sign == .minus
            ? -(limit + resistedOverflow)
            : limit + resistedOverflow
    }

    private func weekPageOpacity(for offset: Int, pageWidth: CGFloat) -> Double {
        let distance = weekPageDistance(for: offset, pageWidth: pageWidth)
        return 1 - (distance * 0.025)
    }

    private func weekPageDistance(for offset: Int, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        let relativeOffset = (CGFloat(offset) * pageWidth + weekPagerOffset) / pageWidth
        return min(abs(relativeOffset), 1)
    }

    private var isWeekPagerInteracting: Bool {
        isWeekPagerSettling || abs(weekPagerOffset) > 0.5
    }

    private func weekDateIsSelected(_ date: Date, index: Int) -> Bool {
        if isWeekPagerInteracting {
            return index == weekMiddleIndex
        }

        return viewModel.isSelectedDate(date)
    }

}

private struct MonthLayoutMetrics {
    let cellHeight: CGFloat
    let rowSpacing: CGFloat
    let fontSize: CGFloat
    let circleSize: CGFloat
    let topPadding: CGFloat
}

private struct TopRevealMotionModifier: ViewModifier {
    let scaleY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: scaleY, anchor: .top)
            .opacity(opacity)
    }
}

private struct HomeInlineFocusChromeModifier: ViewModifier {
    let isFocused: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                focusBackground
            }
            .shadow(
                color: primaryShadowColor.opacity(isFocused ? primaryShadowOpacity : 0),
                radius: isFocused ? (reduceMotion ? 14 : 28) : 0,
                x: 0,
                y: isFocused ? 14 : 0
            )
            .shadow(
                color: focusSurfaceColor.opacity(isFocused ? 0.34 : 0),
                radius: isFocused ? (reduceMotion ? 6 : 10) : 0,
                x: 0,
                y: isFocused ? -3 : 0
            )
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? .black : AppTheme.colors.title
    }

    private var primaryShadowOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.08
    }

    private var focusBackground: some View {
        ZStack {
            topAmbientDimming
            focusPlate
        }
        .allowsHitTesting(false)
    }

    private var focusPlate: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(focusSurfaceColor.opacity(isFocused ? 1 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(focusSurfaceColor.opacity(isFocused ? 1 : 0), lineWidth: 0.8)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(
                        AppTheme.colors.outline.opacity(isFocused ? 0.5 : 0),
                        lineWidth: 0.6
                    )
            }
            .shadow(
                color: primaryShadowColor.opacity(isFocused ? primaryShadowOpacity : 0),
                radius: isFocused ? (reduceMotion ? 14 : 28) : 0,
                x: 0,
                y: isFocused ? 14 : 0
            )
            .shadow(
                color: AppTheme.colors.surface.opacity(isFocused ? 0.88 : 0),
                radius: isFocused ? (reduceMotion ? 12 : 22) : 0,
                x: 0,
                y: isFocused ? -10 : 0
            )
            .padding(.horizontal, 14)
            .padding(.vertical, -16)
            .allowsHitTesting(false)
    }

    private var topAmbientDimming: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    ambientDimColor.opacity(isFocused ? 0.06 : 0),
                    ambientDimColor.opacity(isFocused ? 0.03 : 0),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: reduceMotion ? 48 : 74)
            .blur(radius: reduceMotion ? 3 : 8)
            .offset(y: reduceMotion ? -34 : -48)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var ambientDimColor: Color {
        colorScheme == .dark ? .black : AppTheme.colors.title
    }

    private var focusSurfaceColor: Color {
        AppTheme.colors.surface
    }
}

private extension View {
    func blurReplaceTransition<T: Equatable>(value: T) -> some View {
        self
            .transition(.blurReplace)
            .animation(.easeInOut(duration: 0.2), value: value)
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
        projectsViewModel: context.projectsViewModel,
        routinesViewModel: context.routinesViewModel,
        isProjectModePresented: false,
        isRoutinesModePresented: false,
        onProfileTapped: {},
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
    static let compactRowMinHeight: CGFloat = 34
    static let detailVerticalSpacing: CGFloat = AppTheme.spacing.xxs
    static let attributeLeadingInset: CGFloat = 0
    static let attributeSpacing: CGFloat = 6
    static let attributeMinHeight: CGFloat = 36
    static let attributeHorizontalPadding: CGFloat = 7
    static let attributeIconSize: CGFloat = 13
    static let attributeIconWidth: CGFloat = 15
    static let attributeTextSize: CGFloat = 13
    static let detailTopPadding: CGFloat = AppTheme.spacing.xs
    static let detailBottomPadding: CGFloat = AppTheme.spacing.xs

    static func estimatedDetailHeight(subtaskCount: Int) -> CGFloat {
        let rowCount = max(subtaskCount + 3, 1)
        let compactRows = CGFloat(2) * compactRowMinHeight
        let subtaskRows = CGFloat(subtaskCount) * rowMinHeight
        let rowHeights = compactRows + subtaskRows + attributeMinHeight
        let spacings = CGFloat(max(rowCount - 1, 0)) * detailVerticalSpacing
        return detailTopPadding + rowHeights + spacings + detailBottomPadding
    }
}

private enum HomeInlineFocusTarget: Hashable {
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
    static func text(for entry: HomeTimelineEntry) -> String {
        var components: [String] = []
        if entry.timeText.isEmpty == false {
            components.append(entry.timeText)
        }

        if entry.subtasks.isEmpty == false {
            let total = entry.subtasks.count
            components.append("\(entry.subtaskCompletedCount)/\(total) 子任务")
            return components.joined(separator: " · ")
        }

        if let notes = entry.notes, notes.isEmpty == false {
            components.append(notes)
            return components.joined(separator: " · ")
        }

        components.append(entry.statusText)
        return components.joined(separator: " · ")
    }
}

private struct HomeTimelineDateSectionHeader: View {
    let section: HomeTimelineSection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.xs) {
            Text(section.title)
                .font(AppTheme.typography.sized(14, weight: .bold))
                .foregroundStyle(AppTheme.colors.title.opacity(0.82))
                .lineLimit(1)

            Text(section.subtitle)
                .font(AppTheme.typography.sized(11, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing.sm)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated.opacity(section.isUnscheduled ? 0.58 : 0.74))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppTheme.colors.outline.opacity(0.36), lineWidth: 0.6)
        )
        .accessibilityElement(children: .combine)
    }
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
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            symbol
            content
        }
    }
}

private struct HomeTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let isAnimatingReopening: Bool
    let titleLineLimit: Int
    let titleMinimumScaleFactor: CGFloat
    let isDetailPresented: Bool
    let isDetailExpanded: Bool
    let expandedTitle: String
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    let onUpdateTitle: (String) -> Void
    let onInlineFocus: (HomeInlineFocusTarget) -> Void
    @FocusState private var isTitleFocused: Bool
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
    @State private var isEditingTitle = false
    @State private var isCommittingTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeTimelineRowShell {
                Button(action: onToggleCompletion) {
                    timelineSymbol
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } content: {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                    if isDetailPresented {
                        titleRow(isInteractive: false)
                            .contentShape(Rectangle())
                    } else {
                        Button {
                            HomeInteractionFeedback.soft()
                            onOpenDetail()
                        } label: {
                            titleRow(isInteractive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .scaleEffect(rowScale, anchor: .center)
        .offset(y: rowVerticalOffset)
        .opacity(rowOpacity)
        .animation(rowDetailAnimation, value: isDetailPresented)
        .onAppear {
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
        .onChange(of: isDetailPresented) { _, isPresented in
            guard isPresented == false else { return }
            isEditingTitle = false
            isCommittingTitle = false
            isTitleFocused = false
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
        HomeTimelineSubtitleText.text(for: entry)
    }

    private var showsSubtitle: Bool {
        displaySubtitle.isEmpty == false
    }

    private func titleRow(isInteractive: Bool) -> some View {
        titleStack
        .contentShape(Rectangle())
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            if isDetailPresented, isEditingTitle {
                expandedTitleEditor
            } else if isDetailPresented {
                expandedTitleDisplay
            } else {
                titleText(entry.title)
            }

            if showsSubtitle {
                Text(displaySubtitle)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedTitleDisplay: some View {
        Button {
            beginTitleEditing()
        } label: {
            titleText(expandedTitle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑任务标题")
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.typography.sized(19, weight: .bold))
            .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
            .lineLimit(titleLineLimit)
            .minimumScaleFactor(titleMinimumScaleFactor)
            .allowsTightening(true)
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
        TextField(
            "任务标题",
            text: $titleDraft
        )
        .font(AppTheme.typography.sized(19, weight: .bold))
        .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.done)
        .lineLimit(1)
        .minimumScaleFactor(titleMinimumScaleFactor)
        .allowsTightening(true)
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

    private var subtitleColor: Color {
        // Use textTertiary (dedicated tier) for default state to avoid
        // compound opacity regressing dark-mode contrast below WCAG AA.
        if entry.timeText.isEmpty == false,
           entry.urgency == .imminent || entry.urgency == .overdue {
            return AppTheme.colors.coral.opacity(entry.isMuted ? 0.5 : 1)
        }
        guard entry.notes?.isEmpty != false else {
            return entry.isMuted ? AppTheme.colors.body.opacity(0.4) : AppTheme.colors.textTertiary
        }
        if entry.statusText == "已逾期" {
            return AppTheme.colors.coral.opacity(entry.isMuted ? 0.5 : 1)
        }
        return entry.isMuted ? AppTheme.colors.body.opacity(0.4) : AppTheme.colors.textTertiary
    }

    private var rowDetailAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .snappy(duration: 0.28, extraBounce: 0.02)
    }

    @ViewBuilder
    private var timelineSymbol: some View {
        checkmarkBadge
    }

    private var checkmarkBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .strokeBorder(AppTheme.colors.coral.opacity(0.34), lineWidth: 2)
                .scaleEffect(badgeAuraScale)
                .opacity(badgeAuraOpacity)

            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(shouldPlayCompletionAnimation ? badgeFillOpacity : (entry.isCompleted ? 0 : badgeFillOpacity))

            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: shouldPlayCompletionAnimation ? 1.7 : 1.6, dash: [3.6, 4.4])
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
            switch entry.accentColorName {
            case "coral":
                return AppTheme.colors.coral.opacity(0.58)
            default:
                return AppTheme.colors.body.opacity(0.44)
            }
        }

        if entry.isCompleted {
            return .clear
        }

        if shouldPlayCompletionAnimation {
            return AppTheme.colors.body.opacity(0.32)
        }

        switch entry.accentColorName {
        case "coral":
            return AppTheme.colors.coral.opacity(0.58)
        default:
            return AppTheme.colors.body.opacity(0.44)
        }
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

private struct HomeInlineTaskDetailView: View {
    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel
    let isExpanded: Bool
    let animationBatch: Int
    let onOpenMenu: (TaskEditorMenu) -> Void
    let onFocus: (HomeInlineFocusTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: InlineTaskDetailField?
    @State private var newSubtaskTitle = ""
    @State private var notesDraft = ""

    private enum InlineTaskDetailField: Hashable {
        case notes
        case newSubtask

        var focusTarget: HomeInlineFocusTarget {
            switch self {
            case .notes:
                return .notes
            case .newSubtask:
                return .newSubtask
            }
        }
    }

    var body: some View {
        HomeInlineCascadeStack(
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion,
            fallbackHeight: HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: subtasks.count)
        ) {
            VStack(alignment: .leading, spacing: HomeInlineTaskLayoutMetrics.detailVerticalSpacing) {
                notesEditor
                    .id(HomeInlineFocusTarget.notes.anchorID(for: entry.itemID))
                    .modifier(cascadeItem(index: 0))

                ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                    HomeInlineSubtaskRow(
                        subtask: subtask,
                        viewModel: viewModel,
                        onFocus: {
                            onFocus(.subtask(subtask.id))
                        }
                    )
                    .id(HomeInlineFocusTarget.subtask(subtask.id).anchorID(for: entry.itemID))
                    .modifier(cascadeItem(index: index + 1))
                }

                addSubtaskRow
                    .id(HomeInlineFocusTarget.newSubtask.anchorID(for: entry.itemID))
                    .modifier(cascadeItem(index: subtasks.count + 1))

                attributePills
                    .modifier(cascadeItem(index: subtasks.count + 2))
            }
            .padding(.top, HomeInlineTaskLayoutMetrics.detailTopPadding)
            .padding(.bottom, HomeInlineTaskLayoutMetrics.detailBottomPadding)
        }
        .animation(detailAnimation, value: viewModel.inlineDetailDraft?.subtasks)
        .onAppear {
            notesDraft = viewModel.inlineDetailDraft?.notes ?? ""
        }
        .onChange(of: viewModel.inlineDetailDraft?.notes) { _, notes in
            guard focusedField != .notes else { return }
            notesDraft = notes ?? ""
        }
        .onChange(of: focusedField) { oldField, field in
            if oldField == .notes, field != .notes {
                commitNotesAfterFocusUpdate()
            }
            if let field {
                onFocus(field.focusTarget)
            }
        }
        .onDisappear {
            viewModel.updateDraftNotes(notesDraft)
        }
    }

    private var subtasks: [TaskSubtaskDraft] {
        viewModel.inlineDetailDraft?.subtasks ?? []
    }

    private var cascadeRowCount: Int {
        subtasks.count + 3
    }

    private func cascadeItem(index: Int) -> HomeInlineCascadeItemModifier {
        HomeInlineCascadeItemModifier(
            index: index,
            rowCount: cascadeRowCount,
            isExpanded: isExpanded,
            animationBatch: animationBatch,
            reduceMotion: reduceMotion
        )
    }

    private var notesEditor: some View {
        TextField(
            "添加备注...",
            text: $notesDraft,
            axis: .vertical
        )
        .font(AppTheme.typography.sized(16, weight: .medium))
        .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        .lineLimit(1...4)
        .textInputAutocapitalization(.sentences)
        .focused($focusedField, equals: .notes)
        .padding(.leading, HomeInlineTaskLayoutMetrics.titleLeadingInset)
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.compactRowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func commitNotesAfterFocusUpdate() {
        Task { @MainActor in
            notesDraft = TextInputSnapshotReader.resolvedText(fallback: notesDraft)
            await Task.yield()
            viewModel.updateDraftNotes(notesDraft)
        }
    }

    private var addSubtaskRow: some View {
        HStack(alignment: .center, spacing: HomeInlineTaskLayoutMetrics.titleGap) {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(13, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(canAttemptAddSubtask ? 0.72 : 0.38))
                .frame(width: HomeInlineTaskLayoutMetrics.actionSlotWidth, height: HomeInlineTaskLayoutMetrics.compactRowMinHeight, alignment: .trailing)

            TextField(
                "添加子任务",
                text: $newSubtaskTitle
            )
            .font(AppTheme.typography.sized(15, weight: .medium))
            .foregroundStyle(AppTheme.colors.title)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($focusedField, equals: .newSubtask)
            .onSubmit {
                addSubtaskAfterFocusUpdate()
            }

            Button("添加") {
                addSubtaskAfterFocusUpdate()
            }
            .buttonStyle(.plain)
            .font(AppTheme.typography.sized(14, weight: .bold))
            .foregroundStyle(canAttemptAddSubtask ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.34))
            .disabled(!canAttemptAddSubtask)
        }
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.compactRowMinHeight, alignment: .leading)
    }

    private var attributePills: some View {
        HStack(spacing: HomeInlineTaskLayoutMetrics.attributeSpacing) {
            settingButton(title: dateTitle, systemImage: "calendar", menu: .date)
            settingButton(title: timeTitle, systemImage: "clock", menu: .time)
            settingButton(title: reminderTitle, systemImage: "bell", menu: .reminder)
            settingButton(title: repeatTitle, systemImage: "arrow.triangle.2.circlepath", menu: .repeatRule)
        }
        .padding(.leading, HomeInlineTaskLayoutMetrics.attributeLeadingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingButton(title: String, systemImage: String, menu: TaskEditorMenu) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            focusedField = nil
            onOpenMenu(menu)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(HomeInlineTaskLayoutMetrics.attributeIconSize, weight: .semibold))
                    .frame(width: HomeInlineTaskLayoutMetrics.attributeIconWidth)

                Text(title)
                    .font(AppTheme.typography.sized(HomeInlineTaskLayoutMetrics.attributeTextSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(AppTheme.colors.title.opacity(isSettingEnabled(menu) ? 0.72 : 0.32))
            .padding(.horizontal, HomeInlineTaskLayoutMetrics.attributeHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.attributeMinHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill).opacity(isSettingEnabled(menu) ? 0.72 : 0.46))
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isSettingEnabled(menu))
    }

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAttemptAddSubtask: Bool {
        canAddSubtask || focusedField == .newSubtask
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        HomeInteractionFeedback.soft()
        withAnimation(detailAnimation) {
            viewModel.addDetailDraftSubtask(title: trimmed)
            newSubtaskTitle = ""
        }
        focusedField = .newSubtask
    }

    private func addSubtaskAfterFocusUpdate() {
        Task { @MainActor in
            newSubtaskTitle = TextInputSnapshotReader.resolvedText(fallback: newSubtaskTitle)
            focusedField = nil
            await Task.yield()
            addSubtask()
        }
    }

    private var dateTitle: String {
        guard let dueAt = viewModel.inlineDetailDraft?.dueAt else { return "日期" }
        if Calendar.current.isDateInToday(dueAt) {
            return "今天"
        }
        return dueAt.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())
    }

    private var timeTitle: String {
        guard viewModel.inlineDetailDraft?.hasExplicitTime == true,
              let dueAt = viewModel.inlineDetailDraft?.dueAt
        else { return "时间" }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.inlineDetailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.inlineDetailDraft?.dueAt else {
            return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        let target = viewModel.inlineDetailDraft?.hasExplicitTime == true
            ? dueAt
            : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
        let delta = target.timeIntervalSince(remindAt)
        return TaskEditorReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard let rule = viewModel.inlineDetailDraft?.repeatRule else { return "重复" }
        let anchor = viewModel.inlineDetailDraft?.dueAt ?? viewModel.selectedDate
        return rule.title(anchorDate: anchor, calendar: .current)
    }

    private func isSettingEnabled(_ menu: TaskEditorMenu) -> Bool {
        menu != .reminder || viewModel.inlineDetailDraft?.hasExplicitTime == true
    }

    private var detailAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.86)
    }
}

private struct HomeInlineCascadeStack<Content: View>: View {
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
                            .preference(key: HomeInlineDetailHeightPreferenceKey.self, value: proxy.size.height)
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
        .onPreferenceChange(HomeInlineDetailHeightPreferenceKey.self) { height in
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
        max(measuredHeight, fallbackHeight)
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
            return
        }

        guard animated else {
            heightProgress = 0
            return
        }

        withAnimation(heightAnimation) {
            heightProgress = 0
        }
    }

    private var heightAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .snappy(duration: 0.34, extraBounce: 0.02)
    }
}

private struct HomeInlineDetailHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HomeInlineCascadeItemModifier: ViewModifier {
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
            .scaleEffect(isVisible ? 1 : 0.985, anchor: .top)
            .onAppear {
                isVisible = false
                guard isExpanded else { return }
                Task { @MainActor in
                    await Task.yield()
                    updateVisibility(true, animated: true)
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                updateVisibility(expanded, animated: true)
            }
            .onChange(of: animationBatch) { _, _ in
                updateVisibility(isExpanded, animated: true)
            }
    }

    private func updateVisibility(_ visible: Bool, animated: Bool) {
        guard animated else {
            isVisible = visible
            return
        }
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

private struct HomeInlineSubtaskRow: View {
    let subtask: TaskSubtaskDraft
    @Bindable var viewModel: HomeViewModel
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @State private var draftTitle = ""

    var body: some View {
        HStack(alignment: .center, spacing: HomeInlineTaskLayoutMetrics.titleGap) {
            HomeInlineSubtaskCheckbox(
                isCompleted: subtask.isCompleted,
                onToggle: {
                    HomeInteractionFeedback.selection()
                    viewModel.toggleDetailDraftSubtask(subtask.id)
                }
            )

            if isEditing {
                TextField(
                    subtask.title,
                    text: $draftTitle
                )
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit {
                    commitAfterFocusUpdate()
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        onFocus()
                    } else if isEditing {
                        commitAfterFocusUpdate()
                    }
                }
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    draftTitle = subtask.title
                    isEditing = true
                    isFocused = true
                } label: {
                    Text(subtask.title)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.title.opacity(subtask.isCompleted ? 0.46 : 0.9))
                        .strikethrough(subtask.isCompleted, color: AppTheme.colors.body.opacity(0.36))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                HomeInteractionFeedback.selection()
                if isEditing {
                    commitAfterFocusUpdate()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        viewModel.deleteDetailDraftSubtask(subtask.id)
                    }
                }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "xmark")
                    .font(AppTheme.typography.sized(10, weight: .bold))
                    .foregroundStyle(isEditing ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.46))
                    .frame(width: 18, height: 18)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditing ? "保存子任务" : "删除子任务")
        }
        .frame(maxWidth: .infinity, minHeight: HomeInlineTaskLayoutMetrics.compactRowMinHeight, alignment: .leading)
        .onChange(of: subtask.title) { _, title in
            guard !isEditing else { return }
            draftTitle = title
        }
    }

    private func commit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            isEditing = false
            isFocused = false
            draftTitle = ""
        }
        guard trimmed.isEmpty == false, trimmed != subtask.title else { return }
        viewModel.updateDetailDraftSubtask(subtask.id, title: trimmed)
    }

    private func commitAfterFocusUpdate() {
        Task { @MainActor in
            draftTitle = TextInputSnapshotReader.resolvedText(fallback: draftTitle)
            isFocused = false
            await Task.yield()
            guard isEditing else { return }
            commit()
        }
    }
}

private struct HomeInlineSubtaskCheckbox: View {
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.radius.xs, style: .continuous)
                    .strokeBorder(
                        isCompleted ? Color.clear : AppTheme.colors.body.opacity(0.44),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3.2, 4.0])
                    )

                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .opacity(isCompleted ? 1 : 0)
                    .offset(
                        x: AppTheme.metrics.checkmarkVisualOffset.width,
                        y: AppTheme.metrics.checkmarkVisualOffset.height
                    )
            }
            .frame(
                width: HomeInlineTaskLayoutMetrics.checkboxSize,
                height: HomeInlineTaskLayoutMetrics.checkboxSize
            )
            .frame(
                width: HomeInlineTaskLayoutMetrics.actionSlotWidth,
                height: HomeInlineTaskLayoutMetrics.rowMinHeight,
                alignment: .trailing
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeAvatarToggleButton: View {
    private let compactAvatarSize: CGFloat = 32
    private let regularAvatarSize: CGFloat = 46
    let avatar: HomeAvatar
    let foregroundColor: Color
    let secondaryForegroundColor: Color
    let compact: Bool
    let showsRestorePlaceholder: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.colors.surfaceElevated.opacity(0.82))

                avatarBadge(avatar)
            }
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(compact ? 0.86 : 1, anchor: .trailing)
        .frame(width: controlSize, height: controlSize)
    }

    private var controlSize: CGFloat {
        avatarSize + 2
    }

    private var avatarSize: CGFloat {
        compact ? compactAvatarSize : regularAvatarSize
    }

    @ViewBuilder
    private func avatarBadge(_ avatar: HomeAvatar) -> some View {
        Group {
            if showsRestorePlaceholder {
                Circle()
                    .fill(AppTheme.colors.surfaceElevated)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(AppTheme.typography.sized(16, weight: .semibold))
                            .foregroundStyle(secondaryForegroundColor.opacity(0.58))
                    }
            } else {
                UserAvatarView(
                    avatarAsset: avatar.avatarAsset,
                    displayName: avatar.displayName,
                    size: avatarSize,
                    fillColor: AppTheme.colors.surfaceElevated,
                    symbolColor: foregroundColor,
                    symbolFont: AppTheme.typography.sized(16, weight: .semibold),
                    overrideImage: avatar.overrideImage
                )
            }
        }
            .frame(width: avatarSize, height: avatarSize)
            .shadow(color: AppTheme.colors.shadow.opacity(0.65), radius: 6, y: 4)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        onSnooze()
                    } label: {
                        Image(systemName: "arrowshape.turn.up.forward.fill")
                    }
                    .tint(AppTheme.colors.sky)

                    if canDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
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
                        statusText: "已逾期",
                        accentColorName: "coral",
                        isMuted: false,
                        isCompleted: false,
                        urgency: .overdue,
                        relationText: nil,
                        primaryAvatar: nil,
                        secondaryAvatar: nil,
                        lastActionAt: nil,
                        subtasks: [],
                        subtaskCompletedCount: 0
                    ),
                    isAnimatingCompletion: animatingCompletionIDs.contains(entry.id),
                    isAnimatingReopening: false,
                    titleLineLimit: 1,
                    titleMinimumScaleFactor: 0.68,
                    isDetailPresented: false,
                    isDetailExpanded: false,
                    expandedTitle: entry.title,
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
