import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var viewModel: HomeViewModel

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                weekStrip
                pendingSection
                inProgressSection
                anniversarySection
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, 100)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("一起")
        .overlay(alignment: .bottomTrailing) {
            FloatingComposerButton(
                onCreateItem: { appContext.router.activeComposer = .newItem },
                onCreateDecision: { appContext.router.activeComposer = .newDecision }
            )
            .padding(.trailing, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.lg)
        }
        .task {
            if viewModel.loadState == .idle {
                await viewModel.load()
            }
        }
    }

    private var weekStrip: some View {
        CardSection(title: "本周", subtitle: "首页优先展示需要回应和推进的双人事项") {
            HStack(spacing: AppTheme.spacing.sm) {
                ForEach(weekDates, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
                    VStack(spacing: AppTheme.spacing.xs) {
                        Text(date, format: .dateTime.weekday(.narrow))
                            .font(.caption)
                        Text(date, format: .dateTime.day())
                            .font(.headline)
                    }
                    .foregroundStyle(isSelected ? .white : AppTheme.colors.title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? AppTheme.colors.accent : AppTheme.colors.accentSoft)
                    )
                    .onTapGesture {
                        viewModel.selectedDate = date
                    }
                }
            }
        }
    }

    private var pendingSection: some View {
        CardSection(
            title: "待回应事项",
            subtitle: "最高优先级，先把需要反馈的事从聊天里拎出来"
        ) {
            if let item = viewModel.pendingItems.first {
                NavigationLink {
                    DetailPlaceholderView(
                        title: "事项详情",
                        message: "后续接入完整字段、反馈记录、修改与删除策略。"
                    )
                } label: {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.colors.title)
                                Text(item.executionRole.label(
                                    for: viewModel.currentUserID ?? MockDataFactory.currentUserID,
                                    creatorID: item.creatorID
                                ))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.colors.body)
                            }

                            Spacer()
                            StatusBadge(title: item.status.title, tint: AppTheme.colors.warning)
                        }

                        if let dueAt = item.dueAt {
                            Text("截止：\(dueAt, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(AppTheme.colors.body)
                        }

                        HStack {
                            StatusBadge(title: item.priority.title, tint: AppTheme.colors.accent)
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: AppTheme.spacing.sm) {
                    ForEach(viewModel.availableResponses(for: item), id: \.self) { response in
                        Button(response.title) {
                            Task {
                                await viewModel.submitResponse(for: item, response: response)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(buttonTint(for: response))
                    }
                }
            } else {
                EmptyStateCard(
                    title: "现在没有待回应事项",
                    message: "这不是普通待办清单，而是两个人之间需要回应的协作流。"
                )
            }
        }
    }

    private var inProgressSection: some View {
        CardSection(title: "进行中事项", subtitle: "持续推进双方已经达成共识或已知情的事项") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing.sm) {
                    ForEach(HomeFilter.allCases, id: \.self) { filter in
                        Button(filter.title) {
                            viewModel.selectedFilter = filter
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.selectedFilter == filter ? AppTheme.colors.accent : AppTheme.colors.body)
                    }
                }
            }

            if viewModel.filteredInProgressItems.isEmpty {
                EmptyStateCard(title: "还没有进行中的事项", message: "待确认被接受后，事项会进入这里。")
            } else {
                VStack(spacing: AppTheme.spacing.md) {
                    ForEach(viewModel.filteredInProgressItems, id: \.id) { item in
                        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.colors.title)
                                    if let notes = item.notes {
                                        Text(notes)
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.colors.body)
                                    }
                                }
                                Spacer()
                                StatusBadge(title: item.priority.title, tint: AppTheme.colors.accent)
                            }

                            HStack {
                                Text(item.executionRole.label(
                                    for: viewModel.currentUserID ?? MockDataFactory.currentUserID,
                                    creatorID: item.creatorID
                                ))
                                .font(.caption)
                                .foregroundStyle(AppTheme.colors.body)

                                Spacer()

                                if let dueAt = item.dueAt {
                                    Text(dueAt, format: .dateTime.month().day())
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.colors.body)
                                }
                            }

                            Button("标记完成") {
                                Task {
                                    await viewModel.markCompleted(item)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.colors.success)
                        }
                        .padding(AppTheme.spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.colors.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private var anniversarySection: some View {
        CardSection(title: "纪念日轻提示", subtitle: "首页只轻量露出，不抢占协作主线") {
            if let anniversary = viewModel.highlightedAnniversary {
                VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                    Text(anniversary.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.colors.title)
                    Text(relativeAnniversaryText(for: anniversary))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.colors.body)

                    Button("进入纪念日页") {
                        appContext.router.selectedTab = .anniversaries
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                EmptyStateCard(title: "还没有纪念日", message: "后续可以在这里承接关系日期和提醒。")
            }
        }
    }

    private var weekDates: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: viewModel.selectedDate) ?? DateInterval(
            start: viewModel.selectedDate,
            duration: 86_400 * 7
        )
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func relativeAnniversaryText(for anniversary: Anniversary) -> String {
        let dayDelta = calendar.dateComponents([.day], from: MockDataFactory.now, to: anniversary.eventDate).day ?? 0
        if dayDelta >= 0 {
            return "距离 \(anniversary.name) 还有 \(dayDelta) 天"
        }
        return "\(anniversary.name) 已经过去 \(abs(dayDelta)) 天"
    }

    private func buttonTint(for response: ItemResponseKind) -> Color {
        switch response {
        case .willing, .acknowledged:
            return AppTheme.colors.success
        case .notAvailableNow:
            return AppTheme.colors.warning
        case .notSuitable:
            return AppTheme.colors.danger
        }
    }
}
