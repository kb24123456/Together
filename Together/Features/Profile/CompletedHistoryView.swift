import SwiftUI

struct CompletedHistoryView: View {
    @State private var viewModel: CompletedHistoryViewModel
    @State private var isPreciseFilterPresented = false
    @State private var didRunInitialLoad = false

    init(viewModel: CompletedHistoryViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        List {
            if viewModel.isInitialLoading {
                initialLoadingSection
            } else if viewModel.didFailLoading {
                failedSection
            } else if viewModel.sections.isEmpty {
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
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("已完成")
        .navigationSubtitle(viewModel.selectedFilter.navigationSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                quickFilterMenu
            }

            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }

            ToolbarItem(placement: .bottomBar) {
                preciseFilterToolbarButton
            }
        }
        .searchable(text: $bindableViewModel.searchText, prompt: "搜索")
        .sheet(isPresented: $isPreciseFilterPresented) {
            NavigationStack {
                CompletedHistoryPreciseFilterSheet(
                    viewModel: viewModel,
                    onApply: { filter in
                        viewModel.applyFilter(filter)
                        isPreciseFilterPresented = false
                    }
                )
            }
            .presentationDetents([.height(540)])
            .presentationDragIndicator(.visible)
        }
        .task {
            guard didRunInitialLoad == false else { return }
            didRunInitialLoad = true
            await viewModel.loadIfNeeded()
            await viewModel.refreshCompletedStats()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            guard didRunInitialLoad else { return }
            Task { await viewModel.reload() }
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            guard didRunInitialLoad else { return }
            Task { await viewModel.reload() }
        }
    }

    private var quickFilterMenu: some View {
        Menu {
            quickFilterButton(title: "本周", filter: .week)
            quickFilterButton(title: "本月", filter: .month)
            quickFilterButton(title: "全部", filter: .all)
        } label: {
            ToolbarTextActionLabel(title: quickFilterMenuTitle)
        }
        .accessibilityLabel("快捷筛选")
        .accessibilityValue(viewModel.selectedFilter.navigationSubtitle)
    }

    private var quickFilterMenuTitle: String {
        switch viewModel.selectedFilter {
        case .week:
            return "本周"
        case .month:
            return "本月"
        case .all:
            return "全部"
        case .specificMonth, .specificDay:
            return "筛选"
        }
    }

