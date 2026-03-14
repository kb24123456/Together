import Foundation

enum MockServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        let syncCoordinator = NoOpSyncCoordinator()
        let itemRepository = MockItemRepository()
        let cloudGateway = PlaceholderCloudSyncGateway()
        let remoteSyncApplier = LocalRemoteSyncApplier(itemRepository: itemRepository)
        let syncOrchestrator = DefaultSyncOrchestrator(
            syncCoordinator: syncCoordinator,
            cloudGateway: cloudGateway,
            remoteSyncApplier: remoteSyncApplier
        )
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )

        return AppContainer(
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            syncOrchestrator: syncOrchestrator,
            relationshipService: MockRelationshipService(),
            itemRepository: itemRepository,
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: MockNotificationService()
        )
    }
}
