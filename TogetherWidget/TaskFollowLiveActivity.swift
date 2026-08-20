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
                DynamicIslandExpandedRegion(.leading) {
                    Label("关注", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TaskFollowWidgetTheme.tint)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: "\(context.state.totalFollowedCount) 项")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        ForEach(Array(context.state.visibleTasks.enumerated()), id: \.element.taskID) { index, task in
                            TaskFollowActivityRow(task: task, isPrimary: index == 0)
                        }

                        if context.state.remainingCount > 0 {
                            Text(verbatim: "+\(context.state.remainingCount) 项")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 38)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "scope")
                    .foregroundStyle(TaskFollowWidgetTheme.tint)
            } compactTrailing: {
                ViewThatFits(in: .horizontal) {
                    Text(compactTitle(for: context.state.primaryTask))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(verbatim: "\(context.state.totalFollowedCount)")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
            } minimal: {
                HStack(spacing: 1) {
                    Image(systemName: "scope")
                    Text(verbatim: "\(context.state.totalFollowedCount)")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(TaskFollowWidgetTheme.tint)
            }
            .keylineTint(TaskFollowWidgetTheme.tint)
            .widgetURL(context.state.primaryTask?.deepLink)
        }
    }

    private func compactTitle(for task: FollowedTaskSnapshot?) -> String {
        guard let task else { return "关注" }
        return String(task.displayTitle.prefix(6))
    }
}

private struct TaskFollowLockScreenView: View {
    let state: TaskFollowActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .foregroundStyle(TaskFollowWidgetTheme.tint)
                Text("关注")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: "\(state.totalFollowedCount) 项")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 24)

            Divider()

            ForEach(Array(state.visibleTasks.enumerated()), id: \.element.taskID) { index, task in
                TaskFollowActivityRow(task: task, isPrimary: index == 0)
            }

            if state.remainingCount > 0 {
                Text(verbatim: "+\(state.remainingCount) 项")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct TaskFollowActivityRow: View {
    let task: FollowedTaskSnapshot
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: CompleteFollowedTaskIntent(taskID: task.taskID)) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(TaskFollowWidgetTheme.tint.opacity(0.62), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成 \(task.displayTitle)")

            Link(destination: task.deepLink) {
                HStack(spacing: 8) {
                    Text(task.displayTitle)
                        .font(.caption.weight(isPrimary ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)

                    if let scheduleText {
                        Text(scheduleText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开任务 \(task.displayTitle)")
        }
        .frame(height: 38)
    }

    private var scheduleText: String? {
        guard let dueAt = task.dueAt else { return nil }
        if task.hasExplicitTime {
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
