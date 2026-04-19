import SwiftUI

struct RoutinesCycleSection: View {
    let cycle: PeriodicCycle
    let viewModel: RoutinesViewModel

    @State private var isExpanded = true

    private var cycleTasks: [PeriodicTask] {
        switch cycle {
        case .weekly: viewModel.weeklyTasks
        case .monthly: viewModel.monthlyTasks
        case .quarterly: viewModel.quarterlyTasks
        case .yearly: viewModel.yearlyTasks
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            sectionHeader
            periodProgressBar

            if isExpanded {
                VStack(spacing: 0) {
                    let sortedTasks = cycleTasks.sorted { lhs, rhs in
                        let lhsCompleted = viewModel.isCompleted(lhs)
                        let rhsCompleted = viewModel.isCompleted(rhs)
                        if lhsCompleted != rhsCompleted { return !lhsCompleted }
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    ForEach(sortedTasks) { task in
                        RoutinesTaskRow(task: task, viewModel: viewModel)

                        if task.id != sortedTasks.last?.id {
                            Divider()
                                .foregroundStyle(AppTheme.colors.separator)
                                .padding(.leading, AppTheme.spacing.xxl)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        }
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(cycle.title)
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)

                    HStack(spacing: AppTheme.spacing.sm) {
                        Text(viewModel.sectionSummary(for: cycle))
                            .font(AppTheme.typography.textStyle(.caption1))
                            .foregroundStyle(AppTheme.colors.body)

                        Text("·")
                            .foregroundStyle(AppTheme.colors.textTertiary)

                        Text("还剩 \(viewModel.daysRemaining(for: cycle)) 天")
                            .font(AppTheme.typography.textStyle(.caption1))
                            .foregroundStyle(AppTheme.colors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
    }

    private var periodProgressBar: some View {
        GeometryReader { proxy in
            let progress = viewModel.periodProgress(for: cycle)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2) // 4pt progress bar — tiny radius intentional
                    .fill(AppTheme.colors.outline)
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2) // 4pt progress bar — tiny radius intentional
                    .fill(AppTheme.colors.coral)
                    .frame(width: proxy.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }


}
