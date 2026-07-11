import Foundation

enum TodayWidgetConstants {
    nonisolated static let appGroupIdentifier = "group.com.pigdog.together.shared"

    nonisolated static let focusWidgetKind = "com.pigdog.Together.widgets.today-focus"
    nonisolated static let listWidgetKind = "com.pigdog.Together.widgets.today-list"
    nonisolated static let snapshotFileName = "today-widget-snapshot.json"

    nonisolated static var todayDeepLink: URL {
        URL(string: "together://today")!
    }
}
