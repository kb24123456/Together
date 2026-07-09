import Foundation
import SwiftData
import Testing
import UIKit
@testable import Together

@MainActor
@Suite(.serialized)
struct TogetherTests {
    private func clearRoutineCycleVisibilityPreferences() {
        UserDefaults.standard.removeObject(forKey: "together.routines.visibleCycles.v2")
        UserDefaults.standard.removeObject(forKey: "together.routines.visibleOptionalCycles")
    }

    @Test func routineInlineDetailFallbackHeightMatchesVisibleRows() {
        #expect(RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: true) == 86)
        #expect(RoutineInlineLayoutMetrics.estimatedDetailHeight(showsAddNote: false) == 52)
    }

    @Test func routineModeTransitionCascadeIsOrderedAndReversible() {
        let entryDelays = (0..<7).map {
            RoutineModeTransitionTiming.delay(
                for: $0,
                taskCount: 7,
                isPresented: true,
                reduceMotion: false
            )
        }
        let exitDelays = (0..<5).map {
            RoutineModeTransitionTiming.delay(
                for: $0,
                taskCount: 7,
                isPresented: false,
                reduceMotion: false
            )
        }

        #expect(entryDelays == [0, 0.02, 0.04, 0.06, 0.08, 0.08, 0.08])
        #expect(exitDelays == [0.08, 0.06, 0.04, 0.02, 0])
        #expect(
            RoutineModeTransitionTiming.delay(
                for: 3,
                taskCount: 7,
                isPresented: true,
                reduceMotion: true
            ) == 0
        )
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

