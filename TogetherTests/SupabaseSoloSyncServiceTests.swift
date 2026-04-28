import Foundation
import SwiftData
import Testing
@testable import Together

@Suite("SupabaseSoloSyncService")
@MainActor
struct SupabaseSoloSyncServiceTests {
    @Test("fresh install pulls remote snapshot and writes migration metadata")
    func freshInstallPullsRemoteSnapshot() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let taskID = UUID()
        let importantDateID = UUID()
        harness.remote.setSpaceID(spaceID)
        harness.remote.setSnapshot(SoloRemoteSnapshot(
            tasks: [
                TaskDTO(from: PersistentItem.sample(id: taskID, spaceID: spaceID, creatorID: harness.userID, title: "remote task"), spaceID: spaceID, supabaseUserID: harness.userID)
            ],
            importantDates: [
                ImportantDateDTO(from: PersistentImportantDate.sample(id: importantDateID, spaceID: spaceID, creatorID: harness.userID, title: "remote date"))
            ]
        ))

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let context = ModelContext(harness.container)
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        let dates = try context.fetch(FetchDescriptor<PersistentImportantDate>())

        #expect(items.map(\.title) == ["remote task"])
        #expect(dates.map(\.title) == ["remote date"])
        #expect(harness.metadata.migrationCompletedAt(spaceID: spaceID) != nil)
        #expect(harness.metadata.lastPulledAt(spaceID: spaceID) != nil)
    }

    @Test("existing local store uploads local records before marking migration complete and rewrites space ids")
    func existingLocalStoreUploadsBeforeBaseline() async throws {
        let harness = try SoloSyncHarness()
        let localSpaceID = UUID()
        let remoteSpaceID = UUID()
        let taskID = UUID()
        let importantDateID = UUID()
        harness.remote.setSpaceID(remoteSpaceID)

        let context = ModelContext(harness.container)
        context.insert(PersistentSpace(
            space: Space(
                id: localSpaceID,
                type: .single,
                displayName: "旧空间",
                ownerUserID: harness.userID,
                status: .active,
                createdAt: .now,
                updatedAt: .now
            )
        ))
        context.insert(PersistentItem.sample(id: taskID, spaceID: localSpaceID, creatorID: harness.userID, title: "local task"))
        context.insert(PersistentImportantDate.sample(id: importantDateID, spaceID: localSpaceID, creatorID: harness.userID, title: "local date"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: localSpaceID)))
        try context.save()

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let upserted = harness.remote.upsertedSnapshot()
        #expect(upserted.tasks.map(\.title) == ["local task"])
        #expect(upserted.tasks.first?.spaceId == remoteSpaceID)
        #expect(upserted.importantDates.map(\.title) == ["local date"])
        #expect(upserted.importantDates.first?.spaceId == remoteSpaceID)

        let spaces = try context.fetch(FetchDescriptor<PersistentSpace>())
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        let dates = try context.fetch(FetchDescriptor<PersistentImportantDate>())
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())

        #expect(spaces.map(\.id) == [remoteSpaceID])
        #expect(items.first?.spaceID == remoteSpaceID)
        #expect(dates.first?.spaceID == remoteSpaceID)
        #expect(changes.first?.spaceID == remoteSpaceID)
        #expect(harness.metadata.migrationCompletedAt(spaceID: remoteSpaceID) != nil)
        #expect(harness.metadata.lastPushedAt(spaceID: remoteSpaceID) != nil)
    }

    @Test("pair data is not adopted as solo bootstrap data")
    func pairDataIsNotRewrittenToRemoteSoloSpace() async throws {
        let harness = try SoloSyncHarness()
        let pairSpaceID = UUID()
        let remoteSpaceID = UUID()
        let taskID = UUID()
        let importantDateID = UUID()
        harness.remote.setSpaceID(remoteSpaceID)

        let context = ModelContext(harness.container)
        context.insert(PersistentSpace(
            space: Space(
                id: pairSpaceID,
                type: .pair,
                displayName: "共享空间",
                ownerUserID: harness.userID,
                status: .active,
                createdAt: .now,
                updatedAt: .now
            )
        ))
        context.insert(PersistentItem.sample(id: taskID, spaceID: pairSpaceID, creatorID: harness.userID, title: "shared task"))
        context.insert(PersistentImportantDate.sample(id: importantDateID, spaceID: pairSpaceID, creatorID: harness.userID, title: "shared date"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: pairSpaceID)))
        try context.save()

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let spaces = try context.fetch(FetchDescriptor<PersistentSpace>())
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        let dates = try context.fetch(FetchDescriptor<PersistentImportantDate>())
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())

        #expect(Set(spaces.map(\.id)) == Set([pairSpaceID, remoteSpaceID]))
        #expect(spaces.first(where: { $0.id == pairSpaceID })?.typeRawValue == SpaceType.pair.rawValue)
        #expect(spaces.first(where: { $0.id == remoteSpaceID })?.typeRawValue == SpaceType.single.rawValue)
        #expect(items.first(where: { $0.id == taskID })?.spaceID == pairSpaceID)
        #expect(dates.first(where: { $0.id == importantDateID })?.spaceID == pairSpaceID)
        #expect(changes.first(where: { $0.recordID == taskID })?.spaceID == pairSpaceID)
        #expect(harness.remote.upsertCallCount() == 0)
        #expect(harness.remote.fetchSnapshotCallCount() == 1)
        #expect(harness.metadata.migrationCompletedAt(spaceID: remoteSpaceID) != nil)
    }

    @Test("iPad without Pro throws requiresPro and does not fetch or push")
    func ipadWithoutProBlocked() async throws {
        let harness = try SoloSyncHarness()

        do {
            try await harness.service.start(
                userID: harness.userID,
                localUserID: harness.userID,
                displayName: "我",
                platform: .ipad,
                isPro: false
            )
            Issue.record("Expected requiresPro")
        } catch SoloSyncServiceError.requiresPro {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(harness.remote.ensureSingleSpaceCallCount() == 0)
        #expect(harness.remote.registerDeviceCallCount() == 0)
        #expect(harness.remote.fetchSnapshotCallCount() == 0)
        #expect(harness.remote.upsertCallCount() == 0)
    }

    @Test("baseline startup pushes pending solo task changes and clears outbox")
    func baselineStartupPushesPendingSoloTaskChanges() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let taskID = UUID()
        harness.remote.setSpaceID(spaceID)
        harness.metadata.markMigrationCompleted(spaceID: spaceID, at: .now, build: "13")

        let context = ModelContext(harness.container)
        context.insert(PersistentSpace(
            space: Space(
                id: spaceID,
                type: .single,
                displayName: "我的空间",
                ownerUserID: harness.userID,
                status: .active,
                createdAt: .now,
                updatedAt: .now
            )
        ))
        context.insert(PersistentItem.sample(id: taskID, spaceID: spaceID, creatorID: harness.userID, title: "pending task"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: spaceID)))
        try context.save()

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let upserted = harness.remote.upsertedSnapshot()
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())

        #expect(upserted.tasks.map(\.title) == ["pending task"])
        #expect(upserted.tasks.first?.spaceId == spaceID)
        #expect(harness.remote.upsertCallCount() == 1)
        #expect(changes.isEmpty)
        #expect(harness.metadata.lastPushedAt(spaceID: spaceID) != nil)
    }

    @Test("baseline startup revives sending changes before pushing")
    func baselineStartupRevivesSendingChangesBeforePush() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let taskID = UUID()
        harness.remote.setSpaceID(spaceID)
        harness.metadata.markMigrationCompleted(spaceID: spaceID, at: .now, build: "13")

        let context = ModelContext(harness.container)
        context.insert(PersistentSpace(
            space: Space(
                id: spaceID,
                type: .single,
                displayName: "我的空间",
                ownerUserID: harness.userID,
                status: .active,
                createdAt: .now,
                updatedAt: .now
            )
        ))
        context.insert(PersistentItem.sample(id: taskID, spaceID: spaceID, creatorID: harness.userID, title: "stuck sending task"))
        let change = PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: spaceID))
        change.lifecycleState = .sending
        context.insert(change)
        try context.save()

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let upserted = harness.remote.upsertedSnapshot()
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())

        #expect(upserted.tasks.map(\.title) == ["stuck sending task"])
        #expect(harness.remote.upsertCallCount() == 1)
        #expect(changes.isEmpty)
    }

    @Test("pending important date is pushed and cleared")
    func pendingImportantDatePushesAndClearsOutbox() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let importantDateID = UUID()
        harness.metadata.markMigrationCompleted(spaceID: spaceID, at: .now, build: "13")

        let context = ModelContext(harness.container)
        context.insert(PersistentImportantDate.sample(id: importantDateID, spaceID: spaceID, creatorID: harness.userID, title: "renewal"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .importantDate, operation: .upsert, recordID: importantDateID, spaceID: spaceID)))
        try context.save()

        try await harness.service.pushPending(spaceID: spaceID, userID: harness.userID)

        let upserted = harness.remote.upsertedSnapshot()
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())

        #expect(upserted.importantDates.map(\.title) == ["renewal"])
        #expect(upserted.importantDates.first?.spaceId == spaceID)
        #expect(harness.remote.upsertCallCount() == 1)
        #expect(changes.isEmpty)
        #expect(harness.metadata.lastPushedAt(spaceID: spaceID) != nil)
    }

    @Test("project subtask with parent project outside solo space is failed without pushing")
    func projectSubtaskOutsideSoloSpaceFailsWithoutPushing() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let otherSpaceID = UUID()
        let projectID = UUID()
        let subtaskID = UUID()

        let context = ModelContext(harness.container)
        context.insert(PersistentProject.sample(id: projectID, spaceID: otherSpaceID, creatorID: harness.userID, name: "other project"))
        context.insert(PersistentProjectSubtask.sample(id: subtaskID, projectID: projectID, creatorID: harness.userID, title: "wrong space subtask"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .projectSubtask, operation: .upsert, recordID: subtaskID, spaceID: spaceID)))
        try context.save()

        try await harness.service.pushPending(spaceID: spaceID, userID: harness.userID)

        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())
        let change = try #require(changes.first)

        #expect(harness.remote.upsertCallCount() == 0)
        #expect(changes.count == 1)
        #expect(change.lifecycleState == .failed)
        #expect(change.lastError?.contains("missingLocalRow") == true)
    }

    @Test("missing local row does not block valid pending task")
    func missingLocalRowDoesNotBlockValidPendingTask() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let missingTaskID = UUID()
        let validTaskID = UUID()

        let context = ModelContext(harness.container)
        context.insert(PersistentItem.sample(id: validTaskID, spaceID: spaceID, creatorID: harness.userID, title: "valid task"))
        context.insert(PersistentSyncChange(change: SyncChange(
            entityKind: .task,
            operation: .upsert,
            recordID: missingTaskID,
            spaceID: spaceID,
            changedAt: Date(timeIntervalSince1970: 1)
        )))
        context.insert(PersistentSyncChange(change: SyncChange(
            entityKind: .task,
            operation: .upsert,
            recordID: validTaskID,
            spaceID: spaceID,
            changedAt: Date(timeIntervalSince1970: 2)
        )))
        try context.save()

        try await harness.service.pushPending(spaceID: spaceID, userID: harness.userID)

        let upserted = harness.remote.upsertedSnapshot()
        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())
        let failedChange = try #require(changes.first)

        #expect(harness.remote.upsertCallCount() == 1)
        #expect(upserted.tasks.map(\.title) == ["valid task"])
        #expect(changes.count == 1)
        #expect(failedChange.recordID == missingTaskID)
        #expect(failedChange.lifecycleState == .failed)
        #expect(failedChange.lastError?.contains("missingLocalRow") == true)
    }

    @Test("unsupported solo changes are marked failed without remote upsert")
    func unsupportedSoloChangesAreMarkedFailedWithoutRemoteUpsert() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let recordID = UUID()

        let context = ModelContext(harness.container)
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .space, operation: .upsert, recordID: recordID, spaceID: spaceID)))
        try context.save()

        try await harness.service.pushPending(spaceID: spaceID, userID: harness.userID)

        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())
        let change = try #require(changes.first)

        #expect(harness.remote.upsertCallCount() == 0)
        #expect(changes.count == 1)
        #expect(change.lifecycleState == .failed)
        #expect(change.lastError == "unsupported solo sync entity kind: space")
    }

    @Test("remote upsert failure leaves changes failed with last error")
    func remoteUpsertFailureLeavesChangesFailed() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let taskID = UUID()
        harness.remote.setUpsertError(FakeSoloRemoteError.upsertFailed)

        let context = ModelContext(harness.container)
        context.insert(PersistentItem.sample(id: taskID, spaceID: spaceID, creatorID: harness.userID, title: "will fail"))
        context.insert(PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: spaceID)))
        try context.save()

        do {
            try await harness.service.pushPending(spaceID: spaceID, userID: harness.userID)
            Issue.record("Expected upsert failure")
        } catch FakeSoloRemoteError.upsertFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>())
        let change = try #require(changes.first)

        #expect(harness.remote.upsertCallCount() == 1)
        #expect(changes.count == 1)
        #expect(change.lifecycleState == .failed)
        #expect(change.lastAttemptedAt != nil)
        #expect(change.lastError?.contains("upsertFailed") == true)
        #expect(harness.metadata.lastPushedAt(spaceID: spaceID) == nil)
    }
}

