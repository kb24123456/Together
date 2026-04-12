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
        let ckContainer = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
        let zoneManager = CloudKitZoneManager(container: ckContainer)
        let shareManager = CloudKitShareManager(container: ckContainer)

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
        let quickCaptureParser = RuleBasedQuickCaptureParser()
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: reminderScheduler
        )
        let periodicTaskRepository = LocalPeriodicTaskRepository(container: modelContainer)
        let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
            repository: periodicTaskRepository,
            reminderScheduler: reminderScheduler,
            syncCoordinator: syncCoordinator
        )

        // CKSyncEngine coordinator (private DB multi-device sync + shared authority data plane)
        let healthMonitor = SyncHealthMonitor()
        let syncEngineCoordinator = SyncEngineCoordinator(
            ckContainer: ckContainer,
            modelContainer: modelContainer,
            healthMonitor: healthMonitor
        )

        let container = AppContainer(
            authService: AppleAuthService(container: modelContainer),
            spaceService: LocalSpaceService(container: modelContainer),
            taskApplicationService: taskApplicationService,
            quickCaptureParser: quickCaptureParser,
            syncCoordinator: syncCoordinator,
            pairingService: pairingService,
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: LocalTaskListRepository(container: modelContainer, syncCoordinator: syncCoordinator),
            projectRepository: LocalProjectRepository(
                container: modelContainer,
                reminderScheduler: reminderScheduler,
                syncCoordinator: syncCoordinator
            ),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            cloudKitContainer: ckContainer,
            zoneManager: zoneManager,
            shareManager: shareManager,
            syncEngineCoordinator: syncEngineCoordinator
        )
        StartupTrace.mark("LocalServiceFactory.makeContainer.end")
        return container
    }
}
