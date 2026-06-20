import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
@Suite(.serialized)
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

    @Test func ocrParserCreatesTaskWithSubtasksFromHeadingAndBullets() {
        let draft = OCRImportDraftParser.parse(rawText: """
        搬家准备:
        - 预约搬家公司
        - 打包厨房
        """)

        #expect(draft.projectDrafts.isEmpty)
        #expect(draft.taskDrafts.count == 1)
        #expect(draft.taskDrafts.first?.title == "搬家准备")
        #expect(draft.taskDrafts.first?.subtasks.map(\.title) == ["预约搬家公司", "打包厨房"])
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
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let items = [
            makeHomeFilterItem(title: "今天完成", completedAt: today, status: .completed),
            makeHomeFilterItem(title: "昨天完成", completedAt: yesterday, status: .completed)
        ]
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: items),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.reload()

        #expect(viewModel.completedVisibilityButtonTitle == "本周已完成")
        #expect(viewModel.completedTimelineEntries.map(\.title) == ["今天完成"])
        #expect(viewModel.weeklyCompletedEntryCount == 1)
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
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.reload()

        #expect(viewModel.activeTimelineEntries.map(\.title) == ["未完成仍显示"])
        #expect(viewModel.weeklyCompletedEntryCount == expectedWeeklyCount)
    }

    @Test func weeklyCompletedSheetExcludesTodayAndSortsDescending() async throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let todayStart = calendar.startOfDay(for: .now)
        let today = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: todayStart))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -1, to: yesterday))
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let items = [
            makeHomeFilterItem(title: "今天完成", completedAt: today, status: .completed),
            makeHomeFilterItem(title: "昨天完成", completedAt: yesterday, status: .completed),
            makeHomeFilterItem(title: "前天完成", completedAt: twoDaysAgo, status: .completed)
        ]
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: CapturingTaskApplicationService(),
            itemRepository: MockItemRepository(items: items),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.loadWeeklyCompletedSheet()

        #expect(viewModel.weeklyCompletedSheetItems.map(\.title) == ["昨天完成", "前天完成"])
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
            itemRepository: MockItemRepository(items: [item]),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.reload()

        let entry = try #require(viewModel.activeTimelineEntries.first)
        #expect(entry.subtasks.count == 2)
        #expect(entry.subtasks.filter(\.isCompleted).count == 1)
        #expect(entry.subtaskCompletedCount == 1)
    }

    @Test func inlineDetailExpansionCreatesDraftAndSavesWhenSwitchingTasks() async throws {
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

        #expect(viewModel.expandedDetailItemID == second.id)
        #expect(try await repository.fetchItem(itemID: first.id)?.title == "第一条已编辑")
    }

    @Test func inlineDetailSettingsPersistThroughExistingUpdatePath() async throws {
        let calendar = Calendar.current
        let item = makeHomeFilterItem(title: "设置任务", completedAt: nil, status: .inProgress)
        let repository = MockItemRepository(items: [item])
        let viewModel = makeInlineDetailHomeViewModel(repository: repository)
        let dueDate = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20)))
        let dueTime = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18, minute: 30)))
        let remindAt = try #require(calendar.date(from: DateComponents(year: 2030, month: 6, day: 20, hour: 18)))
        let repeatRule = ItemRepeatRule(frequency: .weekly, weekday: 5)

        await viewModel.reload()
        await viewModel.toggleInlineDetail(item.id)
        viewModel.updateDraftDueDate(dueDate)
        viewModel.updateDraftDueTime(dueTime)
        viewModel.updateDraftReminder(remindAt)
        viewModel.updateDraftRepeatRule(repeatRule)
        await viewModel.saveDetailDraft()

        let saved = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(saved.dueAt == dueTime)
        #expect(saved.hasExplicitTime)
        #expect(saved.remindAt == remindAt)
        #expect(saved.repeatRule == repeatRule)
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
        await viewModel.saveDetailDraft()

        let saved = try #require(try await repository.fetchItem(itemID: item.id))
        #expect(saved.subtasks.map(\.title) == ["补充子任务"])
        #expect(saved.subtasks.map(\.isCompleted) == [true])
        #expect(saved.subtasks.map(\.sortOrder) == [0])
    }

    @Test func inlineDetailMenuDoesNotExposeSubtasks() {
        #expect(TaskEditorMenuContext.taskInline.menus == [.date, .time, .reminder, .repeatRule])
        #expect(TaskEditorMenuContext.taskInline.menus.contains(.subtasks) == false)
    }

    @Test func inlineDetailLayoutMetricsAlignSubtasksWithParentTitle() {
        #expect(HomeInlineTaskLayoutMetrics.actionSlotWidth == 40)
        #expect(HomeInlineTaskLayoutMetrics.titleLeadingInset == HomeInlineTaskLayoutMetrics.actionSlotWidth + HomeInlineTaskLayoutMetrics.titleGap)
        #expect(HomeInlineTaskLayoutMetrics.checkboxSize < HomeInlineTaskLayoutMetrics.actionSlotWidth)
        #expect(HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0) > 0)
        #expect(
            HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 2)
                > HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0)
        )
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
        taskTemplateRepository: MockTaskTemplateRepository()
    )
}

@MainActor
private func makeCompletedHistoryViewModel(
    items: [Item],
    initialFilter: CompletedHistoryFilter
) -> CompletedHistoryViewModel {
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    let itemRepository = MockItemRepository(items: items)
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
    let configuration = ModelConfiguration(
        "TogetherTests-\(UUID().uuidString)",
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
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

private func makeHomeFilterItem(title: String, completedAt: Date?, status: ItemStatus) -> Item {
    Item(
        id: UUID(),
        spaceID: MockDataFactory.singleSpaceID,
        listID: nil,
        projectID: nil,
        creatorID: MockDataFactory.currentUserID,
        title: title,
        notes: nil,
        locationText: nil,
        dueAt: nil,
        hasExplicitTime: false,
        remindAt: nil,
        status: status,
        lastActionByUserID: MockDataFactory.currentUserID,
        lastActionAt: completedAt ?? .now,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: completedAt ?? Date(timeIntervalSince1970: 1_800_000_000),
        completedAt: completedAt,
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
