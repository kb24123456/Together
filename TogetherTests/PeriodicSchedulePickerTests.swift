import Foundation
import Testing
@testable import Together

@MainActor
struct PeriodicSchedulePickerTests {
    @Test func weekdayLabelsRespectTheRecurrenceCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let mondayFirst = PeriodicSchedulePickerValues.days(cycle: .weekly, selected: nil, calendar: calendar)
        #expect(mondayFirst.first?.label == "周一")
        #expect(mondayFirst.last?.label == "周日")
        #expect(mondayFirst[2].timing == .dayOfPeriod(3))
        calendar.firstWeekday = 1
        #expect(PeriodicSchedulePickerValues.days(cycle: .weekly, selected: nil, calendar: calendar).first?.label == "周日")
    }

    @Test func monthEndHasOneSlotAndOpeningDoesNotRewriteLegacyTiming() {
        let legacy = PeriodicReminderRule(timing: .dayOfPeriod(31))
        let options = PeriodicSchedulePickerValues.days(cycle: .monthly, selected: legacy.timing)
        #expect(options.count == 31)
        #expect(options[14].timing == .dayOfPeriod(15))
        #expect(options[29].title == "30号")
        #expect(options.last?.timing == .daysBeforeEnd(1))
        #expect(PeriodicSchedulePickerValues.displayedTiming(legacy.timing, cycle: .monthly) == .daysBeforeEnd(1))
        #expect(legacy.timing == .dayOfPeriod(31))
    }

    @Test func specialAndHistoricalRulesRemainRepresentable() {
        let timings: [PeriodicReminderRule.Timing] = [
            .businessDayOfPeriod(12), .daysBeforeEnd(6), .lastBusinessDay,
            .weekdayOfMonth(ordinal: .last, weekday: 6)
        ]
        for timing in timings {
            let options = PeriodicSchedulePickerValues.days(cycle: .monthly, selected: timing)
            #expect(options.filter { $0.timing == timing }.count == 1)
            #expect(options.last?.title.isEmpty == false)
        }
        #expect(PeriodicSchedulePickerValues.specialTitle(timings[3]) == "最后一个周五")
    }

    @Test func emptyAndLongCyclesKeepExistingRuleSemantics() {
        #expect(PeriodicSchedulePickerValues.days(cycle: .daily, selected: nil).isEmpty)
        #expect(PeriodicSchedulePickerValues.displayedTiming(nil, cycle: .monthly) == nil)
        let quarter = PeriodicSchedulePickerValues.days(cycle: .quarterly, selected: nil)
        #expect(quarter[89].timing == .dayOfPeriod(90))
        #expect(quarter.last?.timing == .daysBeforeEnd(1))
    }

    @Test func annualPresetsReplaceTheOrdinalDayListWithoutChangingSavedRules() {
        let options = PeriodicSchedulePickerValues.days(cycle: .yearly, selected: nil)
        #expect(options.map(\.timing) == [
            .dayOfPeriod(1), .daysBeforeEnd(1), .businessDayOfPeriod(1),
            .lastBusinessDay, .daysBeforeEnd(30)
        ])
        #expect(options.first?.title == "年初")
        #expect(options[1].title == "年末")
        let existing = PeriodicReminderRule(timing: .dayOfPeriod(183), hour: 9, minute: 0, reminderLeadMinutes: 15)
        let restored = PeriodicSchedulePickerValues.days(cycle: .yearly, selected: existing.timing)
        #expect(restored.count == 6)
        #expect(restored.last?.timing == .dayOfPeriod(183))
        #expect(restored.last?.label == "已有日期")
        #expect(restored.last?.title == "第183天")
        #expect(existing.timing == .dayOfPeriod(183))
        #expect(existing.reminderLeadMinutes == 15)
    }

    @Test func periodicClockHasAllWallTimesAndPreservesOffGridValuesOnOpen() {
        let rule = PeriodicReminderRule(timing: .dayOfPeriod(3), hour: 15, minute: 13, reminderLeadMinutes: 30)
        let draft = PeriodicTimePickerValue.draft(rule: rule)
        let scale = TaskTimeRulerScale(on: draft.selectedDate, minuteInterval: 5, calendar: PeriodicTimePickerValue.calendar)
        #expect(scale.times.count == 288)
        #expect(scale.label(for: draft.selectedTime!) == "15:13")
        #expect(scale.label(at: scale.nearestIndex(to: draft.selectedTime!)) == "15:15")
        #expect(scale.times.indices.contains { scale.label(at: $0) == "02:30" })
        #expect(rule.reminderLeadMinutes == 30)
        #expect(rule.timing == .dayOfPeriod(3))
    }

    @Test func localSeedDoesNotSetAnEmptyTimeOrShiftItsHours() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = local.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23, minute: 13))!
        let seed = PeriodicTimePickerValue.seed(now: now, localCalendar: local)
        var draft = PeriodicTimePickerValue.draft(rule: nil)
        #expect(draft.selectedTime == nil)
        #expect(PeriodicTimePickerValue.calendar.component(.hour, from: seed) == 23)
        draft.selectTime(seed, calendar: PeriodicTimePickerValue.calendar)
        #expect(PeriodicTimePickerValue.calendar.component(.hour, from: draft.selectedTime!) == 23)
        #expect(PeriodicTimePickerValue.calendar.component(.minute, from: draft.selectedTime!) == 15)
        draft.setTimeEnabled(false)
        #expect(draft.selectedTime == nil)
    }
}
