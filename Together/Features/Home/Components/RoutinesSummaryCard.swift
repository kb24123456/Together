import SwiftUI

struct RoutinesSummaryCard: View {
    let viewModel: RoutinesViewModel
    let onNavigateToRoutines: () -> Void

    @State private var isExpanded = false

    private var summary: [(PeriodicCycle, Int)] {
        viewModel.pendingSummary(referenceDate: viewModel.referenceDate)
    }

    var body: some View {
        if !summary.isEmpty {
            Button {
                onNavigateToRoutines()
            } label: {
                cardContent
            }
            .buttonStyle(.plain)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.accent)

                Text("例行事务")
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)

                Spacer()

                if summary.count > 1 {
                    expandToggle
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }

            summaryLines
        }
        .padding(AppTheme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.colors.outline)
        }
    }

    @ViewBuilder
    private var summaryLines: some View {
        let displayItems = isExpanded ? summary : Array(summary.prefix(1))

        VStack(alignment: .leading, spacing: 4) {
            ForEach(displayItems, id: \.0) { cycle, count in
                HStack(spacing: 6) {
                    Circle()
                        .fill(cycleColor(for: cycle))
                        .frame(width: 6, height: 6)

                    Text("\(cycle.currentPeriodPrefix)还有 \(count) 项未完成")
                        .font(AppTheme.typography.textStyle(.caption1))
                        .foregroundStyle(AppTheme.colors.body)
                }
            }
        }

        if !isExpanded && summary.count > 1 {
            Text("还有 \(summary.count - 1) 个周期")
                .font(AppTheme.typography.textStyle(.caption2))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
    }

    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .buttonStyle(.plain)
    }

    private func cycleColor(for cycle: PeriodicCycle) -> Color {
        switch cycle {
        case .weekly: AppTheme.colors.accent
        case .monthly: AppTheme.colors.sky
        case .quarterly: AppTheme.colors.violet
        case .yearly: AppTheme.colors.sun
        }
    }
}
