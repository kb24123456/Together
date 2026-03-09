import Foundation

struct AppContainer {
    let authService: AuthServiceProtocol
    let relationshipService: RelationshipServiceProtocol
    let itemRepository: ItemRepositoryProtocol
    let decisionRepository: DecisionRepositoryProtocol
    let anniversaryRepository: AnniversaryRepositoryProtocol
    let notificationService: NotificationServiceProtocol
}
