import Foundation

struct AppContainer {
    let authService: AuthServiceProtocol
    let spaceService: SpaceServiceProtocol
    let taskApplicationService: TaskApplicationServiceProtocol
    let syncCoordinator: SyncCoordinatorProtocol
    let syncOrchestrator: SyncOrchestratorProtocol
    let relationshipService: RelationshipServiceProtocol
    let itemRepository: ItemRepositoryProtocol
    let taskListRepository: TaskListRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol
    let decisionRepository: DecisionRepositoryProtocol
    let anniversaryRepository: AnniversaryRepositoryProtocol
    let notificationService: NotificationServiceProtocol
}
