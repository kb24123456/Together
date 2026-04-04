import Foundation
import SwiftData
import Testing
@testable import Together
#if canImport(UIKit)
import UIKit
#endif

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

    @Test @MainActor
    func mockSpaceServiceProvidesSingleSpaceContext() async throws {
        let context = await MockSpaceService().currentSpaceContext(for: MockDataFactory.currentUserID)

        #expect(context.singleSpace?.type == .single)
        #expect(context.availableSpaces.count == 2)
        #expect(context.pairSpaceSummary?.sharedSpace.id == MockDataFactory.pairSharedSpaceID)
    }

    @Test @MainActor
    func sessionStoreBootstrapsIntoSingleSpace() async throws {
        let sessionStore = SessionStore()

        await sessionStore.bootstrap(
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            pairingService: MockRelationshipService()
        )

        #expect(sessionStore.authState == .signedIn)
        #expect(sessionStore.currentSpace?.id == MockDataFactory.singleSpaceID)
        #expect(sessionStore.bindingState == .paired)
        #expect(sessionStore.availableModeStates == [.single, .pair])
    }

    @Test @MainActor
    func mockTaskListRepositoryReturnsCurrentSpaceLists() async throws {
        let lists = try await MockTaskListRepository().fetchTaskLists(spaceID: MockDataFactory.singleSpaceID)

        #expect(lists.isEmpty == false)
        #expect(lists.contains { $0.kind == .systemToday })
    }

    @Test @MainActor
    func mockProjectRepositoryReturnsActiveProjects() async throws {
        let projects = try await MockProjectRepository(
            reminderScheduler: MockReminderScheduler()
        ).fetchProjects(spaceID: MockDataFactory.singleSpaceID)

        #expect(projects.contains { $0.status == .active })
        #expect(projects.contains { $0.status == .completed })
    }

    @Test @MainActor
    func localRepositoriesSeedSingleSpaceTodoData() async throws {
        let persistence = PersistenceController(inMemory: true)
        let spaceService = LocalSpaceService(container: persistence.container)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let listRepository = LocalTaskListRepository(container: persistence.container)
        let projectRepository = LocalProjectRepository(
            container: persistence.container,
            reminderScheduler: MockReminderScheduler()
        )

        let spaceContext = await spaceService.currentSpaceContext(for: MockDataFactory.currentUserID)
        let items = try await itemRepository.fetchItems(spaceID: MockDataFactory.singleSpaceID)
        let lists = try await listRepository.fetchTaskLists(spaceID: MockDataFactory.singleSpaceID)
        let projects = try await projectRepository.fetchProjects(spaceID: MockDataFactory.singleSpaceID)
        let expectedActiveItemCount = MockDataFactory.makeItems().filter {
            $0.isArchived == false && $0.spaceID == MockDataFactory.singleSpaceID
        }.count

        #expect(spaceContext.singleSpace?.id == MockDataFactory.singleSpaceID)
        #expect(items.count == expectedActiveItemCount)
        #expect(lists.contains { $0.id == MockDataFactory.todayListID && $0.taskCount == 3 })
        #expect(projects.contains { $0.id == MockDataFactory.focusProjectID && $0.taskCount == 3 })
    }

    @Test @MainActor
    func localItemRepositoryFetchCompletedItemsIncludesNonArchivedCompletedTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let completedAt = Date.now
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "未归档但已完成",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: completedAt,
            hasExplicitTime: false,
            remindAt: nil,
            status: .completed,
            latestResponse: nil,
            responseHistory: [],
            createdAt: completedAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            isPinned: false,
            isDraft: false
        )

        _ = try await itemRepository.saveItem(item)
        let fetched = try await itemRepository.fetchCompletedItems(
            spaceID: MockDataFactory.singleSpaceID,
            searchText: "未归档但已完成",
            before: nil,
            limit: 10
        )

        #expect(fetched.contains { $0.id == item.id })
        #expect(fetched.first(where: { $0.id == item.id })?.isArchived == false)
    }

    @Test
    func localItemRepositoryPersistsStatusTransitions() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalItemRepository(container: persistence.container)
        let targetID = UUID(uuidString: "77777777-7777-7777-7777-777777777772")!

        let afterResponse = try await repository.updateItemStatus(
            itemID: targetID,
            response: .willing,
            message: "今晚我来处理",
            actorID: MockDataFactory.partnerUserID
        )
        let afterCompletion = try await repository.markCompleted(
            itemID: targetID,
            actorID: MockDataFactory.partnerUserID
        )

        #expect(afterResponse.status == .inProgress)
        #expect(afterResponse.assignmentState == .accepted)
        #expect(afterResponse.latestResponse?.message == "今晚我来处理")
        #expect(afterCompletion.status == .completed)
        #expect(afterCompletion.completedAt != nil)
    }

    @Test
    func localItemRepositoryRejectsUnauthorizedPairResponse() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalItemRepository(container: persistence.container)
        let targetID = UUID(uuidString: "77777777-7777-7777-7777-777777777772")!

        do {
            _ = try await repository.updateItemStatus(
                itemID: targetID,
                response: .willing,
                message: "我自己先接了",
                actorID: MockDataFactory.currentUserID
            )
            Issue.record("Expected unauthorized pair response to fail.")
        } catch RepositoryError.notFound {
            #expect(Bool(true))
        } catch {
            Issue.record("Expected RepositoryError.notFound, got: \(error)")
        }
    }

    @Test
    func localItemRepositoryArchivesOnlyCompletedTasksPastThreshold() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalItemRepository(container: persistence.container)

        try await repository.archiveCompletedItemsIfNeeded(
            spaceID: MockDataFactory.singleSpaceID,
            referenceDate: MockDataFactory.now,
            autoArchiveDays: 30
        )

        let archived = try await repository.fetchArchivedCompletedItems(
            spaceID: MockDataFactory.singleSpaceID,
            searchText: nil,
            before: nil,
            limit: 30
        )
        let active = try await repository.fetchActiveItems(spaceID: MockDataFactory.singleSpaceID)

        #expect(archived.contains { $0.id == UUID(uuidString: "66666666-6666-6666-6666-666666666668")! })
        #expect(active.contains { $0.id == UUID(uuidString: "66666666-6666-6666-6666-666666666667")! })
    }

    @Test
    func localItemRepositoryRestoresArchivedCompletedTask() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalItemRepository(container: persistence.container)
        let archivedID = UUID(uuidString: "66666666-6666-6666-6666-666666666668")!

        let restored = try await repository.restoreArchivedItem(itemID: archivedID)
        let activeItems = try await repository.fetchActiveItems(spaceID: MockDataFactory.singleSpaceID)

        #expect(restored.isArchived == false)
        #expect(restored.archivedAt == nil)
        #expect(activeItems.contains { $0.id == archivedID })
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
        let repository = LocalProjectRepository(
            container: persistence.container,
            reminderScheduler: MockReminderScheduler()
        )

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
    func projectExpansionPresentationStateStartsCollapsedAndAdvancesAnimationBatch() {
        let first = UUID()
        let second = UUID()
        var state = ProjectExpansionPresentationState()

        state.resetForEntry(visibleProjectIDs: [first, second])

        #expect(state.expandedProjectIDs.isEmpty)
        #expect(state.animationBatch == 1)

        state.toggle(first)
        #expect(state.expandedProjectIDs == Set([first]))

        state.resetForEntry(visibleProjectIDs: [second])

        #expect(state.expandedProjectIDs.isEmpty)
        #expect(state.animationBatch == 2)
    }

    @Test
    func taskApplicationServiceCreatesAndQueriesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
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
    func taskApplicationServiceRejectsPendingTaskWhenQuickReplyIsSent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )

        let created = try await service.createTask(
            in: MockDataFactory.pairSharedSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "等你确认",
                assigneeMode: .partner
            )
        )

        let updated = try await service.respondToTask(
            in: MockDataFactory.pairSharedSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.partnerUserID,
            response: .notSuitable,
            message: "有点忙"
        )

        #expect(updated.assignmentState == .declined)
        #expect(updated.status == .declinedOrBlocked)
        #expect(updated.responseHistory.count == 1)
        #expect(updated.latestResponse?.kind == .notSuitable)
        #expect(updated.assignmentMessages.last?.body == "有点忙")
    }

    @Test
    func taskApplicationServiceCanRequeueDeclinedPartnerTask() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )

        let created = try await service.createTask(
            in: MockDataFactory.pairSharedSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "重新发一次",
                assigneeMode: .partner,
                assignmentNote: "麻烦你确认"
            )
        )

        _ = try await service.respondToTask(
            in: MockDataFactory.pairSharedSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.partnerUserID,
            response: .notSuitable,
            message: "有点忙"
        )

        let requeued = try await service.requeueDeclinedTask(
            in: MockDataFactory.pairSharedSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID
        )

        #expect(requeued.assignmentState == .pendingResponse)
        #expect(requeued.status == .pendingConfirmation)
        #expect(requeued.latestResponse == nil)
        #expect(requeued.responseHistory.isEmpty)
        #expect(requeued.assignmentMessages.map(\.authorID) == [MockDataFactory.currentUserID])
        #expect(requeued.assignmentMessages.last?.body == "麻烦你确认")
    }

    @Test
    func taskApplicationServiceCreatesPeriodicTaskWithExplicitTime() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: MockDataFactory.now)
        let dueAt = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: anchorDate) ?? anchorDate

        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "晚间回顾",
                dueAt: dueAt,
                hasExplicitTime: true,
                remindAt: dueAt.addingTimeInterval(-1_800),
                repeatRule: ItemRepeatRule(frequency: .daily)
            )
        )

        #expect(created.repeatRule?.frequency == .daily)
        #expect(created.hasExplicitTime == true)
        #expect(created.dueAt == dueAt)
        #expect(created.remindAt == dueAt.addingTimeInterval(-1_800))
    }

    @Test
    func taskTemplatePreservesNonDateSettingsFromDraft() async throws {
        let calendar = Calendar.current
        let dueAt = calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 25,
            hour: 20,
            minute: 45
        )) ?? .now
        let remindAt = dueAt.addingTimeInterval(-1_800)
        let template = TaskTemplate(
            spaceID: MockDataFactory.singleSpaceID,
            draft: TaskDraft(
                title: "晚间回顾",
                notes: "复盘今天 3 个关键结果",
                listID: MockDataFactory.todayListID,
                projectID: MockDataFactory.focusProjectID,
                dueAt: dueAt,
                hasExplicitTime: true,
                remindAt: remindAt,
                isPinned: true,
                repeatRule: ItemRepeatRule(frequency: .daily)
            ),
            calendar: calendar
        )

        #expect(template.title == "晚间回顾")
        #expect(template.notes == "复盘今天 3 个关键结果")
        #expect(template.listID == MockDataFactory.todayListID)
        #expect(template.projectID == MockDataFactory.focusProjectID)
        #expect(template.isPinned == true)
        #expect(template.time == TaskTemplateClockTime(hour: 20, minute: 45))
        #expect(template.reminderOffset == 1_800)
        #expect(template.repeatRule == ItemRepeatRule(frequency: .daily))
    }

    @Test
    func taskTemplateAppliesCurrentReferenceDateWhenCreatingDraft() async throws {
        let calendar = Calendar.current
        let template = TaskTemplate(
            spaceID: MockDataFactory.singleSpaceID,
            title: "周会准备",
            notes: "整理阻塞点和下周计划",
            listID: MockDataFactory.todayListID,
            projectID: MockDataFactory.focusProjectID,
            isPinned: true,
            hasExplicitTime: true,
            time: TaskTemplateClockTime(hour: 9, minute: 30),
            reminderOffset: 900,
            repeatRule: nil
        )
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 2,
            hour: 0,
            minute: 0
        )) ?? .now

        let draft = template.makeTaskDraft(for: referenceDate, calendar: calendar)

        #expect(calendar.component(.year, from: draft.dueAt ?? .distantPast) == 2026)
        #expect(calendar.component(.month, from: draft.dueAt ?? .distantPast) == 4)
        #expect(calendar.component(.day, from: draft.dueAt ?? .distantPast) == 2)
        #expect(calendar.component(.hour, from: draft.dueAt ?? .distantPast) == 9)
        #expect(calendar.component(.minute, from: draft.dueAt ?? .distantPast) == 30)
        #expect(draft.remindAt == (draft.dueAt?.addingTimeInterval(-900)))
        #expect(draft.listID == MockDataFactory.todayListID)
        #expect(draft.projectID == MockDataFactory.focusProjectID)
        #expect(draft.isPinned == true)
    }

    @Test
    func localTaskTemplateRepositorySupportsSaveAndFetch() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalTaskTemplateRepository(container: persistence.container)
        let template = TaskTemplate(
            spaceID: MockDataFactory.singleSpaceID,
            title: "每周清单整理",
            notes: "先清 inbox，再排优先级",
            hasExplicitTime: true,
            time: TaskTemplateClockTime(hour: 8, minute: 0),
            reminderOffset: 1_800
        )

        let saved = try await repository.saveTaskTemplate(template)
        let templates = try await repository.fetchTaskTemplates(spaceID: MockDataFactory.singleSpaceID)

        #expect(saved.title == "每周清单整理")
        #expect(templates.contains { $0.id == saved.id && $0.time == TaskTemplateClockTime(hour: 8, minute: 0) })
    }

    @Test
    func taskApplicationServiceUpdatesAndCompletesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
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
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let taskID = UUID(uuidString: "66666666-6666-6666-6666-666666666664")!

        _ = try await service.updateTask(
            in: MockDataFactory.singleSpaceID,
            taskID: taskID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "梳理本周项目优先级",
                notes: "午休前确认本周只保留 2 个高价值项目目标。",
                listID: MockDataFactory.todayListID,
                projectID: MockDataFactory.launchProjectID,
                dueAt: MockDataFactory.now.addingTimeInterval(3_600 * 14),
                hasExplicitTime: true,
                remindAt: MockDataFactory.now.addingTimeInterval(3_600 * 13 + 1_800),
                status: .inProgress
            )
        )
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
    func taskDraftFromExistingPairTaskDoesNotReuseLastMessageAsAssignmentNote() async throws {
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.pairSharedSpaceID,
            listID: MockDataFactory.todayListID,
            projectID: nil,
            creatorID: MockDataFactory.partnerUserID,
            title: "测试双人任务",
            notes: "纯牛奶",
            locationText: nil,
            executionRole: .recipient,
            assigneeMode: .partner,
            dueAt: .now,
            hasExplicitTime: true,
            remindAt: nil,
            status: .pendingConfirmation,
            assignmentState: .pendingResponse,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [
                TaskAssignmentMessage(
                    authorID: MockDataFactory.partnerUserID,
                    body: "这是一条已有留言",
                    createdAt: .now
                )
            ],
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )

        let draft = TaskDraft(item: item)

        #expect(draft.assignmentNote == nil)
        #expect(draft.notes == "纯牛奶")
    }

    @Test @MainActor
    func homeViewModelUpdatesDetailDraftAssigneeModeWithoutExclusivityConflict() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .pair

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        viewModel.detailDraft = TaskDraft(
            title: "测试任务",
            assigneeMode: .self,
            assignmentState: .active
        )

        viewModel.updateDraftAssigneeMode(.partner)
        #expect(viewModel.detailDraft?.assigneeMode == .partner)
        #expect(viewModel.detailDraft?.assignmentState == .pendingResponse)
        #expect(viewModel.detailDraft?.status == .pendingConfirmation)

        viewModel.updateDraftAssigneeMode(.both)
        #expect(viewModel.detailDraft?.assigneeMode == .both)
        #expect(viewModel.detailDraft?.assignmentState == .active)
        #expect(viewModel.detailDraft?.status == .inProgress)
    }

    @Test
    func periodicTaskCompletionUsesVisibleOccurrenceDateForPastDay() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let referenceDate = calendar.date(byAdding: .day, value: -1, to: Date.now) ?? Date.now
        let dueAt = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: referenceDate
        ) ?? referenceDate
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "每日回顾",
                dueAt: dueAt,
                hasExplicitTime: true,
                repeatRule: ItemRepeatRule(frequency: .daily)
            )
        )

        let completed = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: referenceDate
        )

        #expect(completed.status != .completed)
        #expect(completed.completedAt == nil)
        #expect(completed.isCompleted(on: referenceDate, calendar: calendar))
    }

    @Test
    func periodicTaskCompletionKeepsDifferentOccurrenceDaysIndependent() async throws {
        let itemRepository = TestItemRepository()
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let wednesday = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let thursday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let dueAt = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: wednesday
        ) ?? wednesday
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "数据通报",
                dueAt: dueAt,
                hasExplicitTime: true,
                repeatRule: ItemRepeatRule(
                    frequency: .weekly,
                    weekdays: [calendar.component(.weekday, from: wednesday), calendar.component(.weekday, from: thursday)]
                )
            )
        )

        _ = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: thursday
        )

        let completedWednesday = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: wednesday
        )

        #expect(completedWednesday.isCompleted(on: wednesday, calendar: calendar))
        #expect(completedWednesday.isCompleted(on: thursday, calendar: calendar))
    }

    @Test
    func periodicTaskReopenOnlyAffectsCurrentOccurrenceDay() async throws {
        let itemRepository = TestItemRepository()
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let wednesday = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let thursday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let dueAt = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: wednesday
        ) ?? wednesday
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "日报检查",
                dueAt: dueAt,
                hasExplicitTime: true,
                repeatRule: ItemRepeatRule(
                    frequency: .weekly,
                    weekdays: [calendar.component(.weekday, from: wednesday), calendar.component(.weekday, from: thursday)]
                )
            )
        )

        _ = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: wednesday
        )
        _ = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: thursday
        )

        let reopenedWednesday = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: wednesday
        )

        #expect(reopenedWednesday.isCompleted(on: wednesday, calendar: calendar) == false)
        #expect(reopenedWednesday.isCompleted(on: thursday, calendar: calendar))
    }

    @Test
    func oneOffTaskCompletedAfterItsDueDayStillCountsAsCompletedOnScheduledDate() {
        let calendar = Calendar.current
        let scheduledDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)) ?? .now
        let dueAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: scheduledDate) ?? scheduledDate
        let completedAt = calendar.date(byAdding: .day, value: 1, to: dueAt) ?? dueAt
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "补完成的历史任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: nil,
            status: .completed,
            latestResponse: nil,
            responseHistory: [],
            createdAt: dueAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            isPinned: false,
            isDraft: false
        )

        #expect(item.isCompleted(on: scheduledDate, calendar: calendar))
        #expect(item.completionDate(on: scheduledDate, calendar: calendar) == completedAt)
    }

    @Test
    func nonPeriodicTaskCompletionStillUsesActualCompletionDay() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let referenceDate = calendar.date(byAdding: .day, value: -1, to: Date.now) ?? Date.now
        let dueAt = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: referenceDate
        ) ?? referenceDate
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "补发周报",
                dueAt: dueAt,
                hasExplicitTime: true
            )
        )

        let completed = try await service.toggleTaskCompletion(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: referenceDate
        )

        #expect(completed.status == .completed)
        #expect(calendar.isDate(completed.completedAt ?? .distantPast, inSameDayAs: Date.now))
    }

    @Test
    func taskApplicationServiceMovesReschedulesAndArchivesTasks() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
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
    func taskApplicationServiceSnoozesTaskToTomorrowPreservingExplicitTime() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let dueAt = Calendar.current.date(
            bySettingHour: 18,
            minute: 15,
            second: 0,
            of: MockDataFactory.now
        ) ?? MockDataFactory.now
        let remindAt = dueAt.addingTimeInterval(-1_800)
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "明日推进任务",
                dueAt: dueAt,
                hasExplicitTime: true,
                remindAt: remindAt
            )
        )

        let snoozed = try await service.snoozeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            option: .tomorrow
        )

        let expectedDueAt = Calendar.current.date(byAdding: .day, value: 1, to: dueAt)
        let expectedRemindAt = Calendar.current.date(byAdding: .day, value: 1, to: remindAt)

        #expect(snoozed.dueAt == expectedDueAt)
        #expect(snoozed.remindAt == expectedRemindAt)
        #expect(snoozed.hasExplicitTime == true)
    }

    @Test
    func taskApplicationServiceSnoozesTaskByRelativeMinutesAndKeepsReminderDelta() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let dueAt = MockDataFactory.now.addingTimeInterval(3_600)
        let remindAt = dueAt.addingTimeInterval(-900)
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "两小时后再做",
                dueAt: dueAt,
                hasExplicitTime: true,
                remindAt: remindAt
            )
        )

        let snoozed = try await service.snoozeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            option: .minutes(120)
        )

        #expect(snoozed.dueAt != nil)
        #expect(snoozed.hasExplicitTime == true)
        #expect(snoozed.remindAt?.timeIntervalSince(snoozed.dueAt ?? .now) == -900)
    }

    @Test
    func taskApplicationServiceBuildsTodaySummaryFromActionableTasks() async throws {
        let itemRepository = TestItemRepository()
        let syncCoordinator = TestSyncCoordinator()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: MockReminderScheduler()
        )
        let calendar = Calendar.current
        let referenceDate = Date.now
        let baseDueAt = calendar.date(
            bySettingHour: 10,
            minute: 0,
            second: 0,
            of: referenceDate
        ) ?? referenceDate

        let pinnedTask = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "今天的置顶任务",
                dueAt: baseDueAt,
                hasExplicitTime: true,
                isPinned: true
            )
        )
        _ = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "今天的普通任务 A",
                dueAt: baseDueAt.addingTimeInterval(1_800),
                hasExplicitTime: true
            )
        )
        _ = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "今天的普通任务 B",
                dueAt: baseDueAt.addingTimeInterval(3_600),
                hasExplicitTime: true
            )
        )
        let completedTask = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "今天完成的任务",
                dueAt: baseDueAt.addingTimeInterval(5_400),
                hasExplicitTime: true
            )
        )

        _ = try await service.completeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: completedTask.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: referenceDate
        )

        let summary = try await service.todaySummary(
            in: MockDataFactory.singleSpaceID,
            referenceDate: referenceDate
        )

        #expect(summary.actionableCount == 3)
        #expect(summary.dueTodayCount == 3)
        #expect(summary.completedTodayCount == 1)
        #expect(summary.pinnedCount == 1)
        #expect(summary.referenceDate == referenceDate)
        #expect(summary.actionableCount == summary.dueTodayCount)
        #expect(pinnedTask.isPinned == true)
    }

    @Test @MainActor
    func homeViewModelAllowsBackToBackCompletionAcrossDifferentItems() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let taskService = TestHomeTaskApplicationService()
        let itemRepository = TestItemRepository()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskService,
            itemRepository: itemRepository,
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        let baseDate = Date.now
        let first = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "逾期周期任务 A",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: baseDate,
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: nil,
            isPinned: false,
            isDraft: false,
            repeatRule: ItemRepeatRule(frequency: .daily)
        )
        let second = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "逾期周期任务 B",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: baseDate.addingTimeInterval(60),
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: nil,
            isPinned: false,
            isDraft: false,
            repeatRule: ItemRepeatRule(frequency: .daily)
        )
        viewModel.items = [first, second]

        async let completeFirst: Void = viewModel.completeItem(first.id)
        async let completeSecond: Void = viewModel.completeItem(second.id)
        _ = await (completeFirst, completeSecond)

        let completedIDs = await taskService.completedTaskIDs()
        #expect(Set(completedIDs) == Set([first.id, second.id]))
        #expect(viewModel.isAnimatingCompletion(for: first.id, on: baseDate) == false)
        #expect(viewModel.isAnimatingCompletion(for: second.id, on: baseDate) == false)
        #expect(viewModel.items.filter { $0.isCompleted(on: baseDate, calendar: Calendar.current) }.count == 2)
    }

    @Test @MainActor
    func homeViewModelHidesDeclinedPartnerTaskForReceiverButKeepsItForSender() {
        let receiverSession = SessionStore()
        receiverSession.currentUser = MockDataFactory.makeCurrentUser()
        receiverSession.singleSpace = MockDataFactory.makeSingleSpace()
        receiverSession.pairSpaceSummary = MockDataFactory.makePairSpaceSummary()
        receiverSession.activeMode = .pair

        let senderSession = SessionStore()
        senderSession.currentUser = MockDataFactory.makePartnerUser()
        senderSession.singleSpace = MockDataFactory.makeSingleSpace()
        senderSession.pairSpaceSummary = MockDataFactory.makePairSpaceSummary()
        senderSession.activeMode = .pair

        let declinedTask = Item(
            id: UUID(),
            spaceID: MockDataFactory.pairSharedSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.partnerUserID,
            title: "被拒绝的请求",
            notes: nil,
            locationText: nil,
            executionRole: .recipient,
            assigneeMode: .partner,
            dueAt: Date.now,
            hasExplicitTime: false,
            remindAt: nil,
            status: .declinedOrBlocked,
            assignmentState: .declined,
            latestResponse: ItemResponse(
                responderID: MockDataFactory.currentUserID,
                kind: .notSuitable,
                message: "有点忙",
                respondedAt: Date.now
            ),
            responseHistory: [],
            assignmentMessages: [
                TaskAssignmentMessage(
                    authorID: MockDataFactory.currentUserID,
                    body: "有点忙",
                    createdAt: Date.now
                )
            ],
            lastActionByUserID: MockDataFactory.currentUserID,
            lastActionAt: Date.now,
            createdAt: Date.now,
            updatedAt: Date.now,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )

        let receiverViewModel = HomeViewModel(
            sessionStore: receiverSession,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        receiverViewModel.items = [declinedTask]

        let senderViewModel = HomeViewModel(
            sessionStore: senderSession,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        senderViewModel.items = [declinedTask]

        #expect(receiverViewModel.activeTimelineEntries.isEmpty)
        #expect(senderViewModel.activeTimelineEntries.count == 1)
        #expect(senderViewModel.activeTimelineEntries.first?.responseStateText == "已拒绝")
    }

    @Test @MainActor
    func homeViewModelIgnoresDuplicateCompletionWhileSameOccurrenceIsInFlight() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let taskService = TestHomeTaskApplicationService()
        let itemRepository = TestItemRepository()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskService,
            itemRepository: itemRepository,
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        let baseDate = Date.now
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "同一 occurrence 连点",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: baseDate,
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: baseDate,
            updatedAt: baseDate,
            completedAt: nil,
            isPinned: false,
            isDraft: false,
            repeatRule: ItemRepeatRule(frequency: .daily)
        )
        viewModel.items = [item]

        async let firstTap: Void = viewModel.completeItem(item.id)
        async let secondTap: Void = viewModel.completeItem(item.id)
        _ = await (firstTap, secondTap)

        let completedIDs = await taskService.completedTaskIDs()
        #expect(completedIDs == [item.id])
        #expect(viewModel.items.first?.isCompleted(on: baseDate, calendar: Calendar.current) == true)
    }

    @Test
    func dockHubPresentationStateCollapsesWhenBlockingChromeAppears() {
        let state = DockHubPresentationState(
            isProjectModePresented: false,
            isQuickCapturePresented: true,
            isProfilePresented: false,
            hasActiveComposer: false,
            hasPendingQuickCaptureConfirmation: false
        )

        #expect(state.shouldCollapseHub == true)
    }

    @Test
    func dockHubPresentationStateStaysExpandedInDefaultTodayContext() {
        let state = DockHubPresentationState(
            isProjectModePresented: false,
            isQuickCapturePresented: false,
            isProfilePresented: false,
            hasActiveComposer: false,
            hasPendingQuickCaptureConfirmation: false
        )

        #expect(state.shouldCollapseHub == false)
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

    @Test
    func localUserProfileRepositoryPersistsNotificationPreferences() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = MockDataFactory.makeCurrentUser()
        let customPreferences = NotificationSettings(
            taskReminderEnabled: false,
            dailySummaryEnabled: true,
            calendarReminderEnabled: true,
            futureCollaborationInviteEnabled: true,
            taskUrgencyWindowMinutes: 33,
            defaultSnoozeMinutes: 67,
            quickTimePresetMinutes: [7, 31, 62, 95],
            pairQuickReplyMessages: ["不想做", "没时间", "有点忙"],
            completedTaskAutoArchiveEnabled: false,
            completedTaskAutoArchiveDays: 14
        )

        _ = try await repository.savePreferences(for: user, preferences: customPreferences)
        let mergedUser = await repository.mergedUser(user)
        let restoredUser = try #require(mergedUser)

        #expect(restoredUser.preferences.taskReminderEnabled == false)
        #expect(restoredUser.preferences.taskUrgencyWindowMinutes == 35)
        #expect(restoredUser.preferences.defaultSnoozeMinutes == 65)
        #expect(restoredUser.preferences.quickTimePresetMinutes == [5, 30, 60])
        #expect(restoredUser.preferences.completedTaskAutoArchiveEnabled == false)
        #expect(restoredUser.preferences.completedTaskAutoArchiveDays == 14)
    }

    @Test
    func localUserProfileRepositoryPersistsAvatarPhotoFileAcrossMerge() async throws {
        #if canImport(UIKit)
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemPink).jpegData(compressionQuality: 0.9))

        let savedUser = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        let restoredUser = try #require(await repository.mergedUser(user))

        #expect(fileName == "\(user.id.uuidString.lowercased())-avatar.jpg")
        #expect(restoredUser.avatarPhotoFileName == fileName)
        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
            )
        )
        #else
        Issue.record("UIKit unavailable for avatar persistence test")
        #endif
    }

    @Test
    func localUserProfileRepositoryRestoresAvatarAcrossOnDiskRelaunch() async throws {
        #if canImport(UIKit)
        let storeURL = makeAvatarTestStoreURL(testName: "AvatarRelaunch")
        let repository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemOrange).jpegData(compressionQuality: 0.9))

        let savedUser = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        let relaunchedRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let restoredUser = try #require(await relaunchedRepository.mergedUser(user))

        #expect(fileName == "\(user.id.uuidString.lowercased())-avatar.jpg")
        #expect(restoredUser.avatarPhotoFileName == fileName)
        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
            )
        )
        #else
        Issue.record("UIKit unavailable for avatar relaunch persistence test")
        #endif
    }

    @Test
    func localUserProfileRepositoryRebuildsMissingAvatarFileFromPersistentPayload() async throws {
        #if canImport(UIKit)
        let storeURL = makeAvatarTestStoreURL(testName: "AvatarRebuildFromPayload")
        let repository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemPurple).jpegData(compressionQuality: 0.9))

        let savedUser = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        try FileManager.default.removeItem(at: UserAvatarStorage.fileURL(fileName: fileName))

        let relaunchedRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let restoredUser = try #require(await relaunchedRepository.mergedUser(user))
        let verificationContext = ModelContext(try makeUserProfileContainer(storeURL: storeURL))
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )
        let repairedRecord = try #require(try verificationContext.fetch(descriptor).first)

        #expect(restoredUser.avatarPhotoFileName == fileName)
        #expect(repairedRecord.avatarPhotoFileName == fileName)
        #expect(repairedRecord.avatarPhotoData == data)
        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
            )
        )
        #else
        Issue.record("UIKit unavailable for avatar rebuild test")
        #endif
    }

    @Test
    func localUserProfileRepositoryRewritesCorruptedAvatarFileFromPersistentPayload() async throws {
        #if canImport(UIKit)
        let storeURL = makeAvatarTestStoreURL(testName: "AvatarRepairCorruptedFile")
        let repository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemRed).jpegData(compressionQuality: 0.9))

        let savedUser = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
        try Data([0x00, 0x01, 0x02]).write(to: fileURL, options: .atomic)

        let relaunchedRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let restoredUser = try #require(await relaunchedRepository.mergedUser(user))
        let repairedData = try Data(contentsOf: fileURL)

        #expect(restoredUser.avatarPhotoFileName == fileName)
        #expect(repairedData == data)
        #else
        Issue.record("UIKit unavailable for avatar corrupted-file repair test")
        #endif
    }

    @Test @MainActor
    func localUserProfileRepositoryPreloadsRuntimeAvatarCacheFromPersistentPayload() async throws {
        #if canImport(UIKit)
        let storeURL = makeAvatarTestStoreURL(testName: "AvatarRuntimeCacheWarmup")
        let repository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemIndigo).jpegData(compressionQuality: 0.9))

        let savedUser = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        UserAvatarRuntimeStore.remove(fileName: fileName)

        let relaunchedRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: storeURL))
        _ = await relaunchedRepository.mergedUser(user)

        #expect(UserAvatarRuntimeStore.image(for: fileName) != nil)
        #else
        Issue.record("UIKit unavailable for avatar runtime cache warmup test")
        #endif
    }

    @Test @MainActor
    func localUserProfileRepositoryKeepsAvatarWhenPayloadExistsButFileRepairFails() async throws {
        #if canImport(UIKit)
        let persistence = PersistenceController(inMemory: true)
        let failingStore = FailingRepairAvatarMediaStore()
        let repository = LocalUserProfileRepository(
            container: persistence.container,
            avatarMediaStore: failingStore
        )
        let user = makeAvatarTestUser()
        let fileName = failingStore.canonicalFileName(for: user.id)
        let data = try #require(makeAvatarTestImage(fillColor: .systemTeal).jpegData(compressionQuality: 0.9))
        let context = ModelContext(persistence.container)

        UserAvatarRuntimeStore.remove(fileName: fileName)
        context.insert(
            PersistentUserProfile(
                userID: user.id,
                displayName: user.displayName,
                avatarSystemName: nil,
                avatarPhotoFileName: fileName,
                avatarPhotoData: data,
                taskReminderEnabled: user.preferences.taskReminderEnabled,
                dailySummaryEnabled: user.preferences.dailySummaryEnabled,
                calendarReminderEnabled: user.preferences.calendarReminderEnabled,
                futureCollaborationInviteEnabled: user.preferences.futureCollaborationInviteEnabled,
                taskUrgencyWindowMinutes: user.preferences.taskUrgencyWindowMinutes,
                defaultSnoozeMinutes: user.preferences.defaultSnoozeMinutes,
                quickTimePresetMinutes: user.preferences.quickTimePresetMinutes,
                completedTaskAutoArchiveEnabled: user.preferences.completedTaskAutoArchiveEnabled,
                completedTaskAutoArchiveDays: user.preferences.completedTaskAutoArchiveDays,
                updatedAt: user.updatedAt
            )
        )
        try context.save()

        let restoredUser = try #require(await repository.mergedUser(user))

        #expect(restoredUser.avatarPhotoFileName == fileName)
        #expect(UserAvatarRuntimeStore.image(for: fileName) != nil)
        #else
        Issue.record("UIKit unavailable for avatar payload fallback test")
        #endif
    }

    @Test
    func localUserProfileRepositoryRecoversAvatarFromCanonicalFileWhenProfileRecordIsMissing() async throws {
        #if canImport(UIKit)
        let firstStoreURL = makeAvatarTestStoreURL(testName: "AvatarRecoverFromFileWrite")
        let secondStoreURL = makeAvatarTestStoreURL(testName: "AvatarRecoverFromFileRead")
        let savingRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: firstStoreURL))
        let recoveringRepository = LocalUserProfileRepository(container: try makeUserProfileContainer(storeURL: secondStoreURL))
        let user = makeAvatarTestUser()
        let data = try #require(makeAvatarTestImage(fillColor: .systemGreen).jpegData(compressionQuality: 0.9))

        let savedUser = try await savingRepository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(data)
        )
        let fileName = try #require(savedUser.avatarPhotoFileName)
        let recoveredUser = try #require(await recoveringRepository.mergedUser(user))
        let verificationContext = ModelContext(try makeUserProfileContainer(storeURL: secondStoreURL))
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )
        let repairedRecord = try #require(try verificationContext.fetch(descriptor).first)

        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
            )
        )
        #expect(recoveredUser.avatarPhotoFileName == fileName)
        #expect(repairedRecord.avatarPhotoFileName == fileName)
        #else
        Issue.record("UIKit unavailable for avatar recovery test")
        #endif
    }

    @Test
    func localUserProfileRepositoryReplacesExistingCanonicalAvatarFile() async throws {
        #if canImport(UIKit)
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = makeAvatarTestUser()
        let firstData = try #require(makeAvatarTestImage(fillColor: .systemPink).jpegData(compressionQuality: 0.9))
        let secondData = try #require(makeAvatarTestImage(fillColor: .systemBlue).jpegData(compressionQuality: 0.9))

        let firstSave = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(firstData)
        )
        let secondSave = try await repository.saveProfile(
            for: firstSave,
            displayName: firstSave.displayName,
            avatarUpdate: .replacePhoto(secondData)
        )

        let fileName = try #require(secondSave.avatarPhotoFileName)
        let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
        let savedData = try Data(contentsOf: fileURL)

        #expect(fileName == "\(user.id.uuidString.lowercased())-avatar.jpg")
        #expect(savedData == secondData)
        #else
        Issue.record("UIKit unavailable for avatar replace test")
        #endif
    }

    @Test
    func localUserProfileRepositoryRepairsLegacyAvatarPayloadAndClearsBlob() async throws {
        #if canImport(UIKit)
        let storeURL = makeAvatarTestStoreURL(testName: "AvatarLegacyRepair")
        let container = try makeUserProfileContainer(storeURL: storeURL)
        let repository = LocalUserProfileRepository(container: container)
        let user = makeAvatarTestUser()
        let legacyFileName = "\(user.id.uuidString.lowercased())-avatar-legacy.jpg"
        let data = try #require(makeAvatarTestImage(fillColor: .systemTeal).jpegData(compressionQuality: 0.9))

        let context = ModelContext(container)
        let record = PersistentUserProfile(user: user)
        record.avatarPhotoFileName = legacyFileName
        record.avatarPhotoData = data
        context.insert(record)
        try context.save()

        let restoredUser = try #require(await repository.mergedUser(user))
        let repairedFileName = try #require(restoredUser.avatarPhotoFileName)
        let verificationContext = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )
        let repairedRecord = try #require(try verificationContext.fetch(descriptor).first)

        #expect(repairedFileName == "\(user.id.uuidString.lowercased())-avatar.jpg")
        #expect(repairedRecord.avatarPhotoFileName == repairedFileName)
        #expect(repairedRecord.avatarPhotoData == data)
        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: repairedFileName).path(percentEncoded: false)
            )
        )
        #else
        Issue.record("UIKit unavailable for avatar legacy repair test")
        #endif
    }

    @Test @MainActor
    func completedHistoryViewModelShowsCompletedTasksBeforeArchive() async throws {
        let persistence = PersistenceController(inMemory: true)
        let itemRepository = LocalItemRepository(container: persistence.container)
        let sessionStore = SessionStore()
        sessionStore.authState = .signedIn
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let completedAt = Date.now
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "历史页应显示未归档完成任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: completedAt,
            hasExplicitTime: false,
            remindAt: nil,
            status: .completed,
            latestResponse: nil,
            responseHistory: [],
            createdAt: completedAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            isPinned: false,
            isDraft: false
        )
        _ = try await itemRepository.saveItem(item)

        let viewModel = CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: itemRepository,
            taskApplicationService: DefaultTaskApplicationService(
                itemRepository: itemRepository,
                syncCoordinator: NoOpSyncCoordinator(),
                reminderScheduler: MockReminderScheduler()
            ),
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: MockReminderScheduler())
        )

        await viewModel.reload()

        #expect(viewModel.items.contains { $0.id == item.id })
        let fetched = try #require(viewModel.items.first(where: { $0.id == item.id }))
        #expect(viewModel.isArchived(fetched) == false)
    }

    @Test @MainActor
    func homeViewModelSuppressesImminentUrgencyWhenTaskReminderIsDisabled() async throws {
        let sessionStore = SessionStore()
        var user = MockDataFactory.makeCurrentUser()
        user.preferences.taskReminderEnabled = false
        user.preferences.taskUrgencyWindowMinutes = 30
        sessionStore.currentUser = user
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        let now = Date.now
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "临期任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: now.addingTimeInterval(5 * 60),
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )

        viewModel.selectedDate = now
        viewModel.items = [item]

        #expect(viewModel.timelineEntries.first?.urgency == .normal)
    }

    @Test @MainActor
    func homeViewModelDoesNotShowOverdueCapsuleForPastSelectedDate() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)) ?? .now
        let firstDueAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let secondDueAt = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let completedAt = calendar.date(byAdding: .day, value: 1, to: firstDueAt) ?? firstDueAt

        viewModel.selectedDate = selectedDate
        viewModel.items = [
            Item(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                listID: nil,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "历史逾期任务 A",
                notes: nil,
                locationText: nil,
                executionRole: .initiator,
                dueAt: firstDueAt,
                hasExplicitTime: true,
                remindAt: nil,
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: firstDueAt,
                updatedAt: firstDueAt,
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                listID: nil,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "历史逾期任务 B",
                notes: nil,
                locationText: nil,
                executionRole: .initiator,
                dueAt: secondDueAt,
                hasExplicitTime: true,
                remindAt: nil,
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: secondDueAt,
                updatedAt: secondDueAt,
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                listID: nil,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "同日已完成任务",
                notes: nil,
                locationText: nil,
                executionRole: .initiator,
                dueAt: firstDueAt,
                hasExplicitTime: true,
                remindAt: nil,
                status: .completed,
                latestResponse: nil,
                responseHistory: [],
                createdAt: firstDueAt,
                updatedAt: completedAt,
                completedAt: completedAt,
                isPinned: false,
                isDraft: false
            )
        ]

        #expect(viewModel.overdueEntryCount == 2)
        #expect(viewModel.showsOverdueCapsule == false)
        #expect(viewModel.overdueSummaryEntries.isEmpty)
    }

    @Test @MainActor
    func homeViewModelKeepsTodayOverdueItemsInSummaryInsteadOfMainTimeline() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: TestHomeTaskApplicationService(),
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let overdueDueAt = calendar.date(byAdding: .hour, value: -3, to: today) ?? today
        let todayDueAt = calendar.date(byAdding: .hour, value: 23, to: today) ?? today

        viewModel.selectedDate = Date.now
        viewModel.items = [
            Item(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                listID: nil,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "昨天没完成",
                notes: nil,
                locationText: nil,
                executionRole: .initiator,
                dueAt: overdueDueAt,
                hasExplicitTime: true,
                remindAt: nil,
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: overdueDueAt,
                updatedAt: overdueDueAt,
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(),
                spaceID: MockDataFactory.singleSpaceID,
                listID: nil,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "今天要做",
                notes: nil,
                locationText: nil,
                executionRole: .initiator,
                dueAt: todayDueAt,
                hasExplicitTime: true,
                remindAt: nil,
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: todayDueAt,
                updatedAt: todayDueAt,
                completedAt: nil,
                isPinned: false,
                isDraft: false
            )
        ]

        #expect(viewModel.showsOverdueCapsule)
        #expect(viewModel.overdueSummaryEntries.count == 1)
        #expect(viewModel.activeTimelineEntries.count == 1)
        #expect(viewModel.activeTimelineEntries.first?.title == "今天要做")
    }

    @Test @MainActor
    func homeViewModelAnimatesHistoricalCompletionForOneOffOverdueTask() async throws {
        let sessionStore = SessionStore()
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.singleSpace = MockDataFactory.makeSingleSpace()
        sessionStore.activeMode = .single

        let taskService = TestHistoricalOneOffCompletionTaskService()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskService,
            itemRepository: TestItemRepository(),
            quickCaptureParser: RuleBasedQuickCaptureParser(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)) ?? .now
        let dueAt = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "历史逾期单次任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: dueAt,
            updatedAt: dueAt,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )

        viewModel.selectedDate = selectedDate
        viewModel.items = [item]

        let completionTask = Task {
            await viewModel.completeItem(item.id)
        }

        var didEnterAnimatingState = viewModel.isAnimatingCompletion(for: item.id, on: selectedDate)
        if didEnterAnimatingState == false {
            for _ in 0..<8 where didEnterAnimatingState == false {
                try? await Task.sleep(for: .milliseconds(20))
                didEnterAnimatingState = viewModel.isAnimatingCompletion(for: item.id, on: selectedDate)
            }
        }
        #expect(didEnterAnimatingState)

        await completionTask.value

        #expect(viewModel.isAnimatingCompletion(for: item.id, on: selectedDate) == false)
        #expect(viewModel.items.first?.isCompleted(on: selectedDate, calendar: calendar) == true)
        #expect(viewModel.completedEntryCount == 1)
    }

    @Test
    func notificationSettingsNormalizesCustomMinutesToFiveMinuteSteps() {
        #expect(NotificationSettings.normalizedSnoozeMinutes(3) == 5)
        #expect(NotificationSettings.normalizedSnoozeMinutes(33) == 35)
        #expect(NotificationSettings.normalizedSnoozeMinutes(188) == 180)
    }

    @Test
    func notificationSettingsNormalizesPairQuickReplyMessages() {
        let normalized = NotificationSettings.normalizedPairQuickReplyMessages([
            "  不想做  ",
            "",
            "有点忙",
            "没时间"
        ])

        #expect(normalized == ["不想做", "有点忙", "没时间"])
    }

    @Test
    func stagedReminderContextEnablesReminderAfterTimeSelection() {
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30)) ?? .now
        let selectedTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 18, minute: 45)) ?? .now
        let context = TaskEditorStagedReminderContext(
            selectedDate: selectedDate,
            selectedTime: selectedTime,
            reminderOffset: 1_800
        )

        #expect(context.isReminderMenuDisabled == false)
        #expect(calendar.component(.hour, from: context.reminderTargetDate) == 18)
        #expect(calendar.component(.minute, from: context.reminderTargetDate) == 45)
        #expect(calendar.component(.hour, from: context.remindAt ?? .distantPast) == 18)
        #expect(calendar.component(.minute, from: context.remindAt ?? .distantPast) == 15)
    }

    @Test
    func stagedReminderContextDisablesReminderWithoutExplicitTime() {
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30)) ?? .now
        let context = TaskEditorStagedReminderContext(
            selectedDate: selectedDate,
            selectedTime: nil,
            reminderOffset: 1_800
        )

        #expect(context.isReminderMenuDisabled)
        #expect(calendar.component(.hour, from: context.reminderTargetDate) == 9)
        #expect(calendar.component(.minute, from: context.reminderTargetDate) == 0)
        #expect(calendar.component(.hour, from: context.remindAt ?? .distantPast) == 8)
        #expect(calendar.component(.minute, from: context.remindAt ?? .distantPast) == 30)
    }

    @Test
    func stagedReminderContextRecomputesReminderFromLatestStagedTime() {
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30)) ?? .now
        let originalTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 9, minute: 0)) ?? .now
        let updatedTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 14, minute: 20)) ?? .now

        let originalContext = TaskEditorStagedReminderContext(
            selectedDate: selectedDate,
            selectedTime: originalTime,
            reminderOffset: 900
        )
        let updatedContext = TaskEditorStagedReminderContext(
            selectedDate: selectedDate,
            selectedTime: updatedTime,
            reminderOffset: 900
        )

        #expect(calendar.component(.hour, from: originalContext.remindAt ?? .distantPast) == 8)
        #expect(calendar.component(.minute, from: originalContext.remindAt ?? .distantPast) == 45)
        #expect(calendar.component(.hour, from: updatedContext.remindAt ?? .distantPast) == 14)
        #expect(calendar.component(.minute, from: updatedContext.remindAt ?? .distantPast) == 5)
    }
}

