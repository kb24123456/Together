import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let isProjectLayerPresented: Bool
    @State private var weekPagerOffset: CGFloat = 0
    @State private var isWeekPagerSettling = false
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
    private let timelineBottomInset: CGFloat = 144

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundView

                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AppTheme.spacing.xl)
                        .padding(.top, proxy.safeAreaInsets.top + AppTheme.spacing.sm)

                    weekCalendarSection
                        .padding(.horizontal, AppTheme.spacing.xl)
                        .padding(.top, 0)
                        .padding(.bottom, 0)

                    contentCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(y: projectCardOffset)
                }

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
        }
        .task(id: viewModel.selectedDateKey) {
            await viewModel.reload()
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
            item: Binding(
                get: { viewModel.activeSnoozeMenu },
                set: {
                    if let value = $0 {
                        viewModel.activeSnoozeMenu = value
                    } else {
                        viewModel.dismissSnoozeUI()
                    }
                }
            )
        ) { menu in
            HomeSnoozeMenuSheet(
                menu: menu,
                viewModel: viewModel
            )
            .presentationDetents(menu.detents)
            .presentationBackground {
                TaskEditorSettingsPresentationBackground()
            }
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.disabled)
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
            .modifier(TaskEditorMenuPresentationSizingModifier())
        }
        .onAppear {
            isCompletedSectionVisible = viewModel.showsCompletedItems
        }
    }

    private var backgroundView: some View {
        Group {
            if isProjectLayerPresented {
                Color.clear
            } else {
                AppTheme.colors.surface
            }
        }
        .ignoresSafeArea()
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(viewModel.headerDateText)
                    .font(AppTheme.typography.sized(40, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(headerPrimaryColor)
                    .contentTransition(.numericText())

                if !viewModel.isViewingToday {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.returnToToday()
                        }
                        HomeInteractionFeedback.selection()
                    } label: {
                        Text("今天")
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(headerPrimaryColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppTheme.colors.surfaceElevated)
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.84, anchor: .leading)
                                .combined(with: .opacity)
                                .combined(with: .offset(x: -10, y: 1)),
                            removal: .scale(scale: 0.9, anchor: .leading)
                                .combined(with: .opacity)
                                .combined(with: .offset(x: -6, y: -1))
                        )
                    )
                }
            }

            Spacer(minLength: 0)

            HomeAvatarToggleButton(
                avatars: viewModel.headerAvatars,
                foregroundColor: headerPrimaryColor,
                secondaryForegroundColor: headerSecondaryColor,
                action: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        viewModel.toggleAvatarPreview()
                    }
                    triggerSoftDateFeedback()
                }
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.selectedDateKey)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: viewModel.isViewingToday)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: viewModel.showsPairAvatarPreview)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isProjectLayerPresented)
    }

    private var contentCard: some View {
        Group {
            if viewModel.timelineEntries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        timelineSection
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, AppTheme.spacing.lg)
                    .padding(.bottom, 144)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(isProjectLayerPresented)
            } else {
                timelineList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : contentCardCornerRadius, style: .continuous)
                .fill(AppTheme.colors.surface)
        )
        .overlay(alignment: .top) {
            if isProjectLayerPresented {
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.outlineStrong.opacity(0.32))
                    .frame(width: 76, height: 7)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .shadow(
            color: isProjectLayerPresented ? AppTheme.colors.shadow.opacity(2.2) : .clear,
            radius: isProjectLayerPresented ? 34 : 0,
            y: isProjectLayerPresented ? -6 : 0
        )
        .clipShape(
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : contentCardCornerRadius, style: .continuous)
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isProjectLayerPresented)
    }

    private var timelineList: some View {
        List {
            Color.clear
                .frame(height: 6)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(AppTheme.colors.surface)
                .listRowSeparator(.hidden)

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
                    .listRowBackground(AppTheme.colors.surface)
                    .listRowSeparator(.hidden)

                if viewModel.showsCompletedItems {
                    completedTimelineSection
                }
            } else {
                Color.clear
                    .frame(height: timelineBottomInset)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(AppTheme.colors.surface)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDisabled(isProjectLayerPresented)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.top, AppTheme.spacing.sm)
        .background(AppTheme.colors.surface)
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
                .listRowBackground(AppTheme.colors.surface)
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
            HomeTimelineRow(
                entry: entry,
                isAnimatingCompletion: viewModel.recentCompletedItemID == entry.id && viewModel.isPerformingCompletion,
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
                .listRowInsets(
                    EdgeInsets(
                        top: timelineRowVerticalInset,
                        leading: timelineRowHorizontalInset,
                        bottom: timelineRowVerticalInset,
                        trailing: timelineRowHorizontalInset
                    )
                )
                .listRowBackground(isCompletedRow ? Color.clear : AppTheme.colors.surface)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        if entry.isCompleted {
                            HomeInteractionFeedback.selection()
                        } else {
                            HomeInteractionFeedback.completion()
                        }
                        Task {
                            await viewModel.completeItem(entry.id, trigger: .swipeAction)
                        }
                    } label: {
                        HomeSwipeActionBubble(
                            systemImage: entry.isCompleted ? "arrow.uturn.backward" : "checkmark",
                            tint: entry.isCompleted ? AppTheme.colors.body.opacity(0.76) : AppTheme.colors.coral,
                            edge: .leading
                        )
                    }
                    .tint(entry.isCompleted ? AppTheme.colors.body.opacity(0.76) : AppTheme.colors.coral)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        guard viewModel.prepareSnoozeContext(for: entry.id) else { return }
                        HomeInteractionFeedback.selection()
                        viewModel.presentCustomSnoozePicker()
                    } label: {
                        HomeSwipeActionBubble(
                            systemImage: "arrowshape.turn.up.backward.badge.clock.fill.rtl",
                            tint: AppTheme.colors.sky,
                            edge: .trailing
                        )
                    }
                    .tint(AppTheme.colors.sky)
                }
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
                    .listRowBackground(sectionVisibility == nil ? AppTheme.colors.surface : Color.clear)
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
                                    22,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.title
                                : AppTheme.colors.textTertiary
                            )

                        Text(viewModel.weekdayLabel(for: date))
                            .font(AppTheme.typography.sized(12, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.coral
                                : AppTheme.colors.body.opacity(0.7)
                            )
                    }
                    .scaleEffect(isSelected ? 1.16 : 1.0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timelineSection: some View {
        ZStack {
            if viewModel.timelineEntries.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                    Text("这一天没有必须处理的事件")
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    Text("保持留白，必要时从底部中间按钮快速添加。")
                        .foregroundStyle(AppTheme.colors.body.opacity(0.72))

                    if viewModel.hasCompletedEntries {
                        completedVisibilityButton
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.spacing.xl)
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

    private var headerPrimaryColor: Color {
        isProjectLayerPresented ? AppTheme.colors.projectLayerText : AppTheme.colors.title
    }

    private var headerSecondaryColor: Color {
        isProjectLayerPresented ? AppTheme.colors.projectLayerSecondaryText : AppTheme.colors.body.opacity(0.55)
    }

    private var projectCardOffset: CGFloat {
        isProjectLayerPresented ? 262 : 0
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

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }
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

private struct HomeSwipeActionBubble: View {
    let systemImage: String
    let tint: Color
    let edge: HorizontalEdge

    private let actionDiameter: CGFloat = 44
    private let contentBiasOffset: CGFloat = 30

    var body: some View {
        ZStack(alignment: alignment) {
            Circle()
                .fill(tint)
                .frame(width: actionDiameter, height: actionDiameter)
                .overlay {
                    Image(systemName: systemImage)
                        .font(AppTheme.typography.sized(18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: edge == .leading ? contentBiasOffset : -contentBiasOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var alignment: Alignment {
        edge == .leading ? .trailing : .leading
    }
}

#if canImport(UIKit)
private struct HomeSnoozeMenuButton: UIViewRepresentable {
    let quickSnoozeMinuteOptions: [Int]
    let relativePresetTitle: (Int) -> String
    let onQuickSnooze: (Int) -> Void
    let onTomorrow: () -> Void
    let onCustom: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = HomeSnoozeMenuHostButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.clipsToBounds = false
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTouchDown),
            for: .touchDown
        )
        context.coordinator.applyConfiguration(to: button, parent: self)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyConfiguration(to: button, parent: self)
    }

    final class Coordinator: NSObject {
        var parent: HomeSnoozeMenuButton

        init(_ parent: HomeSnoozeMenuButton) {
            self.parent = parent
        }

        @objc
        func handleTouchDown() {
            HomeInteractionFeedback.menuTap()
        }

        func applyConfiguration(to button: UIButton, parent: HomeSnoozeMenuButton) {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = UIColor(AppTheme.colors.sky)
            configuration.background.backgroundColor = UIColor(AppTheme.colors.surfaceElevated)
            configuration.background.strokeColor = UIColor(AppTheme.colors.outlineStrong.opacity(0.18))
            configuration.background.strokeWidth = 1
            configuration.background.cornerRadius = 27
            configuration.cornerStyle = .fixed
            configuration.contentInsets = .zero
            configuration.image = UIImage(systemName: "arrowshape.turn.up.backward.badge.clock.fill.rtl")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            configuration.imagePlacement = .all
            button.configuration = configuration
            button.frame.size = CGSize(width: 54, height: 54)
            button.configurationUpdateHandler = { target in
                guard var updatedConfiguration = target.configuration else { return }
                updatedConfiguration.baseForegroundColor = UIColor(AppTheme.colors.sky)
                updatedConfiguration.background.backgroundColor = UIColor(AppTheme.colors.surfaceElevated)
                updatedConfiguration.background.strokeColor = UIColor(AppTheme.colors.outlineStrong.opacity(0.18))
                updatedConfiguration.background.strokeWidth = 1
                updatedConfiguration.image = UIImage(systemName: "arrowshape.turn.up.backward.badge.clock.fill.rtl")
                updatedConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
                target.configuration = updatedConfiguration
                target.alpha = 1
                target.transform = .identity
            }
            button.menu = makeMenu(parent: parent)
            button.tintColor = UIColor(AppTheme.colors.sky)
            button.invalidateIntrinsicContentSize()
        }

        private func makeMenu(parent: HomeSnoozeMenuButton) -> UIMenu {
            var actions: [UIMenuElement] = parent.quickSnoozeMinuteOptions.map { minutes in
                UIAction(title: parent.relativePresetTitle(minutes)) { _ in
                    parent.onQuickSnooze(minutes)
                }
            }

            actions.append(
                UIAction(title: "明天") { _ in
                    parent.onTomorrow()
                }
            )

            actions.append(
                UIAction(title: "自定义") { _ in
                    parent.onCustom()
                }
            )

            return UIMenu(children: actions)
        }
    }
}

private final class HomeSnoozeMenuHostButton: UIButton {
    override var isHighlighted: Bool {
        get { false }
        set {
            super.isHighlighted = false
            alpha = 1
            transform = .identity
        }
    }

    override var isSelected: Bool {
        get { false }
        set {
            super.isSelected = false
        }
    }
}
#else
private struct HomeSnoozeMenuButton: View {
    let quickSnoozeMinuteOptions: [Int]
    let relativePresetTitle: (Int) -> String
    let onQuickSnooze: (Int) -> Void
    let onTomorrow: () -> Void
    let onCustom: () -> Void

    var body: some View {
        Menu {
            ForEach(quickSnoozeMinuteOptions, id: \.self) { minutes in
                Button(relativePresetTitle(minutes)) {
                    onQuickSnooze(minutes)
                }
            }

            Button("明天") {
                onTomorrow()
            }

            Button("自定义") {
                onCustom()
            }
        } label: {
            Image(systemName: "arrowshape.turn.up.backward.badge.clock.fill.rtl")
                .font(AppTheme.typography.sized(20, weight: .bold))
                .foregroundStyle(AppTheme.colors.sky)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(AppTheme.colors.surfaceElevated)
                )
                .overlay {
                    Circle()
                        .stroke(AppTheme.colors.outlineStrong.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
#endif

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
    let avatars: [HomeAvatar]
    let foregroundColor: Color
    let secondaryForegroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: -12) {
                ForEach(Array(avatars.enumerated()), id: \.element.id) { index, avatar in
                    avatarBadge(avatar, zIndex: Double(avatars.count - index))
                }
            }
            .padding(.horizontal, avatars.count > 1 ? 16 : 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .modifier(HomeAvatarGlassModifier())
    }

    @ViewBuilder
    private func avatarBadge(_ avatar: HomeAvatar, zIndex: Double) -> some View {
        Image(systemName: avatar.systemImageName)
            .font(AppTheme.typography.sized(18, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 34, height: 34)
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

private struct HomeSnoozeMenuSheet: View {
    let menu: HomeSnoozeMenu
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        Group {
            switch menu {
            case .settings:
                HomeSnoozeSettingsSheet(viewModel: viewModel)
            }
        }
        .id(menu.id)
    }
}

private struct HomeSnoozeSettingsSheet: View {
    @Bindable var viewModel: HomeViewModel
    @State private var showsCalendarReturnToToday = false

    private let menus: [TaskEditorMenu] = [.time, .date, .reminder, .repeatRule]

    var body: some View {
        TaskEditorSettingsSheet(
            title: viewModel.stagedSnoozeTitle,
            menus: menus,
            activeMenu: snoozeMenuBinding,
            disabledMenus: viewModel.stagedSnoozeDisabledMenus,
            selectionFeedback: HomeInteractionFeedback.selection,
            onCancel: {
                HomeInteractionFeedback.selection()
                viewModel.cancelSnoozeSettings()
            },
            onConfirm: {
                Task {
                    await viewModel.confirmSnoozeSettings()
                    HomeInteractionFeedback.selection()
                }
            },
            onMenuTap: handleMenuTap,
            titleTrailingAccessory: titleTrailingAccessory,
            menuPresentation: menuPresentation(for:)
        ) { menu in
            menuContent(for: menu)
        }
        .onChange(of: viewModel.stagedCustomSnoozeDate) { _, newValue in
            if Calendar.current.isDateInToday(newValue) {
                showsCalendarReturnToToday = false
            }
        }
    }

    @ViewBuilder
    private func menuContent(for menu: TaskEditorMenu) -> some View {
        switch menu {
        case .time:
            TaskEditorSettingsTimePage(
                selectedTime: $viewModel.stagedCustomSnoozeTime,
                isAllDay: allDayBinding,
                anchorDate: viewModel.stagedCustomSnoozeDate,
                selectedDate: $viewModel.stagedCustomSnoozeDate,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .date:
            TaskEditorSettingsMonthPage(
                selectedDate: $viewModel.stagedCustomSnoozeDate,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .reminder:
            TaskEditorFadedOptionList(
                options: reminderOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .repeatRule:
            TaskEditorFadedOptionList(
                options: repeatOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .priority, .subtasks, .template:
            EmptyView()
        }
    }

    private var snoozeMenuBinding: Binding<TaskEditorMenu> {
        Binding(
            get: { viewModel.stagedSnoozeActiveMenu },
            set: { viewModel.setSnoozeActiveMenu($0) }
        )
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { viewModel.stagedCustomSnoozeAllDay },
            set: { viewModel.setSnoozeAllDay($0) }
        )
    }

    private var titleTrailingAccessory: AnyView? {
        guard viewModel.stagedSnoozeActiveMenu == .time else { return nil }
        return AnyView(
            Button {
                HomeInteractionFeedback.selection()
                viewModel.setSnoozeAllDay(!viewModel.stagedCustomSnoozeAllDay)
            } label: {
                Text("全天")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(
                        viewModel.stagedCustomSnoozeAllDay
                        ? AppTheme.colors.title
                        : AppTheme.colors.body.opacity(0.76)
                    )
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                viewModel.stagedCustomSnoozeAllDay
                                ? AppTheme.colors.pillSurface
                                : Color.white.opacity(0.16)
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                viewModel.stagedCustomSnoozeAllDay
                                ? AppTheme.colors.pillOutline
                                : Color.white.opacity(0.28),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(.plain)
        )
    }

    private func menuPresentation(for menu: TaskEditorMenu) -> TaskEditorMenuSwitcherPresentation {
        if menu == .date, showsCalendarReturnToToday {
            return .title("今天", accessibilityTitle: "返回今天")
        }
        return .icon(systemImage: menu.systemImage, accessibilityTitle: menu.accessibilityTitle)
    }

    private func handleMenuTap(_ menu: TaskEditorMenu) -> Bool {
        guard
            menu == .date,
            viewModel.stagedSnoozeActiveMenu == .date,
            showsCalendarReturnToToday
        else {
            return false
        }

        HomeInteractionFeedback.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            viewModel.stagedCustomSnoozeDate = Calendar.current.startOfDay(for: .now)
            showsCalendarReturnToToday = false
        }
        return true
    }

    private func handleCalendarDaySelection(_ date: Date) {
        let isToday = Calendar.current.isDateInToday(date)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showsCalendarReturnToToday = !isToday
        }
    }

    private var reminderOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不提醒", isSelected: viewModel.stagedCustomSnoozeReminderOffset == nil) {
            viewModel.stagedCustomSnoozeReminderOffset = nil
        }] + TaskEditorReminderPreset.allCases.map { preset in
            TaskEditorOptionRow(
                title: preset.title,
                isSelected: viewModel.stagedCustomSnoozeReminderOffset == preset.secondsBeforeTarget
            ) {
                viewModel.stagedCustomSnoozeReminderOffset = preset.secondsBeforeTarget
            }
        }
    }

    private var repeatOptions: [TaskEditorOptionRow] {
        TaskEditorRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: viewModel.stagedCustomSnoozeDate)
            return TaskEditorOptionRow(
                title: title,
                isSelected: viewModel.stagedCustomSnoozeRepeatRule?.title(anchorDate: viewModel.stagedCustomSnoozeDate) == title
            ) {
                viewModel.stagedCustomSnoozeRepeatRule = preset.makeRule(anchorDate: viewModel.stagedCustomSnoozeDate)
            }
        }
    }
}

private struct HomeCustomSnoozeEditorSheet: View {
    @Bindable var viewModel: HomeViewModel

    private let presetMinutes = [5, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            presetRow
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            HomeSnoozeWeekStrip(
                selectedDate: $viewModel.stagedCustomSnoozeDate,
                selectionFeedback: HomeInteractionFeedback.selection
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            HStack(spacing: 14) {
                Text("时间")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.74))

                Spacer(minLength: 0)

                TaskEditorSingleColumnTimeWheel(
                    selection: selectedTimeBinding,
                    minuteInterval: 5
                )
                .frame(width: 216, height: 126)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Spacer()

            Button {
                Task {
                    await viewModel.applyCustomSnoozeSelection()
                    HomeInteractionFeedback.selection()
                }
            } label: {
                Text("确认")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(TaskEditorMenuOptionButtonStyle())
            .modifier(TaskEditorMenuOptionGlassModifier())
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var presetRow: some View {
        HStack(spacing: 10) {
            ForEach(presetMinutes, id: \.self) { minutes in
                Button(relativePresetTitle(minutes)) {
                    Task {
                        await viewModel.applySnooze(minutes: minutes)
                        HomeInteractionFeedback.selection()
                    }
                }
                .buttonStyle(HomeSnoozePresetButtonStyle())
            }

            Button("明天") {
                Task {
                    await viewModel.applySnoozeTomorrow()
                    HomeInteractionFeedback.selection()
                }
            }
            .buttonStyle(HomeSnoozePresetButtonStyle())
        }
    }

    private var selectedTimeBinding: Binding<Date> {
        Binding(
            get: {
                viewModel.stagedCustomSnoozeTime
                    ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: viewModel.stagedCustomSnoozeDate)
                    ?? viewModel.stagedCustomSnoozeDate
            },
            set: { viewModel.stagedCustomSnoozeTime = $0 }
        )
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }
}

private struct HomeSnoozeWeekStrip: View {
    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(visibleDates, id: \.self) { date in
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

                        Button {
                            selectionFeedback()
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                selectedDate = calendar.startOfDay(for: date)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(weekdayLabel(for: date))
                                    .font(AppTheme.typography.sized(12, weight: .semibold))
                                    .foregroundStyle(isSelected ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.6))

                                Text("\(calendar.component(.day, from: date))")
                                    .font(AppTheme.typography.sized(18, weight: isSelected ? .bold : .semibold))
                                    .foregroundStyle(isSelected ? AppTheme.colors.title : AppTheme.colors.title.opacity(0.82))
                            }
                            .frame(width: 58, height: 62)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(AppTheme.colors.pillSurface)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isSelected ? AppTheme.colors.pillOutline : AppTheme.colors.outline.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(date.timeIntervalSince1970)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                proxy.scrollTo(selectedDate.timeIntervalSince1970, anchor: .center)
            }
            .onChange(of: selectedDate) { _, newValue in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    proxy.scrollTo(newValue.timeIntervalSince1970, anchor: .center)
                }
            }
        }
        .frame(height: 74)
    }

    private var visibleDates: [Date] {
        (-7...13).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: selectedDate))
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return ""
        }
    }
}

private struct HomeSnoozePresetButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: nil, action: configuration.trigger) {
            configuration.label
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(TaskEditorMenuOptionButtonStyle())
        .modifier(TaskEditorMenuOptionGlassModifier())
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
