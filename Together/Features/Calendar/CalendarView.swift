import SwiftUI

struct CalendarView: View {
    @Bindable var viewModel: CalendarViewModel
    let showsNavigationChrome: Bool

    init(
        viewModel: CalendarViewModel,
        showsNavigationChrome: Bool = true
    ) {
        self.viewModel = viewModel
        self.showsNavigationChrome = showsNavigationChrome
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                if viewModel.isPairModeActive {
                    pairModeHeader
                }

                CardSection(
                    title: viewModel.isMonthMode ? "月视图骨架" : "周视图骨架",
                    subtitle: "先把焦点日期和任务映射跑通，再补完整日历栅格与切换动效"
                ) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                        HStack {
                            Text(viewModel.selectedDateTitle)
                                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer()
                            Button(viewModel.isMonthMode ? "切到周视图" : "切到月视图") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    viewModel.toggleMode()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.colors.accent)
                        }

                        Text("当前日期共有 \(viewModel.selectedItems.count) 个任务")
                            .foregroundStyle(AppTheme.colors.body)
                    }
                }

                CardSection(title: "焦点日期任务", subtitle: "后续这里会承接日期切换和任务详情联动") {
                    VStack(spacing: AppTheme.spacing.sm) {
                        if viewModel.selectedItems.isEmpty {
                            EmptyStateCard(title: "这一天还没有安排", message: "下一步会补齐跨天拖动、快速安排和焦点日期切换。")
                        } else {
                            ForEach(viewModel.selectedItems) { item in
                                if viewModel.isPairModeActive {
                                    PairCalendarTaskCard(
                                        item: item,
                                        currentUser: viewModel.currentUser,
                                        partner: viewModel.partner,
                                        trailingText: trailingText(for: item)
                                    )
                                } else {
                                    HStack {
                                        Text(item.title)
                                            .foregroundStyle(AppTheme.colors.title)
                                        Spacer()
                                        if let trailingText = trailingText(for: item) {
                                            Text(trailingText)
                                                .foregroundStyle(AppTheme.colors.body)
                                        }
                                    }
                                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                                    .padding(.vertical, AppTheme.spacing.xxs)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.spacing.xl)
            .padding(.bottom, showsNavigationChrome ? AppTheme.spacing.xl : 164) // tab-bar clearance, outside token scale
        }
        .applyScrollEdgeProtection()
        .background(GradientGridBackground())
        .navigationTitle("日历")
        .toolbar(showsNavigationChrome ? .visible : .hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }

    private var pairModeHeader: some View {
        CardSection(title: "双人日历", subtitle: viewModel.spaceSummary) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                HStack(spacing: AppTheme.spacing.md) {
                    PairModeAvatarStrip(
                        currentUser: viewModel.currentUser,
                        partner: viewModel.partner
                    )

                    VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                        Text("共享安排")
                            .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)

                        Text("按归属与响应状态快速查看这一天的双人任务。")
                            .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacing.xs) {
                        ForEach(CalendarPairTaskFilter.allCases, id: \.self) { filter in
                            Button(filter.title) {
                                viewModel.setPairTaskFilter(filter)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, AppTheme.spacing.md)
                            .padding(.vertical, AppTheme.spacing.sm)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        viewModel.pairTaskFilter == filter
                                        ? AppTheme.colors.coral
                                        : AppTheme.colors.surfaceElevated
                                    )
                            )
                            .foregroundStyle(
                                viewModel.pairTaskFilter == filter
                                ? Color.white
                                : AppTheme.colors.title
                            )
                            .font(AppTheme.typography.sized(13, weight: .bold))
                        }
                    }
                }
            }
        }
        .applyCalendarScrollEdgeProtection()
    }

    private func trailingText(for item: Item) -> String? {
        guard let dueAt = item.dueAt else { return nil }
        guard item.hasExplicitTime else {
            if let repeatRule = item.repeatRule {
                return repeatRule.title(anchorDate: item.anchorDateForRepeatRule, calendar: .current)
            }
            return "未设时间"
        }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct PairCalendarTaskCard: View {
    let item: Item
    let currentUser: User?
    let partner: User?
    let trailingText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.md) {
                Text(item.title)
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .allowsTightening(true)

                Spacer(minLength: 0)

                if let trailingText, trailingText.isEmpty == false {
                    Text(trailingText)
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(timeColor)
                        .lineLimit(1)
                }
            }

            Text(subtitleText)
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            HStack(spacing: AppTheme.spacing.sm) {
                PairCalendarAvatarStrip(
                    currentUser: currentUser,
                    partner: partner,
                    mode: item.assigneeMode,
                    creatorID: item.creatorID
                )

                Text(messageText)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(messageColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Spacer(minLength: 0)

                statusChip
            }
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.xl, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var subtitleText: String {
        if item.assignmentState == .pendingResponse {
            return item.canActorRespond(viewerID) ? "待你处理这个请求" : "等待对方确认"
        }
        if item.assigneeMode == .both {
            return "这一天里的一条共享安排"
        }
        return "轻点查看这条安排"
    }

    private var messageText: String {
        if let latestMessage = item.assignmentMessages.last?.body.trimmingCharacters(in: .whitespacesAndNewlines),
           latestMessage.isEmpty == false {
            if let authorName = latestMessageAuthorName {
                return "\(authorName)：\(latestMessage)"
            }
            return latestMessage
        }
        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), notes.isEmpty == false {
            return notes
        }
        return "暂时还没有留言"
    }

    private var latestMessageAuthorName: String? {
        guard let latestMessage = item.assignmentMessages.last else { return nil }
        if latestMessage.authorID == currentUser?.id {
            return "你"
        }
        if latestMessage.authorID == partner?.id {
            return partner?.displayName
        }
        return nil
    }

    private var viewerID: UUID {
        currentUser?.id ?? item.creatorID
    }

    private var messageColor: Color {
        item.assignmentMessages.isEmpty && (item.notes?.isEmpty != false)
            ? AppTheme.colors.body.opacity(0.5)
            : AppTheme.colors.body.opacity(0.74)
    }

    private var timeColor: Color {
        if item.status == .completed {
            return AppTheme.colors.body.opacity(0.44)
        }
        if let dueAt = item.dueAt, dueAt < .now {
            return AppTheme.colors.coral
        }
        return AppTheme.colors.body.opacity(0.58)
    }

    private var backgroundFill: some ShapeStyle {
        switch item.assigneeMode {
        case .both:
            return AppTheme.colors.sky.opacity(0.08)
        case .partner where item.assignmentState == .pendingResponse:
            return AppTheme.colors.coral.opacity(0.08)
        default:
            return AppTheme.colors.background
        }
    }

    private var borderColor: Color {
        switch item.assigneeMode {
        case .both:
            return AppTheme.colors.sky.opacity(0.16)
        case .partner where item.assignmentState == .pendingResponse:
            return AppTheme.colors.coral.opacity(0.16)
        default:
            return AppTheme.colors.outlineStrong.opacity(0.1)
        }
    }

    private var statusChip: some View {
        Text(statusText)
            .font(AppTheme.typography.sized(12, weight: .bold))
            .foregroundStyle(statusForeground)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(statusBackground)
            )
    }

    private var statusText: String {
        switch item.assignmentState {
        case .pendingResponse:
            return item.canActorRespond(viewerID) ? "待回应" : "已发出"
        case .accepted:
            return "已接受"
        case .snoozed:
            return "稍后"
        case .declined:
            return "已拒绝"
        case .active:
            return item.status == .completed ? "已完成" : "进行中"
        case .completed:
            return "已完成"
        }
    }

    private var statusBackground: Color {
        switch item.assignmentState {
        case .pendingResponse:
            return item.canActorRespond(viewerID)
                ? AppTheme.colors.coral.opacity(0.14)
                : AppTheme.colors.surfaceElevated
        case .accepted, .active:
            return AppTheme.colors.sky.opacity(0.14)
        case .snoozed:
            return AppTheme.colors.surfaceElevated
        case .declined:
            return AppTheme.colors.background
        case .completed:
            return AppTheme.colors.surfaceElevated
        }
    }

    private var statusForeground: Color {
        switch item.assignmentState {
        case .pendingResponse:
            return item.canActorRespond(viewerID) ? AppTheme.colors.coral : AppTheme.colors.title
        case .accepted, .active:
            return AppTheme.colors.sky
        case .snoozed:
            return AppTheme.colors.title
        case .declined:
            return AppTheme.colors.coral
        case .completed:
            return AppTheme.colors.body
        }
    }
}

