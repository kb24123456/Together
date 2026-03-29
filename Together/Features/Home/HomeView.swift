import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: HomeViewModel
    @Bindable var projectsViewModel: ProjectsViewModel
    let isProjectModePresented: Bool
    let onCreateTaskTapped: () -> Void
    @State private var weekPagerOffset: CGFloat = 0
    @State private var isWeekPagerSettling = false
    @State private var isTodayJumpButtonVisible = false
    @State private var todayJumpRevealTask: Task<Void, Never>?
    @State private var isCompletedVisibilityButtonCompressed = false
    @State private var isCompletedSectionVisible = true
    @State private var isCompletedSectionTransitioning = false

    private let weekPageBreathingGap: CGFloat = 0
    private let weekDateSpacing: CGFloat = AppTheme.spacing.sm
    private let weekMiddleIndex = 3
    private let contentCardCornerRadius: CGFloat = 40
    private let timelineRowHorizontalInset: CGFloat = AppTheme.spacing.xl
    private let timelineRowVerticalInset: CGFloat = 14
    private let timelineDividerLeadingInset: CGFloat = AppTheme.spacing.xl + 44
    private let timelineBottomInset: CGFloat = 188
    private let homeCanvasColor = AppTheme.colors.homeBackground

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundView

                contentCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, contentTopInset(safeAreaTop: proxy.safeAreaInsets.top))
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
            if projectsViewModel.loadState == .idle {
                await projectsViewModel.load()
            }
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

    private func topChrome(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, horizontalContentPadding)
                    .padding(.top, headerTopPadding(safeAreaTop: safeAreaTop))
                    .offset(y: headerVerticalOffset)

                weekCalendarContainer
                    .padding(.horizontal, horizontalContentPadding)
            }
            .padding(.bottom, isProjectModePresented ? 10 : 14)
            .background(topChromeBackground)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        AppTheme.colors.homeBackground.opacity(0.22),
                        AppTheme.colors.homeBackground.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 26)
                .allowsHitTesting(false)
            }

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var topChromeBackground: some View {
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .background(.bar)
        } else {
            NativeHomeChromeBlur()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: isProjectModePresented ? 6 : 0) {
            headerTopRow(compact: isProjectModePresented)

            if isProjectModePresented {
                projectModeHeaderMeta
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.selectedDateKey)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.isViewingToday)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: viewModel.showsPairAvatarPreview)
    }

    private func headerTopRow(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            headerTitle(compact: compact)

            Spacer(minLength: 0)

            HStack(spacing: AppTheme.spacing.sm) {
                if compact == false, isTodayJumpButtonVisible {
                    todayJumpButton
                        .transition(todayJumpTransition)
                        .layoutPriority(2)
                }

                headerAvatarButton(compact: compact)
            }
        }
        .frame(minHeight: compact ? 40 : 52, alignment: .center)
    }

    private var projectModeHeaderMeta: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Text(projectModeDateLine)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(projectModeProjectsSummary)
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(headerSecondaryColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isProjectModePresented ? 1 : 0)
        .offset(y: isProjectModePresented ? 0 : projectModeContentTransitionOffset)
        .allowsHitTesting(false)
        .animation(projectModeAnimation, value: isProjectModePresented)
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
        .compositingGroup()
    }

    private var contentCard: some View {
        ZStack(alignment: .top) {
            tasksContent
                .opacity(isProjectModePresented ? 0 : 1)
                .allowsHitTesting(!isProjectModePresented)
                .animation(modeFadeAnimation, value: isProjectModePresented)

            if isProjectModePresented {
                projectsModeContent
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .allowsHitTesting(true)
            }
        }
        .animation(projectModeAnimation, value: isProjectModePresented)
    }

    private var tasksContent: some View {
        ZStack {
            if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        timelineSection
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, 0)
                    .padding(.bottom, 144)
                }
                .id("empty-\(viewModel.selectedDateKey)")
                .scrollIndicators(.hidden)
                .scrollDisabled(isProjectModePresented)
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
            contentBottomPadding: 168
        )
    }

    private var weekCalendarContainer: some View {
        weekCalendarSection
            .frame(height: isProjectModePresented ? 0 : 76, alignment: .top)
            .offset(y: weekSectionVerticalOffset)
            .opacity(isProjectModePresented ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isProjectModePresented)
            .animation(projectModeAnimation, value: isProjectModePresented)
    }

    private var timelineList: some View {
        List {
            Color.clear
                .frame(height: 0)
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
        .scrollDisabled(isProjectModePresented)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.top, 0)
        .background(homeCanvasColor)
        .applyScrollEdgeProtection()
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
        .modifier(HomeAvatarGlassModifier())
        .buttonStyle(.plain)
        .accessibilityLabel("返回今天")
    }

    private var todayJumpTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .scale(scale: 0.96, anchor: .trailing))
                .combined(with: .opacity),
            removal: .move(edge: .trailing)
                .combined(with: .scale(scale: 0.98, anchor: .trailing))
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
        guard !viewModel.isViewingToday, !isProjectModePresented else {
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
            .applyTransition(rowTransition)
            .applyCompletedSectionVisibility(
                sectionVisibility.map { $0.rowVisibility(for: index) }
            )

            if index < entries.count - 1 {
                DashedDivider()
                    .stroke(AppTheme.colors.separator, style: StrokeStyle(lineWidth: 1.5, dash: [3, 8]))
                    .frame(height: 1)
                    .padding(.leading, 2)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: timelineDividerLeadingInset,
                            bottom: 0,
                            trailing: timelineRowHorizontalInset
                        )
                    )
                    .listRowBackground(sectionVisibility == nil ? homeCanvasColor : Color.clear)
                    .listRowSeparator(.hidden)
                    .applyCompletedSectionVisibility(
                        sectionVisibility.map { $0.rowVisibility(for: index) }
                    )
            }
        }
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
        .animation(projectModeAnimation, value: isProjectModePresented)
    }

    private func weekPage(for offset: Int) -> some View {
        let dates = viewModel.weekDates(shiftedByWeeks: offset)

        return HStack(spacing: weekDateSpacing) {
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
                    VStack(spacing: 4) {
                        Text(date, format: .dateTime.day())
                            .font(
                                AppTheme.typography.sized(
                                    isProjectModePresented ? 18 : 22,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.title
                                : AppTheme.colors.textTertiary
                            )

                        Text(viewModel.weekdayLabel(for: date))
                            .font(AppTheme.typography.sized(isProjectModePresented ? 11 : 12, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.coral
                                : AppTheme.colors.body.opacity(0.7)
                            )
                    }
                    .scaleEffect(isSelected ? 1.16 : 1.0)
                    .scaleEffect(isProjectModePresented ? 0.92 : 1, anchor: .center)
                    .frame(maxWidth: .infinity)
                    .frame(height: isProjectModePresented ? 66 : 84)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timelineSection: some View {
        ZStack {
            if viewModel.hasAnyTimelineEntriesForSelectedDate == false {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    Text("今天暂时没有非做不可的事")
                        .font(AppTheme.typography.textStyle(.body, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        HomeInteractionFeedback.selection()
                        onCreateTaskTapped()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(AppTheme.typography.sized(16, weight: .semibold))

                            Text("新建任务")
                                .font(AppTheme.typography.sized(16, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.colors.title)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.surfaceElevated)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)

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
                            HStack(spacing: 6) {
                                Text("查看已完成")
                                Text("\(viewModel.completedEntryCount)")
                                Text("项")
                            }
                            .font(AppTheme.typography.sized(14, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.spacing.xxl)
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
            HStack(spacing: 4) {
                Text(viewModel.completedVisibilityButtonTitle)

                Text("\(viewModel.completedEntryCount)")
            }
            .font(AppTheme.typography.sized(13, weight: .semibold))
            .foregroundStyle(AppTheme.colors.body.opacity(0.76))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
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
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                viewModel.toggleOverdueFocus()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.showsOverdueOnly ? "line.3.horizontal.decrease.circle.fill" : "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(16, weight: .semibold))

                Text(viewModel.overdueCapsuleTitle)
                    .font(AppTheme.typography.sized(14, weight: .semibold))

                Spacer(minLength: 0)

                if viewModel.showsOverdueOnly == false {
                    Text("尽快处理")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.coral.opacity(0.8))
                }
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
        isProjectModePresented ? -10 : 0
    }

    private var weekSectionVerticalOffset: CGFloat {
        isProjectModePresented ? -14 : 0
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

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }

    private func headerTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + (isProjectModePresented ? 16 : AppTheme.spacing.sm)
    }

    private var horizontalContentPadding: CGFloat {
        AppTheme.spacing.xl
    }

    private func contentTopInset(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + (isProjectModePresented ? 78 : 154)
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
        .opacity
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

private struct NativeHomeChromeBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
    }
}

private extension View {
    @ViewBuilder
    func applyScrollEdgeProtection() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
        } else {
            self
        }
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
    let context = AppContext.bootstrap()
    if let selectedDateOffset {
        context.homeViewModel.selectDate(
            Calendar.current.date(byAdding: .day, value: selectedDateOffset, to: MockDataFactory.now) ?? MockDataFactory.now
        )
    }

    return HomeView(
        viewModel: context.homeViewModel,
        projectsViewModel: context.projectsViewModel,
        isProjectModePresented: false,
        onCreateTaskTapped: {}
    )
}

private struct HomeTimelineRow: View {
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    @State private var checkmarkProgress: CGFloat = 1
    @State private var badgeScale: CGFloat = 1
    @State private var badgeOutlineOpacity = 1.0

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
        .onChange(of: isAnimatingCompletion) { _, newValue in
            guard newValue else { return }

            checkmarkProgress = 0
            badgeScale = 0.84
            badgeOutlineOpacity = 1

            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                badgeScale = 0.84
            }

            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.1)) {
                    badgeOutlineOpacity = 0
                }

                try? await Task.sleep(for: .milliseconds(55))
                withAnimation(.easeOut(duration: 0.24)) {
                    checkmarkProgress = 1
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.56)) {
                    badgeScale = 1.08
                }

                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.66)) {
                    badgeScale = 1
                }
            }
        }
    }

    private var displaySubtitle: String {
        guard let notes = entry.notes, notes.isEmpty == false else {
            return entry.statusText
        }
        return notes
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
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: isAnimatingCompletion ? 1.8 : 1.6, dash: [3.6, 4.4])
                )
                .opacity(outlineOpacity)

            AnimatedCheckmarkShape()
                .trim(from: 0, to: checkmarkTrim)
                .stroke(
                    AppTheme.colors.coral,
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(-4))
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
        if entry.isCompleted { return 0 }
        if isAnimatingCompletion { return badgeOutlineOpacity }
        return 1
    }

    private var checkmarkTrim: CGFloat {
        if isAnimatingCompletion { return checkmarkProgress }
        return entry.isCompleted ? 1 : 0
    }

    private var checkmarkOpacity: Double {
        (entry.isCompleted || isAnimatingCompletion) ? 1 : 0
    }
}

