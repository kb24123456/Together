import CloudKit
import Foundation
import SwiftData

private struct NoopAnniversaryScheduler: AnniversaryNotificationSchedulerProtocol {
    func refresh(spaceID: UUID, partnerName: String?, myName: String?, myUserID: UUID?) async {}
}

private actor MockSupabaseSoloRemoteGateway: SupabaseSoloRemoteGatewayProtocol {
    private let remoteSpaceID: UUID
    private let emptySnapshot: SoloRemoteSnapshot

    init(remoteSpaceID: UUID, emptySnapshot: SoloRemoteSnapshot) {
        self.remoteSpaceID = remoteSpaceID
        self.emptySnapshot = emptySnapshot
    }

    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID {
        remoteSpaceID
    }

    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws {}

    func countTasks(spaceID: UUID) async throws -> Int {
        emptySnapshot.tasks.count
    }

    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot {
        emptySnapshot
    }

    func upsert(snapshot: SoloRemoteSnapshot) async throws {}
}

enum MockServiceFactory {
    @MainActor
    static func makeContainer(
        supabaseSoloSyncService injectedSupabaseSoloSyncService: (any SupabaseSoloSyncServicing)? = nil
    ) -> AppContainer {
        let syncCoordinator = NoOpSyncCoordinator()
        let itemRepository = MockItemRepository()
        let taskTemplateRepository = MockTaskTemplateRepository()
        let notificationService = MockNotificationService()
        let reminderScheduler = MockReminderScheduler()
        let mockModelContainer = try! ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            PersistentTaskMessage.self,
            PersistentTaskChatReadState.self,
            PersistentImportantDate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let userProfileRepository = MockUserProfileRepository()
        let taskMessageRepository = LocalTaskMessageRepository(container: mockModelContainer)
        let taskApplicationService = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            taskMessageRepository: taskMessageRepository,
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

        // PremiumGate 在 mock/preview 环境里保持 inert：bootstrap 从不被调用，
        // 内部依赖不会触发任何 I/O，也不会写真实 UserDefaults。
        let premiumDate = SystemDateProvider()
        let premiumGate = PremiumGate(
            rcClient: RevenueCatClient(),
            grantsLoader: SupabaseGrantsLoader(client: SupabaseClientProvider.shared),
            cache: PremiumStatusCache(defaults: .standard, dateProvider: premiumDate),
            dateProvider: premiumDate
        )

        return AppContainer(
            supabaseAuthService: SupabaseAuthService(),
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            pairingService: MockRelationshipService(),
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskMessageRepository: taskMessageRepository,
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
            userProfileRemote: MockUserProfileRemoteRepository(),
            cloudKitContainer: ckContainer,
            syncEngineCoordinator: SyncEngineCoordinator(
                ckContainer: ckContainer,
                modelContainer: mockModelContainer,
                healthMonitor: SyncHealthMonitor()
            ),
            supabaseSoloSyncService: injectedSupabaseSoloSyncService ?? makeSupabaseSoloSyncService(modelContainer: mockModelContainer),
            premiumGate: premiumGate
        )
    }

    @MainActor
    private static func makeSupabaseSoloSyncService(modelContainer: ModelContainer) -> SupabaseSoloSyncService {
        let suiteName = "com.pigdog.Together.mock.soloSync.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create isolated mock solo sync defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let remoteSpaceID = MockDataFactory.singleSpaceID
        let installationID = MockDataFactory.currentUserID
        let emptySnapshot = SoloRemoteSnapshot()
        return SupabaseSoloSyncService(
            modelContainer: modelContainer,
            remote: MockSupabaseSoloRemoteGateway(remoteSpaceID: remoteSpaceID, emptySnapshot: emptySnapshot),
            metadata: SoloSyncMetadataStore(defaults: defaults),
            installationIDProvider: { installationID },
            appVersionProvider: { nil },
            buildNumberProvider: { nil }
        )
    }
}