private enum FakeSoloRemoteError: Error {
    case upsertFailed
}

private final class FakeSoloRemoteGateway: SupabaseSoloRemoteGatewayProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _spaceID = UUID()
    private var _snapshot = SoloRemoteSnapshot()
    private var _upserted = SoloRemoteSnapshot()
    private var _upsertError: Error?
    private var _ensureSingleSpaceCallCount = 0
    private var _registerDeviceCallCount = 0
    private var _fetchSnapshotCallCount = 0
    private var _upsertCallCount = 0

    func setSpaceID(_ id: UUID) {
        lock.withLock { _spaceID = id }
    }

    func setSnapshot(_ snapshot: SoloRemoteSnapshot) {
        lock.withLock { _snapshot = snapshot }
    }

    func setUpsertError(_ error: Error?) {
        lock.withLock { _upsertError = error }
    }

    func upsertedSnapshot() -> SoloRemoteSnapshot {
        lock.withLock { _upserted }
    }

    func ensureSingleSpaceCallCount() -> Int {
        lock.withLock { _ensureSingleSpaceCallCount }
    }

    func registerDeviceCallCount() -> Int {
        lock.withLock { _registerDeviceCallCount }
    }

    func fetchSnapshotCallCount() -> Int {
        lock.withLock { _fetchSnapshotCallCount }
    }

    func upsertCallCount() -> Int {
        lock.withLock { _upsertCallCount }
    }

    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID {
        lock.withLock {
            _ensureSingleSpaceCallCount += 1
            return _spaceID
        }
    }

    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws {
        lock.withLock { _registerDeviceCallCount += 1 }
    }

    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot {
        lock.withLock {
            _fetchSnapshotCallCount += 1
            return _snapshot
        }
    }

    func upsert(snapshot: SoloRemoteSnapshot) async throws {
        let error = lock.withLock {
            _upsertCallCount += 1
            return _upsertError
        }
        if let error {
            throw error
        }

        lock.withLock {
            _upserted.tasks.append(contentsOf: snapshot.tasks)
            _upserted.taskLists.append(contentsOf: snapshot.taskLists)
            _upserted.projects.append(contentsOf: snapshot.projects)
            _upserted.projectSubtasks.append(contentsOf: snapshot.projectSubtasks)
            _upserted.periodicTasks.append(contentsOf: snapshot.periodicTasks)
            _upserted.importantDates.append(contentsOf: snapshot.importantDates)
        }
    }
}

