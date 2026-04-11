import CloudKit
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
        let localPairingService = LocalPairingService(container: modelContainer)

        // CloudKit container & managers
        let ckContainer = SyncGatewayFactory.makeContainer()
        let zoneManager = CloudKitZoneManager(container: ckContainer)
        let shareManager = CloudKitShareManager(container: ckContainer)
        let subscriptionManager = CloudKitSubscriptionManager(container: ckContainer)

        let inviteGateway = CloudKitInviteGateway(
            containerIdentifier: CloudKitSyncConfiguration.defaultContainerIdentifier
        )
        let pairingService = CloudPairingService(
            localPairing: localPairingService,
            inviteGateway: inviteGateway,
            zoneManager: zoneManager,
            shareManager: shareManager,
            container: ckContainer
        )

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

        let syncScheduler = SyncScheduler(syncOrchestrator: syncOrchestrator)

        let container = AppContainer(
            authService: AppleAuthService(container: modelContainer),
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
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            syncScheduler: syncScheduler,
            cloudKitContainer: ckContainer,
            zoneManager: zoneManager,
            shareManager: shareManager,
            subscriptionManager: subscriptionManager,
            cloudGateway: cloudGateway
        )
        StartupTrace.mark("LocalServiceFactory.makeContainer.end")
        return container
    }
}
