import SwiftUI
import WidgetKit

@main
struct TogetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidgetPlaceholder()
    }
}

private struct TodayWidgetPlaceholder: Widget {
    let kind = "com.pigdog.Together.widgets.placeholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            Text("今日")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日")
        .description("查看今日任务。")
        .supportedFamilies([.systemSmall])
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .atEnd))
    }
}

private struct Entry: TimelineEntry {
    let date: Date
}
