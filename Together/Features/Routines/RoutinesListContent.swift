import SwiftUI

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat

    @Environment(AppContext.self) private var appContext

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
                    routinesEmptyState
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
        .task(id: appContext.sessionStore.activeMode) {
            await viewModel.reload()
        }
    }

    private var routinesEmptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppTheme.colors.accent.opacity(0.45))
                    .symbolEffect(.breathe.plain, options: .repeating)

                Text("还没有例行事务")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                Text("添加需要定期完成的事务")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.38))
            }

            Button {
                appContext.router.activeComposer = .newPeriodicTask
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))

                    Text("新建例行事务")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
