import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: HomeViewModel
    @Bindable var projectsViewModel: ProjectsViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let isProjectModePresented: Bool
    let isRoutinesModePresented: Bool
    let onCreateTaskTapped: () -> Void
    @State private var weekPagerOffset: CGFloat = 0
    @State private var isRequestStackExpanded = false
    @State private var isWeekPagerSettling = false
    @State private var isTodayJumpButtonVisible = false
    @State private var todayJumpRevealTask: Task<Void, Never>?
    @State private var isCompletedVisibilityButtonCompressed = false
    @State private var isCompletedSectionVisible = true
    @State private var isCompletedSectionTransitioning = false
    @State private var monthPagerOffset: CGFloat = 0
    @State private var isMonthPagerSettling = false
    @State private var previousScrollOffset: CGFloat = 0
    @State private var dockHideTask: Task<Void, Never>?

    private let weekPageBreathingGap: CGFloat = 0
    private let calendarColumnSpacing: CGFloat = AppTheme.spacing.sm
    private let calendarGridHorizontalInset: CGFloat = 4
    private let calendarWeekdayHeight: CGFloat = 20
    private let weekMiddleIndex = 3
    private let contentCardCornerRadius: CGFloat = 40
    private let timelineRowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let timelineRowVerticalInset: CGFloat = 14
    private let timelineBottomInset: CGFloat = 188
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
                    .mask {
                        bottomChromeContentMask(bottomInset: proxy.safeAreaInsets.bottom)
                    }
                    .offset(y: contentCardVerticalOffset)
                    .scaleEffect(contentCardScale, anchor: .top)

                topChrome(safeAreaTop: proxy.safeAreaInsets.top)
                    .zIndex(2)

                if viewModel.selectedItemID != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            HomeInteractionFeedback.selection()
                            viewModel.dismissItemDetail()
                        }
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .font(AppTheme.typography.body)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
            updateTodayJumpButtonVisibility()
            await viewModel.performDeferredMaintenanceIfNeeded()
        }
        .task(id: viewModel.selectedDateKey) {
            await viewModel.reload()
            updateTodayJumpButtonVisibility()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.selectedItemID != nil },
                set: { if !$0 { viewModel.dismissItemDetail() } }
            )
        ) {
            HomeItemDetailSheet(viewModel: viewModel)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isOverdueSheetPresented },
                set: { if !$0 { viewModel.dismissOverdueSheet() } }
            )
        ) {
            HomeOverdueSummarySheet(viewModel: viewModel)
        }
        .onAppear {
            isCompletedSectionVisible = viewModel.showsCompletedItems
        }
        .onDisappear {
            todayJumpRevealTask?.cancel()
        }
    }

    private var backgroundView: some View {
        Group {
            homeCanvasColor
        }
        .ignoresSafeArea()
    }

    private func bottomChromeContentMask(bottomInset: CGFloat) -> some View {
        let fadeHeight = max(78, bottomInset + 42)

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white)
                    .frame(height: max(0, proxy.size.height - fadeHeight))

                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.72),
                                .init(color: .white.opacity(0.94), location: 0.84),
                                .init(color: .white.opacity(0.72), location: 0.92),
                                .init(color: .white.opacity(0.34), location: 0.97),
                                .init(color: .white.opacity(0.12), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: fadeHeight)
            }
        }
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
            }
            .padding(.bottom, isOverlayModeActive ? 4 : 0)
            .background(homeCanvasColor)

            LinearGradient(
                stops: [
                    .init(color: homeCanvasColor, location: 0),
                    .init(color: homeCanvasColor.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
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
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: viewModel.showsPairAvatarPreview)
    }

    private var spaceModeLine: some View {
        HStack(spacing: 8) {
            Text(viewModel.isPairModeActive ? "双人模式" : "单人模式")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(viewModel.isPairModeActive ? AppTheme.colors.coral : headerSecondaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            viewModel.isPairModeActive
                            ? AppTheme.colors.coral.opacity(0.12)
                            : AppTheme.colors.surfaceElevated
                        )
                )

            Text(viewModel.spaceDisplayName)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)

            if viewModel.isPairModeActive {
                SyncStatusIndicator(
                    status: appContext.sessionStore.sharedSyncStatus
                )
            }
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
        Text(viewModel.isPairModeActive ? "双人模式" : "单人模式")
            .font(AppTheme.typography.sized(12, weight: .bold))
            .foregroundStyle(viewModel.isPairModeActive ? AppTheme.colors.coral : headerSecondaryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        viewModel.isPairModeActive
                        ? AppTheme.colors.coral.opacity(0.12)
                        : AppTheme.colors.surfaceElevated
                    )
            )
    }

    private var routinesModeHeaderMeta: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Text(viewModel.isPairModeActive ? "双人模式" : "单人模式")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(viewModel.isPairModeActive ? AppTheme.colors.coral : headerSecondaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            viewModel.isPairModeActive
                            ? AppTheme.colors.coral.opacity(0.12)
                            : AppTheme.colors.surfaceElevated
                        )
                )
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
            avatars: viewModel.headerAvatars,
            foregroundColor: headerPrimaryColor,
            secondaryForegroundColor: headerSecondaryColor,
            compact: compact,
            action: {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    viewModel.toggleAvatarPreview()
                }
                triggerSoftDateFeedback()
            }
        )
        .padding(.top, compact ? 0 : 2)
        .id(appContext.sessionStore.userProfileRevision)
        .compositingGroup()
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
            if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if appContext.routinesViewModel.hasPendingTasks {
                            RoutinesSummaryCard(
                                viewModel: appContext.routinesViewModel,
                                onNavigateToRoutines: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                                        viewModel.setCalendarDisplayMode(.week)
                                        appContext.router.currentSurface = .routines
                                    }
                                }
                            )
                        }

                        timelineSection
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, 14)
                    .padding(.bottom, 144)
                }
                .id("empty-\(viewModel.selectedDateKey)")
                .scrollIndicators(.hidden)
                .scrollDisabled(isOverlayModeActive)
                .applyScrollEdgeProtection()
                .transition(timelineTransition)
            } else {
                timelineList
                    .id("timeline-\(viewModel.selectedDateKey)")
                    .transition(timelineTransition)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: viewModel.selectedDateKey)
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
            contentTopPadding: 24,
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

    private var timelineList: some View {
        Group {
            if viewModel.isPairModeActive {
                pairTimelineList
            } else {
                standardTimelineList
            }
        }
    }

    private var standardTimelineList: some View {
        List {
            Color.clear
                .frame(height: 10)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(homeCanvasColor)
                .listRowSeparator(.hidden)

            if viewModel.showsOverdueCapsule {
                overdueReminderCapsule
                    .listRowInsets(
                        EdgeInsets(
                            top: 10,
                            leading: timelineRowHorizontalInset,
                            bottom: 8,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)

            }

            if appContext.routinesViewModel.hasPendingTasks {
                RoutinesSummaryCard(
                    viewModel: appContext.routinesViewModel,
                    onNavigateToRoutines: {
                        appContext.router.currentSurface = .routines
                    }
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: timelineRowHorizontalInset,
                        bottom: 8,
                        trailing: timelineRowHorizontalInset
                    )
                )
                .listRowBackground(homeCanvasColor)
                .listRowSeparator(.hidden)
            }

            timelineRows(
                viewModel.activeTimelineEntries,
                rowTransition: activeRowTransition
            )

            if viewModel.hasCompletedEntries {
                completedVisibilityButton
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(
                        EdgeInsets(
                            top: 12,
                            leading: timelineRowHorizontalInset,
                            bottom: viewModel.completedTimelineEntries.isEmpty ? timelineBottomInset : 10,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)

                if viewModel.showsCompletedItems {
                    completedTimelineSection
                }
            } else {
                Color.clear
                    .frame(height: timelineBottomInset)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDisabled(isOverlayModeActive)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.top, 0)
        .background(homeCanvasColor)
        .applyScrollEdgeProtection()
        .refreshable {
            if appContext.sessionStore.hasActivePairSpace {
                await appContext.syncPairSpaceIfNeeded()
            }
            await viewModel.reload()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { oldOffset, newOffset in
            handleScrollOffsetChange(from: oldOffset, to: newOffset)
        }
    }

    private var pairTimelineList: some View {
        List {
            Color.clear
                .frame(height: 10)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(homeCanvasColor)
                .listRowSeparator(.hidden)

            if viewModel.showsOverdueCapsule {
                overdueReminderCapsule
                    .listRowInsets(
                        EdgeInsets(
                            top: 10,
                            leading: timelineRowHorizontalInset,
                            bottom: 8,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)
            }

            if appContext.routinesViewModel.hasPendingTasks {
                RoutinesSummaryCard(
                    viewModel: appContext.routinesViewModel,
                    onNavigateToRoutines: {
                        appContext.router.currentSurface = .routines
                    }
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: timelineRowHorizontalInset,
                        bottom: 8,
                        trailing: timelineRowHorizontalInset
                    )
                )
                .listRowBackground(homeCanvasColor)
                .listRowSeparator(.hidden)
            }

            pairTimelineRows(viewModel.activeTimelineEntries)

            if viewModel.hasCompletedEntries {
                completedVisibilityButton
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(
                        EdgeInsets(
                            top: 12,
                            leading: timelineRowHorizontalInset,
                            bottom: viewModel.completedTimelineEntries.isEmpty ? timelineBottomInset : 10,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)

                if viewModel.showsCompletedItems, viewModel.completedTimelineEntries.isEmpty == false {
                    completedTimelineSection
                }
            } else {
                Color.clear
                    .frame(height: timelineBottomInset)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(homeCanvasColor)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDisabled(isOverlayModeActive)
        .environment(\.defaultMinListRowHeight, 0)
        .background(homeCanvasColor)
        .applyScrollEdgeProtection()
        .refreshable {
            if appContext.sessionStore.hasActivePairSpace {
                await appContext.syncPairSpaceIfNeeded()
            }
            await viewModel.reload()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { oldOffset, newOffset in
            handleScrollOffsetChange(from: oldOffset, to: newOffset)
        }
    }

    private var todayJumpButton: some View {
        Button("Today", systemImage: "arrow.uturn.backward.circle.fill") {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isTodayJumpButtonVisible = false
                viewModel.returnToToday()
            }
            HomeInteractionFeedback.selection()
        }
        .font(AppTheme.typography.sized(13, weight: .semibold))
        .foregroundStyle(headerPrimaryColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 42)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .modifier(HomeAvatarGlassModifier(isCircular: false))
        .buttonStyle(.plain)
        .accessibilityLabel("返回今天")
    }

    private var todayJumpTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9, anchor: .leading)
                .combined(with: .opacity),
            removal: .scale(scale: 0.95, anchor: .leading)
                .combined(with: .opacity)
        )
    }

    private func updateTodayJumpButtonVisibility() {
        todayJumpRevealTask?.cancel()

        guard shouldShowTodayJumpButton else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
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
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isTodayJumpButtonVisible = true
                }
            }
        }
    }

    private var shouldShowTodayJumpButton: Bool {
        guard !viewModel.isViewingToday, !isOverlayModeActive else {
            return false
        }

        let calendar = Calendar.current
        return !calendar.isDate(viewModel.selectedDate, equalTo: .now, toGranularity: .weekOfYear)
    }

    @ViewBuilder
    private var completedTimelineSection: some View {
        timelineRows(
            viewModel.completedTimelineEntries,
            rowTransition: completedRowTransition,
            sectionVisibility: CompletedSectionVisibility(
                isVisible: isCompletedSectionVisible,
                count: viewModel.completedTimelineEntries.count
            )
        )

        if viewModel.completedTimelineEntries.isEmpty == false {
            Color.clear
                .frame(height: timelineBottomInset)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(homeCanvasColor)
                .listRowSeparator(.hidden)
                .modifier(CompletedSectionMotionModifier(isVisible: isCompletedSectionVisible))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func timelineRows(
        _ entries: [HomeTimelineEntry],
        rowTransition: AnyTransition? = nil,
        sectionVisibility: CompletedSectionVisibility? = nil
    ) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            let isCompletedRow = sectionVisibility != nil || entry.isCompleted
            Group {
                if entry.isCompleted {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.id, on: viewModel.selectedDate),
                        isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.id, on: viewModel.selectedDate),
                        titleLineLimit: 1,
                        titleMinimumScaleFactor: 0.72,
                        onToggleCompletion: {
                            if entry.isCompleted {
                                HomeInteractionFeedback.selection()
                            } else {
                                HomeInteractionFeedback.completion()
                            }
                            Task {
                                await viewModel.completeItem(entry.id)
                            }
                        },
                        onOpenDetail: {
                            viewModel.presentItemDetail(entry.id)
                        }
                    )
                } else {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: viewModel.isAnimatingCompletion(for: entry.id, on: viewModel.selectedDate),
                        isAnimatingReopening: viewModel.isAnimatingReopening(for: entry.id, on: viewModel.selectedDate),
                        titleLineLimit: 2,
                        titleMinimumScaleFactor: 0.84,
                        onToggleCompletion: {
                            if entry.isCompleted {
                                HomeInteractionFeedback.selection()
                            } else {
                                HomeInteractionFeedback.completion()
                            }
                            Task {
                                await viewModel.completeItem(entry.id)
                            }
                        },
                        onOpenDetail: {
                            viewModel.presentItemDetail(entry.id)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            HomeInteractionFeedback.selection()
                            Task {
                                await viewModel.snoozeItem(entry.id)
                            }
                        } label: {
                            Image(systemName: "arrowshape.turn.up.forward.fill")
                        }
                        .tint(AppTheme.colors.sky)

                        Button(role: .destructive) {
                            HomeInteractionFeedback.selection()
                            Task {
                                await viewModel.deleteItem(entry.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .listRowInsets(
                EdgeInsets(
                    top: timelineRowVerticalInset,
                    leading: timelineRowHorizontalInset,
                    bottom: timelineRowVerticalInset,
                    trailing: timelineRowHorizontalInset
                )
            )
            .listRowBackground(isCompletedRow ? Color.clear : homeCanvasColor)
            .listRowSeparator(.hidden)
            .insertedListItemMotion(
                isInserted: viewModel.isAnimatingInsertion(for: entry.id),
                onAnimationCompleted: {
                    viewModel.completeInsertionAnimation(for: entry.id)
                }
            )
            .applyTransition(rowTransition)
            .applyCompletedSectionVisibility(
                sectionVisibility.map { $0.rowVisibility(for: index) }
            )

        }
    }

    /// 请求类卡片（待回应）最多显示数量，超过时堆叠
    private var requestCardStackThreshold: Int { 3 }

    @ViewBuilder
    private func pairTimelineRows(_ entries: [HomeTimelineEntry]) -> some View {
        let requestEntries = entries.filter { $0.pairCardStyle == .request }
        let otherEntries = entries.filter { $0.pairCardStyle != .request }

        // 待回应卡片：超过阈值时堆叠显示
        if requestEntries.count > requestCardStackThreshold && !isRequestStackExpanded {
            stackedRequestCards(requestEntries)
        } else {
            ForEach(requestEntries) { entry in
                pairTimelineCardRow(entry: entry)
            }
        }

        // 其他类型卡片正常显示
        ForEach(otherEntries) { entry in
            pairTimelineCardRow(entry: entry)
        }
    }

    @ViewBuilder
    private func stackedRequestCards(_ entries: [HomeTimelineEntry]) -> some View {
        if let topEntry = entries.first {
            ZStack(alignment: .topTrailing) {
                // 底层卡片（第3张）
                if entries.count > 2 {
                    pairTimelineCardContent(entry: entries[2])
                        .scaleEffect(0.92)
                        .offset(y: 16)
                        .opacity(0.4)
                }
                // 中间卡片（第2张）
                if entries.count > 1 {
                    pairTimelineCardContent(entry: entries[1])
                        .scaleEffect(0.96)
                        .offset(y: 8)
                        .opacity(0.6)
                }
                // 顶部卡片
                pairTimelineCardContent(entry: topEntry)

                // 计数徽章
                Text("+\(entries.count - 1)")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(AppTheme.colors.coral))
                    .offset(x: -8, y: -4)
            }
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: timelineRowHorizontalInset,
                    bottom: 24,
                    trailing: timelineRowHorizontalInset
                )
            )
            .listRowBackground(homeCanvasColor)
            .listRowSeparator(.hidden)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isRequestStackExpanded = true
                }
            }
        }
    }

    /// 仅卡片内容（不含 listRow 修饰符），用于堆叠展示
    private func pairTimelineCardContent(entry: HomeTimelineEntry) -> some View {
        PairTimelineCard(
            entry: entry,
            quickReplyMessages: appContext.sessionStore.currentUser?.preferences.pairQuickReplyMessages
                ?? NotificationSettings.defaultPairQuickReplyMessages,
            onPrimaryAction: {},
            onSecondaryAction: {},
            onOpenDetail: {},
            onQuickMessage: { _ in },
            onResend: {},
            onDelete: {},
            onSendReminder: {}
        )
        .allowsHitTesting(false)
    }

    private func pairTimelineCardRow(entry: HomeTimelineEntry) -> some View {
        PairTimelineCard(
            entry: entry,
            quickReplyMessages: appContext.sessionStore.currentUser?.preferences.pairQuickReplyMessages
                ?? NotificationSettings.defaultPairQuickReplyMessages,
            onPrimaryAction: {
                switch entry.pairCardStyle {
                case .request:
                    HomeInteractionFeedback.selection()
                    Task {
                        await viewModel.respondToItem(entry.id, response: .willing, message: nil)
                    }
                default:
                    if entry.isCompleted {
                        HomeInteractionFeedback.selection()
                    } else {
                        HomeInteractionFeedback.completion()
                    }
                    Task {
                        await viewModel.completeItem(entry.id)
                    }
                }
            },
            onSecondaryAction: {
                HomeInteractionFeedback.selection()
                Task {
                    await viewModel.respondToItem(entry.id, response: .notSuitable, message: nil)
                }
            },
            onOpenDetail: {
                viewModel.presentItemDetail(entry.id)
            },
            onQuickMessage: { message in
                Task {
                    switch entry.pairCardStyle {
                    case .request:
                        await viewModel.respondToItem(entry.id, response: .notSuitable, message: message)
                    case .sent:
                        await viewModel.appendAssignmentMessage(to: entry.id, message: message)
                    case .assigned, .shared, .standard:
                        break
                    }
                }
            },
            onResend: {
                Task {
                    await viewModel.requeueDeclinedItem(entry.id)
                }
            },
            onDelete: {
                Task {
                    await viewModel.deleteItem(entry.id)
                }
            },
            onSendReminder: {
                Task {
                    await viewModel.sendReminderToPartner(entry.id)
                }
            }
        )
        .listRowInsets(
            EdgeInsets(
                top: 8,
                leading: timelineRowHorizontalInset,
                bottom: 8,
                trailing: timelineRowHorizontalInset
            )
        )
        .listRowBackground(homeCanvasColor)
        .listRowSeparator(.hidden)
        .insertedListItemMotion(
            isInserted: viewModel.isAnimatingInsertion(for: entry.id),
            onAnimationCompleted: {
                viewModel.completeInsertionAnimation(for: entry.id)
            }
        )
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            calendarWeekdayHeader
                .padding(.bottom, 8)

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
                        Text(date, format: .dateTime.day())
                            .font(
                                AppTheme.typography.sized(
                                    isOverlayModeActive ? 18 : 22,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
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

    private var timelineSection: some View {
        ZStack {
            if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: viewModel.isPairModeActive ? "leaf.fill" : "sun.max.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(
                                viewModel.isPairModeActive
                                    ? AppTheme.colors.sky.opacity(0.5)
                                    : AppTheme.colors.coral.opacity(0.4)
                            )
                            .symbolEffect(.breathe.plain, options: .repeating)

                        Text(viewModel.isPairModeActive ? "共享空间暂无待办" : "今天没有待办事项")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                        Text(viewModel.isPairModeActive ? "和对方一起创建任务吧" : "享受当下，或规划新任务")
                            .font(AppTheme.typography.sized(14, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.38))
                    }

                    Button {
                        HomeInteractionFeedback.selection()
                        onCreateTaskTapped()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(AppTheme.typography.sized(14, weight: .semibold))

                            Text("新建任务")
                                .font(AppTheme.typography.sized(15, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.colors.title)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)

                    if viewModel.hasCompletedEntries {
                        Button {
                            HomeInteractionFeedback.selection()
                            isCompletedVisibilityButtonCompressed = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(110))
                                isCompletedVisibilityButtonCompressed = false
                            }
                            toggleCompletedSectionVisibility()
                        } label: {
                            Text("查看已完成 \(viewModel.completedEntryCount) 项")
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
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.timelineEntryIDs)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.hasCompletedEntries)
    }

    private var completedVisibilityButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            isCompletedVisibilityButtonCompressed = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                isCompletedVisibilityButtonCompressed = false
            }
            toggleCompletedSectionVisibility()
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.completedVisibilityButtonTitle)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.76))

                Text("\(viewModel.completedEntryCount)")
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(
                        Circle()
                            .fill(AppTheme.colors.background.opacity(0.8))
                    )
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
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
            HStack(spacing: 10) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
        safeAreaTop + topChromeReservedHeight + visibleCalendarContainerHeight
    }

    private var topChromeReservedHeight: CGFloat {
        if isOverlayModeActive {
            return 86
        }

        return viewModel.isPairModeActive ? 98 : 90
    }

    private var visibleCalendarContainerHeight: CGFloat {
        isOverlayModeActive ? 0 : calendarContainerHeight
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

    private func toggleCompletedSectionVisibility() {
        guard isCompletedSectionTransitioning == false else { return }
        isCompletedSectionTransitioning = true
        let staggerCount = min(viewModel.completedTimelineEntries.count, 6)
        let staggerDelay = Double(max(staggerCount - 1, 0)) * 0.028

        if viewModel.showsCompletedItems {
            withAnimation(.bouncy(duration: 0.46, extraBounce: 0.16)) {
                isCompletedSectionVisible = false
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.46 + staggerDelay))
                viewModel.setCompletedVisibility(false)
                isCompletedSectionTransitioning = false
            }
        } else {
            isCompletedSectionVisible = false
            viewModel.setCompletedVisibility(true)

            Task { @MainActor in
                await Task.yield()
                withAnimation(.bouncy(duration: 0.82, extraBounce: 0.2)) {
                    isCompletedSectionVisible = true
                }
                try? await Task.sleep(for: .seconds(0.82 + staggerDelay))
                isCompletedSectionTransitioning = false
            }
        }
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
                active: VerticalMotionModifier(offsetY: -18, scale: 0.984, opacity: 0),
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

    // MARK: - Dock Auto-Hide on Scroll

    private func handleScrollOffsetChange(from oldOffset: CGFloat, to newOffset: CGFloat) {
        let delta = newOffset - oldOffset
        let scrollThreshold: CGFloat = 6

        guard abs(delta) > scrollThreshold else { return }

        let isScrollingUp = delta > 0   // content moving up = finger dragging up
        let shouldHide = isScrollingUp && newOffset > 30  // only hide after some scroll

        dockHideTask?.cancel()

        if shouldHide {
            if !viewModel.isDockHidden {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    viewModel.isDockHidden = true
                }
            }
            // Auto-restore after 1.8s of no scroll activity
            dockHideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    viewModel.isDockHidden = false
                }
            }
        } else {
            // Scrolling down → show dock immediately
            if viewModel.isDockHidden {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    viewModel.isDockHidden = false
                }
            }
        }
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

