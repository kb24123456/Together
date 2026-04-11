import CloudKit
import Foundation

enum MockServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        let syncCoordinator = NoOpSyncCoordinator()
        let itemRepository = MockItemRepository()
        let taskTemplateRepository = MockTaskTemplateRepository()
        let notificationService = MockNotificationService()
        let reminderScheduler = MockReminderScheduler()
        let placeholderGateway = PlaceholderCloudSyncGateway()
        let cloudGateway = SyncGatewayFactory.makeGateway(itemRepository: itemRepository)
        let remoteSyncApplier = LocalRemoteSyncApplier(itemRepository: itemRepository)
        let syncOrchestrator = DefaultSyncOrchestrator(
            syncCoordinator: syncCoordinator,
            cloudGateway: placeholderGateway,
            remoteSyncApplier: remoteSyncApplier
        )
        let userProfileRepository = MockUserProfileRepository()
        let quickCaptureParser = RuleBasedQuickCaptureParser()
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: reminderScheduler
        )
        let periodicTaskRepository = MockPeriodicTaskRepository()
        let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
            repository: periodicTaskRepository,
            reminderScheduler: reminderScheduler
        )

        let ckContainer = SyncGatewayFactory.makeContainer()
        let zoneManager = CloudKitZoneManager(container: ckContainer)
        let shareManager = CloudKitShareManager(container: ckContainer)
        let subscriptionManager = CloudKitSubscriptionManager(container: ckContainer)

        return AppContainer(
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            taskApplicationService: taskApplicationService,
            quickCaptureParser: quickCaptureParser,
            syncCoordinator: syncCoordinator,
            syncOrchestrator: syncOrchestrator,
            pairingService: MockRelationshipService(),
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: reminderScheduler),
            decisionRepository: MockDecisionRepository(),
            anniversaryRepository: MockAnniversaryRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            syncScheduler: SyncScheduler(syncOrchestrator: syncOrchestrator),
            cloudKitContainer: ckContainer,
            zoneManager: zoneManager,
            shareManager: shareManager,
            subscriptionManager: subscriptionManager,
            cloudGateway: cloudGateway
        )
    }
}
