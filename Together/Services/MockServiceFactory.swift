import CloudKit
import Foundation
import SwiftData

enum MockServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        let syncCoordinator = NoOpSyncCoordinator()
        let itemRepository = MockItemRepository()
        let taskTemplateRepository = MockTaskTemplateRepository()
        let notificationService = MockNotificationService()
        let reminderScheduler = MockReminderScheduler()
        let mockModelContainer = try! ModelContainer(
            for: PersistentPairMembership.self, PersistentPairSpace.self, PersistentUserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
            reminderScheduler: reminderScheduler,
            syncCoordinator: syncCoordinator
        )

        let ckContainer = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
        let zoneManager = CloudKitZoneManager(container: ckContainer)
        let shareManager = CloudKitShareManager(container: ckContainer)

        return AppContainer(
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            taskApplicationService: taskApplicationService,
            quickCaptureParser: quickCaptureParser,
            syncCoordinator: syncCoordinator,
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
            cloudKitContainer: ckContainer,
            zoneManager: zoneManager,
            shareManager: shareManager,
            syncEngineCoordinator: SyncEngineCoordinator(
                ckContainer: ckContainer,
                modelContainer: mockModelContainer,
                healthMonitor: SyncHealthMonitor()
            )
        )
    }
}
