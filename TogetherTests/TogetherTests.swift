import Foundation
import Observation
import SwiftData
import Testing
import TogetherCore
import UIKit
@testable import Together

@MainActor
@Suite(.serialized)
struct TogetherTests {
    private final class ObservationChangeFlag: @unchecked Sendable {
        nonisolated(unsafe) var value = false
    }

    private func clearRoutineCycleVisibilityPreferences() {
        UserDefaults.standard.removeObject(forKey: "together.routines.visibleCycles.v2")
        UserDefaults.standard.removeObject(forKey: "together.routines.visibleOptionalCycles")
    }

    @Test func taskLifecycleScheduleClassifierUsesCommittedNetChanges() {
        let baseline = Date(timeIntervalSince1970: 1_800_000_000)
        let later = baseline.addingTimeInterval(86_400)

        #expect(TaskLifecycleEventClassifier.classifyScheduleChange(
            from: TaskScheduleSnapshot(dueAt: nil, hasExplicitTime: false),
            to: TaskScheduleSnapshot(dueAt: baseline, hasExplicitTime: false),
            hasRecordedSchedule: false
        ) == .firstScheduled)
        #expect(TaskLifecycleEventClassifier.classifyScheduleChange(
            from: TaskScheduleSnapshot(dueAt: baseline, hasExplicitTime: false),
            to: TaskScheduleSnapshot(dueAt: later, hasExplicitTime: false),
            hasRecordedSchedule: true
        ) == .postponed)
        #expect(TaskLifecycleEventClassifier.classifyScheduleChange(
            from: TaskScheduleSnapshot(dueAt: baseline, hasExplicitTime: false),
            to: TaskScheduleSnapshot(dueAt: nil, hasExplicitTime: false),
            hasRecordedSchedule: true
        ) == .scheduleCleared)
        #expect(TaskLifecycleEventClassifier.classifyScheduleChange(
            from: TaskScheduleSnapshot(dueAt: nil, hasExplicitTime: false),
            to: TaskScheduleSnapshot(dueAt: later, hasExplicitTime: false),
            hasRecordedSchedule: true
        ) == .rescheduled)
    }

    @Test func dateOnlyPlanCountsThroughEndOfLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueDay = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        let lateEvening = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 23, minute: 59)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 21)))
        let schedule = TaskScheduleSnapshot(dueAt: dueDay, hasExplicitTime: false)

        #expect(TaskLifecycleMetrics.isOnTime(completedAt: lateEvening, schedule: schedule, calendar: calendar))
        #expect(TaskLifecycleMetrics.isOnTime(completedAt: nextDay, schedule: schedule, calendar: calendar) == false)
    }

    @Test func adaptiveSnoozeUsesActionDayAndPreservesExplicitTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 21, hour: 15)))
        let staleDue = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 19, hour: 9, minute: 30)))
        let tomorrow = TaskSnoozeDateCalculator.dueDate(
            currentDueAt: staleDue,
            hasExplicitTime: true,
            option: .tomorrow,
            now: friday,
            calendar: calendar
        )
        let monday = TaskSnoozeDateCalculator.dueDate(
            currentDueAt: staleDue,
            hasExplicitTime: true,
            option: .nextMonday,
            now: friday,
            calendar: calendar
        )

        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)
            == DateComponents(year: 2030, month: 6, day: 22, hour: 9, minute: 30))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: monday)
            == DateComponents(year: 2030, month: 6, day: 24, hour: 9, minute: 30))
    }

    @Test func taskLifecycleEventsAreAtomicWithTaskMutationsAndDeletedWithTask() async throws {
        let container = makeTaskSubtaskModelContainer()
        let repository = LocalItemRepository(container: container)
        var item = makeHomeFilterItem(title: "履历任务", completedAt: nil, status: .inProgress, createdAt: .now)
        item.subtasks = [
            TaskSubtask(
                itemID: item.id,
                creatorID: item.creatorID,
                title: "仍未完成",
                isCompleted: false,
                sortOrder: 0
            )
        ]

        item = try await repository.saveItem(item)
        let firstDue = Date.now.addingTimeInterval(86_400)
        item.dueAt = firstDue
        item.hasExplicitTime = true
        item = try await repository.saveItem(item)
        item.dueAt = firstDue.addingTimeInterval(86_400)
        item = try await repository.saveItem(item)
        _ = try await repository.markCompleted(
            itemID: item.id,
            actorID: item.creatorID,
            referenceDate: .now
        )
        _ = try await repository.markIncomplete(
            itemID: item.id,
            actorID: item.creatorID,
            referenceDate: .now
        )

        let review = try await repository.fetchTaskLifecycleReview(itemID: item.id)
        #expect(review.historyCoverage == .complete)
        #expect(review.events.map(\.kind) == [.created, .firstScheduled, .postponed, .completed, .reopened])
        #expect(review.postponeCount == 1)
        #expect(review.reopenCount == 1)
        #expect(review.events.first(where: { $0.kind == .completed })?.incompleteSubtaskCount == 1)

        try await repository.deleteItem(itemID: item.id)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<PersistentTaskLifecycleEvent>()) == 0)
    }

    @Test func missingTaskDateNormalizationIsIdempotentAndDoesNotCreateLifecycleEvents() async throws {
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        let item = makeHomeFilterItem(title: "历史无日期任务", completedAt: nil, status: .inProgress)
        var completed = makeHomeFilterItem(
            title: "已完成旧记录",
            completedAt: .now,
            status: .completed
        )
        completed.dueAt = nil
        context.insert(PersistentItem(item: item))
        context.insert(PersistentItem(item: completed))
        try context.save()

        let repository = LocalItemRepository(container: container)
        let referenceDate = Date(timeIntervalSince1970: 1_900_000_000)
        let expectedDate = Calendar.current.startOfDay(for: referenceDate)

        #expect(try await repository.normalizeMissingTaskDates(
            spaceID: item.spaceID,
            referenceDate: referenceDate
        ) == 1)
        #expect(try await repository.normalizeMissingTaskDates(
            spaceID: item.spaceID,
            referenceDate: referenceDate
        ) == 0)

        let normalized = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(normalized.dueAt == expectedDate)
        #expect(normalized.hasExplicitTime == false)
        #expect(normalized.remindAt == nil)
        #expect(try await repository.fetchItem(itemID: completed.id)?.dueAt == nil)
        #expect(try context.fetchCount(FetchDescriptor<PersistentTaskLifecycleEvent>()) == 0)
    }

    @Test func taskSharedIdentityShowsOnlyConfiguredAttributes() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "收集对公联动情况",
            notes: "  完整备注  ",
            timeText: "08:30",
            reminderText: "30 分钟前",
            statusText: "进行中",
            isUrgent: true,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "已完成",
                    isCompleted: true,
                    sortOrder: 0
                ),
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "待完成",
                    isCompleted: false,
                    sortOrder: 1
                )
            ],
            subtaskCompletedCount: 1
        )

        let content = TaskSharedIdentityContent.make(entry: entry)

        #expect(content.note == "完整备注")
        #expect(content.completedSubtaskCount == 1)
        #expect(content.totalSubtaskCount == 2)
        #expect(content.visibleElements == [
            .completion, .title, .note, .progress, .time, .reminder, .urgent
        ])
    }

    @Test func taskSharedReminderTextDescribesActualLeadTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueAt = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3, hour: 8, minute: 30)
        ))
        let remindAt = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3, hour: 8, minute: 0)
        ))

        #expect(
            TaskSharedAttributeText.reminderLead(
                dueAt: dueAt,
                hasExplicitTime: true,
                remindAt: remindAt,
                calendar: calendar
            ) == "30 分钟前"
        )
    }

    @Test func inlineDetailSaveRefreshesRowSummaryBeforeCollapse() async throws {
        let item = makeHomeFilterItem(
            title: "原始列表标题",
            completedAt: nil,
            status: .inProgress
        )
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        viewModel.presentItemDetail(item.id)
        viewModel.updateDraftTitle("收起前已同步")

        #expect(await viewModel.saveInlineDetailDraft())
        #expect(viewModel.activeTimelineEntries.first?.title == "收起前已同步")
        #expect(try await repository.fetchItem(itemID: item.id)?.title == "收起前已同步")
    }

    @Test func completedHomeTaskDoesNotOpenInlineDetail() async {
        let item = makeHomeFilterItem(
            title: "已经完成",
            completedAt: .now,
            status: .completed
        )
        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [item])
        )

        await viewModel.reload()
        #expect(viewModel.timelineEntry(for: item.id)?.isCompleted == true)
        viewModel.presentItemDetail(item.id)

        #expect(viewModel.selectedItemID == nil)
        #expect(viewModel.detailDraft == nil)
    }

    @Test func inlineTaskCreationKeepsOneUUIDAcrossFailureAndRetry() async throws {
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let service = CapturingTaskApplicationService()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: service,
            itemRepository: MockItemRepository()
        )

        viewModel.beginTaskCreation()
        let provisionalID = try #require(viewModel.taskCreationSession?.id)
        viewModel.updateTaskCreationDraft { $0.title = "稳定身份任务" }

        guard case .failed = await viewModel.commitTaskCreation() else {
            Issue.record("首次保存应失败")
            return
        }
        #expect(viewModel.taskCreationSession?.id == provisionalID)
        #expect(viewModel.taskCreationSession?.draft.title == "稳定身份任务")
        #expect(viewModel.taskCreationSession?.errorMessage != nil)

        service.capturesCreates = true
        guard case .saved(let createdID) = await viewModel.commitTaskCreation() else {
            Issue.record("重试保存应成功")
            return
        }
        #expect(createdID == provisionalID)
        #expect(service.createdTaskIDs == [provisionalID])
        #expect(viewModel.taskCreationSession?.phase == .committed)
        #expect(viewModel.taskCreationSession?.id == provisionalID)
        viewModel.finalizeCommittedTaskCreation()
        #expect(viewModel.taskCreationSession == nil)
    }

    @Test func taskCreationCarriesFollowIntentAndRequestsLiveActivityReconciliation() async throws {
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let service = CapturingTaskApplicationService()
        service.capturesCreates = true
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: service,
            itemRepository: MockItemRepository()
        )
        var reconciledSpaceID: UUID?
        viewModel.onTaskFollowChanged = { reconciledSpaceID = $0 }

        viewModel.beginTaskCreation()
        viewModel.updateTaskCreationDraft {
            $0.title = "创建时关注"
            $0.shouldFollowOnCreation = true
        }

        guard case .saved = await viewModel.commitTaskCreation() else {
            Issue.record("关注任务应创建成功")
            return
        }

        #expect(service.createdDrafts.first?.shouldFollowOnCreation == true)
        #expect(viewModel.taskCreationSession?.draft.shouldFollowOnCreation == true)
        #expect(reconciledSpaceID == MockDataFactory.singleSpaceID)
    }

    @Test func persistenceFailurePolicyNeverDeletesStoreAutomatically() {
        #expect(PersistenceFailurePolicy.shouldDeleteStoreAfterOpenFailure == false)
    }

    @Test func taskFollowContentStateOrdersLimitsAndStaysBelowPayloadBudget() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = (0..<8).map { index in
            var item = makeHomeFilterItem(
                title: String(repeating: "很长的关注任务", count: 30) + " \(index)",
                completedAt: nil,
                status: .inProgress
            )
            item.isFollowed = true
            item.followedAt = base.addingTimeInterval(TimeInterval(index))
            return item
        }

        let state = TaskFollowSnapshotBuilder.contentState(from: tasks)
        let encoded = try JSONEncoder().encode(state)

        #expect(state.totalFollowedCount == 8)
        #expect(state.visibleTasks.count == 3)
        #expect(state.visibleTasks.map(\.taskID) == tasks.reversed().prefix(3).map(\.id))
        #expect(state.visibleTasks.allSatisfy { $0.displayTitle.count <= 80 })
        #expect(encoded.count < 4_096)
    }

    @Test func completingFollowedTaskClearsFollowAndReopeningDoesNotRestoreIt() async throws {
        let repository = makeTaskSubtaskItemRepository()
        let service = DefaultTaskApplicationService(
            itemRepository: repository,
            syncCoordinator: NoOpSyncCoordinator(),
            reminderScheduler: MockReminderScheduler()
        )
        var item = makeHomeFilterItem(title: "需要持续关注", completedAt: nil, status: .inProgress)
        item.isFollowed = true
        item.followedAt = .now
        _ = try await repository.saveItem(item)

        let completed = try await service.completeTask(
            in: MockDataFactory.singleSpaceID,
            taskID: item.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: .now
        )
        #expect(completed.isFollowed == false)
        #expect(completed.followedAt == nil)

        let reopened = try await repository.markIncomplete(
            itemID: item.id,
            actorID: MockDataFactory.currentUserID,
            referenceDate: .now
        )
        #expect(reopened.isFollowed == false)
        #expect(reopened.followedAt == nil)
    }

    @Test func ocrStructuralOperationsAddDeleteAndMoveTopLevelTasks() {
        let first = OCRImportTaskDraft(title: "第一条")
        let second = OCRImportTaskDraft(title: "第二条")
        let viewModel = OCRImportViewModel()
        viewModel.draft = OCRImportDraft(
            rawText: "第一条\n第二条",
            updatedAt: Date(timeIntervalSince1970: 1),
            status: .needsReview,
            taskDrafts: [first, second]
        )

        let addedID = viewModel.addTask(after: first.id)
        #expect(viewModel.draft.taskDrafts.map(\.id) == [first.id, addedID, second.id])

        viewModel.deleteTask(id: addedID)
        #expect(viewModel.draft.taskDrafts.map(\.id) == [first.id, second.id])

        viewModel.moveTasks(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(viewModel.draft.taskDrafts.map(\.id) == [second.id, first.id])
        #expect(viewModel.draft.rawText == "第一条\n第二条")
        #expect(viewModel.draft.updatedAt > Date(timeIntervalSince1970: 1))
    }

    @Test func ocrMergeAndSplitPreserveRawTextAndSelection() {
        let child = OCRImportSubtaskDraft(
            title: "已有子项",
            isSelected: false,
            sourceText: "- 已有子项"
        )
        let first = OCRImportTaskDraft(title: "主任务", isSelected: false, sourceText: "主任务")
        let second = OCRImportTaskDraft(
            title: "待合并任务",
            isSelected: true,
            sourceText: "待合并任务",
            subtasks: [child]
        )
        let viewModel = OCRImportViewModel()
        viewModel.draft = OCRImportDraft(
            rawText: "主任务\n待合并任务\n- 已有子项",
            status: .needsReview,
            taskDrafts: [first, second]
        )

        #expect(viewModel.mergeTaskWithPrevious(id: second.id))
        #expect(viewModel.draft.taskDrafts.count == 1)
        #expect(viewModel.draft.taskDrafts[0].id == first.id)
        #expect(viewModel.draft.taskDrafts[0].isSelected)
        #expect(viewModel.draft.taskDrafts[0].subtasks.map(\.isSelected) == [true, false])

        #expect(viewModel.splitSubtask(taskID: first.id, subtaskID: child.id))
        #expect(viewModel.draft.taskDrafts.count == 2)
        #expect(viewModel.draft.taskDrafts[1].title == child.title)
        #expect(viewModel.draft.taskDrafts[1].isSelected == false)
        #expect(viewModel.draft.taskDrafts[1].sourceText == child.sourceText)
        #expect(viewModel.draft.rawText == "主任务\n待合并任务\n- 已有子项")
    }

    @Test func appDeepLinkParsesOnlySupportedRoutes() {
        let taskID = UUID()

        #expect(AppDeepLink(url: URL(string: "together://today")!) == .today)
        #expect(AppDeepLink(url: URL(string: "together://new-task")!) == .newTask)
        #expect(AppDeepLink(url: URL(string: "together://task/\(taskID.uuidString)")!) == .task(taskID))
        #expect(AppDeepLink(url: URL(string: "together://task/not-a-uuid")!) == nil)
        #expect(AppDeepLink(url: URL(string: "together://unknown")!) == nil)
        #expect(AppDeepLink(url: URL(string: "together://task")!) == nil)
        #expect(AppDeepLink.task(taskID).url == URL(string: "together://task/\(taskID.uuidString)"))
        #expect(AppDeepLink.newTask.url == URL(string: "together://new-task"))
    }

    @Test func newTaskDeepLinkOpensComposerFromToday() async throws {
        let appContext = try makeOCRAppContext(
            taskApplicationService: CapturingTaskApplicationService()
        )

        await appContext.handleDeepLink(.newTask)

        #expect(appContext.router.currentSurface == .today)
        #expect(appContext.router.activeComposer == .newTask)
    }

    @Test func missingTaskDeepLinkProducesRetryableFeedback() async throws {
        let appContext = try makeOCRAppContext(
            taskApplicationService: CapturingTaskApplicationService()
        )
        let missingTaskID = UUID()

        await appContext.handleDeepLink(.task(missingTaskID))

        #expect(appContext.router.currentSurface == .today)
        #expect(appContext.homeViewModel.failedExternalRouteTaskID == missingTaskID)
        #expect(appContext.homeViewModel.externalRouteErrorMessage != nil)
        #expect(appContext.consumePendingHighlightTaskID() == nil)
    }

    @Test func successfulCloudImportRemovesRemotelyDeletedTaskFromForegroundCache() async throws {
        let appContext = try makeOCRAppContext(
            taskApplicationService: CapturingTaskApplicationService(),
            cloudImportConvergenceDelays: [.zero, .zero]
        )
        let repository = try #require(appContext.container.itemRepository as? MockItemRepository)

        await appContext.homeViewModel.reload(reason: .sync)
        let deletedTaskID = try #require(appContext.homeViewModel.items.first?.id)
        let reloadRevisionBeforeImport = appContext.homeViewModel.reloadRevision
        var importFetchCount = 0
        repository.homeItemsFetchTransform = { items in
            importFetchCount += 1
            guard appContext.homeViewModel.reloadRevision >= reloadRevisionBeforeImport + 2 else {
                return items
            }
            return items.filter { $0.id != deletedTaskID }
        }

        #expect(appContext.homeViewModel.item(for: deletedTaskID) != nil)

        let convergenceTask = await appContext.handleSuccessfulCloudImport()
        await convergenceTask.value

        #expect(importFetchCount >= 2)
        #expect(appContext.homeViewModel.reloadRevision == reloadRevisionBeforeImport + 3)
        #expect(appContext.homeViewModel.item(for: deletedTaskID) == nil)
    }

    @Test func startupProfileRestoreAppliesHydratedAvatarToSession() async throws {
        let originalUser = MockDataFactory.makeCurrentUser()
        var restoredUser = originalUser
        restoredUser.avatarPhotoFileName = "asset-restored-avatar.jpg"
        restoredUser.avatarAssetID = originalUser.id.uuidString.lowercased()
        restoredUser.avatarVersion = 3
        let profileRepository = StartupProfileRestoreRepository(restoredUser: restoredUser)
        let appContext = try makeOCRAppContext(
            taskApplicationService: CapturingTaskApplicationService(),
            userProfileRepository: profileRepository
        )

        await appContext.restorePersistedUserProfileIfNeeded()

        let mergeCallCount = profileRepository.mergedUserCallCount
        #expect(appContext.sessionStore.currentUser?.avatarAsset == .photo(fileName: "asset-restored-avatar.jpg"))
        #expect(mergeCallCount == 1)
    }

    @Test func successfulCloudImportRetriesProfileRestoreForLateAvatarPayload() async throws {
        let restoredUser = MockDataFactory.makeCurrentUser()
        let profileRepository = StartupProfileRestoreRepository(restoredUser: restoredUser)
        let appContext = try makeOCRAppContext(
            taskApplicationService: CapturingTaskApplicationService(),
            userProfileRepository: profileRepository,
            cloudImportConvergenceDelays: [.zero, .zero]
        )

        let convergenceTask = await appContext.handleSuccessfulCloudImport()
        await convergenceTask.value

        let mergeCallCount = profileRepository.mergedUserCallCount
        #expect(mergeCallCount == 3)
    }

    @Test func missingAvatarFilePreservesCloudAssetMetadataUntilPayloadArrives() async throws {
        let container = makeTaskSubtaskModelContainer()
        let userID = UUID()
        var user = makeIdentityTestUser(id: userID)
        user.avatarPhotoFileName = "asset-\(userID.uuidString.lowercased()).jpg"
        user.avatarAssetID = userID.uuidString.lowercased()
        user.avatarVersion = 4
        let context = ModelContext(container)
        context.insert(PersistentUserProfile(user: user))
        try context.save()
        let repository = LocalUserProfileRepository(
            container: container,
            avatarMediaStore: MissingAvatarMediaStore()
        )

        let mergedUser = await repository.mergedUser(user)
        let storedProfile = try #require(context.fetch(FetchDescriptor<PersistentUserProfile>()).first)

        #expect(mergedUser?.avatarPhotoFileName == user.avatarPhotoFileName)
        #expect(mergedUser?.avatarAssetID == user.avatarAssetID)
        #expect(storedProfile.avatarPhotoFileName == user.avatarPhotoFileName)
        #expect(storedProfile.avatarAssetID == user.avatarAssetID)
    }

    @Test func routineInlineDetailFallbackHeightMatchesVisibleRows() {
        #expect(RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: true) == 70)
        #expect(RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: false) == 44)
    }

    @Test func homeInlineDetailFallbackHeightExcludesHiddenAddNoteRow() {
        let withoutExistingNote = HomeInlineTaskLayoutMetrics.estimatedDetailHeight(
            subtaskCount: 0,
            showsAddNote: true
        )
        let withExistingNote = HomeInlineTaskLayoutMetrics.estimatedDetailHeight(
            subtaskCount: 0,
            showsAddNote: false
        )

        #expect(withoutExistingNote - withExistingNote == HomeInlineTaskLayoutMetrics.compactRowMinHeight + HomeInlineTaskLayoutMetrics.detailVerticalSpacing)
    }

    @Test func todayWidgetSnapshotUsesOnlyOverdueAndTodayTasksForOverview() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let referenceDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12))
        )
        let overdueDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 19))
        )
        let todayDueDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 16))
        )
        let todayCompletionDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 10))
        )
        let todayDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 20))
        )
        let futureDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 21))
        )
        let repeatingAnchorDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 18, hour: 9))
        )

        var overdue = makeHomeFilterItem(title: "已逾期", completedAt: nil, status: .inProgress)
        overdue.dueAt = overdueDate

        var today = makeHomeFilterItem(title: "今天处理", completedAt: nil, status: .inProgress)
        today.dueAt = todayDueDate
        today.hasExplicitTime = true

        var completed = makeHomeFilterItem(
            title: "今天已完成",
            completedAt: todayCompletionDate,
            status: .completed
        )
        completed.dueAt = todayDate

        var future = makeHomeFilterItem(title: "明天处理", completedAt: nil, status: .inProgress)
        future.dueAt = futureDate
        var repeatingLater = makeHomeFilterItem(title: "下周例行", completedAt: nil, status: .inProgress)
        repeatingLater.dueAt = repeatingAnchorDate
        repeatingLater.repeatRule = ItemRepeatRule(
            frequency: .weekly,
            weekday: calendar.component(.weekday, from: repeatingAnchorDate)
        )
        let noDate = makeHomeFilterItem(title: "无日期", completedAt: nil, status: .inProgress)

        let snapshot = TodayWidgetSnapshotBuilder(calendar: calendar).build(
            items: [future, noDate, repeatingLater, today, completed, overdue],
            referenceDate: referenceDate,
            limit: .max
        )

        #expect(snapshot.tasks.map(\.title) == ["已逾期", "今天处理"])
        #expect(snapshot.remainingCount == 2)
        #expect(snapshot.completedTodayCount == 1)
        #expect(snapshot.totalTodayCount == 3)
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.nextUpcomingTask?.title == "明天处理")
        #expect(snapshot.nextUpcomingTask?.dueTimeText == "明天")
    }

    @Test func todayWidgetSnapshotDecodesLegacyCacheWithoutOverviewFields() throws {
        let taskID = UUID()
        let data = try #require(
            """
            {
              "generatedAt": "2030-06-20T10:00:00Z",
              "referenceDate": "2030-06-20T10:00:00Z",
              "remainingCount": 1,
              "tasks": [
                {
                  "id": "\(taskID.uuidString)",
                  "title": "旧缓存任务",
                  "dueTimeText": "12:00",
                  "sortIndex": 0
                }
              ]
            }
            """.data(using: .utf8)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(TodayWidgetSnapshot.self, from: data)

        #expect(snapshot.completedTodayCount == 0)
        #expect(snapshot.overdueCount == 0)
        #expect(snapshot.nextUpcomingTask == nil)
        #expect(snapshot.tasks.first?.isOverdue == false)
    }

    @Test func homeModeTaskTransitionCascadeCoversTheFullListAndIsReversible() {
        let entryDelays = (0..<40).map {
            HomeModeTaskTransitionTiming.delay(
                for: $0,
                taskCount: 40,
                isPresented: true,
                reduceMotion: false
            )
        }
        let exitDelays = (0..<40).map {
            HomeModeTaskTransitionTiming.delay(
                for: $0,
                taskCount: 40,
                isPresented: false,
                reduceMotion: false
            )
        }

        #expect(entryDelays[0] == 0)
        #expect(abs(entryDelays[4] - 0.20) < 0.000_1)
        #expect(
            zip(entryDelays, entryDelays.dropFirst()).allSatisfy { previous, next in
                previous < next
            }
        )
        #expect(entryDelays[39] < HomeModeTaskTransitionTiming.maximumCascadeDelay)
        #expect(exitDelays == Array(entryDelays.reversed()))
        #expect(
            HomeModeTaskTransitionTiming.delay(
                for: 3,
                taskCount: 40,
                isPresented: true,
                reduceMotion: true
            ) == 0
        )
    }

    @Test func homeModeTimelineWaveSequenceIncludesCompletedSummariesInVisualOrder() {
        let activeIDs = [UUID(), UUID()]
        let completedIDs = [UUID(), UUID()]
        let sequence = HomeModeTimelineWaveSequence(
            activeTaskIDs: activeIDs,
            completedTaskIDs: completedIDs,
            includesWeeklyCompletedSummary: true
        )

        #expect(sequence.taskIndex(for: activeIDs[0]) == 0)
        #expect(sequence.taskIndex(for: activeIDs[1]) == 1)
        #expect(sequence.todayCompletedHeaderIndex == 2)
        #expect(sequence.taskIndex(for: completedIDs[0]) == 3)
        #expect(sequence.taskIndex(for: completedIDs[1]) == 4)
        #expect(sequence.weeklyCompletedSummaryIndex == 5)
        #expect(sequence.elementCount == 6)

        let weeklyOnly = HomeModeTimelineWaveSequence(
            activeTaskIDs: [],
            completedTaskIDs: [],
            includesWeeklyCompletedSummary: true
        )
        #expect(weeklyOnly.todayCompletedHeaderIndex == nil)
        #expect(weeklyOnly.weeklyCompletedSummaryIndex == 0)
        #expect(weeklyOnly.elementCount == 1)

        #expect(sequence.taskIndex(for: UUID()) == nil)
    }

    @Test func ocrMediaControlsPreserveDeviceBottomSafeArea() {
        #expect(
            OCRMediaLayout.controlsBottomPadding(
                safeAreaBottom: 34,
                designSpacing: 16
            ) == 50
        )
    }

    @Test func ocrSourceSheetSessionStartsFromSelectedMenuAction() {
        let cameraSession = OCRSourceSheetSession(source: .camera)
        let photosSession = OCRSourceSheetSession(source: .photos)
        let pasteTextSession = OCRSourceSheetSession(source: .pasteText)

        #expect(cameraSession.viewModel.flowState == .camera)
        #expect(photosSession.viewModel.flowState == .photos)
        #expect(pasteTextSession.viewModel.flowState == .pasteText)
        #expect(cameraSession.viewModel !== photosSession.viewModel)
        #expect(photosSession.viewModel !== pasteTextSession.viewModel)
    }

    @Test func itemStateMachineCompletesInProgressTask() async throws {
        let next = ItemStateMachine.nextStatus(
            from: .inProgress,
            isCompletion: true
        )

        #expect(next == .completed)
    }

    @Test func sessionStoreAppliesPersonalIdentityToSingleSpace() {
        let sessionStore = SessionStore()
        let user = MockDataFactory.makeCurrentUser()
        let space = MockDataFactory.makeSingleSpace()

        sessionStore.applyPersonalIdentity(user: user, space: space)

        #expect(sessionStore.currentUser?.id == user.id)
        #expect(sessionStore.currentSpace?.type == .single)
        #expect(sessionStore.availableModeStates == [.single])
        #expect(sessionStore.activeMode == .single)
    }

    @Test func identityResolutionPreservesExistingProfileAndSpaceIDs() async throws {
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        let userID = UUID()
        let spaceID = UUID()
        let user = makeIdentityTestUser(id: userID)
        let space = Space(
            id: spaceID,
            type: .single,
            displayName: "原有空间",
            ownerUserID: userID,
            status: .active,
            createdAt: .now,
            updatedAt: .now
        )
        context.insert(PersistentUserProfile(user: user))
        context.insert(PersistentSpace(space: space))
        context.insert(PersistentItem(item: Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: userID,
            title: "原有任务",
            notes: nil,
            dueAt: nil,
            status: .inProgress,
            lastActionByUserID: userID,
            lastActionAt: .now,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isDraft: false
        )))
        try context.save()

        let resolution = PersonalIdentityService(container: container).resolve(afterInitialCloudImport: false)

        guard case let .ready(resolvedUser, resolvedSpace) = resolution else {
            Issue.record("已有身份和数据空间应直接进入应用")
            return
        }
        #expect(resolvedUser.id == userID)
        #expect(resolvedSpace.id == spaceID)
        #expect(resolvedSpace.ownerUserID == userID)
    }

    @Test func spaceLookupDoesNotClaimOrRewriteCreatorIDs() async throws {
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        let originalOwnerID = UUID()
        let temporaryUserID = UUID()
        let spaceID = UUID()
        let itemID = UUID()
        context.insert(PersistentSpace(space: Space(
            id: spaceID,
            type: .single,
            displayName: "待恢复空间",
            ownerUserID: originalOwnerID,
            status: .active,
            createdAt: .now,
            updatedAt: .now
        )))
        context.insert(PersistentItem(item: Item(
            id: itemID,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: originalOwnerID,
            title: "不可改写",
            notes: nil,
            dueAt: nil,
            status: .inProgress,
            lastActionByUserID: originalOwnerID,
            lastActionAt: .now,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isDraft: false
        )))
        try context.save()

        _ = await LocalSpaceService(container: container).currentSpaceContext(for: temporaryUserID)

        let storedSpace = try #require(context.fetch(FetchDescriptor<PersistentSpace>()).first)
        let storedItem = try #require(context.fetch(FetchDescriptor<PersistentItem>()).first)
        #expect(storedSpace.ownerUserID == originalOwnerID)
        #expect(storedItem.creatorID == originalOwnerID)
    }

    @Test func emptyIdentityRequiresExplicitLocalStart() throws {
        let container = makeTaskSubtaskModelContainer()
        let service = PersonalIdentityService(container: container)

        #expect(service.resolve(afterInitialCloudImport: false) == .waitingForCloudRestore)
        #expect(service.resolve(afterInitialCloudImport: true) == .requiresLocalStart)

        let resolution = try service.startLocally()
        guard case let .ready(user, space) = resolution else {
            Issue.record("用户明确选择后应创建本机身份")
            return
        }
        #expect(space.ownerUserID == user.id)
        #expect(service.resolve(afterInitialCloudImport: false) == resolution)
    }

    @Test func provisionalIdentityMergesIntoRestoredRemoteSpace() throws {
        let container = makeTaskSubtaskModelContainer()
        let suiteName = "TogetherIdentityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PersonalIdentityService(container: container, defaults: defaults)
        let localResolution = try service.startLocally()
        guard case let .ready(localUser, localSpace) = localResolution else {
            Issue.record("应先创建 provisional 本机空间")
            return
        }

        let context = ModelContext(container)
        let localItemID = UUID()
        context.insert(PersistentItem(item: Item(
            id: localItemID,
            spaceID: localSpace.id,
            listID: nil,
            projectID: nil,
            creatorID: localUser.id,
            title: "离线创建的任务",
            notes: nil,
            dueAt: nil,
            status: .inProgress,
            lastActionByUserID: localUser.id,
            lastActionAt: .now,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isDraft: false
        )))
        let remoteUser = makeIdentityTestUser(id: UUID())
        let remoteSpace = Space(
            id: UUID(),
            type: .single,
            displayName: "iCloud 空间",
            ownerUserID: remoteUser.id,
            status: .active,
            createdAt: .now,
            updatedAt: .now.addingTimeInterval(10)
        )
        context.insert(PersistentUserProfile(user: remoteUser))
        context.insert(PersistentSpace(space: remoteSpace))
        try context.save()

        let resolution = service.resolve(afterInitialCloudImport: true)

        guard case let .ready(resolvedUser, resolvedSpace) = resolution else {
            Issue.record("远端身份恢复后应切换到远端空间")
            return
        }
        #expect(resolvedUser.id == remoteUser.id)
        #expect(resolvedSpace.id == remoteSpace.id)
        let storedItem = try #require(
            context.fetch(FetchDescriptor<PersistentItem>()).first { $0.id == localItemID }
        )
        #expect(storedItem.spaceID == remoteSpace.id)
        #expect(storedItem.creatorID == remoteUser.id)
        #expect(defaults.string(forKey: PersonalIdentityService.provisionalSpaceIDKey) == nil)
    }

    @Test func personalDataDeletionRemovesManifestAndCreatesFreshIdentity() async throws {
        let container = makeTaskSubtaskModelContainer()
        let seeded = try seedPersonalDataDeletionStore(container: container)
        let suiteName = "TogetherDeletionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "together.appLockEnabled")
        defaults.set(seeded.spaceID.uuidString, forKey: PersonalIdentityService.provisionalSpaceIDKey)
        let fileCleaner = DeletionTestFileCleaner()
        let reminderScheduler = DeletionTestReminderScheduler()
        let service = PersonalDataDeletionService(
            container: container,
            reminderScheduler: reminderScheduler,
            fileCleaner: fileCleaner,
            defaults: defaults
        )

        let result = await service.deleteAllData()

        guard case let .completed(newUser, newSpace) = result else {
            Issue.record("完整清理后应重建空身份")
            return
        }
        #expect(newUser.id != seeded.userID)
        #expect(newSpace.id != seeded.spaceID)
        #expect(newSpace.ownerUserID == newUser.id)
        #expect(fileCleaner.clearCallCount == 1)
        #expect(defaults.object(forKey: "together.appLockEnabled") == nil)

        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<PersistentItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentTaskSubtask>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentItemOccurrenceCompletion>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentPeriodicTask>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentTaskList>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentProject>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentProjectSubtask>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentUserProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PersistentSpace>()) == 1)
        #expect(reminderScheduler.removedTaskIDs.contains(seeded.itemID))
        #expect(reminderScheduler.removedPeriodicTaskIDs.contains(seeded.periodicTaskID))
    }

    @Test func personalDataDeletionFailureIsNotReportedAsCompleted() async throws {
        let container = makeTaskSubtaskModelContainer()
        _ = try seedPersonalDataDeletionStore(container: container)
        let cleaner = DeletionTestFileCleaner(shouldFail: true)
        let service = PersonalDataDeletionService(
            container: container,
            reminderScheduler: DeletionTestReminderScheduler(),
            fileCleaner: cleaner,
            defaults: try #require(UserDefaults(suiteName: "TogetherDeletionFailure-\(UUID().uuidString)"))
        )

        let result = await service.deleteAllData()

        guard case .failed = result else {
            Issue.record("文件清理失败时不得报告删除完成")
            return
        }
    }

    @Test func ocrParserCreatesTaskDraftsFromPlainLines() {
        let draft = OCRImportDraftParser.parse(rawText: """
        - 买牛奶
        2. 整理周报
        □ 给房东发消息
        """)

        #expect(draft.status == .needsReview)
        #expect(draft.taskDrafts.map(\.title) == ["买牛奶", "整理周报", "给房东发消息"])
    }

    @Test func ocrParserCreatesTaskWithSubtasksFromHeadingAndBullets() {
        let draft = OCRImportDraftParser.parse(rawText: """
        搬家准备:
        - 预约搬家公司
        - 打包厨房
        """)

        #expect(draft.taskDrafts.count == 1)
        #expect(draft.taskDrafts.first?.title == "搬家准备")
        #expect(draft.taskDrafts.first?.subtasks.map(\.title) == ["预约搬家公司", "打包厨房"])
    }

    @Test func ocrParserPreservesTopLevelSourceOrder() {
        let draft = OCRImportDraftParser.parse(rawText: """
        先买牛奶
        搬家准备:
        - 预约搬家公司
        - 打包厨房
        """)

        #expect(draft.taskDrafts.map(\.title) == ["先买牛奶", "搬家准备"])
        #expect(draft.taskDrafts.last?.subtasks.map(\.title) == ["预约搬家公司", "打包厨房"])
    }

    @Test func ocrViewModelCreatesReviewFromPastedMultilineText() {
        let viewModel = OCRImportViewModel()

        viewModel.showPasteText()
        viewModel.processText("""
        1. 买牛奶
        2. 整理周报
        """)

        #expect(viewModel.flowState == .review)
        #expect(viewModel.draft.status == .needsReview)
        #expect(viewModel.draft.taskDrafts.map(\.title) == ["买牛奶", "整理周报"])
    }

    @Test func ocrViewModelKeepsPasteSurfaceForBlankText() {
        let viewModel = OCRImportViewModel()

        viewModel.showPasteText()
        viewModel.processText("  \n\n ")

        #expect(viewModel.flowState == .pasteText)
        #expect(viewModel.draft.status == .failed)
        #expect(viewModel.draft.taskDrafts.isEmpty)
        #expect(viewModel.errorMessage == "剪贴板中没有可导入的文字。")
    }

    @MainActor
    @Test func ocrViewModelUsesSingleTaskFlowForRecognition() async throws {
        let image = try #require(makeTestImage())
        let viewModel = OCRImportViewModel(
            recognizer: StubOCRTextRecognizer(result: .success("""
            信用卡商户:
            - 客户经理对接名单
            - 召开线下沙龙会
            """))
        )

        await viewModel.processImage(image)

        #expect(viewModel.flowState == .review)
        #expect(viewModel.draft.status == .needsReview)
        #expect(viewModel.draft.taskDrafts.count == 1)
        #expect(viewModel.draft.taskDrafts.first?.title == "信用卡商户")
        #expect(viewModel.draft.taskDrafts.first?.subtasks.map(\.title) == ["客户经理对接名单", "召开线下沙龙会"])
    }

    @MainActor
    @Test func ocrViewModelCombinesMultipleSelectedImages() async throws {
        let firstImage = try #require(makeTestImage())
        let secondImage = try #require(makeTestImage())
        let viewModel = OCRImportViewModel(
            recognizer: StubOCRTextRecognizer(results: [
                .success("买牛奶"),
                .success("整理周报")
            ])
        )

        await viewModel.processImages([firstImage, secondImage])

        #expect(viewModel.flowState == .review)
        #expect(viewModel.draft.status == .needsReview)
        #expect(viewModel.draft.rawText == "买牛奶\n整理周报")
        #expect(viewModel.draft.taskDrafts.map(\.title) == ["买牛奶", "整理周报"])
    }

    @Test func ocrReviewDetentPolicyStartsShortDraftAtMedium() {
        let draft = OCRImportDraft(
            rawText: "测试任务",
            status: .needsReview,
            taskDrafts: [OCRImportTaskDraft(title: "测试任务")]
        )

        #expect(
            OCRReviewDetentPolicy.initialDetent(for: draft, availableHeight: 844)
                == .medium
        )
    }

    @Test func ocrReviewDetentPolicyStartsLongDraftAtLarge() {
        let draft = OCRImportDraft(
            rawText: "批量任务",
            status: .needsReview,
            taskDrafts: (0..<4).map { index in
                OCRImportTaskDraft(
                    title: "任务 \(index)",
                    subtasks: (0..<2).map { OCRImportSubtaskDraft(title: "子任务 \($0)") }
                )
            }
        )

        #expect(
            OCRReviewDetentPolicy.initialDetent(for: draft, availableHeight: 844)
                == .large
        )
    }

    @Test func ocrReviewDetentPolicyOnlyPromotesAutomatically() {
        #expect(
            OCRReviewDetentPolicy.resolvedDetent(
                current: .medium,
                measuredContentHeight: 500,
                availableHeight: 844,
                keyboardIsVisible: false
            ) == .large
        )
        #expect(
            OCRReviewDetentPolicy.resolvedDetent(
                current: .large,
                measuredContentHeight: 120,
                availableHeight: 844,
                keyboardIsVisible: false
            ) == .large
        )
        #expect(
            OCRReviewDetentPolicy.resolvedDetent(
                current: .medium,
                measuredContentHeight: 120,
                availableHeight: 844,
                keyboardIsVisible: true
            ) == .large
        )
    }

    @MainActor
    @Test func ocrReviewSessionRetainsDraftAndDetectsUserChanges() {
        let viewModel = OCRImportViewModel(recognizer: StubOCRTextRecognizer(result: .success("测试测试")))
        viewModel.draft = OCRImportDraft(
            rawText: "测试测试",
            status: .needsReview,
            taskDrafts: [OCRImportTaskDraft(title: "测试测试")]
        )
        let session = OCRReviewSession(viewModel: viewModel, availableHeight: 844)

        #expect(session.viewModel === viewModel)
        #expect(session.viewModel.draft.taskDrafts.first?.title == "测试测试")
        #expect(session.hasUserChanges == false)

        var updated = viewModel.draft.taskDrafts[0]
        updated.title = "测试测试完整保存"
        viewModel.updateTask(updated)

        #expect(session.hasUserChanges)
        #expect(session.viewModel.draft.taskDrafts.first?.title == "测试测试完整保存")
    }

    @MainActor
    @Test func ocrApplyPreservesTaskAttributes() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 25, hour: 18, minute: 30)))
        let remindAt = try #require(calendar.date(byAdding: .minute, value: -15, to: dueAt))
        let taskApplicationService = CapturingTaskApplicationService()
        taskApplicationService.capturesCreates = true
        let appContext = try makeOCRAppContext(taskApplicationService: taskApplicationService)
        let viewModel = OCRImportViewModel(recognizer: StubOCRTextRecognizer(result: .success("信用卡商户")))
        viewModel.draft = OCRImportDraft(
            rawText: "信用卡商户",
            status: .needsReview,
            taskDrafts: [
                OCRImportTaskDraft(
                    title: "信用卡商户",
                    notes: "客户名单",
                    dueAt: dueAt,
                    hasExplicitTime: true,
                    remindAt: remindAt,
                    isUrgent: true,
                    subtasks: [
                        OCRImportSubtaskDraft(title: "客户经理对接名单"),
                        OCRImportSubtaskDraft(title: "召开线下沙龙会", isSelected: false)
                    ]
                )
            ]
        )
        viewModel.flowState = .review

        let applied = await viewModel.apply(to: appContext)

        #expect(applied)
        let captured = try #require(taskApplicationService.createdDrafts.first)
        #expect(captured.title == "信用卡商户")
        #expect(captured.notes == "客户名单")
        #expect(captured.dueAt == dueAt)
        #expect(captured.hasExplicitTime)
        #expect(captured.remindAt == remindAt)
        #expect(captured.isUrgent)
        #expect(captured.subtasks.map(\.title) == ["客户经理对接名单"])
    }

    @Test func homeTaskDateLabelUsesCreatedDateDueDateAndExplicitTime() throws {
        let calendar = gregorianCalendar()
        let createdAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 9)))
        let dueDate = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        let dueTime = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18, minute: 30)))

        var item = Item(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: MockDataFactory.currentUserID,
            title: "无截止任务",
            notes: nil,
            locationText: nil,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            lastActionByUserID: MockDataFactory.currentUserID,
            lastActionAt: .now,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil,
            isDraft: false
        )
        #expect(HomeTaskDateLabel.text(for: item, calendar: calendar) == "6月14日")

        item.dueAt = dueDate
        item.hasExplicitTime = false
        #expect(HomeTaskDateLabel.text(for: item, calendar: calendar) == "6月20日")

        item.dueAt = dueTime
        item.hasExplicitTime = true
        #expect(HomeTaskDateLabel.text(for: item, calendar: calendar) == "18:30")
    }

    @Test func completedTaskRangeUsesExpectedDayWeekAndMonthBounds() throws {
        let calendar = gregorianCalendar()
        let thursday = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12)))
        let today = CompletedTaskRange.today.bounds(for: thursday, calendar: calendar)
        let workweek = CompletedTaskRange.workweek.bounds(for: thursday, calendar: calendar)
        let workweekExcludingToday = CompletedTaskRange.workweekExcludingToday.bounds(for: thursday, calendar: calendar)
        let month = CompletedTaskRange.month.bounds(for: thursday, calendar: calendar)

        #expect(today.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        #expect(today.upperBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 21)))
        #expect(workweek.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 17)))
        #expect(workweek.upperBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 22)))
        #expect(workweekExcludingToday.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 17)))
        #expect(workweekExcludingToday.upperBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        #expect(month.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 1)))
        #expect(month.upperBound == calendar.date(from: DateComponents(year: 2030, month: 7, day: 1)))
        #expect(CompletedTaskRange.all.bounds(for: thursday, calendar: calendar).lowerBound == nil)
    }

    @Test func completedHistoryFilterUsesShortcutAndPreciseBounds() throws {
        let calendar = gregorianCalendar()
        let reference = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12)))
        let specificMonth = CompletedHistoryFilter.specificMonth(reference)
            .normalized(calendar: calendar)
            .bounds(for: reference, calendar: calendar)
        let specificDay = CompletedHistoryFilter.specificDay(reference)
            .normalized(calendar: calendar)
            .bounds(for: reference, calendar: calendar)

        #expect(CompletedHistoryFilter.week.bounds(for: reference, calendar: calendar).lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 17)))
        #expect(CompletedHistoryFilter.month.bounds(for: reference, calendar: calendar).lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 1)))
        #expect(CompletedHistoryFilter.all.bounds(for: reference, calendar: calendar).lowerBound == nil)
        #expect(specificMonth.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 1)))
        #expect(specificMonth.upperBound == calendar.date(from: DateComponents(year: 2030, month: 7, day: 1)))
        #expect(specificDay.lowerBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        #expect(specificDay.upperBound == calendar.date(from: DateComponents(year: 2030, month: 6, day: 21)))
    }

    @Test func completedHistoryFilterNavigationSubtitleUsesShortcutAndPreciseLabels() throws {
        let calendar = gregorianCalendar()
        let reference = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 12)))

        #expect(CompletedHistoryFilter.week.navigationSubtitle == "本周")
        #expect(CompletedHistoryFilter.month.navigationSubtitle == "本月")
        #expect(CompletedHistoryFilter.all.navigationSubtitle == "全部")
        #expect(CompletedHistoryFilter.specificMonth(reference).navigationSubtitle == "2030年6月")
        #expect(CompletedHistoryFilter.specificDay(reference).navigationSubtitle == "2030年6月20日")
    }

    @Test func homeFetchIncludesOnlyIncompleteAndTodayCompletedTasks() async throws {
        let calendar = gregorianCalendar()
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))

        let todayStart = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        let tomorrowStart = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 21)))
        let todayCompleted = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 10)))
        let yesterdayCompleted = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 19, hour: 18)))
        let previousWeekCompleted = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 18)))

        context.insert(PersistentItem(item: makeHomeFilterItem(title: "未完成任务", completedAt: nil, status: .inProgress)))
        context.insert(PersistentItem(item: makeHomeFilterItem(title: "今天已完成", completedAt: todayCompleted, status: .completed)))
        context.insert(PersistentItem(item: makeHomeFilterItem(title: "昨天已完成", completedAt: yesterdayCompleted, status: .completed)))
        context.insert(PersistentItem(item: makeHomeFilterItem(title: "上周已完成", completedAt: previousWeekCompleted, status: .completed)))
        try context.save()

        let repository = LocalItemRepository(container: container)
        let fetched = try await repository.fetchHomeItems(
            spaceID: MockDataFactory.singleSpaceID,
            completedFrom: todayStart,
            completedBefore: tomorrowStart
        )

        let fetchedTitles = Set(fetched.map(\.title))
        let expectedTitles: Set<String> = ["未完成任务", "今天已完成"]
        #expect(fetchedTitles == expectedTitles, "Fetched titles: \(fetchedTitles.sorted())")
    }

    @Test func completedTimelineEntriesShowOnlyTodayCompletedTasks() async throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let todayStart = calendar.startOfDay(for: .now)
        let today = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: todayStart))
        let weeklyRange = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: calendar)
        let weeklyCompleted = weeklyRange.upperBound.flatMap { upperBound in
            calendar.date(byAdding: .hour, value: -1, to: upperBound)
        }.flatMap { candidate in
            if let lowerBound = weeklyRange.lowerBound, candidate >= lowerBound {
                return candidate
            }
            return nil
        }
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        var items = [
            makeHomeFilterItem(title: "今天完成", completedAt: today, status: .completed),
        ]
        if let weeklyCompleted {
            items.append(makeHomeFilterItem(title: "本周历史完成", completedAt: weeklyCompleted, status: .completed))
        }
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: items),
        )

        await viewModel.reload()

        #expect(viewModel.completedVisibilityButtonTitle == "本周已完成")
        #expect(viewModel.completedTimelineEntries.map(\.title) == ["今天完成"])
        #expect(viewModel.weeklyCompletedEntryCount == (weeklyCompleted == nil ? 0 : 1))
    }

    @Test func completingTaskMovesToCompletedPresentationIdentity() async throws {
        let item = makeHomeFilterItem(title: "完成后进入已完成", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        let activeEntry = try #require(viewModel.activeTimelineEntries.first)

        await viewModel.completeItem(item.id)

        #expect(viewModel.activeTimelineEntries.isEmpty)
        #expect(viewModel.activeTimelineSections.isEmpty)
        let completedEntry = try #require(viewModel.completedTimelineEntries.first)
        #expect(activeEntry.itemID == item.id)
        #expect(completedEntry.itemID == item.id)
        #expect(completedEntry.isCompleted)
        #expect(completedEntry.statusText == "已完成")
        #expect(activeEntry.presentationID != completedEntry.presentationID)
    }

    @Test func homeReloadFailurePreservesLastSuccessfulItems() async throws {
        let item = makeHomeFilterItem(title: "保留的任务", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        repository.throwsOnFetchHomeItems = true
        await viewModel.reload()

        #expect(viewModel.items.map(\.id) == [item.id])
        guard case .failed = viewModel.loadState else {
            Issue.record("刷新失败后应保留数据并暴露失败状态")
            return
        }
    }

    @Test func completingFutureDatedTaskUsesCompletionAnimationBranch() async throws {
        var item = makeHomeFilterItem(title: "提前完成未来任务", completedAt: nil, status: .inProgress)
        item.dueAt = Date.now.addingTimeInterval(86_400)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        let completionTask = Task { @MainActor in
            await viewModel.completeItem(item.id)
        }

        try await Task.sleep(for: .milliseconds(80))

        #expect(viewModel.isAnimatingCompletion(for: item.id, on: viewModel.selectedDate))
        #expect(viewModel.isAnimatingReopening(for: item.id, on: viewModel.selectedDate) == false)

        await completionTask.value
        let completedEntry = try #require(viewModel.completedTimelineEntries.first { $0.itemID == item.id })
        #expect(completedEntry.isCompleted)
    }

    @Test func recurringTaskCompletionOnlyAppliesToSelectedOccurrence() async throws {
        var item = makeHomeFilterItem(title: "每日复盘", completedAt: nil, status: .inProgress)
        item.repeatRule = ItemRepeatRule(frequency: .daily)
        item.dueAt = Calendar.current.startOfDay(for: .now)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        await viewModel.completeItem(item.id)

        let todayEntry = try #require(viewModel.completedTimelineEntries.first)
        #expect(todayEntry.itemID == item.id)
        #expect(todayEntry.isCompleted)
        #expect(viewModel.todayCompletedEntryCount == 1)

        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        viewModel.selectDate(tomorrow)

        let tomorrowEntry = try #require(viewModel.activeTimelineEntries.first)
        #expect(tomorrowEntry.itemID == item.id)
        #expect(tomorrowEntry.isCompleted == false)
        #expect(tomorrowEntry.statusText != "已完成")
    }

    @Test func dailyPeriodicCycleUsesCalendarDayAsPeriod() throws {
        let calendar = gregorianCalendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 15, minute: 45)))

        let key = PeriodicCycleCalculator.periodKey(for: .daily, date: date, calendar: calendar)
        let range = PeriodicCycleCalculator.periodDateRange(for: .daily, date: date, calendar: calendar)

        #expect(key == "2026-06-30")
        #expect(range.start == calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        #expect(range.end == calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        #expect(PeriodicCycleCalculator.totalDaysInPeriod(for: .daily, date: date, calendar: calendar) == 1)
    }

    @Test func routineTargetTextUsesGoalRhythmLanguage() {
        var calendar = gregorianCalendar()
        calendar.firstWeekday = 2

        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(timing: .dayOfPeriod(1), hour: 8, minute: 30),
                cycle: .daily,
                calendar: calendar
            ) == "目标 08:30"
        )
        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 0),
                cycle: .weekly,
                calendar: calendar
            ) == "周三 18:00"
        )
        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(timing: .dayOfPeriod(31), hour: 9, minute: 0),
                cycle: .monthly,
                calendar: calendar
            ) == "每月最后一天 09:00"
        )
    }

    @Test func routineTargetTextSupportsPartialTargetConfiguration() {
        var calendar = gregorianCalendar()
        calendar.firstWeekday = 2

        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(timing: .dayOfPeriod(3)),
                cycle: .weekly,
                calendar: calendar
            ) == "周三"
        )
        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(hour: 18, minute: 30),
                cycle: .weekly,
                calendar: calendar
            ) == "目标 18:30"
        )
        #expect(
            RoutineTargetText.text(
                for: PeriodicReminderRule(),
                cycle: .weekly,
                calendar: calendar
            ).isEmpty
        )
    }

    @Test func periodicReminderRuleDecodesLegacyCompleteValues() throws {
        struct LegacyRule: Encodable {
            let timing: PeriodicReminderRule.Timing
            let hour: Int
            let minute: Int
        }

        let data = try JSONEncoder().encode(
            LegacyRule(timing: .dayOfPeriod(3), hour: 9, minute: 15)
        )
        let decoded = try JSONDecoder().decode(PeriodicReminderRule.self, from: data)

        #expect(decoded.timing == .dayOfPeriod(3))
        #expect(decoded.hour == 9)
        #expect(decoded.minute == 15)
        #expect(decoded.hasTargetDay)
        #expect(decoded.hasTargetTime)
        #expect(decoded.reminderLeadMinutes == 0)
        #expect(decoded.reminderDelivery == .notification)
    }

    @Test func periodicTargetOnlyRuleRoundTripsWithoutEnablingReminder() throws {
        let original = PeriodicReminderRule(
            timing: .dayOfPeriod(3),
            hour: 9,
            minute: 15
        )

        let decoded = try JSONDecoder().decode(
            PeriodicReminderRule.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded.hasReminder == false)
        #expect(decoded.reminderLeadMinutes == nil)
        #expect(decoded.reminderDelivery == nil)
    }

    @Test func dailyTimeOnlyRuleProducesReminderOnCurrentDay() throws {
        var calendar = gregorianCalendar()
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 18, hour: 12))
        )

        let trigger = try #require(
            PeriodicCycleCalculator.reminderTriggerDate(
                rule: PeriodicReminderRule(hour: 18, minute: 30),
                cycle: .daily,
                date: referenceDate,
                calendar: calendar
            )
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: trigger)

        #expect(components.year == 2030)
        #expect(components.month == 6)
        #expect(components.day == 18)
        #expect(components.hour == 18)
        #expect(components.minute == 30)
    }

    @Test func periodicReminderDateAppliesLeadMinutes() throws {
        var calendar = gregorianCalendar()
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 18, hour: 8))
        )
        let rule = PeriodicReminderRule(
            hour: 18,
            minute: 30,
            reminderLeadMinutes: 30,
            reminderDelivery: .notification
        )

        let trigger = try #require(
            PeriodicCycleCalculator.periodicReminderDate(
                rule: rule,
                cycle: .daily,
                date: referenceDate,
                calendar: calendar
            )
        )
        let components = calendar.dateComponents([.hour, .minute], from: trigger)
        #expect(components.hour == 18)
        #expect(components.minute == 0)
    }

    @Test func routineDraftDoesNotAddDefaultDayOrTimeWhenCycleChanges() async {
        let task = makePeriodicTask(title: "未设置目标", cycle: .daily, reminderRules: [])
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftCycle(.weekly)

        #expect(viewModel.detailDraft?.reminderRules.isEmpty == true)
        #expect(RoutinesViewModel.defaultRule(for: .weekly).isEmpty)
    }

    @Test func inlineDateTimePickerDraftStagesClearAndRestoreWithoutMutatingInitialValue() {
        let initial = Date(timeIntervalSince1970: 1_000)
        let replacement = Date(timeIntervalSince1970: 2_000)
        var draft = InlineDateTimePickerDraft(
            initialSelection: initial,
            fallbackSelection: replacement
        )

        draft.clear()
        #expect(draft.stagedSelection == nil)
        #expect(draft.initialSelection == initial)

        draft.restore()
        #expect(draft.stagedSelection == initial)

        draft.select(replacement)
        #expect(draft.stagedSelection == replacement)
        #expect(draft.initialSelection == initial)
    }

    @Test func inlineDateTimePickerDraftSeedsUnsetValueWithoutCreatingAnExternalSelection() {
        let fallback = Date(timeIntervalSince1970: 3_000)
        let draft = InlineDateTimePickerDraft(
            initialSelection: nil,
            fallbackSelection: fallback
        )

        #expect(draft.initialSelection == nil)
        #expect(draft.stagedSelection == fallback)
        #expect(draft.pickerSelection == fallback)
    }

    @Test func routinesFailureIsNotPresentedAsEmptyState() async {
        let service = CapturingPeriodicTaskApplicationService(tasks: [], shouldFailFetch: true)
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)

        await viewModel.load()

        #expect(viewModel.tasks.isEmpty)
        guard case .failed = viewModel.loadState else {
            Issue.record("首次读取失败应暴露失败状态")
            return
        }
        #expect(viewModel.taskStreamPresentation == .failure)
    }

    @Test func periodicFocusCreationUsesItsPreallocatedIdentityForLanding() async throws {
        let service = CapturingPeriodicTaskApplicationService(tasks: [])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)

        viewModel.beginTaskCreation(defaultCycle: .weekly)
        let provisionalID = try #require(viewModel.creationSession?.id)
        viewModel.updateCreationDraft { $0.title = "稳定身份定期任务" }

        let result = await viewModel.commitTaskCreation()
        let createdID: UUID
        switch result {
        case .saved(let value):
            createdID = value
        case .failed(let message):
            Issue.record(Comment(rawValue: message))
            return
        }

        #expect(service.tasks.last?.id == provisionalID)
        #expect(createdID == provisionalID)
        #expect(service.tasks.last?.cycle == .weekly)
        #expect(viewModel.creationSession?.phase == .committed)
    }

    @Test func periodicCreationCommitsToEditedCycleWithStableIdentity() async throws {
        let existingTask = makePeriodicTask(title: "已有每周任务", cycle: .weekly)
        let service = CapturingPeriodicTaskApplicationService(tasks: [existingTask])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)

        await viewModel.loadIfNeeded()

        viewModel.beginTaskCreation(defaultCycle: .weekly)
        let sessionID = try #require(viewModel.creationSession?.id)
        viewModel.updateDraftTitle("月末复盘")
        viewModel.updateDraftCycle(.monthly)

        #expect(viewModel.activeEditorDraft?.cycle == .monthly)

        guard case .saved(let createdID) = await viewModel.commitTaskCreation() else {
            Issue.record("定期任务应保存成功")
            return
        }
        #expect(createdID == sessionID)
        #expect(service.tasks.last?.cycle == .monthly)
    }

    @Test func routineDraftClearsTargetDayAndTimeIndependently() async {
        let task = makePeriodicTask(
            title: "分别清空",
            cycle: .weekly,
            reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)]
        )
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.clearDraftTargetDay()
        #expect(viewModel.detailDraft?.reminderRules.first?.timing == nil)
        #expect(viewModel.detailDraft?.reminderRules.first?.hour == 18)
        #expect(viewModel.detailDraft?.reminderRules.first?.minute == 30)

        viewModel.updateDraftTargetDay(.dayOfPeriod(5))
        viewModel.clearDraftTargetTime()
        #expect(viewModel.detailDraft?.reminderRules.first?.timing == .dayOfPeriod(5))
        #expect(viewModel.detailDraft?.reminderRules.first?.hour == nil)
        #expect(viewModel.detailDraft?.reminderRules.first?.minute == nil)
    }

    @Test func routineIndependentTargetClearsPersistOnlyAfterCollapse() async throws {
        let task = makePeriodicTask(
            title: "持久化分别清空",
            cycle: .weekly,
            reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)]
        )
        let service = CapturingPeriodicTaskApplicationService(tasks: [task])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.clearDraftTargetDay()
        #expect(service.updatedDrafts.isEmpty)
        #expect(await viewModel.collapseInlineDetail())

        let dayCleared = try #require(service.updatedDrafts.last?.reminderRules.first)
        #expect(dayCleared.timing == nil)
        #expect(dayCleared.hour == 18)
        #expect(dayCleared.minute == 30)

        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftTargetDay(.dayOfPeriod(5))
        viewModel.clearDraftTargetTime()
        #expect(await viewModel.collapseInlineDetail())

        let timeCleared = try #require(service.updatedDrafts.last?.reminderRules.first)
        #expect(timeCleared.timing == .dayOfPeriod(5))
        #expect(timeCleared.hour == nil)
        #expect(timeCleared.minute == nil)
    }

    @Test func routineDisplayPlacesPropertiesBelowNotes() {
        var calendar = gregorianCalendar()
        calendar.firstWeekday = 2
        let task = makePeriodicTask(
            title: "回访",
            cycle: .weekly,
            reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)]
        )
        var notedTask = task
        notedTask.notes = "等待客户回复"

        let display = RoutineTaskDisplayText.text(
            for: notedTask,
            isCompleted: false,
            calendar: calendar
        )
        #expect(display.primarySubtitle == "等待客户回复")
        #expect(display.propertyText == "周三 18:30")
    }

    @Test func routineDisplayFallsBackToStatusWithoutNoteOrTarget() {
        let task = makePeriodicTask(title: "无目标", cycle: .weekly, reminderRules: [])

        let active = RoutineTaskDisplayText.text(for: task, isCompleted: false)
        let completed = RoutineTaskDisplayText.text(for: task, isCompleted: true)

        #expect(active.primarySubtitle == "进行中")
        #expect(active.propertyText == nil)
        #expect(completed.primarySubtitle == "已完成")
        #expect(completed.propertyText == nil)
    }

    @Test func routinesVisibleCyclesDefaultToDayWeekMonthWithoutForcingTaskDimensions() {
        clearRoutineCycleVisibilityPreferences()
        defer { clearRoutineCycleVisibilityPreferences() }
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [
            makePeriodicTask(title: "每日", cycle: .daily),
            makePeriodicTask(title: "季度", cycle: .quarterly)
        ]

        #expect(viewModel.persistedVisibleCycles == Set([.daily, .weekly, .monthly]))
        #expect(viewModel.visibleCycles == [.daily, .weekly, .monthly])
        #expect(viewModel.hiddenCycles == [.quarterly, .yearly])
        #expect(viewModel.tasks.count == 2)
    }

    @Test func routinesVisibleCyclesMigrateLegacyOptionalCycles() {
        clearRoutineCycleVisibilityPreferences()
        defer { clearRoutineCycleVisibilityPreferences() }
        UserDefaults.standard.set(
            [PeriodicCycle.quarterly.rawValue],
            forKey: "together.routines.visibleOptionalCycles"
        )

        let viewModel = makeRoutinesViewModel()

        #expect(viewModel.persistedVisibleCycles == Set([.daily, .weekly, .monthly, .quarterly]))
        #expect(viewModel.visibleCycles == [.daily, .weekly, .monthly, .quarterly])
    }

    @Test func routinesCycleVisibilityKeepsAtLeastOneAndMovesSelection() {
        clearRoutineCycleVisibilityPreferences()
        defer { clearRoutineCycleVisibilityPreferences() }
        let viewModel = makeRoutinesViewModel()
        viewModel.selectCycle(.weekly)

        viewModel.setCycle(.weekly, isVisible: false)
        #expect(viewModel.selectedCycle == .daily)
        #expect(viewModel.visibleCycles == [.daily, .monthly])

        viewModel.setCycle(.daily, isVisible: false)
        viewModel.setCycle(.monthly, isVisible: false)
        #expect(viewModel.persistedVisibleCycles == Set([.monthly]))
        #expect(viewModel.visibleCycles == [.monthly])

        let restoredViewModel = makeRoutinesViewModel()
        #expect(restoredViewModel.selectedCycle == .monthly)
        #expect(restoredViewModel.visibleCycles == [.monthly])
    }

    @Test func routinesHiddenAttentionCycleIsTemporaryUntilSelectionChanges() {
        clearRoutineCycleVisibilityPreferences()
        defer { clearRoutineCycleVisibilityPreferences() }
        let viewModel = makeRoutinesViewModel()

        viewModel.selectCycleTemporarily(.yearly)
        #expect(viewModel.selectedCycle == .yearly)
        #expect(viewModel.visibleCycles == [.daily, .weekly, .monthly, .yearly])
        #expect(viewModel.persistedVisibleCycles.contains(.yearly) == false)

        viewModel.selectCycle(.weekly)
        #expect(viewModel.selectedCycle == .weekly)
        #expect(viewModel.visibleCycles == [.daily, .weekly, .monthly])
        #expect(viewModel.persistedVisibleCycles.contains(.yearly) == false)
    }

    @Test func routinesAttentionSummaryOnlyIncludesUnfinishedApproachingTasks() {
        let viewModel = makeRoutinesViewModel()
        let referenceDate = Date.now
        let todayKey = PeriodicCycleCalculator.periodKey(for: .daily, date: referenceDate)
        viewModel.referenceDate = referenceDate
        viewModel.tasks = [
            makePeriodicTask(
                title: "已临期",
                cycle: .daily,
                reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(1), hour: 0, minute: 0)]
            ),
            makePeriodicTask(
                title: "已完成不提醒",
                cycle: .daily,
                reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(1), hour: 0, minute: 0)],
                completions: [PeriodicCompletion(periodKey: todayKey, completedAt: referenceDate)]
            ),
            makePeriodicTask(title: "无目标不提醒", cycle: .daily, reminderRules: [])
        ]

        #expect(viewModel.attentionSummary(referenceDate: referenceDate).map(\.0) == [.daily])
        #expect(viewModel.attentionSummary(referenceDate: referenceDate).first?.1 == 1)
        #expect(viewModel.hasAttentionTasks)
    }

    @Test func routineInlineEditingPersistsOnlyWhenCollapsed() async throws {
        let task = makePeriodicTask(title: "旧标题", cycle: .daily)
        let service = CapturingPeriodicTaskApplicationService(tasks: [task])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftTitle("新标题")

        #expect(service.updatedDrafts.isEmpty)
        await viewModel.collapseInlineDetail()

        #expect(service.updatedDrafts.map(\.title) == ["新标题"])
        #expect(viewModel.tasks.first?.title == "新标题")
    }

    @Test func routineDimensionSummaryReportsCompletionProgress() {
        let viewModel = makeRoutinesViewModel()
        let periodKey = PeriodicCycleCalculator.periodKey(
            for: .daily,
            date: viewModel.referenceDate
        )
        viewModel.tasks = [
            makePeriodicTask(
                title: "已完成",
                cycle: .daily,
                completions: [PeriodicCompletion(periodKey: periodKey, completedAt: viewModel.referenceDate)]
            ),
            makePeriodicTask(title: "未完成", cycle: .daily)
        ]

        let summary = viewModel.summary(for: .daily)

        #expect(summary.completedCount == 1)
        #expect(summary.pendingCount == 1)
        #expect(summary.totalCount == 2)
        #expect(summary.completionProgress == 0.5)
    }

    @Test func routineExpandedCompletionKeepsRowActiveUntilAnimationFinishes() async {
        let task = makePeriodicTask(title: "动画完成后再重排", cycle: .daily)
        let service = CapturingPeriodicTaskApplicationService(tasks: [task])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        #expect(await viewModel.prepareExpandedCompletion(taskID: task.id))

        #expect(viewModel.isAnimatingCompletion(taskID: task.id))
        #expect(viewModel.isCompleted(viewModel.tasks[0]) == false)

        viewModel.finishExpandedCompletion(taskID: task.id)

        #expect(viewModel.isCompleted(viewModel.tasks[0]))
        #expect(viewModel.isAnimatingCompletion(taskID: task.id) == false)
    }

    @Test func routineCycleSelectionIsBlockedWhileInlineDetailIsExpanded() async {
        let task = makePeriodicTask(title: "每日复盘", cycle: .daily)
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.selectCycle(.weekly)

        #expect(viewModel.selectedCycle == .daily)
        #expect(viewModel.expandedTaskID == task.id)
    }

    @Test func routineDraftCycleAndTargetPersistOnlyAfterCollapse() async throws {
        let task = makePeriodicTask(title: "每日复盘", cycle: .daily)
        let service = CapturingPeriodicTaskApplicationService(tasks: [task])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]
        let weeklyRule = PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)

        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftCycle(.weekly)
        viewModel.updateDraftReminderRule(weeklyRule)

        #expect(service.updatedDrafts.isEmpty)
        #expect(viewModel.currentTasks.map(\.id) == [task.id])

        await viewModel.collapseInlineDetail()

        let savedDraft = try #require(service.updatedDrafts.last)
        #expect(savedDraft.cycle == .weekly)
        #expect(savedDraft.reminderRules == [weeklyRule])
        #expect(viewModel.currentTasks.isEmpty)
    }

    @Test func routineAttributesPersistForLegacyCreatorInCurrentSingleSpace() async throws {
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        let task = PeriodicTask(
            id: UUID(),
            spaceID: MockDataFactory.singleSpaceID,
            creatorID: UUID(),
            title: "旧身份例行任务",
            notes: nil,
            cycle: .daily,
            reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(1), hour: 9, minute: 0)],
            completions: [],
            sortOrder: 0,
            isActive: true,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))
        context.insert(PersistentPeriodicTask(task: task))
        try context.save()

        let repository = LocalPeriodicTaskRepository(container: container)
        let service = DefaultPeriodicTaskApplicationService(
            repository: repository,
            reminderScheduler: MockReminderScheduler(),
            syncCoordinator: NoOpSyncCoordinator()
        )
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)

        await viewModel.load()
        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftNotes("收起后保存")
        viewModel.updateDraftCycle(.weekly)
        viewModel.updateDraftReminderRule(
            PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)
        )
        await viewModel.collapseInlineDetail()

        let saved = try #require(try await repository.fetchTask(taskID: task.id))
        #expect(saved.notes == "收起后保存")
        #expect(saved.cycle == .weekly)
        #expect(saved.reminderRules == [
            PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)
        ])
    }

    @Test func routineCanBeDeferredUntilTomorrowWithoutChangingItsRule() async throws {
        let task = makePeriodicTask(
            title: "明天再做",
            cycle: .weekly,
            reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 18, minute: 30)]
        )
        let service = CapturingPeriodicTaskApplicationService(tasks: [task])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]
        viewModel.selectCycle(.weekly)

        await viewModel.deferTaskUntilTomorrow(taskID: task.id)

        let deferredTask = try #require(viewModel.tasks.first)
        let deferredUntil = try #require(deferredTask.deferredUntil)
        #expect(deferredTask.reminderRules == task.reminderRules)
        #expect(viewModel.currentTasks.isEmpty)
        #expect(viewModel.summary(for: .weekly).totalCount == 0)

        viewModel.referenceDate = deferredUntil.addingTimeInterval(1)
        #expect(viewModel.currentTasks.map(\.id) == [task.id])
    }

    @Test func legacyCreatorRoutineCanBeDeletedInsideCurrentPersonalSpace() async throws {
        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        let task = PeriodicTask(
            spaceID: MockDataFactory.singleSpaceID,
            creatorID: UUID(),
            title: "旧身份可删除",
            cycle: .daily
        )
        context.insert(PersistentPeriodicTask(task: task))
        try context.save()

        let reminderScheduler = DeletionTestReminderScheduler()
        let repository = LocalPeriodicTaskRepository(container: container)
        let service = DefaultPeriodicTaskApplicationService(
            repository: repository,
            reminderScheduler: reminderScheduler,
            syncCoordinator: NoOpSyncCoordinator()
        )

        try await service.deleteTask(
            in: MockDataFactory.singleSpaceID,
            taskID: task.id,
            actorID: MockDataFactory.currentUserID
        )

        #expect(try await repository.fetchTask(taskID: task.id) == nil)
        #expect(reminderScheduler.removedPeriodicTaskIDs.contains(task.id))
    }

    @Test func routineCollapseKeepsDraftOpenWhenPersistenceFails() async throws {
        let task = makePeriodicTask(title: "保存失败时保留", cycle: .daily)
        let service = CapturingPeriodicTaskApplicationService(tasks: [task], shouldFailUpdates: true)
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)
        viewModel.updateDraftCycle(.monthly)
        let didCollapse = await viewModel.collapseInlineDetail()

        #expect(didCollapse == false)
        #expect(viewModel.expandedTaskID == task.id)
        #expect(viewModel.detailDraft?.cycle == .monthly)
        #expect(viewModel.loadState != .loaded)
    }

    @Test func routineTappingAnotherTaskOnlyCollapsesCurrentDetail() async {
        let first = makePeriodicTask(title: "第一项", cycle: .daily)
        let second = makePeriodicTask(title: "第二项", cycle: .daily)
        let service = CapturingPeriodicTaskApplicationService(tasks: [first, second])
        let viewModel = makeRoutinesViewModel(periodicTaskApplicationService: service)
        viewModel.tasks = [first, second]

        await viewModel.toggleInlineDetail(first.id)
        await viewModel.toggleInlineDetail(second.id)

        #expect(viewModel.expandedTaskID == nil)
        #expect(viewModel.detailDraft == nil)
    }

    @Test func completedRoutineDoesNotOpenInlineDetail() async {
        let periodKey = PeriodicCycleCalculator.periodKey(for: .daily, date: .now)
        let task = makePeriodicTask(
            title: "已经打卡",
            cycle: .daily,
            completions: [PeriodicCompletion(periodKey: periodKey, completedAt: .now)]
        )
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)

        #expect(viewModel.expandedTaskID == nil)
        #expect(viewModel.detailDraft == nil)
        #expect(viewModel.presentDetailForMorph(task.id) == false)
    }

    @Test func homeReloadKeepsTasksWhenWeeklyCompletedCountFails() async throws {
        let weeklyRange = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: .current)
        var expectedWeeklyCount = 0
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        var items = [
            makeHomeFilterItem(title: "未完成仍显示", completedAt: nil, status: .inProgress)
        ]
        if let lowerBound = weeklyRange.lowerBound,
           let upperBound = weeklyRange.upperBound,
           lowerBound < upperBound,
           let completedAt = Calendar.current.date(byAdding: .hour, value: 1, to: lowerBound) {
            items.append(makeHomeFilterItem(title: "本周完成仍计数", completedAt: completedAt, status: .completed))
            expectedWeeklyCount = 1
        }
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: items, throwsOnCompletedItemCount: true),
        )

        await viewModel.reload()

        #expect(viewModel.activeTimelineEntries.map(\.title) == ["未完成仍显示"])
        #expect(viewModel.weeklyCompletedEntryCount == expectedWeeklyCount)
    }

    @Test func overdueTasksAppearOnlyInOverdueSummaryWhileViewingToday() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        var overdue = makeHomeFilterItem(
            title: "逾期任务只进汇总",
            completedAt: nil,
            status: .inProgress
        )
        overdue.dueAt = yesterday
        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [overdue])
        )

        await viewModel.reload()

        #expect(viewModel.overdueEntryCount == 1)
        #expect(viewModel.overdueSummaryEntries.map(\.id) == [overdue.id])
        #expect(viewModel.activeTimelineEntries.isEmpty)
        #expect(viewModel.activeTimelineSections.isEmpty)
    }

    @Test func overdueSummaryEntryPresentsOnlyWhileViewingToday() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        var overdue = makeHomeFilterItem(
            title: "逾期入口任务",
            completedAt: nil,
            status: .inProgress
        )
        overdue.dueAt = yesterday
        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [overdue])
        )

        await viewModel.reload()

        #expect(viewModel.showsOverdueCapsule)
        #expect(viewModel.isOverdueSheetPresented == false)

        viewModel.presentOverdueSheet()
        #expect(viewModel.isOverdueSheetPresented)

        viewModel.selectDate(tomorrow)
        #expect(viewModel.showsOverdueCapsule == false)
        #expect(viewModel.isOverdueSheetPresented == false)

        viewModel.presentOverdueSheet()
        #expect(viewModel.isOverdueSheetPresented == false)
    }

    @Test func homeTimelineSortsIncompleteTasksByDueDateAscendingBeforeSortOrder() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let earlyDue = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let lateDue = try #require(calendar.date(byAdding: .day, value: 3, to: todayStart))
        var early = makeHomeFilterItem(title: "更早截止", completedAt: nil, status: .inProgress)
        early.dueAt = earlyDue
        early.sortOrder = 99
        var late = makeHomeFilterItem(title: "更晚截止", completedAt: nil, status: .inProgress)
        late.dueAt = lateDue
        late.sortOrder = 0
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: [late, early]),
        )

        await viewModel.reload()

        #expect(viewModel.activeTimelineEntries.map(\.title) == ["更早截止", "更晚截止"])
    }

    @Test func activeTimelineSectionsDefensivelyTreatMissingDateAsToday() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        let tomorrowStart = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let tomorrowTime = try #require(calendar.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrowStart))

        let missingDate = makeHomeFilterItem(
            title: "旧数据归入今天",
            completedAt: nil,
            status: .inProgress,
            createdAt: yesterdayStart
        )

        var scheduled = makeHomeFilterItem(title: "有截止按截止日", completedAt: nil, status: .inProgress)
        scheduled.dueAt = tomorrowStart
        scheduled.sortOrder = 0

        var timed = makeHomeFilterItem(title: "有时间仍在截止日组", completedAt: nil, status: .inProgress)
        timed.dueAt = tomorrowTime
        timed.hasExplicitTime = true
        timed.sortOrder = 1

        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [missingDate, timed, scheduled])
        )

        await viewModel.reload()

        let sections = viewModel.activeTimelineSections
        #expect(sections.count == 2)
        #expect(sections.map(\.isUnscheduled) == [false, false])
        #expect(sections.map(\.dayStart) == [todayStart, tomorrowStart])
        #expect(sections[0].entries.map(\.title) == ["旧数据归入今天"])
        #expect(sections[1].entries.map(\.title) == ["有截止按截止日", "有时间仍在截止日组"])
    }

    @Test func urgentTasksLeadEachDateGroupInCreationOrder() async throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let firstCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondCreatedAt = firstCreatedAt.addingTimeInterval(60)

        var regular = makeHomeFilterItem(title: "普通任务", completedAt: nil, status: .inProgress)
        regular.dueAt = day
        regular.sortOrder = -100

        var laterUrgent = makeHomeFilterItem(
            title: "后创建紧急",
            completedAt: nil,
            status: .inProgress,
            createdAt: secondCreatedAt
        )
        laterUrgent.dueAt = day
        laterUrgent.isUrgent = true

        var earlierUrgent = makeHomeFilterItem(
            title: "先创建紧急",
            completedAt: nil,
            status: .inProgress,
            createdAt: firstCreatedAt
        )
        earlierUrgent.dueAt = day
        earlierUrgent.isUrgent = true

        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [regular, laterUrgent, earlierUrgent])
        )

        await viewModel.reload()

        #expect(viewModel.activeTimelineSections.first?.entries.map(\.title) == [
            "先创建紧急", "后创建紧急", "普通任务"
        ])
    }

    @Test func repositoryAllowsMultipleUrgentTasks() async throws {
        var first = makeHomeFilterItem(title: "紧急一", completedAt: nil, status: .inProgress)
        var second = makeHomeFilterItem(title: "紧急二", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [first, second])

        first.isUrgent = true
        second.isUrgent = true
        _ = try await repository.saveItem(first)
        _ = try await repository.saveItem(second)

        #expect(try await repository.fetchItem(itemID: first.id)?.isUrgent == true)
        #expect(try await repository.fetchItem(itemID: second.id)?.isUrgent == true)
    }

    @Test func localRepositoryKeepsMultipleUrgentTasks() async throws {
        let repository = makeTaskSubtaskItemRepository()
        var first = makeHomeFilterItem(title: "本地紧急一", completedAt: nil, status: .inProgress)
        var second = makeHomeFilterItem(title: "本地紧急二", completedAt: nil, status: .inProgress)
        first.isUrgent = true
        second.isUrgent = true

        _ = try await repository.saveItem(first)
        _ = try await repository.saveItem(second)

        #expect(try await repository.fetchItem(itemID: first.id)?.isUrgent == true)
        #expect(try await repository.fetchItem(itemID: second.id)?.isUrgent == true)
    }

    @Test func explicitTimelineTimeMovesToSecondaryTextOnly() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let tomorrowStart = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let dueTime = try #require(calendar.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrowStart))
        var timed = makeHomeFilterItem(title: "明确时间任务", completedAt: nil, status: .inProgress)
        timed.dueAt = dueTime
        timed.hasExplicitTime = true

        let viewModel = makeInlineDetailHomeViewModel(
            repository: MockItemRepository(items: [timed])
        )

        await viewModel.reload()

        let entry = try #require(viewModel.activeTimelineEntries.first)
        #expect(entry.timeText == "18:30")
        #expect(HomeTimelineSubtitleText.text(for: entry) == "18:30")
    }

    @Test func homeSnoozeUpdatesDueDateAndResortsTimelineImmediately() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let initialDue = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let nextDue = try #require(calendar.date(byAdding: .day, value: 2, to: todayStart))
        let laterDue = try #require(calendar.date(byAdding: .day, value: 3, to: todayStart))
        var snoozed = makeHomeFilterItem(title: "要推迟", completedAt: nil, status: .inProgress)
        snoozed.dueAt = initialDue
        snoozed.sortOrder = 0
        var later = makeHomeFilterItem(title: "后面的任务", completedAt: nil, status: .inProgress)
        later.dueAt = nextDue
        later.sortOrder = 1
        var savedSnoozed = snoozed
        savedSnoozed.dueAt = laterDue
        savedSnoozed.updatedAt = .now
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let taskApplicationService = CapturingTaskApplicationService()
        taskApplicationService.snoozeItemToReturn = savedSnoozed
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskApplicationService,
            itemRepository: MockItemRepository(items: [snoozed, later]),
        )
        await viewModel.reload()

        await viewModel.snoozeItem(snoozed.id)

        #expect(taskApplicationService.capturedSnoozeOption == .tomorrow)
        #expect(viewModel.activeTimelineEntries.map(\.title) == ["后面的任务", "要推迟"])
        #expect(viewModel.item(for: snoozed.id)?.dueAt == laterDue)
    }

    @Test func overdueRescheduleToTodayMovesItemBackToPrimaryTimeline() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        var overdue = makeHomeFilterItem(title: "逾期任务", completedAt: nil, status: .inProgress)
        overdue.dueAt = yesterdayStart
        overdue.hasExplicitTime = false

        var saved = overdue
        saved.dueAt = todayStart
        saved.updatedAt = .now

        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let taskApplicationService = CapturingTaskApplicationService()
        taskApplicationService.rescheduleItemToReturn = saved
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskApplicationService,
            itemRepository: MockItemRepository(items: [overdue]),
        )
        await viewModel.reload()

        #expect(viewModel.overdueEntryCount == 1)
        #expect(viewModel.activeTimelineEntries.isEmpty)

        await viewModel.rescheduleOverdueItemToToday(overdue.id)

        #expect(taskApplicationService.capturedRescheduleDueAt == todayStart)
        #expect(taskApplicationService.capturedRescheduleRemindAt == nil)
        #expect(viewModel.overdueEntryCount == 0)
        #expect(viewModel.activeTimelineEntries.map(\.title) == ["逾期任务"])
    }

    @Test func overdueReschedulePreservesFutureReminderLead() async throws {
        let calendar = Calendar.current
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)
        let laterTodaySource = now.addingTimeInterval(7_200)
        let targetTime = try #require(calendar.date(
            bySettingHour: calendar.component(.hour, from: laterTodaySource),
            minute: calendar.component(.minute, from: laterTodaySource),
            second: 0,
            of: todayStart
        ))
        let yesterdayTime = try #require(calendar.date(byAdding: .day, value: -1, to: targetTime))
        var overdue = makeHomeFilterItem(title: "保留提醒", completedAt: nil, status: .inProgress)
        overdue.dueAt = yesterdayTime
        overdue.hasExplicitTime = true
        overdue.remindAt = yesterdayTime.addingTimeInterval(-1)

        var saved = overdue
        saved.dueAt = targetTime
        saved.remindAt = targetTime.addingTimeInterval(-1)

        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let service = CapturingTaskApplicationService()
        service.rescheduleItemToReturn = saved
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: service,
            itemRepository: MockItemRepository(items: [overdue])
        )
        await viewModel.reload()

        #expect(await viewModel.rescheduleOverdueItemToToday(overdue.id))
        let capturedDueAt = try #require(service.capturedRescheduleDueAt)
        #expect(service.capturedRescheduleRemindAt == capturedDueAt.addingTimeInterval(-1))
    }

    @Test func bulkOverdueRescheduleKeepsFailuresInSheetSource() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        var succeeds = makeHomeFilterItem(title: "迁移成功", completedAt: nil, status: .inProgress)
        succeeds.dueAt = yesterday
        var fails = makeHomeFilterItem(title: "迁移失败", completedAt: nil, status: .inProgress)
        fails.dueAt = yesterday

        var saved = succeeds
        saved.dueAt = todayStart
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let service = CapturingTaskApplicationService()
        service.rescheduleItemsToReturn[succeeds.id] = saved
        service.rescheduleFailureIDs.insert(fails.id)
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: service,
            itemRepository: MockItemRepository(items: [succeeds, fails])
        )
        await viewModel.reload()

        let result = await viewModel.rescheduleAllOverdueItemsToToday()

        #expect(Set(result.succeededIDs) == [succeeds.id])
        #expect(Set(result.failedIDs) == [fails.id])
        #expect(viewModel.overdueSummaryEntries.map(\.id) == [fails.id])
        #expect(viewModel.activeTimelineEntries.map(\.id) == [succeeds.id])
    }

    @Test func weeklyCompletedSheetExcludesTodayAndSortsDescending() async throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let todayStart = calendar.startOfDay(for: .now)
        let today = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: todayStart))
        let weeklyRange = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: calendar)
        let latestHistorical = weeklyRange.upperBound.flatMap { upperBound in
            calendar.date(byAdding: .hour, value: -1, to: upperBound)
        }.flatMap { candidate in
            if let lowerBound = weeklyRange.lowerBound, candidate >= lowerBound {
                return candidate
            }
            return nil
        }
        let earlierHistorical = latestHistorical.flatMap { latest in
            calendar.date(byAdding: .day, value: -1, to: latest)
        }.flatMap { candidate in
            if let lowerBound = weeklyRange.lowerBound, candidate >= lowerBound {
                return candidate
            }
            return nil
        }
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        var items = [
            makeHomeFilterItem(title: "今天完成", completedAt: today, status: .completed)
        ]
        var expectedTitles: [String] = []
        if let latestHistorical {
            items.append(makeHomeFilterItem(title: "最近历史完成", completedAt: latestHistorical, status: .completed))
            expectedTitles.append("最近历史完成")
        }
        if let earlierHistorical {
            items.append(makeHomeFilterItem(title: "更早历史完成", completedAt: earlierHistorical, status: .completed))
            expectedTitles.append("更早历史完成")
        }
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: items),
        )

        await viewModel.loadWeeklyCompletedSheet()

        #expect(viewModel.weeklyCompletedSheetItems.map(\.title) == expectedTitles)
    }

    @Test func weeklyCompletedSheetSeparatesListFailureFromCount() async throws {
        let calendar = Calendar.current
        let weeklyRange = CompletedTaskRange.workweekExcludingToday.bounds(for: .now, calendar: calendar)
        guard let lowerBound = weeklyRange.lowerBound,
              let upperBound = weeklyRange.upperBound,
              lowerBound < upperBound else {
            return
        }
        let completedAt = try #require(calendar.date(byAdding: .hour, value: 1, to: lowerBound))
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let items = [
            makeHomeFilterItem(title: "本周完成", completedAt: completedAt, status: .completed)
        ]
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(
                items: items,
                throwsOnFetchCompletedItems: true
            ),
        )

        await viewModel.loadWeeklyCompletedSheet()

        #expect(viewModel.weeklyCompletedEntryCount == 1)
        #expect(viewModel.weeklyCompletedSheetItems.isEmpty)
        #expect(viewModel.didFailLoadingWeeklyCompletedSheet)
    }

    @Test func completedHistoryFiltersAndSearchesSubtasks() async throws {
        let now = Date.now
        var matching = makeHomeFilterItem(title: "客户资料", completedAt: now, status: .completed)
        matching.subtasks = [
            TaskSubtask(
                id: UUID(),
                itemID: matching.id,
                creatorID: MockDataFactory.currentUserID,
                title: "整理报价附件",
                isCompleted: true,
                sortOrder: 0,
                updatedAt: now
            )
        ]
        let other = makeHomeFilterItem(title: "普通完成", completedAt: now, status: .completed)
        let viewModel = makeCompletedHistoryViewModel(
            items: [matching, other],
            initialFilter: .month
        )
        viewModel.searchText = "报价"

        await viewModel.reload()

        #expect(viewModel.items.map(\.title) == ["客户资料"])
        #expect(viewModel.sections.count == 1)
    }

    @Test func completedHistoryDistinguishesLoadingFailureFromEmptyState() async throws {
        let viewModel = makeCompletedHistoryViewModel(
            items: [makeHomeFilterItem(title: "会加载失败", completedAt: .now, status: .completed)],
            initialFilter: .all,
            throwsOnFetchCompletedItems: true
        )

        #expect(viewModel.isInitialLoading)

        await viewModel.reload()

        #expect(viewModel.hasLoaded)
        #expect(viewModel.didFailLoading)
        #expect(viewModel.isInitialLoading == false)
        #expect(viewModel.isEmpty)

        viewModel.applyFilter(.month)
        #expect(viewModel.didFailLoading == false)
        #expect(viewModel.isInitialLoading)
    }

    @Test func completedHistorySubtitleFallsBackToCompletionTime() async throws {
        let calendar = gregorianCalendar()
        let completedAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18, minute: 30)))
        let item = makeHomeFilterItem(title: "普通完成", completedAt: completedAt, status: .completed)
        let viewModel = makeCompletedHistoryViewModel(items: [item], initialFilter: .all)

        let subtitle = viewModel.subtitle(for: item)

        #expect(subtitle.hasPrefix("完成于 "))
        #expect(subtitle.contains(":") == false)
        #expect(subtitle.contains("未归类任务") == false)
    }

    @Test func completedHistoryAllFilterPaginates() async throws {
        let now = Date.now
        let items = (0..<35).compactMap { index -> Item? in
            guard let completedAt = Calendar.current.date(byAdding: .minute, value: -index, to: now) else {
                return nil
            }
            return makeHomeFilterItem(title: "完成 \(index)", completedAt: completedAt, status: .completed)
        }
        let viewModel = makeCompletedHistoryViewModel(items: items, initialFilter: .all)

        await viewModel.reload()
        #expect(viewModel.items.count == 30)
        #expect(viewModel.canLoadMore)

        let last = try #require(viewModel.items.last)
        await viewModel.loadMoreIfNeeded(currentItem: last)

        #expect(viewModel.items.count == 35)
        #expect(viewModel.canLoadMore == false)
    }

    @Test func completedHistoryPreciseFiltersAndPaginationReset() async throws {
        let calendar = gregorianCalendar()
        let juneDay = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 10)))
        let juneOtherDay = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 21, hour: 11)))
        let julyDay = try #require(calendar.date(from: DateComponents(year: 2030, month: 7, day: 1, hour: 12)))
        let items = [
            makeHomeFilterItem(title: "六月当天", completedAt: juneDay, status: .completed),
            makeHomeFilterItem(title: "六月其他", completedAt: juneOtherDay, status: .completed),
            makeHomeFilterItem(title: "七月", completedAt: julyDay, status: .completed)
        ]
        let viewModel = makeCompletedHistoryViewModel(items: items, initialFilter: .all)

        await viewModel.reload()
        #expect(viewModel.items.count == 3)

        viewModel.applyFilter(.specificMonth(juneDay))
        await viewModel.reload()
        #expect(viewModel.items.map(\.title) == ["六月其他", "六月当天"])
        #expect(viewModel.canLoadMore == false)

        viewModel.applyFilter(.specificDay(juneDay))
        await viewModel.reload()
        #expect(viewModel.items.map(\.title) == ["六月当天"])
    }

    @Test func completedItemStatsIncludesFirstAndLastCompletedDates() async throws {
        let calendar = gregorianCalendar()
        let older = try #require(calendar.date(from: DateComponents(year: 2030, month: 5, day: 1, hour: 9)))
        let newer = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 9)))
        let items = [
            makeHomeFilterItem(title: "较早", completedAt: older, status: .completed),
            makeHomeFilterItem(title: "较新", completedAt: newer, status: .completed)
        ]
        let mockStats = try await MockItemRepository(items: items).completedItemStats(
            spaceID: MockDataFactory.singleSpaceID,
            referenceDate: newer
        )
        #expect(mockStats.firstCompletedAt == older)
        #expect(mockStats.lastCompletedAt == newer)

        let container = makeTaskSubtaskModelContainer()
        let context = ModelContext(container)
        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))
        items.forEach { context.insert(PersistentItem(item: $0)) }
        try context.save()

        let localStats = try await LocalItemRepository(container: container).completedItemStats(
            spaceID: MockDataFactory.singleSpaceID,
            referenceDate: newer
        )
        #expect(localStats.firstCompletedAt == older)
        #expect(localStats.lastCompletedAt == newer)
    }

    @Test func projectToTaskMigrationConvertsProjectSubtasksAndLinkedTasksOnce() async throws {
        let container = makeTaskSubtaskModelContainer()
        let projectID = UUID()
        let linkedTaskID = UUID()
        let dueAt = Date(timeIntervalSince1970: 1_900_000_000)
        let remindAt = Date(timeIntervalSince1970: 1_899_996_400)
        let context = ModelContext(container)
        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))
        context.insert(PersistentProject(project: Project(
            id: projectID,
            spaceID: MockDataFactory.singleSpaceID,
            creatorID: MockDataFactory.currentUserID,
            name: "搬家准备",
            notes: "周末前完成",
            colorToken: nil,
            status: .active,
            targetDate: dueAt,
            remindAt: remindAt,
            taskCount: 1,
            sortOrder: 7,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            completedAt: nil
        )))
        context.insert(PersistentProjectSubtask(subtask: ProjectSubtask(
            projectID: projectID,
            creatorID: MockDataFactory.currentUserID,
            title: "打包厨房",
            isCompleted: true,
            sortOrder: 0
        )))
        context.insert(PersistentItem(item: Item(
            id: linkedTaskID,
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: projectID,
            creatorID: MockDataFactory.currentUserID,
            title: "预约搬家公司",
            notes: "确认价格",
            locationText: nil,
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: remindAt,
            status: .inProgress,
            lastActionByUserID: MockDataFactory.currentUserID,
            lastActionAt: .now,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_300),
            completedAt: nil,
            isDraft: false
        )))
        try context.save()

        let migration = ProjectToTaskMigrationService(container: container)
        #expect(try migration.migrateLegacyProjectsToTasks(spaceID: MockDataFactory.singleSpaceID) == 1)
        #expect(try migration.migrateLegacyProjectsToTasks(spaceID: MockDataFactory.singleSpaceID) == 0)

        let itemRepository = LocalItemRepository(container: container, syncCoordinator: NoOpSyncCoordinator())
        let items = try await itemRepository.fetchActiveItems(spaceID: MockDataFactory.singleSpaceID)
        let migrated = try #require(items.first { $0.id == projectID })
        #expect(items.contains { $0.id == linkedTaskID } == false)
        #expect(migrated.title == "搬家准备")
        #expect(migrated.subtasks.map(\.title) == ["打包厨房", "预约搬家公司"])
        let linkedSubtask = try #require(migrated.subtasks.first { $0.sourceTaskID == linkedTaskID })
        #expect(linkedSubtask.sourceNotes == "确认价格")
        #expect(linkedSubtask.sourceDueAt == dueAt)
        #expect(linkedSubtask.sourceHasExplicitTime == true)
        #expect(linkedSubtask.sourceRemindAt == remindAt)

        let projectRepository = LocalProjectRepository(
            container: container,
            reminderScheduler: MockReminderScheduler(),
            syncCoordinator: NoOpSyncCoordinator()
        )
        #expect(try await projectRepository.fetchProjects(spaceID: MockDataFactory.singleSpaceID).isEmpty)
    }

    @Test func homeSnoozeUsesTomorrowInsteadOfConfiguredMinutes() async throws {
        var user = MockDataFactory.makeCurrentUser()
        user.preferences.defaultSnoozeMinutes = 5

        let sessionStore = SessionStore()
        sessionStore.seedMock(currentUser: user, singleSpace: MockDataFactory.makeSingleSpace())

        let taskApplicationService = CapturingTaskApplicationService()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskApplicationService,
            itemRepository: MockItemRepository(),
        )

        let itemID = MockDataFactory.makeItems()[0].id
        await viewModel.snoozeItem(itemID)

        #expect(taskApplicationService.capturedSnoozeOption == .tomorrow)
    }

    @Test func taskReminderUsesExplicitReminderTimeBeforeDueDate() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 15, minute: 30)))
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: MockRoutineAlarmService(status: .unavailable),
            calendar: calendar
        )

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt))

        let notifications = await notificationService.scheduledNotifications()
        #expect(notifications.count == 1)
        #expect(notifications.first?.scheduledAt == remindAt)
    }

    @Test func taskReminderFallsBackToDueTimeWhenReminderTimeIsMissing() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: MockRoutineAlarmService(status: .unavailable),
            calendar: calendar
        )

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: nil))

        let notifications = await notificationService.scheduledNotifications()
        #expect(notifications.count == 1)
        #expect(notifications.first?.scheduledAt == dueAt)
    }

    @Test func dailySummariesUseTodayScopeAtNineAMAndSixPM() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let now = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 6, day: 14, hour: 8)
        ))
        let overdueAt = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 6, day: 13, hour: 16)
        ))
        let dueToday = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)
        ))
        let dueTomorrow = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 6, day: 15, hour: 16)
        ))
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            calendar: calendar,
            now: { now }
        )
        var completedToday = makeReminderTestItem(
            title: "已完成的今日任务",
            dueAt: dueToday,
            hasExplicitTime: true,
            remindAt: nil
        )
        completedToday.status = .completed
        completedToday.completedAt = now

        await scheduler.resync(
            spaceID: MockDataFactory.singleSpaceID,
            tasks: [
                makeReminderTestItem(title: "逾期任务", dueAt: overdueAt, hasExplicitTime: true, remindAt: nil),
                makeReminderTestItem(title: "今日任务", dueAt: dueToday, hasExplicitTime: true, remindAt: nil),
                makeReminderTestItem(title: "未来任务", dueAt: dueTomorrow, hasExplicitTime: true, remindAt: nil),
                makeReminderTestItem(title: "无日期任务", dueAt: nil, remindAt: nil),
                completedToday
            ],
            projects: [],
            includeTaskReminders: true,
            includeDailySummary: true
        )

        let summaries = await notificationService.scheduledNotifications().filter {
            $0.targetType.isDailySummary
        }
        let morning = try #require(summaries.first { $0.targetType == .dailyMorningSummary })
        let evening = try #require(summaries.first { $0.targetType == .dailyEveningSummary })

        #expect(summaries.count == 2)
        #expect(morning.title == "今天有 2 项任务需要完成")
        #expect(morning.body == "其中 1 项已逾期，打开 Together 查看")
        #expect(evening.title == "今天还有 2 项任务没有完成")
        #expect(evening.body == "其中 1 项已逾期，打开 Together 查看")
        #expect(morning.recurrence == .daily)
        #expect(evening.recurrence == .daily)
        #expect(calendar.component(.hour, from: morning.scheduledAt) == 9)
        #expect(calendar.component(.hour, from: evening.scheduledAt) == 18)
    }

    @Test func dailySummariesStillDeliverAnExplicitZeroState() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let now = try #require(calendar.date(
            from: DateComponents(year: 2030, month: 6, day: 14, hour: 8)
        ))
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            calendar: calendar,
            now: { now }
        )

        await scheduler.resync(
            spaceID: MockDataFactory.singleSpaceID,
            tasks: [],
            projects: [],
            includeTaskReminders: true,
            includeDailySummary: true
        )

        let summaries = await notificationService.scheduledNotifications()
        #expect(summaries.first { $0.targetType == .dailyMorningSummary }?.title == "今天没有待完成任务")
        #expect(summaries.first { $0.targetType == .dailyEveningSummary }?.title == "今天的任务已全部完成")
    }

    @Test func dailySummaryCanBeExcludedFromReminderResync() async throws {
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(notificationService: notificationService, calendar: gregorianCalendar())

        await scheduler.resync(
            spaceID: MockDataFactory.singleSpaceID,
            tasks: [
                makeReminderTestItem(title: "无到期任务", dueAt: nil, remindAt: nil)
            ],
            projects: [],
            includeTaskReminders: true,
            includeDailySummary: false
        )
        await scheduler.syncDailySummary(
            for: MockDataFactory.singleSpaceID,
            tasks: [makeReminderTestItem(title: "今日任务", dueAt: .now, remindAt: nil)]
        )

        #expect(notificationService.scheduledNotifications().isEmpty)
        #expect(notificationService.cancelledIdentifiers().contains { $0.hasPrefix("local.dailySummary.") })
        #expect(notificationService.cancelledIdentifiers().contains { $0.hasPrefix("local.dailyMorningSummary.") })
        #expect(notificationService.cancelledIdentifiers().contains { $0.hasPrefix("local.dailyEveningSummary.") })
    }

    @Test func disablingTaskRemindersCancelsNotificationAndAlarmDelivery() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 15, minute: 30)))
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .authorized)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )
        let item = makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt)
        try await alarmService.schedule(id: item.id, title: item.title, at: remindAt)

        await scheduler.resync(
            spaceID: item.spaceID,
            tasks: [item],
            projects: [],
            includeTaskReminders: false,
            includeDailySummary: false
        )
        await scheduler.syncTaskReminder(for: item)
        let spaceID = try #require(item.spaceID)
        await scheduler.syncDailySummary(for: spaceID, tasks: [item])

        #expect(notificationService.scheduledNotifications().isEmpty)
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .item, targetID: item.id)))
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .dailySummary, targetID: spaceID)))
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .dailyMorningSummary, targetID: spaceID)))
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .dailyEveningSummary, targetID: spaceID)))
        #expect(await alarmService.scheduled[item.id] == nil)
    }

    @Test func timedTaskReminderUsesAlarmServiceInsteadOfNotificationWhenAuthorized() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 15, minute: 30)))
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .authorized)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )
        let item = makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt)

        await scheduler.syncTaskReminder(for: item)

        let scheduledAlarm = await alarmService.scheduled[item.id]
        #expect(scheduledAlarm == remindAt)
        #expect(notificationService.scheduledNotifications().isEmpty)
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .item, targetID: item.id)))
    }

    @Test func deniedTimedTaskAlarmFallsBackToNotification() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 15, minute: 30)))
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .denied)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt))

        let notifications = notificationService.scheduledNotifications()
        #expect(notifications.count == 1)
        #expect(notifications.first?.scheduledAt == remindAt)
        #expect(await alarmService.scheduled.isEmpty)
    }

    @Test func coldLaunchReminderSyncDoesNotRequestAlarmAuthorization() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 15, minute: 30)))
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .notDetermined)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )

        await scheduler.syncTaskReminder(
            for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt)
        )

        #expect(await alarmService.authorizationRequestCount == 0)
        #expect(notificationService.scheduledNotifications().count == 1)
    }

    @Test func taskWithoutExplicitTimeDoesNotScheduleAlarm() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 9)))
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .authorized)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: false, remindAt: remindAt))

        #expect(await alarmService.scheduled.isEmpty)
        #expect(notificationService.scheduledNotifications().count == 1)
    }

    @Test func removingTaskReminderCancelsNotificationAndAlarm() async throws {
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .authorized)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: gregorianCalendar()
        )
        let itemID = UUID()

        try await alarmService.schedule(id: itemID, title: "旧闹钟", at: .now.addingTimeInterval(3600))
        await scheduler.removeTaskReminder(for: itemID)

        #expect(await alarmService.scheduled[itemID] == nil)
        #expect(notificationService.cancelledIdentifiers().contains(AppNotification.identifier(for: .item, targetID: itemID)))
    }

    @Test func periodicAlarmDeliveryUsesAlarmServiceInsteadOfNotification() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .authorized)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )
        let referenceDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 18, hour: 8))
        )
        let task = makePeriodicTask(
            title: "原生闹钟",
            cycle: .daily,
            reminderRules: [
                PeriodicReminderRule(
                    hour: 18,
                    minute: 30,
                    reminderLeadMinutes: 15,
                    reminderDelivery: .alarm
                )
            ]
        )

        await scheduler.syncPeriodicTaskReminder(for: task, referenceDate: referenceDate)

        let scheduledAlarm = await alarmService.scheduled[task.id]
        #expect(scheduledAlarm != nil)
        #expect(notificationService.scheduledNotifications().isEmpty)
    }

    @Test func deniedPeriodicAlarmFallsBackToNotification() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let alarmService = MockRoutineAlarmService(status: .denied)
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: alarmService,
            calendar: calendar
        )
        let referenceDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 18, hour: 8))
        )
        let task = makePeriodicTask(
            title: "降级通知",
            cycle: .daily,
            reminderRules: [
                PeriodicReminderRule(
                    hour: 18,
                    minute: 30,
                    reminderLeadMinutes: 0,
                    reminderDelivery: .alarm
                )
            ]
        )

        await scheduler.syncPeriodicTaskReminder(for: task, referenceDate: referenceDate)

        #expect(notificationService.scheduledNotifications().count == 1)
    }

    @Test func deferredRoutineReminderMovesToDeferredDayAndDeletionCancelsItsRealIdentifier() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(
            notificationService: notificationService,
            routineAlarmService: MockRoutineAlarmService(status: .authorized),
            calendar: calendar
        )
        let deferredUntil = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 19))
        )
        var task = makePeriodicTask(
            title: "推迟提醒",
            cycle: .weekly,
            reminderRules: [
                PeriodicReminderRule(
                    timing: .dayOfPeriod(3),
                    hour: 18,
                    minute: 30,
                    reminderLeadMinutes: 30,
                    reminderDelivery: .notification
                )
            ]
        )
        task.deferredUntil = deferredUntil

        await scheduler.syncPeriodicTaskReminder(for: task, referenceDate: deferredUntil)

        let notification = try #require(notificationService.scheduledNotifications().first)
        let scheduledComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notification.scheduledAt
        )
        #expect(scheduledComponents == DateComponents(year: 2030, month: 6, day: 19, hour: 18, minute: 0))

        await scheduler.removePeriodicTaskReminder(for: task.id)
        #expect(
            notificationService.cancelledIdentifiers().contains(
                AppNotification.identifier(for: .periodicTask, targetID: task.id)
            )
        )
    }

    @Test func localTaskRepositoryCreatesAndHydratesTaskSubtasksInSortOrder() async throws {
        let service = makeTaskSubtaskApplicationService()
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "带子任务的普通任务",
                subtasks: [
                    TaskSubtaskDraft(title: "第二步", isCompleted: false, sortOrder: 1),
                    TaskSubtaskDraft(title: "第一步", isCompleted: true, sortOrder: 0)
                ]
            )
        )

        #expect(created.subtasks.map(\.title) == ["第一步", "第二步"])
        #expect(created.subtasks.map(\.isCompleted) == [true, false])
    }

    @Test func ordinaryTaskWritesNormalizeMissingDateToToday() async throws {
        let service = makeTaskSubtaskApplicationService()
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "日期必填任务",
                dueAt: nil,
                hasExplicitTime: true,
                remindAt: .now.addingTimeInterval(3_600)
            )
        )

        let dueAt = try #require(created.dueAt)
        #expect(Calendar.current.isDateInToday(dueAt))
        #expect(created.hasExplicitTime == false)
        #expect(created.remindAt == nil)

        let rescheduled = try await service.rescheduleTask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            dueAt: nil,
            remindAt: .now.addingTimeInterval(3_600)
        )
        let rescheduledDueAt = try #require(rescheduled.dueAt)
        #expect(Calendar.current.isDateInToday(rescheduledDueAt))
        #expect(rescheduled.hasExplicitTime == false)
        #expect(rescheduled.remindAt == nil)
    }

    @Test func ordinaryTaskCreationPersistsFollowState() async throws {
        let repository = makeTaskSubtaskItemRepository()
        let service = DefaultTaskApplicationService(
            itemRepository: repository,
            syncCoordinator: NoOpSyncCoordinator(),
            reminderScheduler: MockReminderScheduler()
        )

        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(title: "创建时关注", shouldFollowOnCreation: true)
        )
        let persisted = try #require(await repository.fetchItem(itemID: created.id))

        #expect(created.isFollowed)
        #expect(created.followedAt != nil)
        #expect(persisted.isFollowed)
        #expect(persisted.followedAt != nil)
    }

    @Test func updatingTaskDraftReplacesSubtasksAndFiltersEmptyTitles() async throws {
        let service = makeTaskSubtaskApplicationService()
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "整理资料",
                subtasks: [
                    TaskSubtaskDraft(title: "收集材料"),
                    TaskSubtaskDraft(title: "输出结论")
                ]
            )
        )

        let updated = try await service.updateTask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "整理资料",
                subtasks: [
                    TaskSubtaskDraft(title: "  "),
                    TaskSubtaskDraft(title: "确认口径", isCompleted: true)
                ]
            )
        )

        #expect(updated.subtasks.map(\.title) == ["确认口径"])
        #expect(updated.subtasks.map(\.isCompleted) == [true])
    }

    @Test func restoredSingleSpaceTaskCanBeUpdatedWithHistoricalCreatorIdentity() async throws {
        let item = makeHomeFilterItem(
            title: "恢复后的旧任务",
            completedAt: nil,
            status: .inProgress,
            creatorID: UUID()
        )
        let repository = MockItemRepository(items: [item])
        let service = DefaultTaskApplicationService(
            itemRepository: repository,
            syncCoordinator: NoOpSyncCoordinator(),
            reminderScheduler: MockReminderScheduler()
        )

        let updated = try await service.updateTask(
            in: MockDataFactory.singleSpaceID,
            taskID: item.id,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(title: "恢复后可编辑")
        )

        #expect(updated.title == "恢复后可编辑")
    }

    @Test func togglingLastTaskSubtaskDoesNotCompleteParentTask() async throws {
        let service = makeTaskSubtaskApplicationService()
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "不自动完成父任务",
                subtasks: [
                    TaskSubtaskDraft(title: "唯一子任务")
                ]
            )
        )
        let subtaskID = try #require(created.subtasks.first?.id)

        let updated = try await service.toggleTaskSubtask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            subtaskID: subtaskID,
            actorID: MockDataFactory.currentUserID
        )

        #expect(updated.subtasks.first?.isCompleted == true)
        #expect(updated.status == .inProgress)
        #expect(updated.completedAt == nil)
    }

    @Test func deletingTaskHidesItsSubtasksFromHydration() async throws {
        let repository = makeTaskSubtaskItemRepository()
        let service = DefaultTaskApplicationService(
            itemRepository: repository,
            syncCoordinator: NoOpSyncCoordinator(),
            reminderScheduler: MockReminderScheduler()
        )
        let created = try await service.createTask(
            in: MockDataFactory.singleSpaceID,
            actorID: MockDataFactory.currentUserID,
            draft: TaskDraft(
                title: "删除父任务",
                subtasks: [TaskSubtaskDraft(title: "也应隐藏")]
            )
        )

        try await service.deleteTask(
            in: MockDataFactory.singleSpaceID,
            taskID: created.id,
            actorID: MockDataFactory.currentUserID
        )

        let fetched = try await repository.fetchItem(itemID: created.id)
        #expect(fetched?.subtasks.isEmpty == true)
    }

    @Test func timelineEntryCarriesTaskSubtaskProgressData() async throws {
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )

        let taskApplicationService = CapturingTaskApplicationService()
        var item = makeReminderTestItem(title: "带子任务的今日任务", dueAt: .now, remindAt: nil)
        item.subtasks = [
            TaskSubtask(
                itemID: item.id,
                creatorID: MockDataFactory.currentUserID,
                title: "已完成",
                isCompleted: true,
                sortOrder: 0
            ),
            TaskSubtask(
                itemID: item.id,
                creatorID: MockDataFactory.currentUserID,
                title: "待完成",
                isCompleted: false,
                sortOrder: 1
            )
        ]
        taskApplicationService.tasksToReturn = [item]
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskApplicationService,
            itemRepository: MockItemRepository(items: [item]),
        )

        await viewModel.reload()

        let entry = try #require(viewModel.activeTimelineEntries.first)
        #expect(entry.subtasks.count == 2)
        #expect(entry.subtasks.filter(\.isCompleted).count == 1)
        #expect(entry.subtaskCompletedCount == 1)
    }

    @Test func inlineDetailExpansionCollapsesBeforeSwitchingTasks() async throws {
        let first = makeHomeFilterItem(title: "第一条", completedAt: nil, status: .inProgress)
        let second = makeHomeFilterItem(title: "第二条", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [first, second])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        await viewModel.toggleInlineDetail(first.id)

        #expect(viewModel.expandedDetailItemID == first.id)
        #expect(viewModel.inlineDetailDraft?.title == "第一条")

        viewModel.updateDraftTitle("第一条已编辑")
        await viewModel.toggleInlineDetail(second.id)

        #expect(viewModel.expandedDetailItemID == nil)
        #expect(try await repository.fetchItem(itemID: first.id)?.title == "第一条已编辑")
        #expect(try await repository.fetchItem(itemID: second.id)?.title == "第二条")
    }

    @Test func inlineDetailSettingsPersistOnlyAfterCollapse() async throws {
        let calendar = Calendar.current
        let item = makeHomeFilterItem(title: "设置任务", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)
        let dueDate = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        let dueTime = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18, minute: 30)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18)))

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftDueDate(dueDate)
        viewModel.updateDraftDueTime(dueTime)
        viewModel.updateDraftReminder(remindAt)
        viewModel.updateDraftUrgent(true)

        let beforeCollapse = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(beforeCollapse.dueAt == item.dueAt)
        #expect(beforeCollapse.remindAt == item.remindAt)
        #expect(beforeCollapse.isUrgent == item.isUrgent)

        await viewModel.collapseInlineDetail()

        let saved = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(saved.dueAt == dueTime)
        #expect(saved.hasExplicitTime)
        #expect(saved.remindAt == remindAt)
        #expect(saved.isUrgent)
    }

    @Test func existingTaskScheduleDraftUsesCurrentTimeAsUncommittedSeed() throws {
        let calendar = gregorianCalendar()
        let fallbackDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))
        )
        let timeSeed = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 13, minute: 53))
        )

        var draft = ExistingTaskScheduleDraft(
            dueAt: nil,
            hasExplicitTime: false,
            fallbackDate: fallbackDate,
            calendar: calendar
        )

        #expect(draft.selectedDate == fallbackDate)
        #expect(draft.selectedTime == nil)

        let pickerSeed = draft.timePickerSeed(seed: timeSeed, calendar: calendar)
        #expect(calendar.component(.hour, from: pickerSeed) == 13)
        #expect(calendar.component(.minute, from: pickerSeed) == 55)
        #expect(ExistingTaskScheduleEditorPolicy.timeMinuteInterval == 5)
        #expect(draft.selectedTime == nil)

        let legacyDraft = ExistingTaskScheduleDraft(
            dueAt: timeSeed,
            hasExplicitTime: true,
            fallbackDate: fallbackDate,
            calendar: calendar
        )
        let roundedLegacySeed = legacyDraft.timePickerSeed(calendar: calendar)
        #expect(calendar.component(.minute, from: roundedLegacySeed) == 55)
        #expect(legacyDraft.selectedTime == timeSeed)

        draft.selectTime(pickerSeed)
        #expect(draft.selectedTime == pickerSeed)

        draft.setTimeEnabled(false, calendar: calendar)
        #expect(draft.selectedTime == nil)
    }

    @Test func dateTimePickerPresentationSeedsReminderOffsetFromCurrentDraft() throws {
        let calendar = gregorianCalendar()
        let fallbackDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))
        )
        let dueAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 14, minute: 30))
        )
        let remindAt = try #require(
            calendar.date(byAdding: .minute, value: -15, to: dueAt)
        )

        let presentation = ExistingTaskScheduleEditorPresentation(
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: remindAt,
            fallbackDate: fallbackDate
        )

        #expect(presentation.initialDraft.selectedDate == Calendar.current.startOfDay(for: dueAt))
        #expect(presentation.initialDraft.selectedTime == dueAt)
        let reminderOffset = try #require(presentation.initialDraft.reminderOffset)
        #expect(reminderOffset == TimeInterval(15 * 60))
    }

    @Test func dateTimePickerDraftRejectsReminderWithoutTimeAndClearsItWithTime() throws {
        let calendar = gregorianCalendar()
        let fallbackDate = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))
        )
        var draft = ExistingTaskScheduleDraft(
            dueAt: fallbackDate,
            hasExplicitTime: false,
            fallbackDate: fallbackDate,
            calendar: calendar
        )

        draft.selectReminderOffset(15 * 60)
        #expect(draft.reminderOffset == nil)

        draft.setTimeEnabled(true, seed: fallbackDate, calendar: calendar)
        draft.selectReminderOffset(15 * 60)
        let reminderOffset = try #require(draft.reminderOffset)
        #expect(reminderOffset == TimeInterval(15 * 60))

        draft.setTimeEnabled(false, calendar: calendar)
        #expect(draft.selectedTime == nil)
        #expect(draft.reminderOffset == nil)
    }

    @Test func existingTaskMonthGridAlwaysReservesSixWeeks() throws {
        let calendar = gregorianCalendar()
        let july = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))
        )
        let dates = ExistingTaskMonthGrid.dates(for: july, calendar: calendar)

        #expect(dates.count == 42)
        #expect(dates.first == calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))
        #expect(dates.last == calendar.date(from: DateComponents(year: 2026, month: 8, day: 8)))
    }

    @Test func unifiedExistingTaskSchedulePreservesReminderLeadAndClearsReminderWithTime() async throws {
        let calendar = Calendar.current
        let dueAt = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18, minute: 30))
        )
        let remindAt = dueAt.addingTimeInterval(-15 * 60)
        let item = makeReminderTestItem(
            title: "统一日期时间",
            dueAt: dueAt,
            hasExplicitTime: true,
            remindAt: remindAt
        )
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)
        let nextDate = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 21))
        )
        let nextTime = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 21, hour: 14, minute: 30))
        )

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftSchedule(date: nextDate, time: nextTime)

        let scheduledDraft = try #require(viewModel.inlineDetailDraft)
        let scheduledDueAt = try #require(scheduledDraft.dueAt)
        #expect(calendar.isDate(scheduledDueAt, inSameDayAs: nextDate))
        #expect(calendar.component(.hour, from: scheduledDueAt) == 14)
        #expect(calendar.component(.minute, from: scheduledDueAt) == 30)
        #expect(scheduledDraft.remindAt == scheduledDueAt.addingTimeInterval(-15 * 60))

        viewModel.updateDraftSchedule(date: nextDate, time: nil)
        let dateOnlyDraft = try #require(viewModel.inlineDetailDraft)
        #expect(dateOnlyDraft.dueAt == calendar.startOfDay(for: nextDate))
        #expect(dateOnlyDraft.hasExplicitTime == false)
        #expect(dateOnlyDraft.remindAt == nil)
    }

    @Test func dateTimePickerScheduleAppliesExplicitReminderOffsetAtomically() async throws {
        let calendar = Calendar.current
        let item = makeReminderTestItem(
            title: "日期时间提醒",
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil
        )
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)
        let date = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 21))
        )
        let time = try #require(
            calendar.date(from: DateComponents(year: 2030, month: 6, day: 21, hour: 14, minute: 30))
        )

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftSchedule(
            date: date,
            time: time,
            reminderOffset: 10 * 60
        )

        let configured = try #require(viewModel.inlineDetailDraft)
        let configuredDueAt = try #require(configured.dueAt)
        #expect(configured.hasExplicitTime)
        #expect(configured.remindAt == configuredDueAt.addingTimeInterval(-10 * 60))

        viewModel.updateDraftSchedule(
            date: date,
            time: nil,
            reminderOffset: 10 * 60
        )
        #expect(viewModel.inlineDetailDraft?.hasExplicitTime == false)
        #expect(viewModel.inlineDetailDraft?.remindAt == nil)
    }

    @Test func inlineDetailMovingDateGroupGetsFreshPresentationIdentityAndCanReopen() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let tomorrowStart = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let item = makeHomeFilterItem(
            title: "移动日期后可再展开",
            completedAt: nil,
            status: .inProgress,
            createdAt: todayStart
        )
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        let initialEntry = try #require(viewModel.activeTimelineSections.flatMap(\.entries).first)

        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftDueDate(tomorrowStart)
        #expect(await viewModel.collapseInlineDetail())

        let movedEntry = try #require(
            viewModel.activeTimelineSections.flatMap(\.entries).first { $0.itemID == item.id }
        )
        #expect(movedEntry.presentationID != initialEntry.presentationID)
        #expect(viewModel.expandedDetailItemID == nil)

        await viewModel.toggleInlineDetail(item.id)
        #expect(viewModel.expandedDetailItemID == item.id)
        #expect(viewModel.inlineDetailDraft?.dueAt == tomorrowStart)
    }

    @Test func inlineDetailCollapseKeepsDraftOpenWhenPersistenceFails() async throws {
        let item = makeHomeFilterItem(title: "保存失败时保留", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let service = CapturingTaskApplicationService()
        service.tasksToReturn = [item]
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: service,
            itemRepository: repository,
        )

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftTitle("尚未保存的标题")
        let didCollapse = await viewModel.collapseInlineDetail()

        #expect(didCollapse == false)
        #expect(viewModel.expandedDetailItemID == item.id)
        #expect(viewModel.inlineDetailDraft?.title == "尚未保存的标题")
        #expect(try await repository.fetchItem(itemID: item.id)?.title == item.title)
    }

    @Test func collapsedUrgentFlagCanDisableUrgentImmediately() async throws {
        var item = makeHomeFilterItem(title: "立即取消紧急", completedAt: nil, status: .inProgress)
        item.isUrgent = true
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        await viewModel.setItemUrgent(item.id, isUrgent: false)

        #expect(try await repository.fetchItem(itemID: item.id)?.isUrgent == false)
        #expect(viewModel.item(for: item.id)?.isUrgent == false)
    }

    @Test func inlineDetailSubtaskEditingPersistsAndReorders() async throws {
        var item = makeHomeFilterItem(title: "子任务任务", completedAt: nil, status: .inProgress)
        item.subtasks = [
            TaskSubtask(
                itemID: item.id,
                creatorID: MockDataFactory.currentUserID,
                title: "旧子任务",
                isCompleted: false,
                sortOrder: 0
            )
        ]
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        let firstSubtaskID = try #require(viewModel.inlineDetailDraft?.subtasks.first?.id)

        viewModel.updateDetailDraftSubtask(firstSubtaskID, title: "新子任务")
        viewModel.addDetailDraftSubtask(title: "补充子任务")
        let secondSubtaskID = try #require(viewModel.inlineDetailDraft?.subtasks.last?.id)
        viewModel.toggleDetailDraftSubtask(secondSubtaskID)
        viewModel.deleteDetailDraftSubtask(firstSubtaskID)

        let beforeCollapse = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(beforeCollapse.subtasks.map(\.title) == ["旧子任务"])

        await viewModel.collapseInlineDetail()

        let saved = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(saved.subtasks.map(\.title) == ["补充子任务"])
        #expect(saved.subtasks.map(\.isCompleted) == [true])
        #expect(saved.subtasks.map(\.sortOrder) == [0])
    }

    @Test func inlineDetailMenuDoesNotExposeSubtasks() {
        #expect(TaskEditorMenuContext.taskInline.menus == [.date, .time, .reminder, .urgent])
        #expect(TaskEditorMenuContext.taskInline.menus.contains(.subtasks) == false)
    }

    @Test func taskPropertyChipTitleVisibilityTracksConfiguredValue() {
        #expect(TaskEditorChipSemanticValue.date(.now).hasConfiguredValue)
        #expect(TaskEditorChipSemanticValue.time(nil).hasConfiguredValue == false)
        #expect(TaskEditorChipSemanticValue.reminder(nil).hasConfiguredValue == false)
        #expect(TaskEditorChipSemanticValue.urgent(false).hasConfiguredValue == false)
        #expect(TaskEditorChipSemanticValue.subtasks(0).hasConfiguredValue == false)
        #expect(TaskEditorChipSemanticValue.time(.now).hasConfiguredValue)
        #expect(TaskEditorChipSemanticValue.reminder(900).hasConfiguredValue)
        #expect(TaskEditorChipSemanticValue.urgent(true).hasConfiguredValue)
        #expect(TaskEditorChipSemanticValue.subtasks(2).hasConfiguredValue)
    }

    @Test func inlineDetailLayoutMetricsAlignSubtasksWithParentTitle() {
        #expect(HomeInlineTaskLayoutMetrics.actionSlotWidth == 40)
        #expect(HomeInlineTaskLayoutMetrics.titleLeadingInset == HomeInlineTaskLayoutMetrics.actionSlotWidth + HomeInlineTaskLayoutMetrics.titleGap)
        #expect(HomeInlineTaskLayoutMetrics.taskTitleLeadingInset == 38)
        #expect(HomeInlineTaskLayoutMetrics.attributeLeadingInset == HomeInlineTaskLayoutMetrics.taskTitleLeadingInset)
        #expect(HomeInlineTaskLayoutMetrics.expandedAttributeLeadingInset == 4)
        #expect(HomeInlineTaskLayoutMetrics.checkboxSize < HomeInlineTaskLayoutMetrics.actionSlotWidth)
        #expect(HomeInlineTaskLayoutMetrics.subtaskSpacing == 3)
        #expect(HomeInlineTaskLayoutMetrics.attributeMinHeight == HomeInlineTaskLayoutMetrics.rowMinHeight)
        #expect(HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0) > 0)
        #expect(
            HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 2)
                > HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0)
        )
    }

    @Test func timelineSharedIdentityKeepsNoteAndSubtaskProgressSeparate() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "信用卡商户",
            notes: "备注不会盖过子任务",
            timeText: "",
            reminderText: "",
            statusText: "进行中",
            isUrgent: false,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "客户经理对接信用卡名单",
                    isCompleted: true,
                    sortOrder: 0
                ),
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "召开线下沙龙会",
                    isCompleted: false,
                    sortOrder: 1
                )
            ],
            subtaskCompletedCount: 1
        )

        let content = TaskSharedIdentityContent.make(entry: entry)
        #expect(HomeTimelineSubtitleText.text(for: entry) == "1/2")
        #expect(content.note == "备注不会盖过子任务")
        #expect(content.visibleElements.contains(.progress))
        #expect(content.completedSubtaskCount == 1)
        #expect(content.totalSubtaskCount == 2)
    }

    @Test func timelineRowDisplayUsesSubtaskProgressAsTextSubtitle() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "对公联动名单",
            notes: nil,
            timeText: "",
            reminderText: "",
            statusText: "进行中",
            isUrgent: false,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "客户经理对接名单",
                    isCompleted: true,
                    sortOrder: 0
                ),
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "打标匹配",
                    isCompleted: false,
                    sortOrder: 1
                )
            ],
            subtaskCompletedCount: 1
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        let content = TaskSharedIdentityContent.make(entry: entry)
        #expect(display.primarySubtitle == "1/2")
        #expect(display.propertyText == nil)
        #expect(content.visibleElements.contains(.progress))
    }

    @Test func timelineRowDisplayUsesExplicitTimeAsTextSubtitle() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "信用卡商户",
            notes: nil,
            timeText: "18:30",
            reminderText: "",
            statusText: "进行中",
            isUrgent: false,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        let content = TaskSharedIdentityContent.make(entry: entry)
        #expect(display.primarySubtitle == "18:30")
        #expect(display.propertyText == nil)
        #expect(content.timeSummary == "18:30")
        #expect(content.visibleElements.contains(.time))
    }

    @Test func timelineRowDisplayKeepsNoteBeforeTextProperties() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "有备注任务",
            notes: "  跟进客户反馈  ",
            timeText: "18:30",
            reminderText: "提醒",
            statusText: "进行中",
            isUrgent: false,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [
                TaskSubtask(
                    itemID: itemID,
                    creatorID: MockDataFactory.currentUserID,
                    title: "确认反馈",
                    isCompleted: false,
                    sortOrder: 0
                )
            ],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        #expect(display.primarySubtitle == "跟进客户反馈")
        #expect(display.propertyText == "18:30 · 提醒 · 0/1")

        let content = TaskSharedIdentityContent.make(entry: entry)
        #expect(content.visibleElements.contains(.time))
        #expect(content.visibleElements.contains(.reminder))
    }

    @Test func timelineRowDisplayDoesNotInventStatusSubtitle() {
        let itemID = UUID()
        let entry = HomeTimelineEntry(
            id: itemID,
            presentationID: "active-test-\(itemID.uuidString)",
            title: "网点通实时数据",
            notes: nil,
            timeText: "",
            reminderText: "",
            statusText: "进行中",
            isUrgent: false,
            isMuted: false,
            isCompleted: false,
            timingUrgency: .normal,
            relationText: nil,
            primaryAvatar: nil,
            secondaryAvatar: nil,
            lastActionAt: nil,
            createdAt: .distantPast,
            subtasks: [],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        #expect(display.primarySubtitle.isEmpty)
        #expect(display.propertyText == nil)

    }

    @Test func inlineDetailCanCollapseTaskWithoutSubtasks() async {
        let item = makeHomeFilterItem(title: "无子任务", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        #expect(viewModel.expandedDetailItemID == item.id)

        await viewModel.collapseInlineDetail()
        #expect(viewModel.expandedDetailItemID == nil)
        #expect(viewModel.inlineDetailDraft == nil)
    }
}

private func makeTaskSubtaskApplicationService() -> DefaultTaskApplicationService {
    DefaultTaskApplicationService(
        itemRepository: makeTaskSubtaskItemRepository(),
        syncCoordinator: NoOpSyncCoordinator(),
        reminderScheduler: MockReminderScheduler()
    )
}

private func makeTaskSubtaskItemRepository() -> LocalItemRepository {
    LocalItemRepository(
        container: makeTaskSubtaskModelContainer(),
        syncCoordinator: NoOpSyncCoordinator()
    )
}

@MainActor
private func makeInlineDetailHomeViewModel(repository: MockItemRepository) -> HomeViewModel {
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    let taskService = DefaultTaskApplicationService(
        itemRepository: repository,
        syncCoordinator: NoOpSyncCoordinator(),
        reminderScheduler: MockReminderScheduler()
    )
    return HomeViewModel(
        sessionStore: sessionStore,
        taskApplicationService: taskService,
        itemRepository: repository,
    )
}

@MainActor
private func makeCompletedHistoryViewModel(
    items: [Item],
    initialFilter: CompletedHistoryFilter,
    throwsOnFetchCompletedItems: Bool = false
) -> CompletedHistoryViewModel {
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    let itemRepository = MockItemRepository(
        items: items,
        throwsOnFetchCompletedItems: throwsOnFetchCompletedItems
    )
    return CompletedHistoryViewModel(
        sessionStore: sessionStore,
        itemRepository: itemRepository,
        taskApplicationService: DefaultTaskApplicationService(
            itemRepository: itemRepository,
            syncCoordinator: NoOpSyncCoordinator(),
            reminderScheduler: MockReminderScheduler()
        ),
        taskListRepository: MockTaskListRepository(),
        projectRepository: MockProjectRepository(reminderScheduler: MockReminderScheduler()),
        initialFilter: initialFilter
    )
}

@MainActor
private func makeOCRAppContext(
    taskApplicationService: CapturingTaskApplicationService,
    userProfileRepository: UserProfileRepositoryProtocol? = nil,
    cloudImportConvergenceDelays: [Duration] = [.milliseconds(800), .seconds(4)]
) throws -> AppContext {
    let syncCoordinator = NoOpSyncCoordinator()
    let itemRepository = MockItemRepository()
    let notificationService = MockNotificationService()
    let reminderScheduler = MockReminderScheduler()
    let resolvedUserProfileRepository: UserProfileRepositoryProtocol
    if let userProfileRepository {
        resolvedUserProfileRepository = userProfileRepository
    } else {
        resolvedUserProfileRepository = MockUserProfileRepository()
    }
    let periodicTaskRepository = MockPeriodicTaskRepository()
    let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
        repository: periodicTaskRepository,
        reminderScheduler: reminderScheduler,
        syncCoordinator: syncCoordinator
    )
    let migrationPersistence = try PersistenceController(inMemory: true)
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    return AppContext(
        container: AppContainer(
            personalIdentityService: PersonalIdentityService(container: migrationPersistence.container),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            userProfileRepository: resolvedUserProfileRepository,
            itemRepository: itemRepository,
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: reminderScheduler),
            projectToTaskMigrationService: ProjectToTaskMigrationService(container: migrationPersistence.container),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            personalDataDeletionService: PersonalDataDeletionService(
                container: migrationPersistence.container,
                reminderScheduler: reminderScheduler
            ),
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            avatarUploader: MockAvatarStorageUploader(),
            userProfileRemote: MockUserProfileRemoteRepository()
        ),
        sessionStore: sessionStore,
        router: AppRouter(),
        cloudImportConvergenceDelays: cloudImportConvergenceDelays
    )
}

