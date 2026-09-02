import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum TaskFollowWidgetTheme {
    // Keep every system-hosted follow surface aligned with the app's Baby blue.
    static let tint = Color(red: 0.42, green: 0.70, blue: 0.98)
}

struct TaskFollowLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskFollowActivityAttributes.self) { context in
            TaskFollowLockScreenView(state: context.state)
                .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("关注中")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TaskFollowWidgetTheme.tint)

                        Spacer(minLength: 0)

                        TaskFollowActivitySummaryLabel(state: context.state)
                    }
                    .frame(maxWidth: .infinity)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let task = context.state.primaryTask {
                        TaskFollowPrimaryTaskView(
                            task: task,
                            titleFont: .headline.weight(.semibold)
                        )
                    }
                }
            } compactLeading: {
                TaskFollowCompactLeadingLabel()
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
    let state: TaskFollowActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("关注中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskFollowWidgetTheme.tint)

                Spacer(minLength: 0)

                TaskFollowActivitySummaryLabel(state: state)
            }

            if let task = state.primaryTask {
                TaskFollowPrimaryTaskView(
                    task: task,
                    titleFont: .title3.weight(.semibold)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct TaskFollowPrimaryTaskView: View {
    let task: FollowedTaskSnapshot
    let titleFont: Font

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Link(destination: task.deepLink) {
                Text(task.displayTitle)
                    .font(titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开任务 \(task.displayTitle)")

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
        }
        .frame(minHeight: 44)
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
        .font(.caption.monospacedDigit().weight(.semibold))
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

private struct TaskFollowCompactLeadingLabel: View {
    var body: some View {
        if #available(iOSApplicationExtension 27.0, *) {
            TaskFollowCompactLeadingLabelIOS27()
        } else {
            label("关注中")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TaskFollowWidgetTheme.tint)
            .lineLimit(1)
    }
}

@available(iOSApplicationExtension 27.0, *)
private struct TaskFollowCompactLeadingLabelIOS27: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

    var body: some View {
        Text(isLimitedInWidth ? "关注" : "关注中")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TaskFollowWidgetTheme.tint)
            .lineLimit(1)
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