private struct FailingRepairAvatarMediaStore: UserAvatarMediaStoreProtocol {
    let baseStore = LocalUserAvatarMediaStore()

    nonisolated func canonicalFileName(for userID: UUID) -> String {
        baseStore.canonicalFileName(for: userID)
    }

    nonisolated func avatarData(named fileName: String) throws -> Data {
        try baseStore.avatarData(named: fileName)
    }

    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws {
        struct SimulatedWriteFailure: LocalizedError {
            var errorDescription: String? { "simulated avatar repair failure" }
        }

        throw SimulatedWriteFailure()
    }

    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws {}

    nonisolated func removeAvatar(named fileName: String) throws {
        try baseStore.removeAvatar(named: fileName)
    }

    nonisolated func fileExists(named fileName: String) -> Bool {
        false
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

actor TestItemRepository: ItemRepositoryProtocol {
    private var items: [Item] = []
    private var occurrenceCompletions: [UUID: [ItemOccurrenceCompletion]] = [:]
    private let calendar = Calendar.current

    func fetchActiveItems(spaceID: UUID?) async throws -> [Item] {
        items
            .filter { $0.spaceID == spaceID && $0.isArchived == false }
            .map(hydratedItem)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchArchivedCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        let normalizedLimit = max(limit, 1)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .filter { item in
                guard item.spaceID == spaceID else { return false }
                guard item.isArchived, item.completedAt != nil, let archivedAt = item.archivedAt else {
                    return false
                }
                if let before, archivedAt >= before {
                    return false
                }
                guard let normalizedSearch, normalizedSearch.isEmpty == false else {
                    return true
                }
                return item.title.localizedStandardContains(normalizedSearch)
            }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
            .prefix(normalizedLimit)
            .map { $0 }
    }

    func fetchCompletedItems(
        spaceID: UUID?,
        searchText: String?,
        before: Date?,
        limit: Int
    ) async throws -> [Item] {
        let normalizedLimit = max(limit, 1)
        let normalizedSearch = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .filter { item in
                guard item.spaceID == spaceID else { return false }
                guard let completedAt = item.completedAt else { return false }
                let cursorDate = item.archivedAt ?? completedAt
                if let before, cursorDate >= before {
                    return false
                }
                guard let normalizedSearch, normalizedSearch.isEmpty == false else {
                    return true
                }
                return item.title.localizedStandardContains(normalizedSearch)
            }
            .sorted {
                ($0.archivedAt ?? $0.completedAt ?? .distantPast) > ($1.archivedAt ?? $1.completedAt ?? .distantPast)
            }
            .prefix(normalizedLimit)
            .map { $0 }
    }

    func archiveCompletedItemsIfNeeded(
        spaceID: UUID?,
        referenceDate: Date,
        autoArchiveDays: Int
    ) async throws -> Bool {
        let thresholdDays = NotificationSettings.normalizedCompletedTaskAutoArchiveDays(autoArchiveDays)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -thresholdDays, to: referenceDate) else {
            return false
        }

        var didArchiveItems = false
        items = items.map { item in
            guard item.spaceID == spaceID else { return item }
            guard item.isArchived == false, let completedAt = item.completedAt else { return item }
            guard completedAt <= cutoffDate else { return item }

            var copy = item
            copy.isArchived = true
            copy.archivedAt = referenceDate
            copy.isPinned = false
            didArchiveItems = true
            return copy
        }
        return didArchiveItems
    }

    func restoreArchivedItem(itemID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        items[index].isArchived = false
        items[index].archivedAt = nil
        return hydratedItem(items[index])
    }

    func fetchItem(itemID: UUID) async throws -> Item? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        return hydratedItem(item)
    }