private struct PairModeAvatarStrip: View {
    let currentUser: User?
    let partner: User?

    var body: some View {
        HStack(spacing: -8) {
            avatar(for: currentUser, fill: AppTheme.colors.surfaceElevated)
            if partner != nil {
                avatar(for: partner, fill: AppTheme.colors.avatarWarm)
            }
        }
        .frame(width: partner == nil ? 40 : 70, height: 40, alignment: .leading)
    }

    @ViewBuilder
    private func avatar(for user: User?, fill: Color) -> some View {
        UserAvatarView(
            avatarAsset: user?.avatarAsset ?? .system("person.crop.circle.fill"),
            displayName: user?.displayName ?? "用户",
            size: 40,
            fillColor: fill,
            symbolColor: AppTheme.colors.title,
            symbolFont: AppTheme.typography.sized(14, weight: .semibold)
        )
        .overlay {
            Circle()
                .stroke(.white.opacity(0.92), lineWidth: 2)
        }
    }
}

private struct PairCalendarAvatarStrip: View {
    let currentUser: User?
    let partner: User?
    let mode: TaskAssigneeMode
    let creatorID: UUID

    var body: some View {
        HStack(spacing: secondaryUser == nil ? 0 : -8) {
            avatar(for: primaryUser, fill: AppTheme.colors.surfaceElevated)
            if let secondaryUser {
                avatar(for: secondaryUser, fill: AppTheme.colors.avatarWarm)
            }
        }
        .frame(width: secondaryUser == nil ? 34 : 58, height: 34, alignment: .leading)
    }

    private var viewerID: UUID {
        currentUser?.id ?? creatorID
    }

    private var primaryUser: User? {
        switch mode {
        case .partner:
            return partner
        case .both:
            return currentUser
        case .self:
            return currentUser
        }
    }

    private var secondaryUser: User? {
        switch mode {
        case .both:
            return partner
        case .partner, .self:
            return nil
        }
    }

    @ViewBuilder
    private func avatar(for user: User?, fill: Color) -> some View {
        UserAvatarView(
            avatarAsset: user?.avatarAsset ?? .system("person.crop.circle.fill"),
            displayName: user?.displayName ?? "用户",
            size: 34,
            fillColor: fill,
            symbolColor: AppTheme.colors.title,
            symbolFont: AppTheme.typography.sized(13, weight: .semibold)
        )
        .overlay {
            Circle()
                .stroke(.white.opacity(0.92), lineWidth: 2)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyCalendarScrollEdgeProtection() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }
}
