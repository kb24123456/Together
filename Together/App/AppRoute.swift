import Foundation

enum ComposerRoute: String, Identifiable {
    case newTask
    case newProject

    var id: String { rawValue }
}

enum TodayRoute: Hashable {
    case itemDetail(UUID)
}

enum ListRoute: Hashable {
    case detail(UUID)
}

enum ProjectRoute: Hashable {
    case detail(UUID)
}

enum CalendarRoute: Hashable {
    case detail(Date)
}

enum ProfileRoute: Hashable {
    case notificationSettings
    case completedHistory
    case futureCollaboration
}