        #expect(cameraSession.viewModel.flowState == .camera)
        #expect(photosSession.viewModel.flowState == .photos)
        #expect(cameraSession.viewModel !== photosSession.viewModel)
    }

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
        let appContext = makeOCRAppContext(taskApplicationService: taskApplicationService)
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
            taskTemplateRepository: MockTaskTemplateRepository()
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

    @Test func routineFocusTapPolicyOnlyCollapsesOutsideFocusedCard() {
        let frame = CGRect(x: 20, y: 100, width: 320, height: 240)

        #expect(RoutineFocusTapPolicy.shouldCollapse(tapLocation: CGPoint(x: 100, y: 180), focusedRowFrame: frame) == false)
        #expect(RoutineFocusTapPolicy.shouldCollapse(tapLocation: CGPoint(x: 100, y: 370), focusedRowFrame: frame))
        #expect(RoutineFocusTapPolicy.shouldCollapse(tapLocation: CGPoint(x: 100, y: 180), focusedRowFrame: nil) == false)
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

    @Test func completedRoutineCanStillOpenInlineDetail() async {
        let periodKey = PeriodicCycleCalculator.periodKey(for: .daily, date: .now)
        let task = makePeriodicTask(
            title: "已经打卡",
            cycle: .daily,
            completions: [PeriodicCompletion(periodKey: periodKey, completedAt: .now)]
        )
        let viewModel = makeRoutinesViewModel()
        viewModel.tasks = [task]

        await viewModel.toggleInlineDetail(task.id)

        #expect(viewModel.expandedTaskID == task.id)
        #expect(viewModel.detailDraft?.title == task.title)
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
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        await viewModel.reload()

        #expect(viewModel.activeTimelineEntries.map(\.title) == ["更早截止", "更晚截止"])
    }

    @Test func activeTimelineSectionsGroupByDueDateThenCreatedDate() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        let tomorrowStart = try #require(calendar.date(byAdding: .day, value: 1, to: todayStart))
        let tomorrowTime = try #require(calendar.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrowStart))

        let unscheduled = makeHomeFilterItem(
            title: "无截止按创建日",
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
            repository: MockItemRepository(items: [unscheduled, timed, scheduled])
        )

        await viewModel.reload()

        let sections = viewModel.activeTimelineSections
        #expect(sections.count == 2)
        #expect(sections.map(\.isUnscheduled) == [false, true])
        #expect(sections.map(\.dayStart) == [tomorrowStart, yesterdayStart])
        #expect(sections[0].entries.map(\.title) == ["有截止按截止日", "有时间仍在截止日组"])
        #expect(sections[1].entries.map(\.title) == ["无截止按创建日"])
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
            taskTemplateRepository: MockTaskTemplateRepository()
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
        #expect(HomeInlineTaskLayoutMetrics.attributeLeadingInset == 0)
        #expect(HomeInlineTaskLayoutMetrics.checkboxSize < HomeInlineTaskLayoutMetrics.actionSlotWidth)
        #expect(HomeInlineTaskLayoutMetrics.attributeMinHeight < HomeInlineTaskLayoutMetrics.rowMinHeight)
        #expect(HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0) > 0)
        #expect(
            HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 2)
                > HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 0)
        )
    }

    @Test func timelineSubtitlePrioritizesSubtaskProgress() {
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

        #expect(HomeTimelineSubtitleText.text(for: entry) == "1/2 子任务")
    }

    @Test func timelineRowDisplayUsesSubtaskProgressInSubtitle() {
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
        #expect(display.primarySubtitle == "1/2 子任务")
        #expect(display.propertyText == nil)
    }

    @Test func timelineRowDisplayKeepsExplicitTimeInSubtitle() {
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
            subtasks: [],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        #expect(display.primarySubtitle == "18:30")
        #expect(display.propertyText == nil)
    }

    @Test func timelineRowDisplayPlacesPropertiesBelowNotes() {
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
            subtasks: [],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        #expect(display.primarySubtitle == "跟进客户反馈")
        #expect(display.propertyText == "18:30 · 提醒")
    }

    @Test func timelineRowDisplayFallsBackToStatusWithoutProperties() {
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
            subtasks: [],
            subtaskCompletedCount: 0
        )

        let display = HomeTimelineRowDisplayText.text(for: entry)
        #expect(display.primarySubtitle == "进行中")
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
        taskTemplateRepository: MockTaskTemplateRepository()
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
private func makeOCRAppContext(taskApplicationService: CapturingTaskApplicationService) -> AppContext {
    let syncCoordinator = NoOpSyncCoordinator()
    let itemRepository = MockItemRepository()
    let taskTemplateRepository = MockTaskTemplateRepository()
    let notificationService = MockNotificationService()
    let reminderScheduler = MockReminderScheduler()
    let userProfileRepository = MockUserProfileRepository()
    let periodicTaskRepository = MockPeriodicTaskRepository()
    let periodicTaskApplicationService = DefaultPeriodicTaskApplicationService(
        repository: periodicTaskRepository,
        reminderScheduler: reminderScheduler,
        syncCoordinator: syncCoordinator
    )
    let migrationPersistence = PersistenceController(inMemory: true)
    let sessionStore = SessionStore()
    sessionStore.seedMock(
        currentUser: MockDataFactory.makeCurrentUser(),
        singleSpace: MockDataFactory.makeSingleSpace()
    )
    return AppContext(
        container: AppContainer(
            authService: MockAuthService(),
            spaceService: MockSpaceService(),
            taskApplicationService: taskApplicationService,
            syncCoordinator: syncCoordinator,
            userProfileRepository: userProfileRepository,
            itemRepository: itemRepository,
            taskTemplateRepository: taskTemplateRepository,
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: reminderScheduler),
            projectToTaskMigrationService: ProjectToTaskMigrationService(container: migrationPersistence.container),
            decisionRepository: MockDecisionRepository(),
            notificationService: notificationService,
            reminderScheduler: reminderScheduler,
            periodicTaskRepository: periodicTaskRepository,
            periodicTaskApplicationService: periodicTaskApplicationService,
            biometricAuthService: BiometricAuthService(),
            avatarUploader: MockAvatarStorageUploader(),
            userProfileRemote: MockUserProfileRemoteRepository()
        ),
        sessionStore: sessionStore,
        router: AppRouter()
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
        taskTemplateRepository: MockTaskTemplateRepository()
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

    init(tasks: [PeriodicTask], shouldFailUpdates: Bool = false) {
        self.tasks = tasks
        self.shouldFailUpdates = shouldFailUpdates
    }

    func fetchTasks(in spaceID: UUID) async throws -> [PeriodicTask] {
        tasks
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: PeriodicTaskDraft) async throws -> PeriodicTask {
        let task = PeriodicTask(
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
    var tasksToReturn: [Item] = []
    var capturesCreates = false
    var createdDrafts: [TaskDraft] = []

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

    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        guard capturesCreates else {
            throw RepositoryError.notFound
        }
        createdDrafts.append(draft)
        let now = Date.now
        return Item(
            id: UUID(),
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
            repeatRule: nil
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
