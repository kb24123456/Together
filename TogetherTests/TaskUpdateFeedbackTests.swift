import Foundation
import Testing
@testable import Together

@MainActor
struct TaskUpdateFeedbackTests {
    private let chinese = Locale(identifier: "zh_Hans_CN")

    private func calendar(_ timeZone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(
        _ calendar: Calendar,
        year: Int = 2026,
        month: Int = 9,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func feedback(
        from previous: Date?,
        to target: Date?,
        timed: Bool = false,
        calendar: Calendar
    ) -> TaskUpdateFeedback? {
        var original = item()
        original.dueAt = previous
        original.hasExplicitTime = timed
        var saved = original
        saved.dueAt = target
        return TaskUpdateFeedback(before: original, after: saved, calendar: calendar)
    }

    @Test func sameDayTimeAndMissingDateChangesProduceFeedbackButNoOpDoesNot() {
        let calendar = calendar()
        let morning = date(calendar, day: 10, hour: 9)
        let evening = date(calendar, day: 10, hour: 19)
        #expect(feedback(from: morning, to: evening, timed: true, calendar: calendar)?.changedFields == ["时间"])
        #expect(feedback(from: morning, to: morning, calendar: calendar) == nil)
        #expect(feedback(from: nil, to: evening, calendar: calendar)?.changedFields == ["日期"])
        #expect(feedback(from: morning, to: nil, calendar: calendar)?.changedFields == ["日期"])
    }

    @Test func naturalDaysAcrossDSTDoNotUseTwentyFourHourIntervals() {
        let calendar = calendar("America/Los_Angeles")
        let springDay = date(calendar, month: 3, day: 8)
        let afterSpringDay = date(calendar, month: 3, day: 9)
        #expect(afterSpringDay.timeIntervalSince(springDay) == 23 * 3600)
        #expect(feedback(from: springDay, to: afterSpringDay, calendar: calendar) != nil)

        let fallMorning = date(calendar, month: 11, day: 1, minute: 15)
        let fallEvening = date(calendar, month: 11, day: 1, hour: 23, minute: 45)
        #expect(fallEvening.timeIntervalSince(fallMorning) > 24 * 3600)
        #expect(feedback(from: fallMorning, to: fallEvening, calendar: calendar) == nil)
    }

    @Test func dayComparisonUsesTheInjectedTimeZone() {
        let utc = calendar("UTC")
        let losAngeles = calendar("America/Los_Angeles")
        let earlier = date(utc, day: 10, hour: 1)
        let later = date(utc, day: 10, hour: 9)
        #expect(feedback(from: earlier, to: later, calendar: utc) == nil)
        #expect(feedback(from: earlier, to: later, calendar: losAngeles) != nil)
    }

    @Test func todayAndTomorrowUseCalendarDaysEvenNearMidnight() throws {
        let calendar = calendar("America/Los_Angeles")
        let now = date(calendar, month: 3, day: 8, hour: 23, minute: 59)
        let tomorrow = date(calendar, month: 3, day: 9)
        let nextDay = try #require(feedback(from: now, to: tomorrow, calendar: calendar))
        #expect(nextDay.destinationText(relativeTo: now, calendar: calendar, locale: chinese) == "明天")
        #expect(nextDay.destinationText(
            relativeTo: tomorrow, calendar: calendar, locale: chinese
        ) == "今天")
    }

