import Foundation
import Testing
@testable import Together

struct TogetherTests {
    @Test func itemStateMachineMovesPendingToInProgressWhenPartnerAgrees() async throws {
        let next = await ItemStateMachine.nextStatus(
            from: .pendingConfirmation,
            executionRole: .recipient,
            response: .willing
        )

        #expect(next == .inProgress)
    }

    @Test func itemStateMachineMovesInProgressToCompletedWhenMarkedDone() async throws {
        let next = await ItemStateMachine.nextStatus(
            from: .inProgress,
            executionRole: .both,
            isCompletion: true
        )

        #expect(next == .completed)
    }

    @Test func decisionStateMachineRequiresBothParticipants() async throws {
        let votes = [
            DecisionVote(voterID: UUID(), value: .agree, respondedAt: .now)
        ]

        let next = await DecisionStateMachine.nextStatus(from: votes, participantCount: 2)

        #expect(next == .pendingResponse)
    }

    @Test func decisionStateMachineMarksNeutralAsNoConsensus() async throws {
        let votes = [
            DecisionVote(voterID: UUID(), value: .agree, respondedAt: .now),
            DecisionVote(voterID: UUID(), value: .neutral, respondedAt: .now)
        ]

        let next = await DecisionStateMachine.nextStatus(from: votes, participantCount: 2)

        #expect(next == .noConsensusYet)
    }

    @Test func mockSpaceServiceProvidesSingleSpaceContext() async throws {
        let context = await MockSpaceService().currentSpaceContext(for: MockDataFactory.currentUserID)

        #expect(context.currentSpace?.type == .single)
        #expect(context.availableSpaces.count == 1)
    }

    @Test @MainActor
    func sessionStoreBootstrapsIntoSingleSpace() async throws {
        let sessionStore = SessionStore()

        await sessionStore.bootstrap(
            authService: MockAuthService(),
            spaceService: MockSpaceService()
        )

        #expect(sessionStore.authState == .signedIn)
        #expect(sessionStore.currentSpace?.id == MockDataFactory.singleSpaceID)
        #expect(sessionStore.bindingState == .singleTrial)
    }

    @Test @MainActor
    func mockTaskListRepositoryReturnsCurrentSpaceLists() async throws {
        let lists = try await MockTaskListRepository().fetchTaskLists(spaceID: MockDataFactory.singleSpaceID)

        #expect(lists.isEmpty == false)
        #expect(lists.contains { $0.kind == .systemToday })
    }

    @Test @MainActor
    func mockProjectRepositoryReturnsActiveProjects() async throws {
        let projects = try await MockProjectRepository().fetchProjects(spaceID: MockDataFactory.singleSpaceID)

        #expect(projects.contains { $0.status == .active })
        #expect(projects.contains { $0.status == .completed })
    }

    @Test
    func localRepositoriesSeedSingleSpaceTodoData() async throws {
        let persistence = PersistenceController(inMemory: true)
        let spaceService = LocalSpaceService(container: persistence.container)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let listRepository = LocalTaskListRepository(container: persistence.container)
        let projectRepository = LocalProjectRepository(container: persistence.container)

        let spaceContext = await spaceService.currentSpaceContext(for: MockDataFactory.currentUserID)
        let items = try await itemRepository.fetchItems(spaceID: MockDataFactory.singleSpaceID)
        let lists = try await listRepository.fetchTaskLists(spaceID: MockDataFactory.singleSpaceID)
        let projects = try await projectRepository.fetchProjects(spaceID: MockDataFactory.singleSpaceID)

        #expect(spaceContext.currentSpace?.id == MockDataFactory.singleSpaceID)
        #expect(items.count == MockDataFactory.makeItems().count)
        #expect(lists.contains { $0.id == MockDataFactory.todayListID && $0.taskCount == 3 })
        #expect(projects.contains { $0.id == MockDataFactory.focusProjectID && $0.taskCount == 3 })
    }

