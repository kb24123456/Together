import Foundation

struct AppContainer {
    let personalIdentityService: PersonalIdentityService
    let taskApplicationService: TaskApplicationServiceProtocol
    let syncCoordinator: SyncCoordinatorProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let itemRepository: ItemRepositoryProtocol
    let taskListRepository: TaskListRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol
    let projectToTaskMigrationService: ProjectToTaskMigrationService
    let notificationService: NotificationServiceProtocol
    let reminderScheduler: ReminderSchedulerProtocol
    let personalDataDeletionService: PersonalDataDeletionService
    let periodicTaskRepository: PeriodicTaskRepositoryProtocol
    let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    let biometricAuthService: BiometricAuthServiceProtocol
    let avatarUploader: AvatarStorageUploaderProtocol
    let userProfileRemote: UserProfileRemoteRepositoryProtocol
}
