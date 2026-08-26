import Foundation

enum ComposerRoute: String, Identifiable {
    case newTask
    case newPeriodicTask

    var id: String { rawValue }
}

enum ProfileRoute: Hashable {
    case editProfile
    case completedHistory
    case planningReview
    case accountDeletion
    case about
}