    @Test
    func localItemRepositoryPersistsStatusTransitions() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalItemRepository(container: persistence.container)
        let targetID = UUID(uuidString: "66666666-6666-6666-6666-666666666664")!

        let afterResponse = try await repository.updateItemStatus(
            itemID: targetID,
            response: .acknowledged,
            actorID: MockDataFactory.currentUserID
        )
        let afterCompletion = try await repository.markCompleted(
            itemID: targetID,
            actorID: MockDataFactory.currentUserID
        )

        #expect(afterResponse.status == .inProgress)
        #expect(afterCompletion.status == .completed)
        #expect(afterCompletion.completedAt != nil)
    }

    @Test
    func localTaskListRepositorySupportsUpsertAndArchive() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalTaskListRepository(container: persistence.container)

        let saved = try await repository.saveTaskList(
            TaskList(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                name: "客户跟进",
                kind: .custom,
                colorToken: "navy",
                sortOrder: 9,
                isArchived: false,
                taskCount: 0,
                createdAt: .now,
                updatedAt: .now
            )
        )
        let archived = try await repository.archiveTaskList(listID: saved.id)

        #expect(saved.name == "客户跟进")
        #expect(archived.isArchived == true)
    }

    @Test
    func localProjectRepositorySupportsUpsertAndArchive() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalProjectRepository(container: persistence.container)

        let saved = try await repository.saveProject(
            Project(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                name: "本地数据库接入",
                notes: "把 SwiftData 和仓库层跑通。",
                colorToken: "ink",
                status: .active,
                targetDate: .now.addingTimeInterval(86_400),
                remindAt: .now.addingTimeInterval(82_800),
                priority: .important,
                taskCount: 0,
                createdAt: .now,
                updatedAt: .now,
                completedAt: nil
            )
        )
        let archived = try await repository.archiveProject(projectID: saved.id)

        #expect(saved.name == "本地数据库接入")
        #expect(archived.status == .archived)
    }

    @Test
    func taskApplicationServiceCreatesAndQueriesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )

        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "整理本周复盘提纲",
                notes: "先列结论，再补 3 个关键证据。",
                listID: MockDataFactory.todayListID,
                projectID: MockDataFactory.focusProjectID,
                dueAt: MockDataFactory.now,
                priority: .important,
                status: .inProgress,
                isPinned: true
            )
        )
        let todayTasks = try await service.tasks(
            in: MockDataFactory.singleSpaceID,
            scope: .today(referenceDate: MockDataFactory.now)
        )
        let recordedChanges = await syncCoordinator.pendingChanges()

        #expect(created.spaceID == MockDataFactory.singleSpaceID)
        #expect(todayTasks.contains { $0.id == created.id })
        #expect(recordedChanges.contains { $0.recordID == created.id && $0.operation == .upsert })
    }

    @Test
    func taskApplicationServiceUpdatesAndCompletesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )
        let taskID = UUID(uuidString: "66666666-6666-6666-6666-666666666664")!

        let updated = try await service.updateTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "梳理本周项目优先级 v2",
                notes: "只保留一个本周必须完成项。",
                listID: MockDataFactory.planningListID,
                projectID: MockDataFactory.launchProjectID,
                dueAt: MockDataFactory.now.addingTimeInterval(3_600),
                remindAt: MockDataFactory.now.addingTimeInterval(1_800),
                priority: .critical,
                status: .inProgress,
                isPinned: false
            )
        )
        let completed = try await service.completeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID
        )
        let changes = await syncCoordinator.pendingChanges()

        #expect(updated.title == "梳理本周项目优先级 v2")
        #expect(updated.listID == MockDataFactory.planningListID)
        #expect(completed.status == .completed)
        #expect(changes.contains { $0.recordID == taskID && $0.operation == .complete })
    }

    @Test
    func taskApplicationServiceCanRestoreCompletedTask() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )
        let taskID = UUID(uuidString: "66666666-6666-6666-6666-666666666664")!

        _ = try await service.completeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID
        )
        let restored = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID
        )

        #expect(restored.completedAt == nil)
        #expect(restored.status == .inProgress)
    }

    @Test
    func taskApplicationServiceMovesReschedulesAndArchivesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )
        let taskID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let newDueAt = MockDataFactory.now.addingTimeInterval(-3_600)

        let moved = try await service.moveTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID,
            listID: MockDataFactory.todayListID,
            projectID: MockDataFactory.launchProjectID
        )
        let rescheduled = try await service.rescheduleTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID,
            dueAt: newDueAt,
            remindAt: nil
        )
        let todayTasks = try await service.tasks(
            in: MockDataFactory.singleSpaceID,
            scope: .today(referenceDate: MockDataFactory.now)
        )
        let archived = try await service.archiveTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID
        )
        let remainingItems = try await itemRepository.fetchItems(spaceID: MockDataFactory.singleSpaceID)
        let changes = await syncCoordinator.pendingChanges()

        #expect(moved.listID == MockDataFactory.todayListID)
        #expect(moved.projectID == MockDataFactory.launchProjectID)
        #expect(rescheduled.dueAt == newDueAt)
        #expect(todayTasks.contains { $0.id == taskID })
        #expect(archived.isArchived == true)
        #expect(remainingItems.contains { $0.id == taskID } == false)
        #expect(changes.contains { $0.recordID == taskID && $0.operation == .archive })
    }

    @Test
    func taskApplicationServiceBuildsTodaySummaryFromActionableTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator
        )

        _ = try await service.completeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: UUID(uuidString: "66666666-6666-6666-6666-666666666661")!,
            actorID: MockDataFactory.currentUserID
        )

        let summary = try await service.todaySummary(
            in: MockDataFactory.singleSpaceID,
            referenceDate: MockDataFactory.now
        )

        #expect(summary.actionableCount == 4)
        #expect(summary.dueTodayCount == 4)
        #expect(summary.completedTodayCount == 1)
        #expect(summary.pinnedCount == 0)
    }

    @Test
    func localSyncCoordinatorPersistsAndClearsPendingChanges() async throws {
        let persistence = PersistenceController(inMemory: true)
        let coordinator = LocalSyncCoordinator(container: persistence.container)
        let taskID = UUID()

        await coordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: taskID,
                spaceID: MockDataFactory.singleSpaceID,
                changedAt: MockDataFactory.now
            )
        )
        await coordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .complete,
                recordID: taskID,
                spaceID: MockDataFactory.singleSpaceID,
                changedAt: MockDataFactory.now.addingTimeInterval(60)
            )
        )

        let pendingBeforeClear = await coordinator.pendingChanges()
        await coordinator.markSyncFailure(
            for: MockDataFactory.singleSpaceID,
            errorMessage: "network timeout",
            failedAt: MockDataFactory.now.addingTimeInterval(90)
        )
        let failedState = await coordinator.syncState(for: MockDataFactory.singleSpaceID)
        await coordinator.markPushSuccess(
            for: MockDataFactory.singleSpaceID,
            cursor: SyncCursor(
                token: "cursor-1",
                updatedAt: MockDataFactory.now.addingTimeInterval(120)
            ),
            clearedRecordIDs: [taskID],
            syncedAt: MockDataFactory.now.addingTimeInterval(120)
        )
        await coordinator.clearPendingChanges(recordIDs: [taskID])
        let pendingAfterClear = await coordinator.pendingChanges()
        let succeededState = await coordinator.syncState(for: MockDataFactory.singleSpaceID)

        #expect(pendingBeforeClear.count == 1)
        #expect(pendingBeforeClear.first?.operation == .complete)
        #expect(failedState?.retryCount == 1)
        #expect(failedState?.lastError == "network timeout")
        #expect(pendingAfterClear.isEmpty)
        #expect(succeededState?.retryCount == 0)
        #expect(succeededState?.lastError == nil)
        #expect(succeededState?.cursor?.token == "cursor-1")
    }

    @Test
    func syncOrchestratorPushesPendingChangesAndUpdatesCursor() async throws {
        let coordinator = TestSyncCoordinator()
        let gateway = TestCloudSyncGateway()
        let applier = TestRemoteSyncApplier()
        let orchestrator = DefaultSyncOrchestrator(
            syncCoordinator: coordinator,
            cloudGateway: gateway,
            remoteSyncApplier: applier
        )
        let taskID = UUID()

        await coordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: taskID,
                spaceID: MockDataFactory.singleSpaceID,
                changedAt: MockDataFactory.now
            )
        )
        await gateway.setPushResult(
            SyncPushResult(
                pushedCount: 1,
                cursor: SyncCursor(token: "push-cursor", updatedAt: MockDataFactory.now.addingTimeInterval(10))
            )
        )

        let result = try await orchestrator.sync(spaceID: MockDataFactory.singleSpaceID)
        let pendingAfterSync = await coordinator.pendingChanges()
        let state = await coordinator.syncState(for: MockDataFactory.singleSpaceID)

        #expect(result.pendingCountBeforeSync == 1)
        #expect(result.pushedCount == 1)
        #expect(result.cursor?.token == "push-cursor")
        #expect(pendingAfterSync.isEmpty)
        #expect(state?.cursor?.token == "push-cursor")
        #expect(state?.retryCount == 0)
    }

    @Test
    func syncOrchestratorMarksFailureWhenGatewayThrows() async throws {
        let coordinator = TestSyncCoordinator()
        let gateway = TestCloudSyncGateway()
        let applier = TestRemoteSyncApplier()
        let orchestrator = DefaultSyncOrchestrator(
            syncCoordinator: coordinator,
            cloudGateway: gateway,
            remoteSyncApplier: applier
        )
        let taskID = UUID()

        await coordinator.recordLocalChange(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: taskID,
                spaceID: MockDataFactory.singleSpaceID,
                changedAt: MockDataFactory.now
            )
        )
        await gateway.setFailure(TestCloudSyncGatewayError.pushFailed)

        do {
            _ = try await orchestrator.sync(spaceID: MockDataFactory.singleSpaceID)
            Issue.record("Expected sync to fail")
        } catch {
            let state = await coordinator.syncState(for: MockDataFactory.singleSpaceID)
            let pendingAfterFailure = await coordinator.pendingChanges()

            #expect(state?.retryCount == 1)
            #expect(state?.lastError?.contains("pushFailed") == true)
            #expect(pendingAfterFailure.count == 1)
        }
    }

    @Test
    func syncOrchestratorFailsWhenRemoteChangesNeedApplyPipeline() async throws {
        let coordinator = TestSyncCoordinator()
        let gateway = TestCloudSyncGateway()
        let applier = TestRemoteSyncApplier()
        let orchestrator = DefaultSyncOrchestrator(
            syncCoordinator: coordinator,
            cloudGateway: gateway,
            remoteSyncApplier: applier
        )

        await gateway.setPullResult(
            SyncPullResult(
                cursor: SyncCursor(token: "remote-cursor", updatedAt: MockDataFactory.now),
                changedRecordIDs: [UUID()],
                payload: .empty
            )
        )

        do {
            _ = try await orchestrator.sync(spaceID: MockDataFactory.singleSpaceID)
            Issue.record("Expected sync to fail for unapplied remote changes")
        } catch let error as SyncOrchestratorError {
            let state = await coordinator.syncState(for: MockDataFactory.singleSpaceID)

            #expect(error == .remoteChangesNotSupported(1))
            #expect(state?.retryCount == 1)
            #expect(state?.lastError == "Remote apply pipeline not implemented")
        }
    }

    @Test
    func syncOrchestratorAppliesRemotePayloadWhenGatewayReturnsTaskRecords() async throws {
        let coordinator = TestSyncCoordinator()
        let gateway = TestCloudSyncGateway()
        let applier = TestRemoteSyncApplier()
        let orchestrator = DefaultSyncOrchestrator(
            syncCoordinator: coordinator,
            cloudGateway: gateway,
            remoteSyncApplier: applier
        )
        let remoteTask = MockDataFactory.makeItems()[0]

        await gateway.setPullResult(
            SyncPullResult(
                cursor: SyncCursor(token: "remote-cursor", updatedAt: MockDataFactory.now),
                changedRecordIDs: [remoteTask.id],
                payload: RemoteSyncPayload(tasks: [remoteTask])
            )
        )

        let result = try await orchestrator.sync(spaceID: MockDataFactory.singleSpaceID)
        let appliedTasks = await applier.appliedTasks
        let state = await coordinator.syncState(for: MockDataFactory.singleSpaceID)

        #expect(result.pulledCount == 1)
        #expect(appliedTasks.map(\.id) == [remoteTask.id])
        #expect(state?.cursor?.token == "remote-cursor")
    }

    @Test
    func cloudKitTaskRecordCodecRoundTripsTaskPayload() async throws {
        let item = MockDataFactory.makeItems()[0]

        let record = try CloudKitTaskRecordCodec.makeRecord(from: item)
        let decoded = try CloudKitTaskRecordCodec.decode(record: record)

        #expect(decoded.id == item.id)
        #expect(decoded.title == item.title)
        #expect(decoded.spaceID == item.spaceID)
        #expect(decoded.projectID == item.projectID)
        #expect(decoded.responseHistory == item.responseHistory)
    }
}

