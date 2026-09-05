import Foundation
import Testing
@testable import Together

@Suite("Execution review metrics")
struct ExecutionReviewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    @Test func weekAndMonthUseCurrentAndPreviousMatchingProgress() {
        let referenceDate = date(2026, 9, 4, 15, 30)

        let currentWeek = ExecutionReviewRange.week.interval(
            through: referenceDate,
            calendar: calendar
        )
        let previousWeek = ExecutionReviewRange.week.previousComparableInterval(
            through: referenceDate,
            calendar: calendar
        )
        #expect(currentWeek.start == date(2026, 8, 31))
        #expect(currentWeek.end == referenceDate)
        #expect(previousWeek.start == date(2026, 8, 24))
        #expect(previousWeek.end == date(2026, 8, 28, 15, 30))

        let currentMonth = ExecutionReviewRange.month.interval(
            through: referenceDate,
            calendar: calendar
        )
        let previousMonth = ExecutionReviewRange.month.previousComparableInterval(
            through: referenceDate,
            calendar: calendar
        )
        #expect(currentMonth.start == date(2026, 9, 1))
        #expect(currentMonth.end == referenceDate)
        #expect(previousMonth.start == date(2026, 8, 1))
        #expect(previousMonth.end == date(2026, 8, 4, 15, 30))
    }

    @Test func previousMonthClampsToShorterCalendarMonth() {
        let referenceDate = date(2027, 3, 31, 18)
        let previous = ExecutionReviewRange.month.previousComparableInterval(
            through: referenceDate,
            calendar: calendar
        )

        #expect(previous.start == date(2027, 2, 1))
        #expect(previous.end == date(2027, 3, 1))
        #expect(ExecutionReviewRange.month.includesCompletion(
            date(2027, 2, 28, 23, 59), in: previous, calendar: calendar
        ))
        #expect(ExecutionReviewRange.month.includesCompletion(
            date(2027, 3, 1), in: previous, calendar: calendar
        ) == false)
    }

    @Test func completionAtReferenceTimeIsIncludedButLaterCompletionIsNot() {
        let now = date(2026, 9, 4, 15, 30)
        let interval = ExecutionReviewRange.week.interval(through: now, calendar: calendar)
        #expect(ExecutionReviewRange.week.includesCompletion(now, in: interval, calendar: calendar))
        #expect(ExecutionReviewRange.week.includesCompletion(
            now.addingTimeInterval(1), in: interval, calendar: calendar
        ) == false)
    }

    @Test func comparisonPreservesUnequalDenominators() {
        let trend = ExecutionReviewTrend(
            metric: .postponedProportion,
            currentCount: 3,
            currentSampleCount: 5,
            previousCount: 3,
            previousSampleCount: 9
        )
        #expect(TaskLifecycleFormatting.executionComparison(trend, range: .month)
            == "曾向后调整：本月 3/5，上月同期 3/9")
    }

    @Test func snapshotUsesOnlyCompleteHistoryForPlanAndPostponementRates() {
        let dueAt = date(2026, 9, 3, 18)
        let completeOnTime = review(
            id: uuid(1),
            title: "完整记录",
            dueAt: dueAt,
            completedAt: date(2026, 9, 3, 17),
            coverage: .complete,
            postponeCount: 1
        )
        let legacyCompletion = review(
            id: uuid(2),
            title: "旧数据",
            dueAt: dueAt,
            completedAt: date(2026, 9, 3, 16),
            coverage: .sinceFeatureUpdate,
            postponeCount: 1
        )

        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: [completeOnTime, legacyCompletion],
            previousReviews: [],
            calendar: calendar
        )

        #expect(snapshot.completionCount == 2)
        #expect(snapshot.firstPlanSampleCount == 1)
        #expect(snapshot.firstPlanOnTimeCount == 1)
        #expect(snapshot.postponementSampleCount == 1)
        #expect(snapshot.postponedCompletionCount == 1)
        #expect(snapshot.trends.isEmpty)
        #expect(TaskLifecycleFormatting.executionSummary(snapshot) == "本周完成 2 项")
        #expect(TaskLifecycleFormatting.firstScheduleSummary(snapshot) == "1 项可判断首次安排，其中 1 项按首次安排完成")
        #expect(snapshot.completedItems.map(\.id) == [uuid(1), uuid(2)])
    }

    @Test func trendsCompareRetainedRatesWhenBothPeriodsHaveFiveSamples() throws {
        let dueAt = date(2026, 9, 3, 18)
        let current = (0..<5).map { index in
            review(
                id: uuid(10 + index),
                title: "当前 \(index)",
                dueAt: dueAt,
                completedAt: index < 3 ? date(2026, 9, 3, 17) : date(2026, 9, 3, 19),
                coverage: .complete,
                postponeCount: index < 2 ? 1 : 0
            )
        }
        let previous = (0..<5).map { index in
            review(
                id: uuid(20 + index),
                title: "上一周期 \(index)",
                dueAt: dueAt,
                completedAt: index < 2 ? date(2026, 9, 3, 17) : date(2026, 9, 3, 19),
                coverage: .complete,
                postponeCount: index < 3 ? 1 : 0
            )
        }

        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: current,
            previousReviews: previous,
            calendar: calendar
        )
        let firstPlanTrend = try #require(
            snapshot.trends.first(where: { $0.metric == .firstPlanOnTimeRate })
        )
        let postponementTrend = try #require(
            snapshot.trends.first(where: { $0.metric == .postponedProportion })
        )

        #expect(firstPlanTrend.currentCount == 3)
        #expect(firstPlanTrend.currentSampleCount == 5)
        #expect(firstPlanTrend.previousCount == 2)
        #expect(firstPlanTrend.previousSampleCount == 5)
        #expect(postponementTrend.currentCount == 2)
        #expect(postponementTrend.previousCount == 3)
        #expect(TaskLifecycleFormatting.executionComparison(firstPlanTrend, range: .week)
            == "按首次安排完成：本周 3/5，上周同期 2/5")
    }

    @Test func trendIsHiddenWhenPreviousPeriodHasFewerThanFiveSamples() {
        let dueAt = date(2026, 9, 3, 18)
        let current = (0..<5).map { index in
            review(
                id: uuid(30 + index),
                title: "当前 \(index)",
                dueAt: dueAt,
                completedAt: date(2026, 9, 3, 17),
                coverage: .complete
            )
        }
        let previous = (0..<4).map { index in
            review(
                id: uuid(40 + index),
                title: "上一周期 \(index)",
                dueAt: dueAt,
                completedAt: date(2026, 9, 3, 17),
                coverage: .complete
            )
        }

        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: current,
            previousReviews: previous,
            calendar: calendar
        )

        #expect(snapshot.trends.isEmpty)
    }

    @Test func noteworthyTasksRepresentDifferentReasonsAndStopAtThree() {
        let dueAt = date(2026, 9, 1, 18)
        let reopenedTwice = review(
            id: uuid(50),
            title: "重新打开两次",
            dueAt: dueAt,
            completedAt: date(2026, 9, 4, 18),
            coverage: .complete,
            postponeCount: 3,
            reopenCount: 2
        )
        let reopenedOnce = review(
            id: uuid(51),
            title: "重新打开一次",
            dueAt: dueAt,
            completedAt: date(2026, 9, 4, 18),
            coverage: .complete,
            reopenCount: 1
        )
        let postponedThreeTimes = review(
            id: uuid(52),
            title: "推迟三次",
            dueAt: dueAt,
            completedAt: date(2026, 9, 4, 18),
            coverage: .complete,
            postponeCount: 3
        )
        let missedByFiveDays = review(
            id: uuid(53),
            title: "晚五天",
            dueAt: dueAt,
            completedAt: date(2026, 9, 6, 18),
            coverage: .complete
        )

        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 6, 20), calendar: calendar),
            currentReviews: [missedByFiveDays, postponedThreeTimes, reopenedOnce, reopenedTwice],
            previousReviews: [],
            calendar: calendar
        )

        #expect(snapshot.noteworthyItems.map(\.id) == [uuid(50), uuid(52), uuid(53)])
        guard case let .reopened(count, _) = snapshot.noteworthyItems[0].reason else {
            Issue.record("最高优先级任务应按重新打开归因")
            return
        }
        #expect(count == 2)
    }

    @Test func noteworthyTasksFillRemainingSlotsWithoutDuplicates() {
        let tasks = (0..<5).map { index in
            review(
                id: uuid(70 + index),
                title: "重新打开 \(index + 1) 次",
                dueAt: date(2026, 9, 3, 18),
                completedAt: date(2026, 9, 3, 17),
                coverage: .complete,
                reopenCount: index + 1
            )
        }
        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: tasks,
            previousReviews: [],
            calendar: calendar
        )
        #expect(snapshot.noteworthyItems.map(\.id) == [uuid(74), uuid(73), uuid(72)])
    }

    @Test func completedDrillDownIncludesOrdinaryResultsAndSortsByCompletion() {
        let tasks = (0..<4).map { index in
            review(
                id: uuid(80 + index),
                title: "完成任务 \(index)",
                dueAt: date(2026, 9, 4, 18),
                completedAt: date(2026, 9, 3, index < 2 ? 10 : 12),
                coverage: index == 0 ? .sinceFeatureUpdate : .complete
            )
        }
        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: tasks.reversed(),
            previousReviews: [],
            calendar: calendar
        )
        #expect(snapshot.completedItems.map(\.id) == [uuid(82), uuid(83), uuid(80), uuid(81)])
        #expect(snapshot.completedItems.count == snapshot.completionCount)
        #expect(snapshot.noteworthyItems.isEmpty)
    }

    @Test func unknownFirstScheduleIsNotPresentedAsZeroSuccess() {
        let task = review(
            id: uuid(90),
            title: "旧任务",
            dueAt: date(2026, 9, 3, 18),
            completedAt: date(2026, 9, 3, 17),
            coverage: .sinceFeatureUpdate
        )
        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: [task],
            previousReviews: [],
            calendar: calendar
        )
        #expect(TaskLifecycleFormatting.firstScheduleSummary(snapshot) == "暂无可判断首次安排的记录")
        #expect(TaskLifecycleFormatting.executionSummary(snapshot) == "本周完成 1 项")
    }

    @Test func singlePostponementDoesNotOverrideMissedFirstPlanReason() throws {
        let task = review(
            id: uuid(60),
            title: "一次推迟后仍超期",
            dueAt: date(2026, 9, 1, 18),
            completedAt: date(2026, 9, 3, 18),
            coverage: .complete,
            postponeCount: 1
        )

        let snapshot = ExecutionReviewMetrics.snapshot(
            range: .week,
            interval: ExecutionReviewRange.week.interval(through: date(2026, 9, 4), calendar: calendar),
            currentReviews: [task],
            previousReviews: [],
            calendar: calendar
        )
        let item = try #require(snapshot.noteworthyItems.first)

        guard case .missedFirstPlan = item.reason else {
            Issue.record("一次推迟应按未兑现首次计划归因")
            return
        }
    }

    private func review(
        id: UUID,
        title: String,
        dueAt: Date,
        completedAt: Date,
        coverage: TaskLifecycleHistoryCoverage,
        postponeCount: Int = 0,
        reopenCount: Int = 0
    ) -> TaskLifecycleReview {
        var events = [event(
            taskID: id,
            kind: .firstScheduled,
            occurredAt: dueAt.addingTimeInterval(-86_400),
            newDueAt: dueAt,
            newHasExplicitTime: true
        )]
        var currentDueAt = dueAt

        for index in 0..<postponeCount {
            let nextDueAt = currentDueAt.addingTimeInterval(86_400)
            events.append(event(
                taskID: id,
                kind: .postponed,
                occurredAt: dueAt.addingTimeInterval(Double(index) * 60),
                oldDueAt: currentDueAt,
                newDueAt: nextDueAt,
                oldHasExplicitTime: true,
                newHasExplicitTime: true
            ))
            currentDueAt = nextDueAt
        }

        for index in 0..<reopenCount {
            events.append(event(
                taskID: id,
                kind: .reopened,
                occurredAt: completedAt.addingTimeInterval(Double(index) - 60)
            ))
        }

        return TaskLifecycleReview(
            taskID: id,
            title: title,
            createdAt: dueAt.addingTimeInterval(-172_800),
            completedAt: completedAt,
            currentDueAt: currentDueAt,
            currentHasExplicitTime: true,
            historyCoverage: coverage,
            events: events
        )
    }

    private func event(
        taskID: UUID,
        kind: TaskLifecycleEventKind,
        occurredAt: Date,
        oldDueAt: Date? = nil,
        newDueAt: Date? = nil,
        oldHasExplicitTime: Bool? = nil,
        newHasExplicitTime: Bool? = nil
    ) -> TaskLifecycleEvent {
        TaskLifecycleEvent(
            id: UUID(),
            taskID: taskID,
            kind: kind,
            occurredAt: occurredAt,
            oldDueAt: oldDueAt,
            newDueAt: newDueAt,
            oldHasExplicitTime: oldHasExplicitTime,
            newHasExplicitTime: newHasExplicitTime,
            incompleteSubtaskCount: nil
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