private struct AnimatedCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.22))
        return path
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
    private let controlHeight: CGFloat = 42
    let avatars: [HomeAvatar]
    let foregroundColor: Color
    let secondaryForegroundColor: Color
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: -12) {
                ForEach(Array(avatars.enumerated()), id: \.element.id) { index, avatar in
                    avatarBadge(avatar, zIndex: Double(avatars.count - index))
                }
            }
            .padding(.horizontal, avatars.count > 1 ? 14 : 10)
            .padding(.vertical, 5)
            .frame(minHeight: controlHeight)
        }
        .buttonStyle(.plain)
        .modifier(HomeAvatarGlassModifier())
        .scaleEffect(compact ? 0.86 : 1, anchor: .trailing)
        .frame(minHeight: controlHeight)
    }

    @ViewBuilder
    private func avatarBadge(_ avatar: HomeAvatar, zIndex: Double) -> some View {
        Image(systemName: avatar.systemImageName)
            .font(AppTheme.typography.sized(16, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .overlay {
                Circle()
                    .stroke(AppTheme.colors.outlineStrong.opacity(0.32), lineWidth: 1.2)
            }
            .shadow(color: AppTheme.colors.shadow.opacity(0.65), radius: 6, y: 4)
            .zIndex(zIndex)
    }
}

private struct HomeAvatarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(AppTheme.colors.surfaceElevated, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(AppTheme.colors.outlineStrong.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct DashedDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
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
