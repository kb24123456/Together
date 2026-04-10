import Foundation

enum LocalServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        StartupTrace.mark("LocalServiceFactory.makeContainer.begin")
        return makeContainer(persistence: .shared)
    }

    @MainActor
    static func makeContainer(
        persistence: PersistenceController
    ) -> AppContainer {
        StartupTrace.mark("LocalServiceFactory.makeContainer.withPersistence.begin")
        let modelContainer = persistence.container
        let notificationService = LocalNotificationService()
        let reminderScheduler = LocalReminderScheduler(notificationService: notificationService)
        let syncCoordinator = LocalSyncCoordinator(container: modelContainer)
        let userProfileRepository = LocalUserProfileRepository(container: modelContainer)
        let pairingService = LocalPairingService(container: modelContainer)
        let itemRepository = LocalItemRepository(container: modelContainer)
        let taskTemplateRepository = LocalTaskTemplateRepository(container: modelContainer)
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
        let periodicTaskRepository = LocalPeriodicTaskRepository(container: modelContainer)
        let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
            repository: periodicTaskRepository,
            reminderScheduler: reminderScheduler
        )

        let container = AppContainer(
            authService: MockAuthService(),
            spaceService: LocalSpaceService(container: modelContainer),
            taskApplicationService: taskApplicationService,
            quickCaptureParser: quickCaptureParser,
            syncCoordinator: syncCoordinator,
            syncOrchestrator: syncOrchestrator,
            pairingService: pairingService,
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: LocalTaskListRepository(container: modelContainer),
            projectRepository: LocalProjectRepository(
                container: modelContainer,
                reminderScheduler: reminderScheduler
            ),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService
        )
        StartupTrace.mark("LocalServiceFactory.makeContainer.end")
        return container
    }
}
