import SwiftUI

struct RoutinesTaskRow: View {
    let task: PeriodicTask
    let viewModel: RoutinesViewModel

    @State private var isAnimatingCompletion = false
    @State private var completionAnimationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var badgeFillScale: CGFloat = 1
    @State private var badgeFillOpacity: CGFloat = 0

    private var isCompleted: Bool {
        viewModel.isCompleted(task)
    }

    private var urgency: PeriodicTaskUrgency {
        viewModel.urgencyState(task)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Button {
                HomeInteractionFeedback.completion()
                Task {
                    await viewModel.toggleCompletion(taskID: task.id)
                }
            } label: {
                completionBadge
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onChange(of: isCompleted) { _, newValue in
                guard newValue else { return }
                triggerCompletionAnimation()
            }

            Button {
                HomeInteractionFeedback.selection()
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

    // MARK: - Animated Completion Badge (matches Today list style)

    private var completionBadge: some View {
        ZStack {
            // Fill flash on completion
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(badgeFillScale)
                .opacity(isCompleted ? 0 : badgeFillOpacity)

            // Dashed ring
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: isAnimatingCompletion ? 1.8 : 1.6, dash: [3.6, 4.4])
                )
                .opacity(isCompleted ? 0 : 1)

            // Checkmark
            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(17, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.15), value: completionAnimationCount)
                .opacity(isCompleted ? 1 : 0)
        }
        .scaleEffect(isAnimatingCompletion ? badgeScale : 1)
        .shadow(
            color: AppTheme.colors.coral.opacity(isAnimatingCompletion ? 0.2 : 0),
            radius: isAnimatingCompletion ? 12 : 0,
            y: isAnimatingCompletion ? 5 : 0
        )
    }

    private var ringColor: Color {
        if isAnimatingCompletion {
            return AppTheme.colors.body.opacity(0.32)
        }
        switch urgency {
        case .pastReminder: return AppTheme.colors.coral.opacity(0.58)
        case .approaching:  return AppTheme.colors.warning.opacity(0.58)
        default:            return AppTheme.colors.body.opacity(0.44)
        }
    }

    private func triggerCompletionAnimation() {
        completionAnimationCount += 1
        isAnimatingCompletion = true
        badgeScale = 1
        badgeFillScale = 1
        badgeFillOpacity = 0

        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            badgeScale = 1.22
            badgeFillScale = 1.4
            badgeFillOpacity = 1
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52).delay(0.1)) {
            badgeScale = 1
            badgeFillOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isAnimatingCompletion = false
            badgeFillScale = 1
        }
    }

    // MARK: - Urgency Badge

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
