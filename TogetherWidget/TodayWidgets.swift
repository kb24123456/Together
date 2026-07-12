import AppIntents
import SwiftUI
import WidgetKit

/// Keep widget emphasis aligned with `AppTheme.colors.sky` in the main app.
/// Widget extensions do not link the app target's design-system source directly.
private enum TodayWidgetTheme {
    static let babyBlue = Color(red: 0.42, green: 0.70, blue: 0.98)
}

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
        .description("查看今日进度，并在中号或大号组件中完成任务。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var smallOverview: some View {
        ViewThatFits(in: .vertical) {
            smallOverviewContent(countSize: 48, verticalSpacing: 8)
            smallOverviewContent(countSize: 38, verticalSpacing: 3)
        }
    }

    private func smallOverviewContent(
        countSize: CGFloat,
        verticalSpacing: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("今天")
                    .font(.headline.weight(.semibold))

                Spacer(minLength: 8)
                TodayWidgetAddTaskLink()
            }

            Spacer(minLength: verticalSpacing)

            Text(verbatim: "\(entry.snapshot.remainingCount)")
                .font(.system(size: countSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())

            Text("项待办")
                .font(.subheadline.weight(.medium))

            Spacer(minLength: verticalSpacing)

            TodayWidgetLinearProgress(snapshot: entry.snapshot)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(smallAccessibilityLabel)
    }

    private var mediumOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayWidgetDashboardHeader(
                snapshot: entry.snapshot,
                title: "今天",
                showsDate: false
            )

            Divider()

            mediumContent
        }
    }

    @ViewBuilder
    private var mediumContent: some View {
        let tasks = Array(entry.snapshot.tasks.prefix(2))
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                TodayWidgetTaskRow(
                    task: task,
                    isCompleting: entry.snapshot.animatingCompletionTaskIDs.contains(task.id),
                    isAppearing: entry.snapshot.appearingTaskIDs.contains(task.id),
                    showsDivider: true
                )
            }

            if tasks.isEmpty {
                TodayWidgetClearedRow()
            }

            if tasks.count < 2, let nextTask = entry.snapshot.nextUpcomingTask {
                TodayWidgetUpcomingRow(task: nextTask)
            }
        }
    }

    private var largeOverview: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayWidgetDashboardHeader(
                snapshot: entry.snapshot,
                title: "今日看板",
                showsDate: true
            )

            Divider()

            ViewThatFits(in: .vertical) {
                largeBoard(rowLimit: 5)
                largeBoard(rowLimit: 4)
                largeBoard(rowLimit: 3)
            }
        }
    }

    private func largeBoard(rowLimit: Int) -> some View {
        let visibleTasks = Array(entry.snapshot.tasks.prefix(rowLimit))
        let overdueTasks = visibleTasks.filter(\.isOverdue)
        let todayTasks = visibleTasks.filter { $0.isOverdue == false }

        return VStack(spacing: 0) {
            if overdueTasks.isEmpty == false {
                TodayWidgetSectionHeader(
                    title: "逾期",
                    count: entry.snapshot.overdueCount,
                    isOverdue: true
                )
                taskRows(overdueTasks)
            }

            if todayTasks.isEmpty == false {
                TodayWidgetSectionHeader(
                    title: "今天",
                    count: max(0, entry.snapshot.remainingCount - entry.snapshot.overdueCount),
                    isOverdue: false
                )
                taskRows(todayTasks)
            }

            if visibleTasks.isEmpty {
                TodayWidgetClearedRow()
            }

            if visibleTasks.count < rowLimit,
               visibleTasks.count >= entry.snapshot.remainingCount,
               let nextTask = entry.snapshot.nextUpcomingTask {
                TodayWidgetUpcomingRow(task: nextTask)
            }
        }
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

    private var smallAccessibilityLabel: String {
        var parts = [
            "今天",
            "剩余 \(entry.snapshot.remainingCount) 项",
            "已完成 \(entry.snapshot.completedTodayCount) 项，共 \(entry.snapshot.totalTodayCount) 项"
        ]
        if entry.snapshot.overdueCount > 0 {
            parts.append("逾期 \(entry.snapshot.overdueCount) 项")
        }
        return parts.joined(separator: "，")
    }
}