private extension View {
    func blurReplaceTransition<T: Equatable>(value: T) -> some View {
        self
            .transition(.blurReplace)
            .animation(.easeInOut(duration: 0.2), value: value)
    }
}

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
        onCreateTaskTapped: {}
    )
}

private struct HomeTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let isAnimatingReopening: Bool
    let titleLineLimit: Int
    let titleMinimumScaleFactor: CGFloat
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    @State private var completionAnimationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var badgeOutlineOpacity = 1.0
    @State private var badgeFillScale: CGFloat = 0.5
    @State private var badgeFillOpacity = 0.0
    @State private var rowScale: CGFloat = 1
    @State private var rowVerticalOffset: CGFloat = 0
    @State private var rowOpacity: Double = 1
    @State private var reopeningCheckmarkOpacity: Double = 1

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Button(action: onToggleCompletion) {
                timelineSymbol
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button {
                HomeInteractionFeedback.soft()
                onOpenDetail()
            } label: {
                HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title)
                            .font(AppTheme.typography.sized(19, weight: .bold))
                            .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
                            .lineLimit(titleLineLimit)
                            .minimumScaleFactor(titleMinimumScaleFactor)
                            .allowsTightening(true)

                        if (entry.assigneeText != nil || entry.needsResponse), entry.isCompleted == false {
                            HStack(spacing: 8) {
                                if let assigneeText = entry.assigneeText {
                                    Text(assigneeText)
                                        .font(AppTheme.typography.sized(12, weight: .bold))
                                        .foregroundStyle(entry.needsResponse ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.72))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(
                                                    entry.needsResponse
                                                    ? AppTheme.colors.coral.opacity(0.12)
                                                    : AppTheme.colors.surfaceElevated
                                                )
                                        )
                                }

                                if entry.needsResponse {
                                    Text("待你回应")
                                        .font(AppTheme.typography.sized(12, weight: .bold))
                                        .foregroundStyle(AppTheme.colors.coral)
                                }
                            }
                        }

                        Text(displaySubtitle)
                            .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        HomeTimelineTimeText(entry: entry)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scaleEffect(rowScale, anchor: .center)
        .offset(y: rowVerticalOffset)
        .opacity(rowOpacity)
        .onChange(of: isAnimatingCompletion) { _, newValue in
            guard newValue else { return }

            completionAnimationCount += 1
            badgeOutlineOpacity = 1
            badgeFillScale = 0.42
            badgeFillOpacity = reduceMotion ? 0.12 : 0.2
            badgeScale = reduceMotion ? 1 : 0.82
            rowScale = reduceMotion ? 1 : 0.988
            rowVerticalOffset = reduceMotion ? 0 : -1

            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.1)) {
                badgeOutlineOpacity = reduceMotion ? 0.18 : 0
            }

            Task { @MainActor in
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.18)) {
                        badgeFillScale = 1
                        badgeFillOpacity = 0
                    }
                    return
                }

                try? await Task.sleep(for: .milliseconds(72))
                withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) {
                    badgeScale = 1.16
                    badgeFillScale = 1.02
                    rowScale = 0.982
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    badgeFillOpacity = 0.26
                }

                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                    badgeScale = 1
                    rowScale = 1
                    rowVerticalOffset = 2
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    badgeFillScale = 1.34
                    badgeFillOpacity = 0
                }

                try? await Task.sleep(for: .milliseconds(84))
                withAnimation(.easeOut(duration: 0.12)) {
                    rowVerticalOffset = 0
                }
            }
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
    }

    private var displaySubtitle: String {
        if let messagePreview = entry.messagePreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           messagePreview.isEmpty == false {
            return messagePreview
        }
        if let notes = entry.notes, notes.isEmpty == false {
            return notes
        }
        if let responseStateText = entry.responseStateText {
            return responseStateText
        }
        return entry.statusText
    }

    private var subtitleColor: Color {
        guard entry.notes?.isEmpty != false else {
            return AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.68)
        }
        if entry.statusText == "已逾期" {
            return AppTheme.colors.coral.opacity(entry.isMuted ? 0.5 : 1)
        }
        return AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.68)
    }

    @ViewBuilder
    private var timelineSymbol: some View {
        checkmarkBadge
    }

    private var checkmarkBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(entry.isCompleted ? 0 : badgeFillOpacity)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: isAnimatingCompletion ? 1.8 : 1.6, dash: [3.6, 4.4])
                )
                .opacity(outlineOpacity)

            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(17, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.15), value: completionAnimationCount)
                .opacity(checkmarkOpacity)
        }
        .scaleEffect(isAnimatingCompletion ? badgeScale : 1)
        .shadow(
            color: AppTheme.colors.coral.opacity(isAnimatingCompletion ? 0.2 : 0),
            radius: isAnimatingCompletion ? 12 : 0,
            y: isAnimatingCompletion ? 5 : 0
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

        if isAnimatingCompletion {
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
        if isAnimatingCompletion { return badgeOutlineOpacity }
        return 1
    }

    private var checkmarkOpacity: Double {
        guard entry.isCompleted || isAnimatingCompletion || isAnimatingReopening else { return 0 }
        return isAnimatingReopening ? reopeningCheckmarkOpacity : 1
    }
}

