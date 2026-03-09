import Foundation

enum ComposerRoute: String, Identifiable {
    case newItem
    case newDecision

    var id: String { rawValue }
}

enum HomeRoute: Hashable {
    case itemDetail(UUID)
}

enum DecisionRoute: Hashable {
    case detail(UUID)
}

enum AnniversaryRoute: Hashable {
    case detail(UUID)
}

enum ProfileRoute: Hashable {
    case notificationSettings
    case bindingDetails
}
