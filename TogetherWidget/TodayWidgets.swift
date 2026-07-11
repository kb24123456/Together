import AppIntents
import SwiftUI
import WidgetKit

struct TodayFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetConstants.focusWidgetKind, provider: TodayWidgetProvider(mode: .focus)) { entry in
            TodayWidgetView(entry: entry, mode: .focus)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("今日重点")
        .description("查看并完成今日优先任务。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct TodayListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayWidgetConstants.listWidgetKind, provider: TodayWidgetProvider(mode: .list)) { entry in
            TodayWidgetView(entry: entry, mode: .list)
                .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
        .configurationDisplayName("今日清单")
        .description("查看并完成今日任务。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

private enum TodayWidgetMode {
    case focus
    case list

    func visibleTasks(from snapshot: TodayWidgetSnapshot, family: WidgetFamily) -> [TodayWidgetTaskSnapshot] {
        switch self {
        case .focus:
            return Array(snapshot.tasks.prefix(1))
        case .list:
            return Array(snapshot.tasks.prefix(family == .systemLarge ? 6 : 3))
        }
    }
}

private struct TodayWidgetProvider: TimelineProvider {
    let mode: TodayWidgetMode

    init(mode: TodayWidgetMode) {
        self.mode = mode
    }

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
            let visibleBefore = Set(mode.visibleTasks(from: snapshot, family: context.family).map(\.id))
            let settledSnapshot = snapshot.removingAnimatingCompletionTasks()
            let visibleAfter = mode.visibleTasks(from: settledSnapshot, family: context.family)
            let appearingIDs = visibleAfter.map(\.id).filter { visibleBefore.contains($0) == false }

            if appearingIDs.isEmpty {
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(0.85), snapshot: settledSnapshot))
            } else {
                var appearingSnapshot = settledSnapshot
                appearingSnapshot.appearingTaskIDs = appearingIDs
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(0.85), snapshot: appearingSnapshot))
                entries.append(TodayWidgetEntry(date: now.addingTimeInterval(1.15), snapshot: settledSnapshot))
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
    @Environment(\.colorScheme) private var colorScheme

    let entry: TodayWidgetEntry
    let mode: TodayWidgetMode

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            header