private struct PairTimelineCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: HomeTimelineEntry
    let quickReplyMessages: [String]
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onOpenDetail: () -> Void
    let onQuickMessage: (String) -> Void
    let onResend: () -> Void
    let onDelete: () -> Void
    let onSendReminder: () -> Void
    @State private var isMorphingToAssigned = false
    @State private var completionAnimationCount = 0
    @State private var completionBadgeScale: CGFloat = 1
    @State private var completionFillScale: CGFloat = 0.5
    @State private var completionFillOpacity = 0.0
    @State private var completionOutlineOpacity = 1.0
    @State private var rowScale: CGFloat = 1
    @State private var rowVerticalOffset: CGFloat = 0
    @State private var rowOpacity: Double = 1
    @State private var transientBubbleText: String?
    @State private var bubbleScale: CGFloat = 1
    @State private var bubbleOpacity: Double = 1
    @State private var lastSentAnimationSignature = ""
    @State private var showsKeepForLaterAction = true
    @State private var isAwaitingCompletionCommit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: handleCardTap) {
                VStack(alignment: .leading, spacing: 14) {
                    headerRow
                    subtitleLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            bottomRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            HStack(spacing: 0) {
                if effectivePairCardStyle == .shared {
                    AppTheme.colors.sky.opacity(0.36)
                        .frame(width: 5)
                }
                AppTheme.colors.surfaceElevated
                    .frame(maxWidth: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 16, y: 10)
        .scaleEffect(rowScale)
        .offset(y: rowVerticalOffset)
        .opacity(rowOpacity)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: effectivePairCardStyle)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: entry.responseStateText)
        .modifier(
            PairNativeContextMenuModifier(
                messages: supportsLongPressMenu ? quickReplyMessages : [],
                onSelectMessage: handleQuickMessage
            )
        )
        .onChange(of: entry.isCompleted) { _, isCompleted in
            guard isCompleted else {
                resetCompletionBadgeState()
                return
            }
            if isAwaitingCompletionCommit {
                isAwaitingCompletionCommit = false
                return
            }
            runCompletionAnimation()
        }
        .onAppear {
            lastSentAnimationSignature = sentAnimationSignature
            showsKeepForLaterAction = entry.pairCardStyle == .sent ? entry.responseStateText == "已拒绝" : true
            if entry.isCompleted == false {
                resetCompletionBadgeState()
            }
        }
        .onChange(of: sentAnimationSignature) { oldValue, newValue in
            guard oldValue != newValue else { return }
            lastSentAnimationSignature = newValue
            guard entry.pairCardStyle == .sent else { return }
            guard newValue.isEmpty == false else { return }
            runSentCardMessageAnimation()
        }
        .onChange(of: entry.responseStateText) { _, newValue in
            guard entry.pairCardStyle == .sent else { return }
            showsKeepForLaterAction = newValue == "已拒绝"
        }
        .onChange(of: effectivePairCardStyle) { _, newValue in
            guard newValue == .assigned || newValue == .shared || newValue == .standard else { return }
            if entry.isCompleted == false {
                resetCompletionBadgeState()
            }
        }
    }

    private var supportsLongPressMenu: Bool {
        entry.pairCardStyle == .request || supportsSentQuickReplyMenu
    }

    private var supportsSentQuickReplyMenu: Bool {
        entry.pairCardStyle == .sent && entry.responseStateText == "已拒绝"
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(entry.title)
                .font(AppTheme.typography.sized(20, weight: .bold))
                .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.42) : AppTheme.colors.title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)

            Spacer(minLength: 0)

            if entry.timeText.isEmpty == false {
                Text(entry.timeText)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(timeColor)
            }
        }
    }

    private var subtitleLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
               notes.isEmpty == false {
                Text(notes)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
            }
            Text(subtitleText)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        switch entry.pairCardStyle {
        case .request:
            HStack(alignment: .center, spacing: 12) {
                messageIdentityRow

                Spacer(minLength: 0)

                if isMorphingToAssigned {
                    PairCompletionBadge(
                        isCompleted: false,
                        isAnimatingCompletion: false,
                        accentColor: AppTheme.colors.coral,
                        scale: 1,
                        fillScale: 1,
                        fillOpacity: 0.12,
                        outlineOpacity: 0.2,
                        animationCount: 0,
                        action: {}
                    )
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                } else {
                    PairCardPillButton(title: "拒绝", isPrimary: false, action: handleSecondaryAction)
                    PairCardPillButton(title: "接受", isPrimary: true, action: handlePrimaryAction)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        case .sent:
            HStack(alignment: .center, spacing: 12) {
                messageIdentityRow
                Spacer(minLength: 0)

                if entry.responseStateText == "已拒绝" {
                    PairCardPillButton(title: "删除", isPrimary: false, action: handleDeleteAction)
                    if showsKeepForLaterAction {
                        PairCardPillButton(title: "暂留", isPrimary: false, action: handleKeepForLaterAction)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    PairCardPillButton(title: "再发", isPrimary: true, action: handleResendAction)
                } else if entry.responseStateText == "已接受" || entry.responseStateText == "进行中" {
                    reminderButton
                }
            }
        case .assigned, .shared, .standard:
            HStack(alignment: .center, spacing: 12) {
                messageIdentityRow

                Spacer(minLength: 0)

                PairCompletionBadge(
                    isCompleted: entry.isCompleted,
                    isAnimatingCompletion: isAwaitingCompletionCommit,
                    accentColor: entry.pairCardStyle == .shared ? AppTheme.colors.sky : AppTheme.colors.coral,
                    scale: completionBadgeScale,
                    fillScale: completionFillScale,
                    fillOpacity: completionFillOpacity,
                    outlineOpacity: completionOutlineOpacity,
                    animationCount: completionAnimationCount,
                    action: handleCompletionAction
                )
            }
        }
    }

    private var messageIdentityRow: some View {
        HStack(alignment: .center, spacing: 10) {
            PairTimelineAvatarStrip(
                primaryAvatar: entry.primaryAvatar,
                secondaryAvatar: entry.secondaryAvatar,
                style: effectivePairCardStyle
            )

            messageTextView
        }
    }

    /// 催促对方的小按钮（30 秒冷却）
    @State private var reminderShakeCount = 0

    private var reminderButton: some View {
        let isOnCooldown: Bool = {
            guard let lastReminder = entry.reminderRequestedAt else { return false }
            return Date.now.timeIntervalSince(lastReminder) < 30
        }()

        return Button {
            // 强震动反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            reminderShakeCount += 1
            onSendReminder()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.bounce.byLayer, value: reminderShakeCount)
                Text("催一下")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
            }
            .foregroundStyle(isOnCooldown ? AppTheme.colors.textTertiary : AppTheme.colors.coral)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isOnCooldown ? AppTheme.colors.background : AppTheme.colors.coral.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(isOnCooldown)
        .animation(.easeInOut(duration: 0.2), value: isOnCooldown)
    }

    private var messageTextView: some View {
        Group {
            if shouldShowMessageBubble {
                Text(displayedMessageText)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(alignment: .bottomLeading) {
                        PairMessageBubbleBackground(fill: bubbleFillColor)
                    }
                    .scaleEffect(bubbleScale)
                    .opacity(bubbleOpacity)
            } else {
                Text(displayedMessageText)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(messagePreview == nil ? AppTheme.colors.body.opacity(0.5) : AppTheme.colors.body.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
        }
    }

    private var messagePreview: String? {
        if let transientBubbleText {
            return transientBubbleText
        }
        guard let message = entry.messagePreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              message.isEmpty == false else {
            return nil
        }

        if let author = entry.latestMessageAuthorName {
            return "\(author)：\(message)"
        }
        return message
    }

    private var subtitleText: String {
        if let responseStateText = entry.responseStateText, responseStateText.isEmpty == false {
            return responseStateText
        }
        if let relationText = entry.relationText, relationText.isEmpty == false {
            return relationText
        }
        return "轻点展开详情"
    }

    private var fallbackMessageText: String {
        if let responseStateText = entry.responseStateText, responseStateText.isEmpty == false {
            return responseStateText
        }
        return "暂时还没有留言"
    }

    private var displayedMessageText: String {
        messagePreview ?? fallbackMessageText
    }

    private var shouldShowMessageBubble: Bool {
        if effectivePairCardStyle == .assigned || effectivePairCardStyle == .standard {
            return false
        }
        if transientBubbleText != nil {
            return true
        }
        return entry.messagePreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var bubbleFillColor: Color {
        switch effectivePairCardStyle {
        case .request:
            return AppTheme.colors.surfaceElevated
        case .sent:
            return AppTheme.colors.surfaceElevated
        case .shared:
            return AppTheme.colors.surfaceElevated
        case .assigned, .standard:
            return AppTheme.colors.surfaceElevated
        }
    }

    private var relationColor: Color {
        switch effectivePairCardStyle {
        case .request:
            return AppTheme.colors.coral
        case .shared:
            return AppTheme.colors.sky
        case .sent:
            return AppTheme.colors.body.opacity(0.74)
        case .assigned, .standard:
            return AppTheme.colors.title.opacity(0.76)
        }
    }

    private var timeColor: Color {
        switch entry.urgency {
        case .overdue:
            return AppTheme.colors.coral
        case .imminent:
            return AppTheme.colors.sky
        case .normal:
            return AppTheme.colors.body.opacity(0.58)
        }
    }

    private var cardBackground: some ShapeStyle {
        switch effectivePairCardStyle {
        case .request:
            return AppTheme.colors.background
        case .shared:
            return AppTheme.colors.sky.opacity(0.08)
        case .sent:
            return AppTheme.colors.surfaceElevated.opacity(0.9)
        case .assigned, .standard:
            return AppTheme.colors.background
        }
    }

    private var cardStroke: Color {
        switch effectivePairCardStyle {
        case .request:
            return AppTheme.colors.outlineStrong.opacity(0.1)
        case .shared:
            return AppTheme.colors.sky.opacity(0.16)
        case .sent:
            return AppTheme.colors.outlineStrong.opacity(0.12)
        case .assigned, .standard:
            return AppTheme.colors.outlineStrong.opacity(0.1)
        }
    }

    private var effectivePairCardStyle: HomePairCardStyle {
        isMorphingToAssigned ? .assigned : entry.pairCardStyle
    }

    private var sentAnimationSignature: String {
        guard entry.pairCardStyle == .sent else { return "" }
        return "\(entry.responseStateText ?? "")|\(entry.messagePreview ?? "")"
    }

    private func handleCardTap() {
        onOpenDetail()
    }

    private func handlePrimaryAction() {
        guard entry.pairCardStyle == .request else {
            onPrimaryAction()
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            isMorphingToAssigned = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(190))
            onPrimaryAction()
            try? await Task.sleep(for: .milliseconds(280))
            isMorphingToAssigned = false
        }
    }

    private func handleSecondaryAction() {
        guard entry.pairCardStyle == .request else {
            onSecondaryAction()
            return
        }

        Task { @MainActor in
            if reduceMotion == false {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    rowScale = 0.98
                    rowVerticalOffset = -8
                    rowOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(140))
            }
            onSecondaryAction()
        }
    }

    private func handleQuickMessage(_ message: String) {
        guard entry.pairCardStyle == .request || supportsSentQuickReplyMenu else { return }
        HomeInteractionFeedback.menuTap()
        transientBubbleText = message
        runMessageBubbleEntranceAnimation()

        Task { @MainActor in
            if entry.pairCardStyle == .request, reduceMotion == false {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    rowScale = 0.98
                    rowVerticalOffset = -8
                    rowOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            onQuickMessage(message)
        }
    }

    private func handleResendAction() {
        HomeInteractionFeedback.selection()
        Task { @MainActor in
            if reduceMotion == false {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    rowScale = 1.02
                }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    rowScale = 1
                }
            }
            onResend()
        }
    }

    private func handleKeepForLaterAction() {
        HomeInteractionFeedback.selection()
        guard entry.pairCardStyle == .sent else {
            return
        }

        if reduceMotion {
            showsKeepForLaterAction = false
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showsKeepForLaterAction = false
            rowScale = 0.992
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                rowScale = 1
            }
        }
    }

    private func handleDeleteAction() {
        HomeInteractionFeedback.selection()
        Task { @MainActor in
            if reduceMotion == false {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    rowScale = 0.98
                    rowOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(140))
            }
            onDelete()
        }
    }

    private func handleCompletionAction() {
        guard entry.isCompleted == false else {
            onPrimaryAction()
            return
        }

        isAwaitingCompletionCommit = true
        runCompletionAnimation()

        Task { @MainActor in
            if reduceMotion == false {
                try? await Task.sleep(for: .milliseconds(70))
            }
            onPrimaryAction()
        }
    }

    private func runMessageBubbleEntranceAnimation() {
        guard reduceMotion == false else {
            bubbleScale = 1
            bubbleOpacity = 1
            return
        }

        bubbleScale = 0.92
        bubbleOpacity = 0.28
        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
            bubbleScale = 1
            bubbleOpacity = 1
            rowScale = 1
            rowVerticalOffset = 0
        }
    }

    private func runSentCardMessageAnimation() {
        guard reduceMotion == false else {
            bubbleScale = 1
            bubbleOpacity = 1
            return
        }

        bubbleScale = 0.9
        bubbleOpacity = 0.18
        rowScale = 0.992
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            bubbleScale = 1
            bubbleOpacity = 1
            rowScale = 1
        }
    }

    private func runCompletionAnimation() {
        completionAnimationCount += 1
        completionOutlineOpacity = 1
        completionFillScale = 0.42
        completionFillOpacity = reduceMotion ? 0.12 : 0.2
        completionBadgeScale = reduceMotion ? 1 : 0.82
        rowScale = reduceMotion ? 1 : 0.988
        rowVerticalOffset = reduceMotion ? 0 : -1

        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.1)) {
            completionOutlineOpacity = reduceMotion ? 0.18 : 0
        }

        Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.18)) {
                    completionFillScale = 1
                    completionFillOpacity = 0
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(72))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) {
                completionBadgeScale = 1.16
                completionFillScale = 1.02
                rowScale = 0.982
            }
            withAnimation(.easeOut(duration: 0.18)) {
                completionFillOpacity = 0.26
            }

            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                completionBadgeScale = 1
                rowScale = 1
                rowVerticalOffset = 2
            }
            withAnimation(.easeOut(duration: 0.2)) {
                completionFillScale = 1.34
                completionFillOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(84))
            withAnimation(.easeOut(duration: 0.12)) {
                rowVerticalOffset = 0
            }
        }
    }

    private func resetCompletionBadgeState() {
        completionBadgeScale = 1
        completionFillScale = 0.5
        completionFillOpacity = 0
        completionOutlineOpacity = 1
        rowScale = 1
        rowVerticalOffset = 0
        rowOpacity = 1
        isAwaitingCompletionCommit = false
    }
}

