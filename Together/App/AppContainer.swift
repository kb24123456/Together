import Foundation

struct AppContainer {
    let personalIdentityService: PersonalIdentityService
    let taskApplicationService: TaskApplicationServiceProtocol
    let syncCoordinator: SyncCoordinatorProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let itemRepository: ItemRepositoryProtocol
    let taskTemplateRepository: TaskTemplateRepositoryProtocol
    let taskListRepository: TaskListRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol
    let projectToTaskMigrationService: ProjectToTaskMigrationService
    let decisionRepository: DecisionRepositoryProtocol
    let notificationService: NotificationServiceProtocol
    let reminderScheduler: ReminderSchedulerProtocol
    let periodicTaskRepository: PeriodicTaskRepositoryProtocol
    let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    let biometricAuthService: BiometricAuthServiceProtocol
    let avatarUploader: AvatarStorageUploaderProtocol
    let userProfileRemote: UserProfileRemoteRepositoryProtocol
}
