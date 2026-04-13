import SwiftUI

struct RoutinesSummaryCard: View {
    let viewModel: RoutinesViewModel
    let onNavigateToRoutines: () -> Void

    private var summary: [(PeriodicCycle, Int)] {
        viewModel.pendingSummary(referenceDate: viewModel.referenceDate)
    }

    private var totalPending: Int {
        summary.reduce(0) { $0 + $1.1 }
    }

    var body: some View {
        if !summary.isEmpty {
            Button {
                onNavigateToRoutines()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack")
                        .font(AppTheme.typography.sized(16, weight: .semibold))

                    Text("\(totalPending) 项例行事务待完成")
                        .font(AppTheme.typography.sized(14, weight: .semibold))

                    Spacer(minLength: 0)

                    Text("查看全部")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.sky.opacity(0.8))
                }
                .foregroundStyle(AppTheme.colors.sky)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.sky.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