private struct PairMessageBubbleBackground: View {
    let fill: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(fill)
    }
}

private struct PairTimelineAvatarStrip: View {
    let primaryAvatar: HomeAvatar?
    let secondaryAvatar: HomeAvatar?
    let style: HomePairCardStyle

    var body: some View {
        HStack(spacing: secondaryAvatar == nil ? 0 : -8) {
            if let primaryAvatar {
                avatar(primaryAvatar, fillColor: AppTheme.colors.surfaceElevated)
            }

            if let secondaryAvatar {
                avatar(secondaryAvatar, fillColor: AppTheme.colors.avatarWarm)
            }
        }
        .frame(width: stripWidth, height: 34, alignment: .leading)
    }

    private var stripWidth: CGFloat {
        switch style {
        case .shared:
            return 58
        default:
            return 34
        }
    }

    private func avatar(_ avatar: HomeAvatar, fillColor: Color) -> some View {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: 34,
            fillColor: fillColor,
            symbolColor: AppTheme.colors.title,
            symbolFont: AppTheme.typography.sized(13, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
        .frame(width: 34, height: 34)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.92), lineWidth: 2)
        }
    }
}

private struct PairCardPillButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(13, weight: .bold))
                .foregroundStyle(isPrimary ? Color.white : AppTheme.colors.title)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isPrimary ? AppTheme.colors.coral : AppTheme.colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }
}