    private func quickFilterButton(
        title: String,
        filter: CompletedHistoryFilter
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            dismissPreciseFilter()
            viewModel.applyFilter(filter)
        } label: {
            Text(title)
        }
    }

    private var preciseFilterToolbarButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            Task { await viewModel.refreshCompletedStats() }
            isPreciseFilterPresented = true
        } label: {
            Label(
                "精确筛选",
                systemImage: viewModel.selectedFilter.isPrecise
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            )
        }
        .font(.body)
        .tint(viewModel.selectedFilter.isPrecise ? AppTheme.colors.sky : nil)
        .accessibilityLabel("精确筛选")
        .accessibilityValue(viewModel.selectedFilter.isPrecise ? viewModel.selectedFilter.title : "未启用")
    }

    private func dismissPreciseFilter() {
        guard isPreciseFilterPresented else { return }
        isPreciseFilterPresented = false
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

    private var initialLoadingSection: some View {
        HStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text("正在加载历史任务")
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, AppTheme.spacing.xl)
        .listRowBackground(AppTheme.colors.background)
        .listRowSeparator(.hidden)
    }

    private var failedSection: some View {
        VStack(spacing: AppTheme.spacing.md) {
            EmptyStateCard(
                title: "历史任务加载失败",
                message: "下拉刷新或点击重试后会重新加载。",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                usesNeutralBackground: true
            )

            Button("重试") {
                Task {
                    await viewModel.reload()
                }
            }
            .font(.body)
        }
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
        case .month, .specificMonth(_):
            guard let completedAt = item.completedAt else { return "" }
            return monthDayText(for: completedAt)
        case .specificDay(_):
            guard let completedAt = item.completedAt else { return "" }
            return completedAt.formatted(date: .omitted, time: .shortened)
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

private enum CompletedHistoryPreciseFilterMode: Hashable {
    case day
    case month
}

private struct CompletedHistoryPrimaryGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct CompletedHistoryPreciseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: CompletedHistoryViewModel
    let onApply: (CompletedHistoryFilter) -> Void

    @State private var mode: CompletedHistoryPreciseFilterMode
    @State private var selectedDay: Date
    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    private let calendar = Calendar.current
    private let contentHeight: CGFloat = 340

    init(
        viewModel: CompletedHistoryViewModel,
        onApply: @escaping (CompletedHistoryFilter) -> Void
    ) {
        self.viewModel = viewModel
        self.onApply = onApply
        let day = viewModel.selectedFilter.daySelectionDate ?? .now
        let monthDate = viewModel.selectedFilter.monthSelectionDate ?? .now
        let components = Calendar.current.dateComponents([.year, .month], from: monthDate)
        let initialMode: CompletedHistoryPreciseFilterMode = viewModel.selectedFilter.monthSelectionDate == nil ? .day : .month
        _mode = State(initialValue: initialMode)
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: day))
        _selectedYear = State(initialValue: components.year ?? Calendar.current.component(.year, from: .now))
        _selectedMonth = State(initialValue: components.month ?? Calendar.current.component(.month, from: .now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
            Picker("筛选类型", selection: $mode) {
                Text("日期").tag(CompletedHistoryPreciseFilterMode.day)
                Text("月份").tag(CompletedHistoryPreciseFilterMode.month)
            }
            .pickerStyle(.segmented)

            ZStack {
                dayFilterContent
                    .opacity(mode == .day ? 1 : 0)
                    .allowsHitTesting(mode == .day)

                monthFilterContent
                    .opacity(mode == .month ? 1 : 0)
                    .allowsHitTesting(mode == .month)
            }
            .frame(maxWidth: .infinity)
            .frame(height: contentHeight, alignment: .top)
            .clipped()
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.top, AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("精确筛选")
        .navigationSubtitle("选择具体日期或月份")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    dismiss()
                }
                .font(.body)
            }
        }
        .task {
            await viewModel.refreshCompletedStats()
            normalizeMonthSelection()
        }
    }

    private var dayFilterContent: some View {
        DatePicker(
            "选择日期",
            selection: $selectedDay,
            in: selectableDateRange,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .frame(maxWidth: .infinity)
        .onChange(of: selectedDay) { _, newValue in
            apply(.specificDay(newValue))
        }
    }

    private var monthFilterContent: some View {
        VStack(spacing: AppTheme.spacing.lg) {
            Spacer(minLength: 0)

            HStack(spacing: AppTheme.spacing.md) {
                Picker("年份", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(.wheel)

                Picker("月份", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 188)
            .clipped()

            Button {
                apply(.specificMonth(selectedMonthDate))
            } label: {
                Label("查看 \(selectedYear)年\(selectedMonth)月", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .modifier(CompletedHistoryPrimaryGlassButtonModifier())
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
    }

    private var selectableDateRange: ClosedRange<Date> {
        let fallback = calendar.startOfDay(for: .now)
        let start = calendar.startOfDay(for: viewModel.completedStats.firstCompletedAt ?? fallback)
        let latestCompleted = viewModel.completedStats.lastCompletedAt ?? fallback
        let end = max(calendar.startOfDay(for: latestCompleted), fallback)
        return start...max(start, end)
    }

    private var availableYears: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        let firstYear = calendar.component(
            .year,
            from: viewModel.completedStats.firstCompletedAt ?? .now
        )
        let lastYear = calendar.component(
            .year,
            from: viewModel.completedStats.lastCompletedAt ?? .now
        )
        let years = [firstYear, lastYear, currentYear]
        let lower = years.min() ?? currentYear
        let upper = years.max() ?? currentYear
        return Array(lower...upper).reversed()
    }

    private var selectedMonthDate: Date {
        calendar.date(from: DateComponents(
            year: selectedYear,
            month: selectedMonth,
            day: 1
        )) ?? .now
    }

    private func apply(_ filter: CompletedHistoryFilter) {
        HomeInteractionFeedback.selection()
        onApply(filter)
    }

    private func normalizeMonthSelection() {
        guard availableYears.contains(selectedYear) == false,
              let firstYear = availableYears.first else {
            return
        }
        selectedYear = firstYear
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
                            .foregroundStyle(AppTheme.colors.title)
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
