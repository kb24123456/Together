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
        let notificationService = LocalNotificationService()
        let reminderScheduler = LocalReminderScheduler(notificationService: notificationService)
        let syncCoordinator = LocalSyncCoordinator(container: modelContainer)
        let itemRepository = LocalItemRepository(container: modelContainer)
        let cloudGateway = SyncGatewayFactory.makeGateway(itemRepository: itemRepository)
        let remoteSyncApplier = LocalRemoteSyncApplier(itemRepository: itemRepository)
        let syncOrchestrator = DefaultSyncOrchestrator(
            syncCoordinator: syncCoordinator,
            cloudGateway: cloudGateway,
            remoteSyncApplier: remoteSyncApplier
        )
        let quickCaptureParser = RuleBasedQuickCaptureParser()
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: reminderScheduler
        )

        return AppContainer(
            authService: MockAuthService(),
            spaceService: LocalSpaceService(container: modelContainer),
            taskApplicationService: taskApplicationService,
            quickCaptureParser: quickCaptureParser,
            syncCoordinator: syncCoordinator,
            syncOrchestrator: syncOrchestrator,
            relationshipService: MockRelationshipService(),
            itemRepository: itemRepository,
            taskListRepository: LocalTaskListRepository(container: modelContainer),
            projectRepository: LocalProjectRepository(
                container: modelContainer,
                reminderScheduler: reminderScheduler
            ),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler
        )
    }
}
