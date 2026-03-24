import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let isProjectLayerPresented: Bool
    @State private var weekPagerOffset: CGFloat = 0
    @State private var isWeekPagerSettling = false

    private let weekPageBreathingGap: CGFloat = 0
    private let weekDateSpacing: CGFloat = AppTheme.spacing.sm
    private let contentCardCornerRadius: CGFloat = 40

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
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.disabled)
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
            .modifier(TaskEditorMenuPresentationSizingModifier())
        }
    }

    private var backgroundView: some View {
        Group {
            if isProjectLayerPresented {
                Color.clear
            } else {
                LinearGradient(
                    colors: [
                        AppTheme.colors.homeBackground,
                        AppTheme.colors.homeBackgroundSoft
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
                                    .fill(AppTheme.colors.surface.opacity(0.88))
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
        .background(
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : contentCardCornerRadius, style: .continuous)
                .fill(AppTheme.colors.surface)
        )
        .overlay(alignment: .top) {
            if isProjectLayerPresented {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.82))
                    .frame(width: 76, height: 7)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .shadow(
            color: isProjectLayerPresented ? AppTheme.colors.shadow.opacity(2.2) : AppTheme.colors.shadow.opacity(0.7),
            radius: isProjectLayerPresented ? 34 : 18,
            y: isProjectLayerPresented ? -6 : 10
        )
        .clipShape(
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : contentCardCornerRadius, style: .continuous)
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isProjectLayerPresented)
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
            .simultaneousGesture(weekPagerDragGesture(pageWidth: pageWidth))
        }
        .frame(height: 76)
        .clipped()
    }

    private func weekPage(for offset: Int) -> some View {
        HStack(spacing: weekDateSpacing) {
            ForEach(viewModel.weekDates(shiftedByWeeks: offset), id: \.self) { date in
                let isSelected = viewModel.isSelectedDate(date)
                Button {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.timelineEntries.enumerated()), id: \.element.id) { index, entry in
                        HomeTimelineRow(
                            entry: entry,
                            isAnimatingCompletion: viewModel.recentCompletedItemID == entry.id && viewModel.isPerformingCompletion,
                            quickSnoozeMinuteOptions: viewModel.quickTimePresetMinutes,
                            onToggleCompletion: {
                                HomeInteractionFeedback.selection()
                                Task {
                                    await viewModel.completeItem(entry.id)
                                    HomeInteractionFeedback.completion()
                                }
                            },
                            onOpenDetail: {
                                HomeInteractionFeedback.soft()
                                viewModel.presentItemDetail(entry.id)
                            },
                            onApplySnoozeMinutes: { minutes in
                                guard viewModel.prepareSnoozeContext(for: entry.id) else { return }
                                Task {
                                    await viewModel.applySnooze(minutes: minutes)
                                    HomeInteractionFeedback.selection()
                                }
                            },
                            onApplySnoozeTomorrow: {
                                guard viewModel.prepareSnoozeContext(for: entry.id) else { return }
                                Task {
                                    await viewModel.applySnoozeTomorrow()
                                    HomeInteractionFeedback.selection()
                                }
                            },
                            onPresentCustomSnooze: {
                                guard viewModel.prepareSnoozeContext(for: entry.id) else { return }
                                HomeInteractionFeedback.selection()
                                viewModel.presentCustomSnoozePicker()
                            }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )

                        if index < viewModel.timelineEntries.count - 1 {
                            DashedDivider()
                                .stroke(AppTheme.colors.separator, style: StrokeStyle(lineWidth: 1.5, dash: [3, 8]))
                                .frame(height: 1)
                                .padding(.leading, 4)
                                .padding(.vertical, 2)
                        }
                    }

                    if viewModel.hasCompletedEntries {
                        completedVisibilityButton
                            .padding(.top, 14)
                            .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .id(viewModel.selectedDateKey)
                .transition(timelineTransition)
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: viewModel.selectedDateKey)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.timelineEntryIDs)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.hasCompletedEntries)
    }

    private var completedVisibilityButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            viewModel.toggleCompletedVisibility()
        } label: {
            Text("\(viewModel.completedVisibilityButtonTitle) \(viewModel.completedEntryCount)")
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
    let quickSnoozeMinuteOptions: [Int]
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void
    let onApplySnoozeMinutes: (Int) -> Void
    let onApplySnoozeTomorrow: () -> Void
    let onPresentCustomSnooze: () -> Void
    @State private var swipeOffset: CGFloat = 0

    private let actionWidth: CGFloat = 74
    private let actionButtonSize: CGFloat = 54
    private let actionOpenThreshold: CGFloat = 36
    @State private var hasTriggeredSwipeFeedback = false

    var body: some View {
        rowContent
            .offset(x: swipeOffset)
            .overlay(alignment: .trailing) {
                if !entry.isCompleted && entry.canSnooze {
                    snoozeMenuTrigger
                        .padding(.trailing, 6)
                        .opacity(swipeRevealProgress)
                        .scaleEffect(0.9 + (swipeRevealProgress * 0.1))
                        .allowsHitTesting(swipeOffset <= -actionOpenThreshold)
                }
            }
            .clipShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: swipeOffset)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Button(action: onToggleCompletion) {
                timelineSymbol
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

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
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if swipeOffset < 0 {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    swipeOffset = 0
                }
            } else {
                onOpenDetail()
            }
        }
        .gesture(rowSwipeGesture)
    }

    private var snoozeMenuTrigger: some View {
        HomeSnoozeMenuButton(
            quickSnoozeMinuteOptions: quickSnoozeMinuteOptions,
            relativePresetTitle: relativePresetTitle,
            onQuickSnooze: { minutes in
                onApplySnoozeMinutes(minutes)
                closeSwipeAction(after: 0.32)
            },
            onTomorrow: {
                onApplySnoozeTomorrow()
                closeSwipeAction(after: 0.32)
            },
            onCustom: {
                onPresentCustomSnooze()
                closeSwipeAction(after: 0.36)
            }
        )
        .frame(width: actionWidth, height: actionButtonSize, alignment: .trailing)
        .shadow(color: AppTheme.colors.shadow.opacity(0.18), radius: 10, y: 5)
    }

    private var rowSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard !entry.isCompleted, entry.canSnooze else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < 0 {
                    swipeOffset = max(value.translation.width, -actionWidth)
                    if swipeOffset <= -actionOpenThreshold, hasTriggeredSwipeFeedback == false {
                        hasTriggeredSwipeFeedback = true
                        HomeInteractionFeedback.swipeReveal()
                    }
                } else if swipeOffset < 0 {
                    swipeOffset = min(0, -actionWidth + value.translation.width)
                    if swipeOffset > -actionOpenThreshold {
                        hasTriggeredSwipeFeedback = false
                    }
                }
            }
            .onEnded { value in
                guard !entry.isCompleted, entry.canSnooze else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    settleSwipeOffset(using: value)
                    return
                }

                settleSwipeOffset(using: value)
            }
    }

    private func settleSwipeOffset(using value: DragGesture.Value) {
        let predictedTravel = value.predictedEndTranslation.width
        let shouldOpen = value.translation.width < -actionOpenThreshold || predictedTravel < -(actionWidth * 0.78)

        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            swipeOffset = shouldOpen ? -actionWidth : 0
        }
        hasTriggeredSwipeFeedback = shouldOpen
    }

    private var swipeRevealProgress: CGFloat {
        let progress = min(max(-swipeOffset / actionWidth, 0), 1)
        return progress
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func closeSwipeAction(after delay: TimeInterval = 0) {
        let reset = {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                swipeOffset = 0
            }
            hasTriggeredSwipeFeedback = false
        }

        guard delay > 0 else {
            reset()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            reset()
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
        Group {
            if entry.isCompleted {
                completionBadge
            } else {
                interactiveBadge
            }
        }
        .scaleEffect(isAnimatingCompletion ? 1.08 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isAnimatingCompletion)
    }

    private var completionBadge: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(AppTheme.colors.surfaceElevated)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.colors.outlineStrong.opacity(0.78), lineWidth: 1.25)
            }
            .overlay {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .symbolEffect(.bounce, value: isAnimatingCompletion)
            }
    }

    @ViewBuilder
    private var interactiveBadge: some View {
        switch entry.accentColorName {
        case "coral":
            symbolBadge(
                foregroundColor: AppTheme.colors.coral,
                borderStyle: .solid,
                fillColor: AppTheme.colors.surfaceElevated
            )
        default:
            symbolBadge(
                foregroundColor: AppTheme.colors.body.opacity(0.58),
                borderStyle: .dashed,
                fillColor: .clear
            )
        }
    }

    private func symbolBadge(
        foregroundColor: Color,
        borderStyle: BadgeBorderStyle,
        fillColor: Color
    ) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(fillColor)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        foregroundColor.opacity(borderStyle == .dashed ? 0.58 : 0.34),
                        style: StrokeStyle(
                            lineWidth: borderStyle == .dashed ? 1.6 : 1.3,
                            dash: borderStyle == .dashed ? [4, 4.8] : []
                        )
                    )
            }
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
            configuration.background.backgroundColor = UIColor(AppTheme.colors.outlineStrong.opacity(0.16))
            configuration.background.cornerRadius = 27
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 17, leading: 17, bottom: 17, trailing: 17)
            configuration.image = UIImage(systemName: "arrowshape.turn.up.backward.badge.clock.fill.rtl")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            configuration.imagePlacement = .all
            button.configuration = configuration
            button.configurationUpdateHandler = { target in
                guard var updatedConfiguration = target.configuration else { return }
                updatedConfiguration.baseForegroundColor = UIColor(AppTheme.colors.sky)
                updatedConfiguration.background.backgroundColor = UIColor(AppTheme.colors.outlineStrong.opacity(0.16))
                updatedConfiguration.background.strokeColor = .clear
                updatedConfiguration.background.strokeWidth = 0
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
                        .fill(AppTheme.colors.outlineStrong.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }
}
#endif

private enum BadgeBorderStyle {
    case solid
    case dashed
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
                    .fill(AppTheme.colors.surface.opacity(0.92))
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 1.2)
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
            case .customDate:
                TaskEditorDatePickerSheet(
                    selectedDate: $viewModel.stagedCustomSnoozeDate,
                    selectionFeedback: HomeInteractionFeedback.selection,
                    onDismiss: viewModel.transitionFromCustomDateToTime
                )
            case .customTime:
                TaskEditorTimePickerSheet(
                    selectedTime: $viewModel.stagedCustomSnoozeTime,
                    anchorDate: viewModel.stagedCustomSnoozeDate,
                    quickPresetMinutes: viewModel.quickTimePresetMinutes,
                    primaryButtonTitle: "确认",
                    selectionFeedback: HomeInteractionFeedback.selection,
                    primaryFeedback: HomeInteractionFeedback.selection,
                    onTimeSaved: {
                        Task {
                            await viewModel.applyCustomSnoozeSelection()
                            HomeInteractionFeedback.selection()
                        }
                    },
                    onDismiss: {
                        viewModel.dismissSnoozeUI()
                    }
                )
            }
        }
        .id(menu.id)
    }
}

private struct HomeAvatarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.7), lineWidth: 1)
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