private struct TodayWidgetDashboardHeader: View {
    let snapshot: TodayWidgetSnapshot
    let title: String
    let showsDate: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Text(showsDate ? referenceDateText : "还剩 \(snapshot.remainingCount) 项")
                    .font(.system(.caption, design: .rounded, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(snapshot.completedTodayCount) / \(snapshot.totalTodayCount)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(TodayWidgetTheme.babyBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if showsDate {
                    Text("已完成")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TodayWidgetAddTaskLink()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private var referenceDateText: String {
        snapshot.referenceDate.formatted(.dateTime.month().day().weekday(.wide))
    }
}

private struct TodayWidgetAddTaskLink: View {
    var body: some View {
        Link(destination: TodayWidgetConstants.newTaskDeepLink) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(TodayWidgetTheme.babyBlue)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建任务")
        .accessibilityHint("打开 Together 的任务创建页")
    }
}

private struct TodayWidgetLinearProgress: View {
    let snapshot: TodayWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "\(snapshot.completedTodayCount) / \(snapshot.totalTodayCount) 已完成")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: snapshot.completionProgress)
                .tint(TodayWidgetTheme.babyBlue)
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日完成进度")
        .accessibilityValue("已完成 \(snapshot.completedTodayCount) 项，共 \(snapshot.totalTodayCount) 项")
    }
}

private struct TodayWidgetSectionHeader: View {
    let title: String
    let count: Int
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isOverdue ? "exclamationmark.circle" : "calendar")
            Text(title)
            Text(verbatim: "\(count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isOverdue ? Color.red : TodayWidgetTheme.babyBlue)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(count) 项")
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
                    .frame(width: 22, height: 22)
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
                            .font(.system(.caption, design: .rounded, weight: task.isOverdue ? .semibold : .regular))
                            .monospacedDigit()
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
        .offset(y: reduceMotion || isAppearing == false ? 0 : 4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: isAppearing)
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isCompleting ? TodayWidgetTheme.babyBlue.opacity(0.16) : .clear)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isCompleting ? TodayWidgetTheme.babyBlue : Color.secondary.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.4, dash: isCompleting ? [] : [3.2, 3.2])
                )
            if isCompleting {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TodayWidgetTheme.babyBlue)
                    .widgetAccentable()
            }
        }
    }
}

private struct TodayWidgetUpcomingRow: View {
    let task: TodayWidgetTaskSnapshot

    var body: some View {
        Link(destination: TodayWidgetConstants.taskDeepLink(taskID: task.id)) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text("下一项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let dueTimeText = task.dueTimeText {
                    Text(dueTimeText)
                        .font(.system(.caption, design: .rounded, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nextTaskAccessibilityLabel)
    }

    private var nextTaskAccessibilityLabel: String {
        ["下一项", task.title, task.dueTimeText].compactMap { $0 }.joined(separator: "，")
    }
}

private struct TodayWidgetClearedRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TodayWidgetTheme.babyBlue)
                .widgetAccentable()
                .frame(width: 44, height: 44)
            Text("今日已清空")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private func tasksVisibleInWidget(
    from snapshot: TodayWidgetSnapshot,
    family: WidgetFamily
) -> [TodayWidgetTaskSnapshot] {
    let limit = family == .systemLarge ? 5 : family == .systemMedium ? 2 : 0
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
            remainingCount: 5,
            completedTodayCount: 3,
            overdueCount: 2,
            tasks: [
                TodayWidgetTaskSnapshot(
                    id: UUID(),
                    title: "小微闪续贷情况反馈",
                    dueTimeText: "逾期",
                    sortIndex: 0,
                    isOverdue: true
                ),
                TodayWidgetTaskSnapshot(
                    id: UUID(),
                    title: "培训班内容",
                    dueTimeText: "逾期",
                    sortIndex: 1,
                    isOverdue: true
                ),
                TodayWidgetTaskSnapshot(id: UUID(), title: "信用卡商户", dueTimeText: "14:00", sortIndex: 2),
                TodayWidgetTaskSnapshot(id: UUID(), title: "生意会对账发计财", dueTimeText: "16:30", sortIndex: 3),
                TodayWidgetTaskSnapshot(id: UUID(), title: "联系毛文君电商贷", dueTimeText: nil, sortIndex: 4)
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