private struct PairNativeContextMenuModifier: ViewModifier {
    let messages: [String]
    let onSelectMessage: (String) -> Void

    func body(content: Content) -> some View {
        if messages.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(messages, id: \.self) { message in
                    Button(message) {
                        onSelectMessage(message)
                    }
                }
            }
        }
    }
}

private struct PairCompletionBadge: View {
    let isCompleted: Bool
    let isAnimatingCompletion: Bool
    let accentColor: Color
    let scale: CGFloat
    let fillScale: CGFloat
    let fillOpacity: Double
    let outlineOpacity: Double
    let animationCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .scaleEffect(fillScale)
                    .opacity(isCompleted ? 0 : fillOpacity)

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        accentColor.opacity(0.58),
                        style: StrokeStyle(lineWidth: 1.6, dash: [3.6, 4.4])
                    )
                    .opacity(isCompleted ? 0 : outlineOpacity)

                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, options: .speed(1.15), value: animationCount)
                    .opacity((isCompleted || isAnimatingCompletion) ? 1 : 0)
            }
            .frame(width: 40, height: 40)
            .scaleEffect(scale)
            .shadow(
                color: accentColor.opacity(isCompleted ? 0 : 0.2),
                radius: isCompleted ? 0 : 12,
                y: isCompleted ? 0 : 5
            )
        }
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

