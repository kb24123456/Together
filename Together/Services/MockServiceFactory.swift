import Foundation

enum MockServiceFactory {
    @MainActor
    static func makeContainer() -> AppContainer {
        let syncCoordinator = NoOpSyncCoordinator()
        let itemRepository = MockItemRepository()
        let taskTemplateRepository = MockTaskTemplateRepository()
        let notificationService = MockNotificationService()
        let reminderScheduler = MockReminderScheduler()
        let userProfileRepository = MockUserProfileRepository()
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
        let migrationPersistence: PersistenceController
        do {
            migrationPersistence = try PersistenceController(inMemory: true)
        } catch {
            preconditionFailure("[MockServiceFactory] In-memory persistence failed: \(error)")
        }
        return AppContainer(
            personalIdentityService: PersonalIdentityService(container: migrationPersistence.container),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: reminderScheduler),
            projectToTaskMigrationService: ProjectToTaskMigrationService(container: migrationPersistence.container),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            personalDataDeletionService: PersonalDataDeletionService(
                container: migrationPersistence.container,
                reminderScheduler: reminderScheduler
            ),
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            avatarUploader: MockAvatarStorageUploader(),
            userProfileRemote: MockUserProfileRemoteRepository()
        )
    }
}