    @Test func specificDatesDisambiguateAnotherYear() throws {
        let calendar = calendar()
        let now = date(calendar, day: 10)
        let thisYear = try #require(feedback(
            from: now, to: date(calendar, day: 15), calendar: calendar
        ))
        let nextYear = try #require(feedback(
            from: now, to: date(calendar, year: 2027, day: 15), calendar: calendar
        ))
        #expect(thisYear.destinationText(relativeTo: now, calendar: calendar, locale: chinese) == "9月15日")
        #expect(nextYear.destinationText(relativeTo: now, calendar: calendar, locale: chinese) == "2027年9月15日")
    }

    @Test func onlyExplicitTimesAppearAndRespectLocale() throws {
        let calendar = calendar()
        let now = date(calendar, day: 10)
        let target = date(calendar, day: 11, hour: 21, minute: 5)
        let allDay = try #require(feedback(from: now, to: target, calendar: calendar))
        let timed = try #require(feedback(from: now, to: target, timed: true, calendar: calendar))
        #expect(allDay.destinationText(relativeTo: now, calendar: calendar, locale: chinese) == "明天")
        #expect(timed.destinationText(relativeTo: now, calendar: calendar, locale: chinese) == "明天 · 21:05")
        let english = timed.destinationText(
            relativeTo: now, calendar: calendar, locale: Locale(identifier: "en_US")
        )
        #expect(english.hasPrefix("tomorrow · "))
        #expect(english.contains("9:05"))
        #expect(english.hasSuffix("PM"))
    }

    @Test func feedbackPreservesFullSavedTitleAndHasUniqueOccurrenceIdentity() throws {
        let calendar = calendar()
        let title = String(repeating: "不应在数据层截断的任务标题", count: 12)
        var original = item()
        original.title = title
        var saved = original
        saved.dueAt = date(calendar, day: 11)
        let first = try #require(TaskUpdateFeedback(before: original, after: saved, calendar: calendar))
        let second = try #require(TaskUpdateFeedback(before: original, after: saved, calendar: calendar))
        #expect(first.title == title)
        #expect(first.taskID == saved.id)
        #expect(first.id != second.id)
    }

    private func item() -> Item {
        Item(id: UUID(), creatorID: UUID(), title: "原始标题", dueAt: date(calendar(), day: 10),
             status: .inProgress, createdAt: .now, updatedAt: .now, isDraft: false)
    }

    @Test func eachEditableFieldProducesAConfirmation() throws {
        let original = item()
        let changes: [(String, (inout Item) -> Void)] = [
            ("日期", { $0.dueAt = self.date(self.calendar(), day: 11) }),
            ("时间", { $0.hasExplicitTime = true; $0.dueAt = self.date(self.calendar(), day: 10, hour: 9) }),
            ("提醒", { $0.remindAt = original.dueAt!.addingTimeInterval(-300) }),
            ("优先级", { $0.isUrgent.toggle() }),
            ("关注", { $0.isFollowed.toggle() }),
            ("标题", { $0.title = "新标题" }),
            ("备注", { $0.notes = "新备注" }),
            ("子任务", { $0.subtasks = [TaskSubtask(itemID: original.id, creatorID: original.creatorID, title: "步骤", sortOrder: 0)] })
        ]
        for (field, change) in changes {
            var saved = original
            change(&saved)
            let result = try #require(TaskUpdateFeedback(before: original, after: saved, calendar: calendar()))
            #expect(result.changedFields == [field])
        }
    }

    @Test func unchangedValuesAndMetadataDoNotConfirmAnEdit() throws {
        var original = item()
        original.subtasks = [TaskSubtask(itemID: original.id, creatorID: original.creatorID, title: "步骤", sortOrder: 0)]
        var saved = original
        saved.updatedAt = .distantFuture
        saved.subtasks[0].updatedAt = .distantFuture
        saved.notes = ""
        #expect(TaskUpdateFeedback(before: original, after: saved) == nil)
        saved.subtasks[0].isCompleted = true
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message() == "已更新子任务")
        saved.subtasks = []
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message() == "已更新子任务")
    }

    @Test func oneSaveSummarizesMultipleFieldsAndUsesSavedTitle() throws {
        let original = item()
        var saved = original
        saved.title = "新标题"
        saved.notes = "新备注"
        saved.isUrgent = true
        let result = try #require(TaskUpdateFeedback(before: original, after: saved))
        #expect(result.title == "新标题")
        #expect(result.message() == "已更新优先级、标题、备注")
        saved.isFollowed = true
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message() == "已更新 4 项内容")
    }

    @Test func snoozeIncludesDestinationWithoutInventingAReminderEdit() throws {
        var original = item()
        original.hasExplicitTime = true
        original.dueAt = date(calendar(), day: 10, hour: 9)
        original.remindAt = original.dueAt!.addingTimeInterval(-300)
        var saved = original
        saved.dueAt = date(calendar(), day: 11, hour: 9)
        saved.remindAt = saved.dueAt!.addingTimeInterval(-300)
        let result = try #require(TaskUpdateFeedback(before: original, after: saved, isSnooze: true, calendar: calendar()))
        #expect(result.changedFields == ["日期"])
        #expect(result.message(relativeTo: original.dueAt!, calendar: calendar(), locale: chinese) == "已推迟到明天 · 9:00")
        saved.isFollowed = true
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message().contains("关注") == true)
        original.isFollowed = true
        saved = original
        saved.isFollowed = false
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message() == "已取消关注")
    }

    @Test func periodicEditsAndDeferralUseTheSameFeedback() throws {
        let original = PeriodicTask(creatorID: UUID(), title: "运动", cycle: .weekly)
        var saved = original
        saved.title = "散步"
        saved.notes = "十分钟"
        #expect(TaskUpdateFeedback(before: original, after: saved)?.message() == "已更新标题、备注")
        saved = original
        saved.reminderRules = [.init(timing: .dayOfPeriod(2), hour: 9, minute: 0, reminderLeadMinutes: 5)]
        #expect(TaskUpdateFeedback(before: original, after: saved)?.changedFields == ["日期", "时间", "提醒"])
        saved = original
        saved.deferredUntil = date(calendar(), day: 11)
        let result = try #require(TaskUpdateFeedback(before: original, after: saved, isSnooze: true))
        #expect(result.message(relativeTo: date(calendar(), day: 10), calendar: calendar(), locale: chinese) == "已推迟到明天")
        #expect(TaskUpdateFeedback(before: saved, after: saved, isSnooze: true) == nil)
    }

    @Test func addingOnlyPeriodicTimeDoesNotReportADateOrReminderChange() {
        let original = PeriodicTask(creatorID: UUID(), title: "运动", cycle: .daily)
        var saved = original
        saved.reminderRules = [.init(hour: 9, minute: 0)]
        #expect(TaskUpdateFeedback(before: original, after: saved)?.changedFields == ["时间"])
        #expect(TaskUpdateFeedback(before: saved, after: original)?.changedFields == ["时间"])
    }

}