private struct HomeTimelineTimeText: View {
    let entry: HomeTimelineEntry
    @State private var isBreathing = false

    var body: some View {
        Group {
            if entry.timeText.isEmpty == false {
                Text(entry.timeText)
                    .font(AppTheme.typography.sized(entry.urgency == .imminent ? 20 : 18, weight: .semibold))
                    .foregroundStyle(timeColor)
                    .scaleEffect(entry.urgency == .imminent ? (isBreathing ? 1.09 : 0.94) : 1)
                    .opacity(entry.urgency == .imminent ? (isBreathing ? 1 : 0.62) : 1)
                    .animation(
                        entry.urgency == .imminent
                        ? .easeInOut(duration: 0.72).repeatForever(autoreverses: true)
                        : .default,
                        value: isBreathing
                    )
                    .onAppear {
                        guard entry.urgency == .imminent else { return }
                        isBreathing = true
                    }
                    .onChange(of: entry.urgency) { _, newValue in
                        isBreathing = newValue == .imminent
                    }
            }
        }
    }

    private var timeColor: Color {
        switch entry.urgency {
        case .normal:
            return AppTheme.colors.timeText.opacity(entry.isMuted ? 0.42 : 0.82)
        case .imminent, .overdue:
            return AppTheme.colors.coral.opacity(entry.isMuted ? 0.5 : 1)
        }
    }
}

