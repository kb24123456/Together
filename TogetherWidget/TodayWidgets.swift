import AppIntents
import SwiftUI
import WidgetKit

struct TodayFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetConstants.focusWidgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(entry: entry, mode: .focus)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("今日重点")
        .description("查看并完成今日优先任务。")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetConstants.listWidgetKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetView(entry: entry, mode: .list)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("今日清单")
        .description("查看并完成今日任务。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(TodayWidgetEntry(date: .now, snapshot: readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let entry = TodayWidgetEntry(date: .now, snapshot: readSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(15 * 60))))
    }

    private func readSnapshot() -> TodayWidgetSnapshot {
        (try? TodayWidgetSnapshotStore().read()) ?? .empty
    }
}

private enum TodayWidgetMode {
    case focus
    case list

    func visibleTasks(from snapshot: TodayWidgetSnapshot, family: WidgetFamily) -> [TodayWidgetTaskSnapshot] {
        switch self {
        case .focus:
            return Array(snapshot.tasks.prefix(1))
        case .list:
            return Array(snapshot.tasks.prefix(family == .systemMedium ? 3 : 3))
        }
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodayWidgetEntry
    let mode: TodayWidgetMode

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 12 : 8) {
            header

            if entry.snapshot.remainingCount == 0 || entry.snapshot.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.95),
                    Color(red: 0.98, green: 0.96, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今日")
                .font(.system(size: family == .systemMedium ? 17 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("还剩 \(entry.snapshot.remainingCount) 项")
                .font(.system(size: family == .systemMedium ? 13 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 8 : 5) {
            ForEach(mode.visibleTasks(from: entry.snapshot, family: family)) { task in
                TodayWidgetTaskRow(task: task, compact: family == .systemSmall)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: family == .systemMedium ? 28 : 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.92, green: 0.36, blue: 0.31))

            Text("今日已清空")
                .font(.system(size: family == .systemMedium ? 18 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("去 App 看看接下来做什么")
                .font(.system(size: family == .systemMedium ? 12 : 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
    }
}

private struct TodayWidgetTaskRow: View {
    let task: TodayWidgetTaskSnapshot
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Button(intent: TodayTaskCompletionIntent(taskID: task.id.uuidString)) {
                TodayWidgetCheckbox()
            }
            .buttonStyle(.plain)
            .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)

            Text(task.title)
                .font(.system(size: compact ? 12 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 4)

            if let dueTimeText = task.dueTimeText {
                Text(dueTimeText)
                    .font(.system(size: compact ? 10 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.92, green: 0.36, blue: 0.31))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(height: compact ? 27 : 32)
    }
}

private struct TodayWidgetCheckbox: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.92, green: 0.36, blue: 0.31).opacity(0.12))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    Color(red: 0.92, green: 0.36, blue: 0.31).opacity(0.58),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3.6, 4.4])
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private extension TodayWidgetSnapshot {
    static var placeholder: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 3,
            tasks: [
                TodayWidgetTaskSnapshot(id: UUID(), title: "买周末早餐", dueTimeText: "09:30", sortIndex: 0),
                TodayWidgetTaskSnapshot(id: UUID(), title: "确认晚餐菜单", dueTimeText: nil, sortIndex: 1),
                TodayWidgetTaskSnapshot(id: UUID(), title: "给花浇水", dueTimeText: "20:00", sortIndex: 2)
            ]
        )
    }
}