#if os(iOS)
@MainActor
struct HomeTaskUpdateFeedbackTests {
    private func item() -> Item {
        var item = MockDataFactory.makeItems()[0]
        item.spaceID = MockDataFactory.makeSingleSpace().id
        item.title = "原始标题"
        item.dueAt = Calendar.current.startOfDay(for: .now)
        item.hasExplicitTime = false
        item.status = .inProgress
        item.completedAt = nil
        item.isDraft = false
        item.isArchived = false
        item.repeatRule = nil
        return item
    }

    private func viewModel(
        item: Item,
        repositoryItems: [Item]? = nil,
        syncCoordinator: SyncCoordinatorProtocol? = nil
    ) -> HomeViewModel {
        let repository = MockItemRepository(items: repositoryItems ?? [item])
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace()
        )
        let model = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: DefaultTaskApplicationService(
                itemRepository: repository,
                syncCoordinator: syncCoordinator ?? NoOpSyncCoordinator(),
                reminderScheduler: MockReminderScheduler()
            ),
            itemRepository: repository
        )
        model.items = [item]
        model.presentItemDetail(item.id)
        return model
    }

    private func reschedule(_ model: HomeViewModel, item: Item) {
        model.updateDraftDueDate(Calendar.current.date(byAdding: .day, value: 1, to: item.dueAt!)!)
    }

    @Test func explicitSuccessfulSaveEmitsSavedValuesAndIsConsumedOnce() async throws {
        let item = item()
        let model = viewModel(item: item)
        reschedule(model, item: item)
        model.updateDraftTitle("  保存后的标题  ")
        #expect(model.updateFeedback == nil)

        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        let feedback = try #require(model.consumeUpdateFeedback())
        #expect(feedback.taskID == item.id)
        #expect(feedback.title == "保存后的标题")
        #expect(feedback.dueAt == model.item(for: item.id)?.dueAt)
        #expect(feedback.hasExplicitTime == false)
        #expect(model.consumeUpdateFeedback() == nil)

        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.updateFeedback == nil)
    }

    @Test func saveBeforeCompletionDoesNotEmitRescheduleFeedback() async {
        let item = item()
        let model = viewModel(item: item)
        reschedule(model, item: item)
        #expect(await model.saveInlineDetailDraft())
        #expect(model.updateFeedback == nil)
    }

    @Test func invalidationDiscardsAnAlreadyProducedFeedback() async {
        let item = item()
        let model = viewModel(item: item)
        reschedule(model, item: item)
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.updateFeedback != nil)
        model.invalidateUpdateFeedback()
        #expect(model.consumeUpdateFeedback() == nil)
    }

    @Test func invalidationDropsAnInFlightSaveButAllowsTheNextExplicitSave() async throws {
        let item = item()
        let checkpoint = RescheduleSaveCheckpoint()
        let model = viewModel(item: item, syncCoordinator: checkpoint)
        reschedule(model, item: item)
        let firstSave = Task { await model.saveInlineDetailDraft(allowsUpdateFeedback: true) }

        // Persistence has completed, but the service has not returned to the presenter.
        await checkpoint.waitUntilPaused()
        model.invalidateUpdateFeedback()
        checkpoint.resume()
        #expect(await firstSave.value)
        #expect(model.updateFeedback == nil)

        let savedItem = try #require(model.item(for: item.id))
        reschedule(model, item: savedItem)
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        let nextFeedback = try #require(model.consumeUpdateFeedback())
        #expect(nextFeedback.taskID == item.id)
        #expect(nextFeedback.dueAt == model.item(for: item.id)?.dueAt)
        #expect(Calendar.current.isDate(try #require(nextFeedback.dueAt), inSameDayAs: savedItem.dueAt!) == false)
    }

    @Test func failedSaveAndCancelledDraftDoNotEmitFeedback() async {
        let item = item()
        let model = viewModel(item: item, repositoryItems: [])
        reschedule(model, item: item)
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true) == false)
        #expect(model.updateFeedback == nil)
        model.dismissItemDetail()
        #expect(model.updateFeedback == nil)
    }

    @Test func sameDayTimeChangeEmitsFeedback() async {
        let item = item()
        let model = viewModel(item: item)
        model.updateDraftDueTime(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: item.dueAt!)!)
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.consumeUpdateFeedback()?.changedFields == ["时间"])
    }

    @Test func recurringTasksDoNotEmitOrdinaryTaskUpdateFeedback() async {
        var item = item()
        item.repeatRule = ItemRepeatRule(frequency: .daily)
        let model = viewModel(item: item)
        reschedule(model, item: item)
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.updateFeedback == nil)
    }

    @Test func completedSnapshotDuringEditingDoesNotEmitFeedback() async {
        let item = item()
        let model = viewModel(item: item)
        reschedule(model, item: item)
        var completed = item
        completed.status = .completed
        completed.completedAt = .now
        model.items = [completed]
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.updateFeedback == nil)
    }

    @Test func titleEditEmitsFeedbackButSyncReloadDoesNotReplayIt() async {
        let item = item()
        let model = viewModel(item: item)
        model.updateDraftTitle("只是更新标题")
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.consumeUpdateFeedback()?.message() == "已更新标题")
        await model.reload(reason: .sync)
        #expect(model.updateFeedback == nil)
    }

    @Test func immediatePriorityFollowAndSnoozeEmitOnlyAfterSuccess() async {
        let item = item()
        let model = viewModel(item: item)
        model.dismissItemDetail()
        await model.setItemUrgent(item.id, isUrgent: !item.isUrgent)
        #expect(model.consumeUpdateFeedback()?.changedFields == ["优先级"])
        await model.toggleTaskFollow(item.id)
        #expect(model.consumeUpdateFeedback()?.changedFields == ["关注"])
        await model.snoozeItemToTomorrow(item.id)
        #expect(model.consumeUpdateFeedback()?.isSnooze == true)

        let failing = viewModel(item: item, repositoryItems: [])
        await failing.setItemUrgent(item.id, isUrgent: !item.isUrgent)
        await failing.toggleTaskFollow(item.id)
        await failing.snoozeItemToTomorrow(item.id)
        #expect(failing.updateFeedback == nil)
    }

    @Test func taskCreationDoesNotEmitRescheduleFeedback() async {
        let item = item()
        let model = viewModel(item: item)
        model.dismissItemDetail()
        model.beginTaskCreation()
        model.updateTaskCreationDraft {
            $0.title = "新建明天的任务"
            $0.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: item.dueAt!)!
        }
        let result = await model.commitTaskCreation()
        if case .saved = result {
            #expect(model.updateFeedback == nil)
        } else {
            Issue.record("Expected the new task to save successfully")
        }
    }
}

