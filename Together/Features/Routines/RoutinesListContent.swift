import SwiftUI

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing.lg) {
                if !viewModel.weeklyTasks.isEmpty {
                    RoutinesCycleSection(cycle: .weekly, viewModel: viewModel)
                }

                if !viewModel.monthlyTasks.isEmpty {
                    RoutinesCycleSection(cycle: .monthly, viewModel: viewModel)
                }

                if !viewModel.quarterlyTasks.isEmpty {
                    RoutinesCycleSection(cycle: .quarterly, viewModel: viewModel)
                }

                if !viewModel.yearlyTasks.isEmpty {
                    RoutinesCycleSection(cycle: .yearly, viewModel: viewModel)
                }

                if viewModel.tasks.isEmpty && viewModel.loadState == .loaded {
                    EmptyStateCard(
                        title: "还没有例行事务",
                        message: "点击底部 + 按钮添加需要定期完成的事务"
                    )
                }
            }
            .padding(.horizontal, AppTheme.spacing.lg)
            .padding(.top, contentTopPadding)
            .padding(.bottom, contentBottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.colors.background)
        .sheet(isPresented: $viewModel.isEditorPresented) {
            RoutinesEditorSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.load()
        }
    }
}
