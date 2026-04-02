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
}