private struct SoloSyncHarness {
    let container: ModelContainer
    let remote = FakeSoloRemoteGateway()
    let metadata: SoloSyncMetadataStore
    let service: SupabaseSoloSyncService
    let userID = UUID()
    private let suiteName: String

    init() throws {
        container = try ModelContainer(
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
            PersistentImportantDate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        suiteName = "SoloSyncHarness.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        metadata = SoloSyncMetadataStore(defaults: defaults)
        service = SupabaseSoloSyncService(
            modelContainer: container,
            remote: remote,
            metadata: metadata,
            installationIDProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            appVersionProvider: { "1.0" },
            buildNumberProvider: { "13" }
        )
    }

    func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

private extension PersistentItem {
    static func sample(id: UUID, spaceID: UUID, creatorID: UUID, title: String) -> PersistentItem {
        PersistentItem(
            id: id,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: creatorID,
            title: title,
            notes: nil,
            locationText: nil,
            executionRoleRawValue: ItemExecutionRole.initiator.rawValue,
            assigneeModeRawValue: TaskAssigneeMode.`self`.rawValue,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            statusRawValue: ItemStatus.pendingConfirmation.rawValue,
            assignmentStateRawValue: TaskAssignmentState.active.rawValue,
            latestResponseData: nil,
            responseHistoryData: Data(),
            assignmentMessagesData: Data(),
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            completedByUserID: nil,
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRuleData: nil,
            reminderRequestedAt: nil,
            isLocallyDeleted: false
        )
    }
}

private extension PersistentProject {
    static func sample(id: UUID, spaceID: UUID, creatorID: UUID, name: String) -> PersistentProject {
        PersistentProject(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            name: name,
            notes: nil,
            colorToken: nil,
            statusRawValue: ProjectStatus.active.rawValue,
            targetDate: nil,
            remindAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil
        )
    }
}

private extension PersistentProjectSubtask {
    static func sample(id: UUID, projectID: UUID, creatorID: UUID, title: String) -> PersistentProjectSubtask {
        PersistentProjectSubtask(
            id: id,
            projectID: projectID,
            creatorID: creatorID,
            title: title,
            isCompleted: false,
            sortOrder: 0
        )
    }
}

private extension PersistentImportantDate {
    static func sample(id: UUID, spaceID: UUID, creatorID: UUID, title: String) -> PersistentImportantDate {
        PersistentImportantDate(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            kindRawValue: "custom",
            title: title,
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            recurrenceRawValue: Recurrence.none.rawValue,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: "calendar",
            createdAt: .now,
            updatedAt: .now
        )
    }
}

private extension SoloRemoteSnapshot {
    init(
        tasks: [TaskDTO] = [],
        taskLists: [TaskListDTO] = [],
        projects: [ProjectDTO] = [],
        projectSubtasks: [ProjectSubtaskDTO] = [],
        periodicTasks: [PeriodicTaskDTO] = [],
        importantDates: [ImportantDateDTO] = []
    ) {
        self.init()
        self.tasks = tasks
        self.taskLists = taskLists
        self.projects = projects
        self.projectSubtasks = projectSubtasks
        self.periodicTasks = periodicTasks
        self.importantDates = importantDates
    }
}