    func fetchOccurrenceCompletions(itemIDs: [UUID]) async throws -> [UUID: [ItemOccurrenceCompletion]] {
        var result: [UUID: [ItemOccurrenceCompletion]] = [:]
        for itemID in itemIDs {
            result[itemID] = occurrenceCompletions[itemID, default: []]
        }
        return result
    }

    func isCompleted(itemID: UUID, on referenceDate: Date) async throws -> Bool {
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        return hydratedItem(item).isCompleted(on: referenceDate, calendar: calendar)
    }

    func updateItemStatus(itemID: UUID, response: ItemResponseKind?, message: String?, actorID: UUID) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if let response {
            let responseRecord = ItemResponse(
                responderID: actorID,
                kind: response,
                message: message,
                respondedAt: .now
            )
            item.latestResponse = responseRecord
            item.responseHistory.append(responseRecord)
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                response: response
            )
            item.assignmentState = ItemStateMachine.nextAssignmentState(
                from: item.assignmentState,
                response: response
            )
            item.lastActionByUserID = actorID
            item.lastActionAt = .now
        }
        item.updatedAt = .now
        items[index] = item
        return hydratedItem(item)
    }

    func markCompleted(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            item.status = ItemStateMachine.nextStatus(
                from: item.status,
                executionRole: item.executionRole,
                isCompletion: true
            )
            item.assignmentState = ItemStateMachine.nextAssignmentState(
                from: item.assignmentState,
                isCompletion: true
            )
            item.completedAt = Date.now
        } else {
            upsertOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate, completedAt: Date.now)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        items[index] = item
        return hydratedItem(item)
    }

    func markIncomplete(itemID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }

        var item = items[index]
        if item.repeatRule == nil {
            item.completedAt = nil
            if item.status == .completed {
                item.status = .inProgress
            }
            item.assignmentState = .active
        } else {
            deleteOccurrenceCompletion(itemID: itemID, referenceDate: referenceDate)
            item.completedAt = nil
        }
        item.lastActionByUserID = actorID
        item.lastActionAt = .now
        item.isArchived = false
        item.archivedAt = nil
        item.updatedAt = .now
        items[index] = item
        return hydratedItem(item)
    }

    func saveItem(_ item: Item) async throws -> Item {
        var savedItem = item
        savedItem.updatedAt = .now
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = savedItem
        } else {
            items.append(savedItem)
        }
        return hydratedItem(savedItem)
    }

    func deleteItem(itemID: UUID) async throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.notFound
        }
        occurrenceCompletions[itemID] = nil
        items.remove(at: index)
    }

    private func hydratedItem(_ item: Item) -> Item {
        var copy = item
        if item.repeatRule != nil {
            copy.occurrenceCompletions = occurrenceCompletions[item.id, default: []]
            copy.completedAt = nil
        }
        return copy
    }

    private func upsertOccurrenceCompletion(itemID: UUID, referenceDate: Date, completedAt: Date) {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        var completions = occurrenceCompletions[itemID, default: []]
        completions.removeAll { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) }
        completions.append(ItemOccurrenceCompletion(occurrenceDate: occurrenceDate, completedAt: completedAt))
        occurrenceCompletions[itemID] = completions.sorted { $0.occurrenceDate < $1.occurrenceDate }
    }

    private func deleteOccurrenceCompletion(itemID: UUID, referenceDate: Date) {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        let filtered = occurrenceCompletions[itemID, default: []]
            .filter { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) == false }
        occurrenceCompletions[itemID] = filtered.isEmpty ? nil : filtered
    }
}

