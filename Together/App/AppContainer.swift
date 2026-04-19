import CloudKit
import Foundation

struct AppContainer {
    let authService: AuthServiceProtocol
    let spaceService: SpaceServiceProtocol
    let taskApplicationService: TaskApplicationServiceProtocol
    let quickCaptureParser: QuickCaptureParserProtocol
    let syncCoordinator: SyncCoordinatorProtocol
    let pairingService: PairingServiceProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let itemRepository: ItemRepositoryProtocol
    let taskTemplateRepository: TaskTemplateRepositoryProtocol
    let taskMessageRepository: TaskMessageRepositoryProtocol
    let taskListRepository: TaskListRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol
    let decisionRepository: DecisionRepositoryProtocol
    let notificationService: NotificationServiceProtocol
    let reminderScheduler: ReminderSchedulerProtocol
    let periodicTaskRepository: PeriodicTaskRepositoryProtocol
    let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    let biometricAuthService: BiometricAuthServiceProtocol
    let avatarUploader: AvatarStorageUploaderProtocol

    // CloudKit infrastructure
    let cloudKitContainer: CKContainer

    // CKSyncEngine-based sync (private DB, solo zone only)
    let syncEngineCoordinator: SyncEngineCoordinator
}
