import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let isProjectLayerPresented: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundView

                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AppTheme.spacing.xl)
                        .padding(.top, proxy.safeAreaInsets.top + AppTheme.spacing.sm)
                        .padding(.bottom, isProjectLayerPresented ? AppTheme.spacing.lg : AppTheme.spacing.xl)

                    contentCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(y: projectCardOffset)
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
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(viewModel.headerDateText)
                    .font(AppTheme.typography.sized(40, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(headerPrimaryColor)
                    .contentTransition(.numericText())
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
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: viewModel.showsPairAvatarPreview)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isProjectLayerPresented)
    }

    private var contentCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                weekCalendarSection
                timelineSection
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, isProjectLayerPresented ? AppTheme.spacing.xl : AppTheme.spacing.lg)
            .padding(.bottom, 144)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isProjectLayerPresented)
        .background(
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : 32, style: .continuous)
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
            RoundedRectangle(cornerRadius: isProjectLayerPresented ? 38 : 32, style: .continuous)
        )
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isProjectLayerPresented)
    }

    private var weekCalendarSection: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.weekDates, id: \.self) { date in
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
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(isSelected ? AppTheme.colors.surfaceElevated : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.timelineEntries.enumerated()), id: \.element.id) { index, entry in
                        HomeTimelineRow(
                            entry: entry,
                            isAnimatingCompletion: viewModel.recentCompletedItemID == entry.id && viewModel.isPerformingCompletion,
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
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .id(viewModel.selectedDateKey)
                .transition(
                    .move(edge: viewModel.selectedDateTransitionEdge)
                    .combined(with: .opacity)
                )
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: viewModel.selectedDateKey)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.timelineEntryIDs)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: viewModel.hasCompletedEntries)
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
}

private struct HomeTimelineRow: View {
    let entry: HomeTimelineEntry
    let isAnimatingCompletion: Bool
    let onToggleCompletion: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
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
                    .foregroundStyle(AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.68))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                HomeTimelineTimeText(entry: entry)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(entry.isCompleted ? "恢复" : "完成", systemImage: entry.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                onToggleCompletion()
            }
            .tint(AppTheme.colors.coral)
        }
    }

    private var displaySubtitle: String {
        guard let notes = entry.notes, notes.isEmpty == false else {
            return entry.urgency == .overdue ? "已超时" : "进行中"
        }
        return notes
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
        case "sun":
            symbolBadge(
                foregroundColor: AppTheme.colors.sun,
                borderStyle: .solid,
                fillColor: AppTheme.colors.surface
            )
        case "violet":
            symbolBadge(
                foregroundColor: AppTheme.colors.violet,
                borderStyle: .solid,
                fillColor: AppTheme.colors.surface
            )
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
            .overlay {
                if entry.symbolName != "circle" {
                    Image(systemName: entry.symbolName)
                        .font(AppTheme.typography.sized(13, weight: .bold))
                        .foregroundStyle(foregroundColor)
                }
            }
    }
}

private enum BadgeBorderStyle {
    case solid
    case dashed
}

private struct HomeTimelineTimeText: View {
    let entry: HomeTimelineEntry
    @State private var isBreathing = false

    var body: some View {
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