actor TestSyncCoordinator: SyncCoordinatorProtocol {
    private var changes: [SyncChange] = []
    private var states: [UUID: SyncState] = [:]

    func recordLocalChange(_ change: SyncChange) async {
        changes.append(change)
    }

    func pendingChanges() async -> [SyncChange] {
        changes
    }

    func clearPendingChanges(recordIDs: [UUID]) async {
        changes.removeAll { recordIDs.contains($0.recordID) }
    }

    func syncState(for spaceID: UUID) async -> SyncState? {
        states[spaceID]
    }

    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async {
        changes.removeAll { clearedRecordIDs.contains($0.recordID) }
        states[spaceID] = SyncState(
            spaceID: spaceID,
            cursor: cursor,
            lastSyncedAt: syncedAt,
            lastError: nil,
            retryCount: 0,
            updatedAt: syncedAt
        )
    }

    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async {
        let current = states[spaceID]
        states[spaceID] = SyncState(
            spaceID: spaceID,
            cursor: current?.cursor,
            lastSyncedAt: current?.lastSyncedAt,
            lastError: errorMessage,
            retryCount: (current?.retryCount ?? 0) + 1,
            updatedAt: failedAt
        )
    }
}

enum TestCloudSyncGatewayError: Error {
    case pushFailed
}

actor TestCloudSyncGateway: CloudSyncGatewayProtocol {
    private var pushResult = SyncPushResult(pushedCount: 0, cursor: nil)
    private var pullResult = SyncPullResult(cursor: nil, changedRecordIDs: [])
    private var failure: Error?

    func setPushResult(_ result: SyncPushResult) {
        pushResult = result
    }

    func setPullResult(_ result: SyncPullResult) {
        pullResult = result
    }

    func setFailure(_ error: Error?) {
        failure = error
    }

    func push(changes: [SyncChange], for spaceID: UUID) async throws -> SyncPushResult {
        if let failure {
            throw failure
        }
        return pushResult
    }

    func pull(spaceID: UUID, since cursor: SyncCursor?) async throws -> SyncPullResult {
        if let failure {
            throw failure
        }
        return pullResult
    }
}

actor TestRemoteSyncApplier: RemoteSyncApplierProtocol {
    private(set) var appliedTasks: [Item] = []

    func apply(_ payload: RemoteSyncPayload, in spaceID: UUID) async throws -> Int {
        appliedTasks.append(contentsOf: payload.tasks)
        return payload.tasks.count
    }
}