            if shouldShowEmptyState {
                emptyState
            } else if mode == .focus {
                focusTask
            } else {
                taskList
            }
        }
        .padding(contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            WidgetTheme.todayBackground(for: colorScheme)
        }
    }

    private var contentInsets: EdgeInsets {
        let minimum: CGFloat = switch family {
        case .systemSmall: 18
        case .systemMedium: 20
        case .systemLarge: 24
        default: 18
        }

        return EdgeInsets(
            top: max(widgetContentMargins.top, minimum),
            leading: max(widgetContentMargins.leading, minimum),
            bottom: max(widgetContentMargins.bottom, minimum),
            trailing: max(widgetContentMargins.trailing, minimum)
        )
    }

    private var header: some View {
        HStack(alignment: family == .systemLarge ? .top : .firstTextBaseline) {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 0) {
                Text(mode == .focus ? "今日重点" : "今日")
                    .font(.system(size: family == .systemLarge ? 28 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if family == .systemLarge {
                    Text(referenceDateText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text("还剩 \(entry.snapshot.remainingCount) 项")
                .font(.system(size: family == .systemLarge ? 15 : 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.top, family == .systemLarge ? 6 : 0)
        }
    }

    private var headerSpacing: CGFloat {
        switch family {
        case .systemLarge: 18
        case .systemMedium: 12
        default: 8
        }
    }

    private var referenceDateText: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: entry.snapshot.referenceDate)
        let day = calendar.component(.day, from: entry.snapshot.referenceDate)
        let weekday = calendar.component(.weekday, from: entry.snapshot.referenceDate)
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayText = symbols[max(0, min(weekday - 1, symbols.count - 1))]
        return "\(month)月\(day)日 周\(weekdayText)"
    }

    private var shouldShowEmptyState: Bool {
        entry.snapshot.animatingCompletionTaskIDs.isEmpty
        && (entry.snapshot.remainingCount == 0 || entry.snapshot.tasks.isEmpty)
    }

    @ViewBuilder
    private var focusTask: some View {
        if let task = mode.visibleTasks(from: entry.snapshot, family: family).first {
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 10) {
                    Button(intent: TodayTaskCompletionIntent(taskID: task.id.uuidString)) {
                        TodayWidgetCheckbox(isCompleting: entry.snapshot.animatingCompletionTaskIDs.contains(task.id))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)

                    Link(destination: TodayWidgetConstants.taskDeepLink(taskID: task.id)) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(task.title)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .minimumScaleFactor(0.78)

                            if let dueTimeText = task.dueTimeText {
                                Text(dueTimeText)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var taskList: some View {
        let visibleTasks = mode.visibleTasks(from: entry.snapshot, family: family)
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 0 : family == .systemMedium ? 8 : 5) {
            ForEach(visibleTasks) { task in
                TodayWidgetTaskRow(
                    task: task,
                    isCompleting: entry.snapshot.animatingCompletionTaskIDs.contains(task.id),
                    isAppearing: entry.snapshot.appearingTaskIDs.contains(task.id)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
                .overlay(alignment: .bottom) {
                    if family == .systemLarge, task.id != visibleTasks.last?.id {
                        Divider()
                            .overlay(WidgetTheme.divider(for: colorScheme))
                            .padding(.leading, 38)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: visibleTasks.map(\.id))
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: family == .systemMedium ? 5 : 3) {
            Spacer(minLength: 0)

            emptyCalendarImage

            Text("今天没有待办事项")
                .font(.system(size: family == .systemMedium ? 15 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("享受当下，或规划新任务")
                .font(.system(size: family == .systemMedium ? 11 : 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var emptyCalendarImage: some View {
        if colorScheme == .dark {
            Image("EmptyCalendar")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary.opacity(0.72))
                .frame(
                    width: family == .systemMedium ? 74 : 58,
                    height: family == .systemMedium ? 54 : 42
                )
                .accessibilityHidden(true)
        } else {
            Image("EmptyCalendar")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: family == .systemMedium ? 74 : 58,
                    height: family == .systemMedium ? 54 : 42
                )
                .accessibilityHidden(true)
        }
    }
}

private struct TodayWidgetTaskRow: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let task: TodayWidgetTaskSnapshot
    let isCompleting: Bool
    let isAppearing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: TodayTaskCompletionIntent(taskID: task.id.uuidString)) {
                TodayWidgetCheckbox(isCompleting: isCompleting)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)

            Link(destination: TodayWidgetConstants.taskDeepLink(taskID: task.id)) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 4)

                    if let dueTimeText = task.dueTimeText {
                        Text(dueTimeText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(height: rowHeight)
        .opacity(isAppearing ? 0 : 1)
        .offset(y: isAppearing ? 6 : 0)
        .animation(.snappy(duration: 0.28, extraBounce: 0.06), value: isAppearing)
    }

    private var rowHeight: CGFloat {
        family == .systemLarge ? 40 : 32
    }
}

private struct TodayWidgetCheckbox: View {
    @Environment(\.colorScheme) private var colorScheme

    let isCompleting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(WidgetTheme.accentFill(for: colorScheme, opacity: isCompleting ? 0.22 : 0))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    WidgetTheme.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.74 : 0.58),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3.6, 4.4])
                )

            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.18), value: isCompleting)
                .opacity(isCompleting ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.bouncy(duration: 0.42, extraBounce: 0.16), value: isCompleting)
    }
}

private extension TodayWidgetSnapshot {
    func removingAnimatingCompletionTasks() -> TodayWidgetSnapshot {
        guard animatingCompletionTaskIDs.isEmpty == false else { return self }
        let completingIDs = Set(animatingCompletionTaskIDs)
        return TodayWidgetSnapshot(
            generatedAt: generatedAt,
            referenceDate: referenceDate,
            remainingCount: remainingCount,
            tasks: tasks.filter { completingIDs.contains($0.id) == false },
            animatingCompletionTaskIDs: [],
            appearingTaskIDs: []
        )
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
