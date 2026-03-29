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
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.spacing.xl)
            .padding(.bottom, showsNavigationChrome ? AppTheme.spacing.xl : 164)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("日历")
        .toolbar(showsNavigationChrome ? .visible : .hidden, for: .navigationBar)
        .task {
            guard viewModel.loadState == .idle else { return }
            await viewModel.load()
        }
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
