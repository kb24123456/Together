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
        HStack(spacing: AppTheme.spacing.sm) {
            completionToggle
            taskContent
            Spacer(minLength: 4)
            urgencyIndicator
        }
        .padding(.vertical, AppTheme.spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.presentEditor(for: task)
        }
    }

    private var completionToggle: some View {
        Button {
            Task {
                await viewModel.toggleCompletion(taskID: task.id)
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(isCompleted ? AppTheme.colors.success : AppTheme.colors.outlineStrong, lineWidth: 1.5)
                    .frame(width: 22, height: 22)

                if isCompleted {
                    Circle()
                        .fill(AppTheme.colors.success)
                        .frame(width: 22, height: 22)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var taskContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(isCompleted ? AppTheme.colors.textTertiary : AppTheme.colors.title)
                .strikethrough(isCompleted, color: AppTheme.colors.textTertiary)

            if !task.reminderRules.isEmpty {
                Text(reminderDescription)
                    .font(AppTheme.typography.textStyle(.caption1))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }
        }
        .opacity(isCompleted ? 0.6 : 1.0)
    }

    @ViewBuilder
    private var urgencyIndicator: some View {
        switch urgency {
        case .pastReminder:
            Circle()
                .fill(AppTheme.colors.coral)
                .frame(width: 8, height: 8)
        case .approaching:
            Circle()
                .fill(AppTheme.colors.warning)
                .frame(width: 8, height: 8)
        case .completed:
            EmptyView()
        case .normal:
            EmptyView()
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
