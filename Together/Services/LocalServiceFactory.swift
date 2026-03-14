import Foundation

enum LocalServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        makeContainer(persistence: .shared)
    }

    @MainActor
    static func makeContainer(
        persistence: PersistenceController
    ) -> AppContainer {
        let modelContainer = persistence.container
        let syncCoordinator = LocalSyncCoordinator(container: modelContainer)
        let itemRepository = LocalItemRepository(container: modelContainer)
        let cloudGateway = SyncGatewayFactory.makeGateway(itemRepository: itemRepository)
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
            spaceService: LocalSpaceService(container: modelContainer),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            syncOrchestrator: syncOrchestrator,
            relationshipService: MockRelationshipService(),
            itemRepository: itemRepository,
            taskListRepository: LocalTaskListRepository(container: modelContainer),
            projectRepository: LocalProjectRepository(container: modelContainer),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: MockNotificationService()
        )
    }
}
