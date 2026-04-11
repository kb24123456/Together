import CloudKit
import Foundation

struct AppContainer {
    let authService: AuthServiceProtocol
    let spaceService: SpaceServiceProtocol
    let taskApplicationService: TaskApplicationServiceProtocol
    let quickCaptureParser: QuickCaptureParserProtocol
    let syncCoordinator: SyncCoordinatorProtocol
    let syncOrchestrator: SyncOrchestratorProtocol
    let pairingService: PairingServiceProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let itemRepository: ItemRepositoryProtocol
    let taskTemplateRepository: TaskTemplateRepositoryProtocol
    let taskListRepository: TaskListRepositoryProtocol
    let projectRepository: ProjectRepositoryProtocol
    let decisionRepository: DecisionRepositoryProtocol
    let anniversaryRepository: AnniversaryRepositoryProtocol
    let notificationService: NotificationServiceProtocol
    let reminderScheduler: ReminderSchedulerProtocol
    let periodicTaskRepository: PeriodicTaskRepositoryProtocol
    let periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol
    let biometricAuthService: BiometricAuthServiceProtocol
    let syncScheduler: SyncScheduler

    // New services for private DB + CKShare
    let cloudKitContainer: CKContainer
    let zoneManager: CloudKitZoneManager
    let shareManager: CloudKitShareManager
    let subscriptionManager: CloudKitSubscriptionManager
    let cloudGateway: CloudKitSyncGateway
}
