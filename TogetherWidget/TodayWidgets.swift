import AppIntents
import SwiftUI
import WidgetKit

struct TodayOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TodayWidgetConstants.listWidgetKind,
            provider: TodayWidgetProvider()
        ) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("今日概览")
        .description("快速查看今日进度，并在中号或大号组件中完成任务。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

private struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: context.isPreview ? .placeholder : readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(TodayWidgetEntry(date: .now, snapshot: readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let snapshot = readSnapshot()
        let now = Date.now
        var entries = [TodayWidgetEntry(date: now, snapshot: snapshot)]

        if snapshot.animatingCompletionTaskIDs.isEmpty == false {
            let visibleBefore = Set(tasksVisibleInWidget(from: snapshot, family: context.family).map(\.id))
            let settledSnapshot = snapshot.removingAnimatingCompletionTasks()
            let visibleAfter = tasksVisibleInWidget(from: settledSnapshot, family: context.family)
            let appearingIDs = visibleAfter.map(\.id).filter { visibleBefore.contains($0) == false }

            if appearingIDs.isEmpty {
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(0.7), snapshot: settledSnapshot))
            } else {
                var appearingSnapshot = settledSnapshot
                appearingSnapshot.appearingTaskIDs = appearingIDs
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(0.7), snapshot: appearingSnapshot))
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(1.0), snapshot: settledSnapshot))
            }

            try? TodayWidgetSnapshotStore().write(settledSnapshot)
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    private func readSnapshot() -> TodayWidgetSnapshot {
        (try? TodayWidgetSnapshotStore().read()) ?? .empty
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var widgetContentMargins

    let entry: TodayWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumOverview
            case .systemLarge:
                largeOverview
            default:
                smallOverview
            }
        }
        .padding(contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var contentInsets: EdgeInsets {
        let minimum: CGFloat = family == .systemLarge ? 20 : 16
        return EdgeInsets(
            top: max(widgetContentMargins.top, minimum),
            leading: max(widgetContentMargins.leading, minimum),
            bottom: max(widgetContentMargins.bottom, minimum),
            trailing: max(widgetContentMargins.trailing, minimum)
        )
    }

    private var smallOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayWidgetHeader(snapshot: entry.snapshot, showsDate: false)

            HStack(spacing: 12) {
                TodayWidgetProgressRing(snapshot: entry.snapshot, diameter: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "已完成 \(entry.snapshot.completedTodayCount) / 共 \(entry.snapshot.totalTodayCount) 项")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(smallSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
            smallAttentionRow
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(smallAccessibilityLabel)
    }

    private var mediumOverview: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日")
                    .font(.headline)

                TodayWidgetProgressRing(snapshot: entry.snapshot, diameter: 58)

                Text(verbatim: "\(entry.snapshot.completedTodayCount) / \(entry.snapshot.totalTodayCount) 已完成")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(verbatim: "剩余 \(entry.snapshot.remainingCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 82, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if visibleTasks.isEmpty {
                    TodayWidgetClearedState(snapshot: entry.snapshot, compact: true)
                } else {
                    taskRows(visibleTasks)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var largeOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TodayWidgetHeader(snapshot: entry.snapshot, showsDate: true)
                Spacer(minLength: 8)
                TodayWidgetProgressRing(snapshot: entry.snapshot, diameter: 54)
            }

            HStack(spacing: 10) {
                TodayWidgetMetric(
                    title: "今日剩余",
                    value: entry.snapshot.remainingCount,
                    systemImage: "circle.dotted"
                )
                TodayWidgetMetric(
                    title: "逾期",
                    value: entry.snapshot.overdueCount,
                    systemImage: "exclamationmark.circle",
                    emphasizesValue: entry.snapshot.overdueCount > 0
                )
            }

            if visibleTasks.isEmpty {
                TodayWidgetClearedState(snapshot: entry.snapshot, compact: false)
            } else {
                ViewThatFits(in: .vertical) {
                    taskRows(Array(visibleTasks.prefix(6)))
                    taskRows(Array(visibleTasks.prefix(5)))
                    taskRows(Array(visibleTasks.prefix(4)))
                    taskRows(Array(visibleTasks.prefix(3)))
                }
            }
        }
    }

    private var visibleTasks: [TodayWidgetTaskSnapshot] {
        tasksVisibleInWidget(from: entry.snapshot, family: family)
    }

    private func taskRows(_ tasks: [TodayWidgetTaskSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TodayWidgetTaskRow(
                    task: task,
                    isCompleting: entry.snapshot.animatingCompletionTaskIDs.contains(task.id),
                    isAppearing: entry.snapshot.appearingTaskIDs.contains(task.id),
                    showsDivider: task.id != tasks.last?.id
                )
            }
        }
    }

    private var smallSummaryText: String {
        if entry.snapshot.remainingCount == 0 { return "今日已清空" }
        if entry.snapshot.overdueCount > 0 { return "含 \(entry.snapshot.overdueCount) 项逾期" }
        return "按计划推进中"
    }

    @ViewBuilder
    private var smallAttentionRow: some View {
        if let task = entry.snapshot.tasks.first {
            HStack(spacing: 6) {
                Image(systemName: task.isOverdue ? "exclamationmark.circle.fill" : "arrow.right.circle.fill")
                    .foregroundStyle(task.isOverdue ? Color.red : Color.accentColor)
                    .widgetAccentable()
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let dueTimeText = task.dueTimeText {
                    Text(dueTimeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                        .lineLimit(1)
                }
            }
        } else if let nextTask = entry.snapshot.nextUpcomingTask {
            VStack(alignment: .leading, spacing: 2) {
                Text("下一项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(nextTask.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let dueTimeText = nextTask.dueTimeText {
                        Text(dueTimeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            Label("今天没有待办事项", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var smallAccessibilityLabel: String {
        var parts = ["今日概览", "已完成 \(entry.snapshot.completedTodayCount) 项，共 \(entry.snapshot.totalTodayCount) 项"]
        if entry.snapshot.overdueCount > 0 {
            parts.append("逾期 \(entry.snapshot.overdueCount) 项")
        }
        if let task = entry.snapshot.tasks.first {
            parts.append("下一项，\(task.title)")
        }
        return parts.joined(separator: "，")
    }
}

private struct TodayWidgetHeader: View {
    let snapshot: TodayWidgetSnapshot
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今日概览")
                .font(.headline)
            if showsDate {
                Text(referenceDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var referenceDateText: String {
        snapshot.referenceDate.formatted(.dateTime.month().day().weekday(.wide))
    }
}

private struct TodayWidgetProgressRing: View {
    let snapshot: TodayWidgetSnapshot
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: snapshot.completionProgress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()

            if snapshot.totalTodayCount == 0 || snapshot.remainingCount == 0 {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            } else {
                Text(verbatim: "\(Int((snapshot.completionProgress * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel("今日完成进度")
        .accessibilityValue("百分之 \(Int((snapshot.completionProgress * 100).rounded()))")
    }
}

private struct TodayWidgetMetric: View {
    let title: String
    let value: Int
    let systemImage: String
    var emphasizesValue = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(emphasizesValue ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(value)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(emphasizesValue ? .red : .primary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) 项")
    }
}

private struct TodayWidgetTaskRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: TodayWidgetTaskSnapshot
    let isCompleting: Bool
    let isAppearing: Bool
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: TodayTaskCompletionIntent(taskID: task.id.uuidString)) {
                TodayWidgetCheckbox(isCompleting: isCompleting)
                    .frame(width: 24, height: 24)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成任务，\(task.title)")
            .accessibilityHint("在小组件中将任务标记为已完成")

            Link(destination: TodayWidgetConstants.taskDeepLink(taskID: task.id)) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 4)

                    if let dueTimeText = task.dueTimeText {
                        Text(dueTimeText)
                            .font(.caption.weight(task.isOverdue ? .semibold : .regular))
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(taskAccessibilityLabel)
        }
        .frame(minHeight: 44)
        .opacity(isAppearing ? 0 : 1)
        .offset(y: reduceMotion || isAppearing == false ? 0 : 5)
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: isAppearing)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    private var taskAccessibilityLabel: String {
        [task.title, task.dueTimeText].compactMap { $0 }.joined(separator: "，")
    }
}

private struct TodayWidgetCheckbox: View {
    let isCompleting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isCompleting ? Color.accentColor.opacity(0.18) : .clear)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isCompleting ? Color.accentColor : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: isCompleting ? [] : [3.5, 3.5])
                )
            if isCompleting {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            }
        }
    }
}

private struct TodayWidgetClearedState: View {
    let snapshot: TodayWidgetSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 5) {
            Spacer(minLength: 0)
            Label("今日已清空", systemImage: "checkmark.circle.fill")
                .font((compact ? Font.subheadline : .headline).weight(.semibold))
                .foregroundStyle(.secondary)

            if let nextTask = snapshot.nextUpcomingTask {
                Text(nextTaskText(nextTask))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(compact ? .leading : .center)
            } else {
                Text("享受当下，或规划新任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .center)
        .accessibilityElement(children: .combine)
    }

    private func nextTaskText(_ task: TodayWidgetTaskSnapshot) -> String {
        let schedule = task.dueTimeText.map { " · \($0)" } ?? ""
        return "下一项：\(task.title)\(schedule)"
    }
}

private func tasksVisibleInWidget(
    from snapshot: TodayWidgetSnapshot,
    family: WidgetFamily
) -> [TodayWidgetTaskSnapshot] {
    let limit = family == .systemLarge ? 6 : family == .systemMedium ? 3 : 0
    return Array(snapshot.tasks.prefix(limit))
}

private extension TodayWidgetSnapshot {
    func removingAnimatingCompletionTasks() -> TodayWidgetSnapshot {
        guard animatingCompletionTaskIDs.isEmpty == false else { return self }
        let completingIDs = Set(animatingCompletionTaskIDs)
        return TodayWidgetSnapshot(
            generatedAt: generatedAt,
            referenceDate: referenceDate,
            remainingCount: remainingCount,
            completedTodayCount: completedTodayCount,
            overdueCount: overdueCount,
            tasks: tasks.filter { completingIDs.contains($0.id) == false },
            nextUpcomingTask: nextUpcomingTask,
            animatingCompletionTaskIDs: [],
            appearingTaskIDs: []
        )
    }

    static var placeholder: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 3,
            completedTodayCount: 2,
            overdueCount: 1,
            tasks: [
                TodayWidgetTaskSnapshot(
                    id: UUID(),
                    title: "确认信用卡账单",
                    dueTimeText: "逾期",
                    sortIndex: 0,
                    isOverdue: true
                ),
                TodayWidgetTaskSnapshot(id: UUID(), title: "整理会议记录", dueTimeText: "14:30", sortIndex: 1),
                TodayWidgetTaskSnapshot(id: UUID(), title: "提交本周总结", dueTimeText: nil, sortIndex: 2)
            ],
            nextUpcomingTask: TodayWidgetTaskSnapshot(
                id: UUID(),
                title: "准备周会材料",
                dueTimeText: "明天 09:00",
                sortIndex: 0
            )
        )
    }
}
