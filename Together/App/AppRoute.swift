import Foundation

enum ComposerRoute: String, Identifiable {
    case newTask
    case newProject
    case newPeriodicTask

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

enum RoutinesRoute: Hashable {
    case detail(UUID)
}

enum ProfileRoute: Hashable {
    case editProfile
    case editPairProfile
    case notificationSettings
    case completedHistory
    case futureCollaboration
}
