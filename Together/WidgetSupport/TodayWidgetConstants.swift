import Foundation

enum TodayWidgetConstants {
    static let appGroupIdentifier = "group.com.pigdog.Together"

    static let focusWidgetKind = "com.pigdog.Together.widgets.today-focus"
    static let listWidgetKind = "com.pigdog.Together.widgets.today-list"

    static let snapshotFileName = "today-widget-snapshot.json"

    static var todayDeepLink: URL {
        URL(string: "together://today")!
    }
}
