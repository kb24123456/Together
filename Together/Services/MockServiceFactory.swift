import Foundation

enum MockServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        AppContainer(
            authService: MockAuthService(),
            relationshipService: MockRelationshipService(),
            itemRepository: MockItemRepository(),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: MockNotificationService()
        )
    }
}
