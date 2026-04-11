import SwiftUI

struct RoutinesTaskRow: View {
    let task: PeriodicTask
    let viewModel: RoutinesViewModel

    private var isCompleted: Bool {
        viewModel.isCompleted(task)
    }

    private var urgency: PeriodicTaskUrgency {
        viewModel.urgencyState(task)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Button {
                Task {
                    await viewModel.toggleCompletion(taskID: task.id)
                }
            } label: {
                completionSymbol
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button {
                viewModel.presentDetail(for: task)
            } label: {
                HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(AppTheme.typography.sized(19, weight: .bold))
                            .foregroundStyle(isCompleted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)
                            .lineLimit(2)
                            .allowsTightening(true)

                        if !task.reminderRules.isEmpty {
                            Text(reminderDescription)
                                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                        }
                    }

                    Spacer(minLength: 0)

                    urgencyBadge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var completionSymbol: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isCompleted ? AppTheme.colors.success.opacity(0.58) : accentColor.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.6, dash: [3.6, 4.4])
                )
                .opacity(isCompleted ? 0 : 1)

            if isCompleted {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.colors.success.opacity(0.15))

                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(AppTheme.colors.success)
            }
        }
    }

    @ViewBuilder
    private var urgencyBadge: some View {
        switch urgency {
        case .pastReminder:
            Text("逾期")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.coral.opacity(0.12))
                )
        case .approaching:
            Text("临近")
                .font(AppTheme.typography.sized(12, weight: .bold))
                .foregroundStyle(AppTheme.colors.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.warning.opacity(0.12))
                )
        case .completed, .normal:
            EmptyView()
        }
    }

    private var accentColor: Color {
        switch urgency {
        case .pastReminder: AppTheme.colors.coral
        case .approaching: AppTheme.colors.warning
        default: AppTheme.colors.body
        }
    }

    private var reminderDescription: String {
        guard let rule = task.reminderRules.first else { return "" }
        let timeString = String(format: "%02d:%02d", rule.hour, rule.minute)
        switch rule.timing {
        case .dayOfPeriod(let day):
            return "第 \(day) 天 \(timeString) 提醒"
        case .businessDayOfPeriod(let day):
            return "第 \(day) 个工作日 \(timeString) 提醒"
        case .daysBeforeEnd(let days):
            return "截止前 \(days) 天 \(timeString) 提醒"
        }
    }
}
