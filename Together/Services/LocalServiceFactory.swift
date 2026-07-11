import Foundation

enum LocalServiceFactory {
    @MainActor
    static func makeContainer() throws -> AppContainer {
        StartupTrace.mark("LocalServiceFactory.makeContainer.begin")
        return makeContainer(persistence: try PersistenceController())
    }

    @MainActor
    static func makeContainer(
        persistence: PersistenceController
    ) -> AppContainer {
        StartupTrace.mark("LocalServiceFactory.makeContainer.withPersistence.begin")
        let modelContainer = persistence.container
        let notificationService = LocalNotificationService()
        let reminderScheduler = LocalReminderScheduler(notificationService: notificationService)
        let syncCoordinator = NoOpSyncCoordinator()
        let userProfileRepository = LocalUserProfileRepository(container: modelContainer)

        let itemRepository = LocalItemRepository(container: modelContainer, syncCoordinator: syncCoordinator)
        let taskTemplateRepository = LocalTaskTemplateRepository(container: modelContainer)
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: reminderScheduler
        )
        let periodicTaskRepository = LocalPeriodicTaskRepository(
            container: modelContainer,
            syncCoordinator: syncCoordinator
        )
        let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
            repository: periodicTaskRepository,
            reminderScheduler: reminderScheduler,
            syncCoordinator: syncCoordinator
        )

        let avatarUploader = AvatarStorageUploader()
        let userProfileRemote = UserProfileRemoteRepository()

        let container = AppContainer(
            personalIdentityService: PersonalIdentityService(container: modelContainer),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: LocalTaskListRepository(container: modelContainer, syncCoordinator: syncCoordinator),
            projectRepository: LocalProjectRepository(
                container: modelContainer,
                reminderScheduler: reminderScheduler,
                syncCoordinator: syncCoordinator
            ),
            projectToTaskMigrationService: ProjectToTaskMigrationService(container: modelContainer),
            decisionRepository: MockDecisionRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            avatarUploader: avatarUploader,
            userProfileRemote: userProfileRemote
        )
        StartupTrace.mark("LocalServiceFactory.makeContainer.end")
        return container
    }
}