actor TestHomeTaskApplicationService: TaskApplicationServiceProtocol {
    private var completed: [UUID] = []

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] { [] }
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            completedTodayCount: 0,
            pinnedCount: 0
        )
    }
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func moveTask(in spaceID: UUID, taskID: UUID, actorID: UUID, listID: UUID?, projectID: UUID?) async throws -> Item { throw RepositoryError.notFound }
    func rescheduleTask(in spaceID: UUID, taskID: UUID, actorID: UUID, dueAt: Date?, remindAt: Date?) async throws -> Item { throw RepositoryError.notFound }
    func snoozeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, option: TaskSnoozeOption) async throws -> Item { throw RepositoryError.notFound }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        completed.append(taskID)
        try? await Task.sleep(for: .milliseconds(40))
        return Item(
            id: taskID,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "已完成",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: referenceDate,
            hasExplicitTime: true,
            remindAt: nil,
            status: .inProgress,
            latestResponse: nil,
            responseHistory: [],
            createdAt: referenceDate,
            updatedAt: referenceDate,
            completedAt: nil,
            occurrenceCompletions: [
                ItemOccurrenceCompletion(
                    occurrenceDate: Calendar.current.startOfDay(for: referenceDate),
                    completedAt: referenceDate
                )
            ],
            isPinned: false,
            isDraft: false,
            repeatRule: ItemRepeatRule(frequency: .daily)
        )
    }

    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        try await toggleTaskCompletion(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { throw RepositoryError.notFound }
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
    func respondToTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        response: ItemResponseKind,
        message: String?
    ) async throws -> Item { throw RepositoryError.notFound }
    func requeueDeclinedTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID
    ) async throws -> Item { throw RepositoryError.notFound }
    func appendAssignmentMessage(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        message: String
    ) async throws -> Item { throw RepositoryError.notFound }

    func completedTaskIDs() -> [UUID] {
        completed
    }
}

