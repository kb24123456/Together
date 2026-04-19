import CloudKit
import Foundation
import SwiftData

private struct NoopAnniversaryScheduler: AnniversaryNotificationSchedulerProtocol {
    func refresh(spaceID: UUID, partnerName: String?, myName: String?, myUserID: UUID?) async {}
}

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
            taskMessageRepository: MockTaskMessageRepository(),
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
            taskMessageRepository: LocalTaskMessageRepository(container: mockModelContainer),
            importantDateRepository: MockImportantDateRepository(),
            anniversaryScheduler: NoopAnniversaryScheduler(),
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: reminderScheduler),
            decisionRepository: MockDecisionRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            avatarUploader: MockAvatarStorageUploader(),
            cloudKitContainer: ckContainer,
            syncEngineCoordinator: SyncEngineCoordinator(
                ckContainer: ckContainer,
                modelContainer: mockModelContainer,
                healthMonitor: SyncHealthMonitor()
            )
        )
    }
}
