import SwiftUI

struct ListsView: View {
    @Bindable var viewModel: ListsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                CardSection(
                    title: viewModel.isPairModeActive ? "当前是共享清单视图" : "当前是个人清单视图",
                    subtitle: viewModel.spaceSummary
                ) {
                    Text(
                        viewModel.isPairModeActive
                        ? "这里展示的是双人空间下的清单数据，和单人模式完全隔离。"
                        : "这里展示的是单人空间下的清单数据。"
                    )
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CardSection(title: "系统清单", subtitle: "先把收集、Today 和即将到来分清") {
                    VStack(spacing: AppTheme.spacing.sm) {
                        ForEach(viewModel.systemLists) { list in
                            listRow(list)
                        }
                    }
                }

                CardSection(title: "自定义清单", subtitle: "后续在这里继续扩展标签、分组和批量整理") {
                    VStack(spacing: AppTheme.spacing.sm) {
                        if viewModel.customLists.isEmpty {
                            EmptyStateCard(title: "还没有自定义清单", message: "下一步会把新建、编辑和整理流程接进这里。")
                        } else {
                            ForEach(viewModel.customLists) { list in
                                listRow(list)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("清单")
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewModel.loadState == .idle else { return }
            await viewModel.load()
        }
    }

    private func listRow(_ list: TaskList) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            Circle()
                .fill(list.kind == .custom ? AppTheme.colors.secondaryAccent : AppTheme.colors.accent)
                .frame(width: 10, height: 10)

            Text(list.name)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)

            Spacer()

            Text("\(list.taskCount)")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
        }
        .padding(.vertical, 2)
    }
}
