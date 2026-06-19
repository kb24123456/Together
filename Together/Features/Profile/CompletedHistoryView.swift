import SwiftUI

struct CompletedHistoryView: View {
    @Bindable var viewModel: CompletedHistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterPicker
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.sm)
                .padding(.bottom, AppTheme.spacing.xs)

            List {
                if viewModel.sections.isEmpty {
                    emptySection
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionHeader(section.title)

                        ForEach(section.items) { item in
                            CompletedTaskRow(
                                item: item,
                                subtitle: viewModel.subtitle(for: item),
                                trailingText: trailingText(for: item),
                                showsArchivedDate: viewModel.isArchived(item),
                                archivedDateText: viewModel.archivedDateText(for: item)
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
                            .task {
                                await viewModel.loadMoreIfNeeded(currentItem: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("恢复", systemImage: "arrow.uturn.backward.circle") {
                                    Task {
                                        await viewModel.restore(item)
                                    }
                                }
                                .tint(AppTheme.colors.selectionTint)

                                Button("删除", systemImage: "trash") {
                                    Task {
                                        await viewModel.delete(item)
                                    }
                                }
                                .tint(AppTheme.colors.danger)
                            }
                            .contextMenu {
                                Button("恢复", systemImage: "arrow.uturn.backward.circle") {
                                    Task {
                                        await viewModel.restore(item)
                                    }
                                }

                                Button("删除", systemImage: "trash", role: .destructive) {
                                    Task {
                                        await viewModel.delete(item)
                                    }
                                }
                            }
                        }
                    }

                    if viewModel.isLoading {
                        loadingRow
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .applyScrollEdgeProtection()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("已完成")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "搜索已完成任务")
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: viewModel.searchText) {
            await viewModel.reload()
        }
        .task(id: viewModel.selectedFilter) {
            await viewModel.reload()
        }
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $viewModel.selectedFilter) {
            ForEach(CompletedHistoryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("已完成任务筛选")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.typography.textStyle(.title3, weight: .regular))
            .foregroundStyle(AppTheme.colors.body.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xs)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: AppTheme.spacing.xl,
                    bottom: 0,
                    trailing: AppTheme.spacing.xl
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var emptySection: some View {
        EmptyStateCard(
            title: "还没有历史任务",
            message: "已完成任务会在这里沉淀，Today 只保留当前仍需处理的任务。",
            illustration: "EmptyHistory",
            usesNeutralBackground: true
        )
        .listRowInsets(EdgeInsets(top: AppTheme.spacing.lg, leading: AppTheme.spacing.lg, bottom: AppTheme.spacing.lg, trailing: AppTheme.spacing.lg))
        .listRowBackground(AppTheme.colors.background)
        .listRowSeparator(.hidden)
    }

    private var loadingRow: some View {
        HStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text("正在加载更多历史任务")
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(AppTheme.colors.background)
        .listRowSeparator(.hidden)
    }

    private func accessibilityLabel(for item: Item) -> String {
        let completedDate = viewModel.completedDateText(for: item)
        return "\(item.title) · \(completedDate)"
    }

    private func trailingText(for item: Item) -> String {
        switch viewModel.selectedFilter {
        case .week:
            guard let completedAt = item.completedAt else { return "" }
            return weekdayLabel(for: completedAt)
        case .month:
            guard let completedAt = item.completedAt else { return "" }
            return monthDayText(for: completedAt)
        case .all:
            return viewModel.completedDateText(for: item)
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return ""
        }
    }

    private func monthDayText(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

}

struct CompletedTaskRow: View {
    let item: Item
    let subtitle: String
    let trailingText: String
    let showsArchivedDate: Bool
    let archivedDateText: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            completedBadge
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                        Text(item.title)
                            .font(AppTheme.typography.sized(18, weight: .bold))
                            .foregroundStyle(AppTheme.colors.title.opacity(0.62))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .allowsTightening(true)

                        Text(subtitle)
                            .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.52))
                            .lineLimit(2)

                        if showsArchivedDate {
                            Text("归档 \(archivedDateText)")
                                .font(AppTheme.typography.textStyle(.caption2, weight: .medium))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.44))
                        }
                    }

                    Spacer(minLength: 0)

                    Text(trailingText)
                        .font(AppTheme.typography.sized(17, weight: .bold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, AppTheme.spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title) · \(trailingText)")
    }

    private var completedBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    AppTheme.colors.body.opacity(0.24),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6])
                )

            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(15, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.42))
        }
        .padding(4)
    }
}

#if DEBUG
#Preview("Completed History") {
    NavigationStack {
        CompletedHistoryView(
            viewModel: CompletedHistoryViewModel(
                sessionStore: {
                    let store = SessionStore()
                    store.seedMock(
                        currentUser: MockDataFactory.makeCurrentUser(),
                        singleSpace: MockDataFactory.makeSingleSpace()
                    )
                    return store
                }(),
                itemRepository: MockItemRepository(),
                taskApplicationService: DefaultTaskApplicationService(
                    itemRepository: MockItemRepository(),
                    syncCoordinator: NoOpSyncCoordinator(),
                    reminderScheduler: MockReminderScheduler()
                ),
                taskListRepository: MockTaskListRepository(),
                projectRepository: MockProjectRepository(reminderScheduler: MockReminderScheduler())
            )
        )
    }
    .environment(AppContext.makeBootstrappedContext())
}
#endif