@MainActor
struct PeriodicTaskUpdateFeedbackTests {
    private func fixture(persisted: Bool = true) async throws -> (RoutinesViewModel, PeriodicTask) {
        let user = MockDataFactory.makeCurrentUser()
        let space = MockDataFactory.makeSingleSpace()
        let session = SessionStore()
        session.seedMock(currentUser: user, singleSpace: space)
        let task = PeriodicTask(spaceID: space.id, creatorID: user.id, title: "运动", cycle: .daily)
        let repository = MockPeriodicTaskRepository()
        if persisted { _ = try await repository.saveTask(task) }
        let model = RoutinesViewModel(
            sessionStore: session,
            periodicTaskApplicationService: DefaultPeriodicTaskApplicationService(
                repository: repository, reminderScheduler: MockReminderScheduler(), syncCoordinator: NoOpSyncCoordinator()
            )
        )
        model.tasks = [task]
        return (model, task)
    }

    @Test func periodicExplicitSaveAndQuickDeferralConfirmOnce() async throws {
        let (model, task) = try await fixture()
        #expect(model.presentDetailForMorph(task.id))
        model.updateDraftNotes("十分钟")
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.consumeUpdateFeedback()?.message() == "已更新备注")
        #expect(await model.saveInlineDetailDraft(allowsUpdateFeedback: true))
        #expect(model.consumeUpdateFeedback() == nil)
        model.finishMorphDetail()
        await model.deferTaskUntilTomorrow(taskID: task.id)
        #expect(model.consumeUpdateFeedback()?.isSnooze == true)
        await model.deferTaskUntilTomorrow(taskID: task.id)
        #expect(model.consumeUpdateFeedback() == nil)
    }

    @Test func periodicFailureCancelAndCompletionPreSaveDoNotConfirmEdits() async throws {
        let (model, task) = try await fixture()
        #expect(model.presentDetailForMorph(task.id))
        model.updateDraftTitle("散步")
        model.finishMorphDetail()
        #expect(model.consumeUpdateFeedback() == nil)
        #expect(model.presentDetailForMorph(task.id))
        model.updateDraftTitle("散步")
        #expect(await model.saveInlineDetailDraft())
        #expect(model.consumeUpdateFeedback() == nil)

        let (failing, missing) = try await fixture(persisted: false)
        #expect(failing.presentDetailForMorph(missing.id))
        failing.updateDraftTitle("散步")
        #expect(await failing.saveInlineDetailDraft(allowsUpdateFeedback: true) == false)
        #expect(failing.consumeUpdateFeedback() == nil)
    }
}

/// Pauses exactly one service return after persistence without timing assumptions.
@MainActor
private final class RescheduleSaveCheckpoint: SyncCoordinatorProtocol {
    private var hasPaused = false
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var waiterContinuation: CheckedContinuation<Void, Never>?

    func recordLocalChange(_ change: SyncChange) async {
        guard hasPaused == false else { return }
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
            hasPaused = true
            waiterContinuation?.resume()
            waiterContinuation = nil
        }
    }

    func waitUntilPaused() async {
        guard hasPaused == false else { return }
        await withCheckedContinuation { waiterContinuation = $0 }
    }

    func resume() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}
#endif