@MainActor
private final class StartupProfileRestoreRepository: UserProfileRepositoryProtocol {
    private let restoredUser: User
    private(set) var mergedUserCallCount = 0

    init(restoredUser: User) {
        self.restoredUser = restoredUser
    }

    func mergedUser(_ user: User?) async -> User? {
        mergedUserCallCount += 1
        return restoredUser
    }

    func saveProfile(
        for user: User,
        displayName: String,
        avatarUpdate: UserAvatarUpdate
    ) async throws -> User {
        user
    }

    func savePreferences(
        for user: User,
        preferences: NotificationSettings
    ) async throws -> User {
        user
    }

    func hydrateFromRemote(
        for user: User,
        displayName: String,
        avatarBytes: Data?,
        avatarAssetID: String?,
        avatarSystemName: String?,
        avatarVersion: Int
    ) async throws -> User {
        user
    }
}

private struct MissingAvatarMediaStore: UserAvatarMediaStoreProtocol {
    nonisolated func canonicalFileName(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())-avatar.jpg"
    }

    nonisolated func cacheFileName(for assetID: String) -> String {
        UserAvatarStorage.fileName(forAssetID: assetID)
    }

    nonisolated func versionedCacheFileName(for assetID: String, version: Int) -> String {
        UserAvatarStorage.versionedFileName(forAssetID: assetID, version: version)
    }

    nonisolated func avatarData(named fileName: String) throws -> Data {
        throw CocoaError(.fileNoSuchFile)
    }

    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws {}

    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws {}

    nonisolated func removeAvatar(named fileName: String) throws {}

    nonisolated func fileExists(named fileName: String) -> Bool {
        false
    }
}