private struct HomeAvatarToggleButton: View {
    private let compactAvatarSize: CGFloat = 30
    private let regularAvatarSize: CGFloat = 40
    let avatars: [HomeAvatar]
    let foregroundColor: Color
    let secondaryForegroundColor: Color
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: overlapSpacing) {
                ForEach(Array(avatars.enumerated()), id: \.element.id) { index, avatar in
                    avatarBadge(avatar, zIndex: Double(avatars.count - index))
                }
            }
            .padding(.horizontal, edgeInset)
            .padding(.vertical, edgeInset)
            .frame(minHeight: controlHeight)
        }
        .buttonStyle(.plain)
        .modifier(HomeAvatarGlassModifier(isCircular: isCircular))
        .scaleEffect(compact ? 0.86 : 1, anchor: .trailing)
        .frame(width: isCircular ? controlHeight : nil, height: controlHeight)
    }

    private var controlHeight: CGFloat {
        avatarSize + (edgeInset * 2)
    }

    private var avatarSize: CGFloat {
        compact ? compactAvatarSize : regularAvatarSize
    }

    private var isCircular: Bool {
        avatars.count == 1
    }

    private var overlapSpacing: CGFloat {
        avatars.count > 1 ? -14 : 0
    }

    private var edgeInset: CGFloat {
        if compact {
            return avatars.count > 1 ? 4 : 3
        }

        return avatars.count > 1 ? 4 : 4
    }

    @ViewBuilder
    private func avatarBadge(_ avatar: HomeAvatar, zIndex: Double) -> some View {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: avatarSize,
            fillColor: AppTheme.colors.surfaceElevated,
            symbolColor: foregroundColor,
            symbolFont: AppTheme.typography.sized(16, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Circle()
                    .stroke(AppTheme.colors.outlineStrong.opacity(0.32), lineWidth: 1.2)
            }
            .shadow(color: AppTheme.colors.shadow.opacity(0.65), radius: 6, y: 4)
            .zIndex(zIndex)
    }
}

