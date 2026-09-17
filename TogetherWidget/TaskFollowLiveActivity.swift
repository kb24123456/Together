import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum TaskFollowWidgetTheme {
    // Base follow accent; light Lock Screen status text uses a darker variant.
    static let tint = Color(red: 0.42, green: 0.70, blue: 0.98)
}

struct TaskFollowLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskFollowActivityAttributes.self) { context in
            TaskFollowLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    TaskFollowTaskContentView(
                        state: context.state,
                        colorScheme: .dark,
                        mascotSize: 48,
                        titleFont: .callout.weight(.semibold)
                    )
                }
            } compactLeading: {
                TaskFollowMascotView(colorScheme: .dark)
                    .frame(width: 20, height: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("关注中")
            } compactTrailing: {
                TaskFollowCompactTrailingLabel(state: context.state)
            } minimal: {
                Text(verbatim: TaskFollowWidgetTheme.minimalCountText(context.state.totalFollowedCount))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(TaskFollowWidgetTheme.tint)
            }
            .keylineTint(TaskFollowWidgetTheme.tint)
            .widgetURL(context.state.primaryTask?.deepLink)
        }
    }
}

private struct TaskFollowLockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: TaskFollowActivityAttributes.ContentState

    var body: some View {
        TaskFollowTaskContentView(
            state: state,
            colorScheme: colorScheme,
            mascotSize: 56,
            titleFont: .headline.weight(.semibold)
        )
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 16)
        .activityBackgroundTint(colorScheme == .dark ? .black : .white)
        .widgetURL(state.primaryTask?.deepLink)
    }
}

/// Shared A composition: full sphere, task information, then an independent action.
private struct TaskFollowTaskContentView: View {
    let state: TaskFollowActivityAttributes.ContentState
    let colorScheme: ColorScheme
    let mascotSize: CGFloat
    let titleFont: Font

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TaskFollowMascotView(colorScheme: colorScheme)
                .frame(width: mascotSize, height: mascotSize)
                .accessibilityHidden(true)

            if let task = state.primaryTask {
                Link(destination: task.deepLink) {
                    VStack(alignment: .leading, spacing: 5) {
                        statusLabel

                        Text(task.displayTitle)
                            .font(titleFont)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)
                            .allowsTightening(true)
                            .foregroundStyle(.primary)

                        TaskFollowActivitySummaryLabel(state: state)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("打开任务详情")

                Button(intent: CompleteFollowedTaskIntent(taskID: task.taskID)) {
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 1.25)
                        .opacity(0.72)
                        .frame(width: 26, height: 26)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("完成 \(task.displayTitle)")
                .accessibilityHint("在实时活动中将任务标记为已完成")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    statusLabel
                    TaskFollowActivitySummaryLabel(state: state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: mascotSize)
        // Keep two-line titles within the system's bounded Live Activity surface.
        // VoiceOver still reads the complete task title and summary.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var statusLabel: some View {
        Text("关注中")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colorScheme == .dark
                ? TaskFollowWidgetTheme.tint
                : Color(red: 0.21, green: 0.37, blue: 0.49))
            .lineLimit(1)
    }
}

private struct TaskFollowActivitySummaryLabel: View {
    let state: TaskFollowActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let primaryTask = state.primaryTask {
                Text(verbatim: preferredText(for: primaryTask))
                    .fixedSize(horizontal: true, vertical: false)

                if let scheduleText = primaryTask.followScheduleText {
                    Text(verbatim: scheduleText)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Text(verbatim: "\(state.totalFollowedCount) 项")
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func preferredText(for task: FollowedTaskSnapshot) -> String {
        let additionalTaskCount = max(0, state.totalFollowedCount - 1)
        switch (task.followScheduleText, additionalTaskCount) {
        case let (schedule?, count) where count > 0:
            return "\(schedule) · 另有 \(count) 项"
        case let (schedule?, _):
            return schedule
        case let (nil, count) where count > 0:
            return "另有 \(count) 项"
        default:
            return "1 项"
        }
    }
}

private struct TaskFollowCompactTrailingLabel: View {
    let state: TaskFollowActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let scheduleText = state.primaryTask?.followScheduleText {
                Text(verbatim: scheduleText)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(verbatim: "\(state.totalFollowedCount)")
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
}

private extension TaskFollowWidgetTheme {
    static func minimalCountText(_ count: Int) -> String {
        count > 9 ? "9+" : "\(max(0, count))"
    }
}

private extension FollowedTaskSnapshot {
    var followScheduleText: String? {
        guard let dueAt else { return nil }
        if hasExplicitTime {
            return dueAt.formatted(
                .dateTime
                    .locale(Locale(identifier: "zh_CN"))
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
            )
        }
        if Calendar.current.isDateInToday(dueAt) { return "今天" }
        return dueAt.formatted(.dateTime.month(.defaultDigits).day())
    }
}