actor TestHistoricalOneOffCompletionTaskService: TaskApplicationServiceProtocol {
    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] { [] }
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            completedTodayCount: 0,
            pinnedCount: 0
        )
    }
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func moveTask(in spaceID: UUID, taskID: UUID, actorID: UUID, listID: UUID?, projectID: UUID?) async throws -> Item { throw RepositoryError.notFound }
    func rescheduleTask(in spaceID: UUID, taskID: UUID, actorID: UUID, dueAt: Date?, remindAt: Date?) async throws -> Item { throw RepositoryError.notFound }
    func snoozeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, option: TaskSnoozeOption) async throws -> Item { throw RepositoryError.notFound }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        let dueAt = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: referenceDate) ?? referenceDate
        return Item(
            id: taskID,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "已完成的历史单次任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: nil,
            status: .completed,
            latestResponse: nil,
            responseHistory: [],
            createdAt: dueAt,
            updatedAt: .now,
            completedAt: .now,
            isPinned: false,
            isDraft: false
        )
    }

    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        try await toggleTaskCompletion(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { throw RepositoryError.notFound }
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
    func respondToTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        response: ItemResponseKind,
        message: String?
    ) async throws -> Item { throw RepositoryError.notFound }
    func requeueDeclinedTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID
    ) async throws -> Item { throw RepositoryError.notFound }
    func appendAssignmentMessage(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        message: String
    ) async throws -> Item { throw RepositoryError.notFound }
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

#if canImport(UIKit)
private func makeAvatarTestUser(id: UUID = UUID()) -> User {
    var user = MockDataFactory.makeCurrentUser()
    user = User(
        id: id,
        appleUserID: user.appleUserID,
        displayName: user.displayName,
        avatarSystemName: user.avatarSystemName,
        avatarPhotoFileName: nil,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        preferences: user.preferences
    )
    return user
}

private func makeAvatarTestImage(fillColor: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    return renderer.image { context in
        fillColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
}
#endif

private func makeAvatarTestStoreURL(testName: String) -> URL {
    let fileName = "\(testName)-\(UUID().uuidString).store"
    return FileManager.default.temporaryDirectory
        .appending(path: "TogetherAvatarTests", directoryHint: .isDirectory)
        .appending(path: fileName)
}

private func makeUserProfileContainer(storeURL: URL) throws -> ModelContainer {
    try FileManager.default.createDirectory(
        at: storeURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let configuration = ModelConfiguration("AvatarTestStore", url: storeURL)
    return try ModelContainer(for: PersistentUserProfile.self, configurations: configuration)
}