private struct HomeAvatarGlassModifier: ViewModifier {
    let isCircular: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: isCircular ? AnyShape(Circle()) : AnyShape(Capsule(style: .continuous))
                )
        } else {
            content
                .background(
                    AppTheme.colors.surfaceElevated,
                    in: isCircular ? AnyShape(Circle()) : AnyShape(Capsule(style: .continuous))
                )
                .overlay {
                    (isCircular ? AnyShape(Circle()) : AnyShape(Capsule(style: .continuous)))
                        .stroke(AppTheme.colors.outlineStrong.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct HomeOverdueSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: HomeViewModel
    @State private var displayedEntries: [HomeOverdueEntry] = []
    @State private var animatingCompletionIDs: Set<UUID> = []

    private var entries: [HomeOverdueEntry] {
        viewModel.overdueSummaryEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, 22)
                .padding(.bottom, 10)

            overdueList
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.bottom, 8)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
            LazyVStack(spacing: 12) {
                overdueRows
            }
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var overdueRows: some View {
        ForEach(displayedEntries) { entry in
            HomeTimelineRow(
                entry: HomeTimelineEntry(
                    id: entry.id,
                    title: entry.title,
                    notes: entry.detailText,
                    timeText: entry.timeText,
                    statusText: "已逾期",
                    assigneeText: nil,
                    messagePreview: nil,
                    responseStateText: nil,
                    needsResponse: false,
                    accentColorName: "coral",
                    isMuted: false,
                    isCompleted: false,
                    urgency: .overdue,
                    pairCardStyle: .standard,
                    relationText: nil,
                    primaryAvatar: nil,
                    secondaryAvatar: nil,
                    latestMessageAuthorName: nil,
                    reminderRequestedAt: nil
                ),
                isAnimatingCompletion: animatingCompletionIDs.contains(entry.id),
                isAnimatingReopening: false,
                titleLineLimit: 1,
                titleMinimumScaleFactor: 0.68,
                onToggleCompletion: {
                    HomeInteractionFeedback.completion()
                    Task {
                        await handleCompletion(for: entry.id)
                    }
                },
                onOpenDetail: {
                    viewModel.presentItemDetail(entry.id)
                }
            )
            .padding(.vertical, 12)
        }
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
        return .bouncy(duration: visibility.isVisible ? 0.78 : 0.46, extraBounce: visibility.isVisible ? 0.22 : 0.12)
            .delay(Double(delayIndex) * 0.028)
    }

    func body(content: Content) -> some View {
        content
            .offset(y: visibility.isVisible ? 0 : 26)
            .scaleEffect(
                x: visibility.isVisible ? 1 : 1.022,
                y: visibility.isVisible ? 1 : 0.936,
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
