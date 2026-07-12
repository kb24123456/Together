import Foundation

enum TodayWidgetConstants {
    nonisolated static let appGroupIdentifier = "group.com.pigdog.together.shared"

    nonisolated static let listWidgetKind = "com.pigdog.Together.widgets.today-list"
    nonisolated static let snapshotFileName = "today-widget-snapshot.json"

    nonisolated static var todayDeepLink: URL {
        URL(string: "together://today")!
    }

    nonisolated static var newTaskDeepLink: URL {
        URL(string: "together://new-task")!
    }

    nonisolated static func taskDeepLink(taskID: UUID) -> URL {
        URL(string: "together://task/\(taskID.uuidString)")!
    }
}
