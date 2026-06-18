import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TogetherTests {
    @Test func itemStateMachineCompletesInProgressTask() async throws {
        let next = ItemStateMachine.nextStatus(
            from: .inProgress,
            isCompletion: true
        )

        #expect(next == .completed)
    }

    @Test func sessionStoreBootstrapsSingleSpaceOnly() async throws {
        let sessionStore = SessionStore()

        await sessionStore.bootstrap(
            authService: MockAuthService(),
            spaceService: MockSpaceService()
        )

        #expect(sessionStore.authState == .signedIn)
        #expect(sessionStore.currentSpace?.type == .single)
        #expect(sessionStore.availableModeStates == [.single])
        #expect(sessionStore.activeMode == .single)
    }

    @Test func ocrParserCreatesTaskDraftsFromPlainLines() {
        let draft = OCRImportDraftParser.parse(rawText: """
        - 买牛奶
        2. 整理周报
        □ 给房东发消息
        """)

        #expect(draft.status == .needsReview)
        #expect(draft.projectDrafts.isEmpty)
        #expect(draft.taskDrafts.map(\.title) == ["买牛奶", "整理周报", "给房东发消息"])
    }

    @Test func ocrParserCreatesProjectDraftFromHeadingAndBullets() {
        let draft = OCRImportDraftParser.parse(rawText: """
        搬家准备:
        - 预约搬家公司
        - 打包厨房
        """)

        #expect(draft.taskDrafts.isEmpty)
        #expect(draft.projectDrafts.count == 1)
        #expect(draft.projectDrafts.first?.name == "搬家准备")
        #expect(draft.projectDrafts.first?.taskDrafts.map(\.title) == ["预约搬家公司", "打包厨房"])
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
        let scheduler = LocalReminderScheduler(notificationService: notificationService, calendar: calendar)

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: remindAt))

        let notifications = await notificationService.scheduledNotifications()
        #expect(notifications.count == 1)
        #expect(notifications.first?.scheduledAt == remindAt)
    }

    @Test func taskReminderFallsBackToDueTimeWhenReminderTimeIsMissing() async throws {
        let calendar = gregorianCalendar()
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(notificationService: notificationService, calendar: calendar)

        await scheduler.syncTaskReminder(for: makeReminderTestItem(dueAt: dueAt, hasExplicitTime: true, remindAt: nil))

        let notifications = await notificationService.scheduledNotifications()
        #expect(notifications.count == 1)
        #expect(notifications.first?.scheduledAt == dueAt)
    }

    @Test func dailySummarySchedulesIncompleteTasksWithoutDueDateAtSixPM() async throws {
        let calendar = gregorianCalendar()
        let notificationService = CapturingNotificationService()
        let scheduler = LocalReminderScheduler(notificationService: notificationService, calendar: calendar)
        let dueAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 14, hour: 16)))
        var completedNoDueItem = makeReminderTestItem(title: "已完成无到期任务", dueAt: nil, remindAt: nil)
        completedNoDueItem.status = .completed
        completedNoDueItem.completedAt = .now

        await scheduler.resync(
            tasks: [
                makeReminderTestItem(title: "无到期任务 A", dueAt: nil, remindAt: nil),
                makeReminderTestItem(title: "无到期任务 B", dueAt: nil, remindAt: nil),
                makeReminderTestItem(title: "有到期任务", dueAt: dueAt, hasExplicitTime: true, remindAt: nil),
                completedNoDueItem
            ],
            projects: []
        )

        let notifications = await notificationService.scheduledNotifications()
        let summary = try #require(notifications.first { $0.title == "今天还有 2 件事没完成" })
        let components = calendar.dateComponents([.hour, .minute], from: summary.scheduledAt)
        #expect(components.hour == 18)
        #expect(components.minute == 0)
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

    @Test func taskTemplatePreservesSubtasksWhenCreatingDraft() throws {
        let template = TaskTemplate(
            spaceID: MockDataFactory.singleSpaceID,
            draft: TaskDraft(
                title: "模板任务",
                subtasks: [
                    TaskSubtaskDraft(title: "第一步", isCompleted: true),
                    TaskSubtaskDraft(title: "第二步", isCompleted: false)
                ]
            ),
            calendar: gregorianCalendar()
        )

        let draft = template.makeTaskDraft(for: Date(timeIntervalSince1970: 0), calendar: gregorianCalendar())

        #expect(draft.subtasks.map(\.title) == ["第一步", "第二步"])
        #expect(draft.subtasks.map(\.isCompleted) == [true, false])
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
            itemRepository: MockItemRepository(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.reload()

        let entry = try #require(viewModel.activeTimelineEntries.first)
        #expect(entry.subtasks.count == 2)
        #expect(entry.subtasks.filter(\.isCompleted).count == 1)
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

private func makeTaskSubtaskModelContainer() -> ModelContainer {
    let schema = Schema([
        PersistentUserProfile.self,
        PersistentSpace.self,
        PersistentTaskList.self,
        PersistentProject.self,
        PersistentProjectSubtask.self,
        PersistentItem.self,
        PersistentTaskSubtask.self,
        PersistentItemOccurrenceCompletion.self,
        PersistentTaskTemplate.self,
        PersistentPeriodicTask.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try! ModelContainer(for: schema, configurations: [configuration])
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

private actor CapturingNotificationService: NotificationServiceProtocol {
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
    var tasksToReturn: [Item] = []

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
            pinnedCount: 0
        )
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        throw RepositoryError.notFound
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
        throw RepositoryError.notFound
    }

    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item {
        capturedSnoozeOption = option
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