private func makeTaskSubtaskModelContainer() -> ModelContainer {
    let schema = Schema([
        PersistentUserProfile.self,
        PersistentSpace.self,
        PersistentTaskList.self,
        PersistentProject.self,
        PersistentProjectSubtask.self,
        PersistentItem.self,
        PersistentTaskFollow.self,
        PersistentTaskSubtask.self,
        PersistentItemOccurrenceCompletion.self,
        PersistentPeriodicTask.self,
        PersistentTaskLifecycleEvent.self
    ])
    let configuration = ModelConfiguration(
        "TogetherTests-\(UUID().uuidString)",
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try! ModelContainer(for: schema, configurations: [configuration])
}

private func makeIdentityTestUser(id: UUID) -> User {
    User(
        id: id,
        displayName: "原有用户",
        avatarSystemName: "person.crop.circle.fill",
        createdAt: .now,
        updatedAt: .now,
        preferences: NotificationSettings(
            taskReminderEnabled: true,
            dailySummaryEnabled: false,
            calendarReminderEnabled: true
        )
    )
}

private struct PersonalDataDeletionSeed {
    let userID: UUID
    let spaceID: UUID
    let itemID: UUID
    let periodicTaskID: UUID
}

private func seedPersonalDataDeletionStore(container: ModelContainer) throws -> PersonalDataDeletionSeed {
    let context = ModelContext(container)
    let userID = UUID()
    let spaceID = UUID()
    let itemID = UUID()
    let projectID = UUID()
    let listID = UUID()
    let periodicTaskID = UUID()
    let now = Date.now
    let user = makeIdentityTestUser(id: userID)
    context.insert(PersistentUserProfile(user: user))
    context.insert(PersistentSpace(space: Space(
        id: spaceID,
        type: .single,
        displayName: "待删除空间",
        ownerUserID: userID,
        status: .active,
        createdAt: now,
        updatedAt: now
    )))
    context.insert(PersistentTaskList(
        id: listID,
        spaceID: spaceID,
        creatorID: userID,
        name: "待删除清单",
        kindRawValue: TaskListKind.custom.rawValue,
        colorToken: nil,
        sortOrder: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now
    ))
    context.insert(PersistentProject(
        id: projectID,
        spaceID: spaceID,
        creatorID: userID,
        name: "待删除项目",
        notes: nil,
        colorToken: nil,
        statusRawValue: ProjectStatus.active.rawValue,
        targetDate: nil,
        remindAt: nil,
        createdAt: now,
        updatedAt: now,
        completedAt: nil
    ))
    context.insert(PersistentProjectSubtask(
        id: UUID(),
        projectID: projectID,
        creatorID: userID,
        title: "项目子任务",
        isCompleted: false,
        sortOrder: 0
    ))
    context.insert(PersistentItem(item: Item(
        id: itemID,
        spaceID: spaceID,
        listID: listID,
        projectID: projectID,
        creatorID: userID,
        title: "待删除任务",
        notes: nil,
        dueAt: nil,
        status: .inProgress,
        lastActionByUserID: userID,
        lastActionAt: now,
        createdAt: now,
        updatedAt: now,
        completedAt: nil,
        isDraft: false
    )))
    context.insert(PersistentTaskSubtask(
        id: UUID(),
        itemID: itemID,
        creatorID: userID,
        title: "普通任务子任务",
        isCompleted: false,
        sortOrder: 0
    ))
    context.insert(PersistentItemOccurrenceCompletion(
        itemID: itemID,
        occurrenceDate: now,
        completedAt: now,
        createdAt: now,
        updatedAt: now
    ))
    context.insert(PersistentPeriodicTask(
        id: periodicTaskID,
        spaceID: spaceID,
        creatorID: userID,
        title: "待删除例行任务",
        notes: nil,
        cycleRawValue: PeriodicCycle.daily.rawValue,
        reminderRulesData: nil,
        completionsData: Data(),
        sortOrder: 0,
        isActive: true,
        createdAt: now,
        updatedAt: now
    ))
    try context.save()
    return PersonalDataDeletionSeed(
        userID: userID,
        spaceID: spaceID,
        itemID: itemID,
        periodicTaskID: periodicTaskID
    )
}

@MainActor
private final class DeletionTestFileCleaner: PersonalDataFileCleaning {
    private(set) var clearCallCount = 0
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func clearPersonalFiles() throws {
        clearCallCount += 1
        if shouldFail {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@MainActor
private final class DeletionTestReminderScheduler: ReminderSchedulerProtocol {
    private(set) var removedTaskIDs = Set<UUID>()
    private(set) var removedPeriodicTaskIDs = Set<UUID>()
    func syncTaskReminder(for item: Item) async {}
    func removeTaskReminder(for itemID: UUID) async { removedTaskIDs.insert(itemID) }
    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async {}
    func syncProjectReminder(for project: Project) async {}
    func removeProjectReminder(for projectID: UUID) async {}
    func syncDailySummary(for spaceID: UUID, tasks: [Item]) async {}
    func resync(
        spaceID: UUID?,
        tasks: [Item],
        projects: [Project],
        includeTaskReminders: Bool,
        includeDailySummary: Bool
    ) async {}
    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async {}
    func removePeriodicTaskReminder(for taskID: UUID) async { removedPeriodicTaskIDs.insert(taskID) }
    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus { .authorized }
    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus { .authorized }
    func periodicAlarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus { .authorized }
    func requestPeriodicAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus { .authorized }
}

private actor StubOCRTextRecognizer: OCRTextRecognizing {
    private var results: [Result<String, Error>]

    init(result: Result<String, Error>) {
        self.results = [result]
    }

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func recognizeText(in image: UIImage) async throws -> String {
        if results.count > 1 {
            return try results.removeFirst().get()
        }
        guard let result = results.first else {
            throw StubOCRTextRecognizerError.missingResult
        }
        return try result.get()
    }
}

private enum StubOCRTextRecognizerError: Error {
    case missingResult
}

private func makeTestImage() -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
    return renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    }
}

private func gregorianCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}

private func makeReminderTestItem(
    title: String = "提醒测试任务",
    dueAt: Date?,
    hasExplicitTime: Bool = false,
    remindAt: Date?
) -> Item {
    Item(
        id: UUID(),
        spaceID: MockDataFactory.singleSpaceID,
        listID: nil,
        projectID: nil,
        creatorID: MockDataFactory.currentUserID,
        title: title,
        notes: nil,
        locationText: nil,
        dueAt: dueAt,
        hasExplicitTime: hasExplicitTime,
        remindAt: remindAt,
        status: .inProgress,
        lastActionByUserID: MockDataFactory.currentUserID,
        lastActionAt: .now,
        createdAt: .now,
        updatedAt: .now,
        completedAt: nil,
        isDraft: false
    )
}

private func makeHomeFilterItem(
    title: String,
    completedAt: Date?,
    status: ItemStatus,
    createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    creatorID: UUID = MockDataFactory.currentUserID
) -> Item {
    Item(
        id: UUID(),
        spaceID: MockDataFactory.singleSpaceID,
        listID: nil,
        projectID: nil,
        creatorID: creatorID,
        title: title,
        notes: nil,
        locationText: nil,
        dueAt: nil,
        hasExplicitTime: false,
        remindAt: nil,
        status: status,
        lastActionByUserID: MockDataFactory.currentUserID,
        lastActionAt: completedAt ?? .now,
        createdAt: createdAt,
        updatedAt: completedAt ?? createdAt,
        completedAt: completedAt,
        isDraft: false
    )
}

@MainActor
private func makeRoutinesViewModel(
    periodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol? = nil
) -> RoutinesViewModel {
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    let service = periodicTaskApplicationService ?? CapturingPeriodicTaskApplicationService(tasks: [])
    return RoutinesViewModel(
        sessionStore: sessionStore,
        periodicTaskApplicationService: service,
    )
}

private func makePeriodicTask(
    title: String,
    cycle: PeriodicCycle,
    reminderRules: [PeriodicReminderRule] = [PeriodicReminderRule(timing: .dayOfPeriod(1), hour: 9, minute: 0)],
    completions: [PeriodicCompletion] = []
) -> PeriodicTask {
    PeriodicTask(
        id: UUID(),
        spaceID: MockDataFactory.singleSpaceID,
        creatorID: MockDataFactory.currentUserID,
        title: title,
        notes: nil,
        cycle: cycle,
        reminderRules: reminderRules,
        completions: completions,
        sortOrder: 0,
        isActive: true,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

@MainActor
private final class CapturingPeriodicTaskApplicationService: PeriodicTaskApplicationServiceProtocol, @unchecked Sendable {
    private(set) var tasks: [PeriodicTask]
    private(set) var updatedDrafts: [PeriodicTaskDraft] = []
    private let shouldFailUpdates: Bool
    private let shouldFailFetch: Bool

    init(
        tasks: [PeriodicTask],
        shouldFailUpdates: Bool = false,
        shouldFailFetch: Bool = false
    ) {
        self.tasks = tasks
        self.shouldFailUpdates = shouldFailUpdates
        self.shouldFailFetch = shouldFailFetch
    }

    func fetchTasks(in spaceID: UUID) async throws -> [PeriodicTask] {
        if shouldFailFetch {
            throw PeriodicTaskError.notSupported
        }
        return tasks
    }

    func createTask(id: UUID, in spaceID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask {
        let task = PeriodicTask(
            id: id,
            spaceID: spaceID,
            creatorID: actorID,
            title: draft.title,
            notes: draft.notes,
            cycle: draft.cycle,
            reminderRules: draft.reminderRules
        )
        tasks.append(task)
        return task
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask {
        if shouldFailUpdates {
            throw PeriodicTaskError.notSupported
        }
        updatedDrafts.append(draft)
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw PeriodicTaskError.notFound
        }
        tasks[index].title = draft.title
        tasks[index].notes = draft.notes
        tasks[index].cycle = draft.cycle
        tasks[index].reminderRules = draft.reminderRules
        tasks[index].updatedAt = .now
        return tasks[index]
    }

    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus { .authorized }

    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus { .authorized }

    func reorderTasks(in spaceID: UUID, taskIDs: [UUID]) async throws -> [PeriodicTask] {
        taskIDs.compactMap { taskID in tasks.first { $0.id == taskID } }
    }

    func toggleCompletion(in spaceID: UUID, taskID: UUID, referenceDate: Date) async throws -> PeriodicTask {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw PeriodicTaskError.notFound
        }
        let periodKey = PeriodicCycleCalculator.periodKey(for: tasks[index].cycle, date: referenceDate)
        if tasks[index].isCompleted(forPeriodKey: periodKey) {
            tasks[index].completions.removeAll { $0.periodKey == periodKey }
        } else {
            tasks[index].completions.append(PeriodicCompletion(periodKey: periodKey, completedAt: referenceDate))
        }
        return tasks[index]
    }

    func deferTaskUntilTomorrow(
        in spaceID: UUID,
        taskID: UUID,
        referenceDate: Date
    ) async throws -> PeriodicTask {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw PeriodicTaskError.notFound
        }
        let dayStart = Calendar.current.startOfDay(for: referenceDate)
        tasks[index].deferredUntil = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        return tasks[index]
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {
        tasks.removeAll { $0.id == taskID }
    }
}

@MainActor
private final class CapturingNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    private var scheduled: [AppNotification] = []
    private var cancelled: [String] = []

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        .authorized
    }

    func schedule(_ notifications: [AppNotification]) async throws {
        scheduled.append(contentsOf: notifications)
    }

    func cancel(_ identifiers: [String]) async {
        cancelled.append(contentsOf: identifiers)
    }

    func scheduledNotifications() -> [AppNotification] {
        scheduled
    }

    func cancelledIdentifiers() -> [String] {
        cancelled
    }
}

@MainActor
private final class CapturingTaskApplicationService: TaskApplicationServiceProtocol, @unchecked Sendable {
    var capturedSnoozeOption: TaskSnoozeOption?
    var snoozeItemToReturn: Item?
    var capturedRescheduleDueAt: Date?
    var capturedRescheduleRemindAt: Date?
    var rescheduleItemToReturn: Item?
    var rescheduleItemsToReturn: [UUID: Item] = [:]
    var rescheduleFailureIDs: Set<UUID> = []
    var tasksToReturn: [Item] = []
    var capturesCreates = false
    var createdDrafts: [TaskDraft] = []
    var createdTaskIDs: [UUID] = []

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] {
        tasksToReturn
    }

    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            completedTodayCount: 0,
            urgentCount: 0
        )
    }

    func createTask(id: UUID, in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        guard capturesCreates else {
            throw RepositoryError.notFound
        }
        createdDrafts.append(draft)
        createdTaskIDs.append(id)
        let now = Date.now
        return Item(
            id: id,
            spaceID: spaceID,
            listID: draft.listID,
            projectID: draft.projectID,
            creatorID: actorID,
            title: draft.title,
            notes: draft.notes,
            dueAt: draft.dueAt,
            hasExplicitTime: draft.hasExplicitTime,
            remindAt: draft.remindAt,
            status: draft.status,
            lastActionByUserID: actorID,
            lastActionAt: now,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            subtasks: draft.subtasks.map { subtask in
                TaskSubtask(
                    itemID: UUID(),
                    creatorID: actorID,
                    title: subtask.title,
                    isCompleted: subtask.isCompleted,
                    sortOrder: subtask.sortOrder
                )
            },
            sortOrder: now.timeIntervalSinceReferenceDate,
            isUrgent: draft.isUrgent,
            isDraft: draft.isDraft,
            repeatRule: nil,
            isFollowed: draft.shouldFollowOnCreation,
            followedAt: draft.shouldFollowOnCreation ? now : nil
        )
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        throw RepositoryError.notFound
    }

    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func rescheduleTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        dueAt: Date?,
        remindAt: Date?
    ) async throws -> Item {
        capturedRescheduleDueAt = dueAt
        capturedRescheduleRemindAt = remindAt
        if rescheduleFailureIDs.contains(taskID) {
            throw RepositoryError.invalidInput("reschedule failed")
        }
        if let item = rescheduleItemsToReturn[taskID] {
            return item
        }
        if let rescheduleItemToReturn {
            return rescheduleItemToReturn
        }
        throw RepositoryError.notFound
    }

    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item {
        capturedSnoozeOption = option
        if let snoozeItemToReturn {
            return snoozeItemToReturn
        }
        return MockDataFactory.makeItems()[0]
    }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func completeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func setTaskFollowed(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        isFollowed: Bool
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func addTaskSubtask(in spaceID: UUID, taskID: UUID, actorID: UUID, title: String) async throws -> Item {
        throw RepositoryError.notFound
    }

    func toggleTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        throw RepositoryError.notFound
    }

    func updateTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID, title: String) async throws -> Item {
        throw RepositoryError.notFound
    }

    func deleteTaskSubtask(in spaceID: UUID, taskID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Item {
        throw RepositoryError.notFound
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        throw RepositoryError.notFound
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
}
