import Foundation
import Testing
@testable import Together

struct TaskTimeRulerTests {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, month: Int = 9, day: Int = 17, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func fullDayHasFiveMinuteChoicesAndQuarterHourLabels() {
        let calendar = calendar()
        let scale = TaskTimeRulerScale(on: date(calendar), minuteInterval: 5, calendar: calendar)
        #expect(scale.times.count == 288)
        #expect(scale.label(at: 0) == "00:00")
        #expect(scale.label(at: 287) == "23:55")
        #expect(scale.label(at: 181) == "15:05")
        #expect(scale.showsLabel(at: 180, every: 15))
        #expect(!scale.showsLabel(at: 181, every: 15))
        #expect(scale.showsLabel(at: 183, every: 15))
        #expect(!scale.showsLabel(at: 183, every: 30))
    }

    @Test func endsClampWithoutWrappingToAnotherDay() {
        let calendar = calendar()
        let day = date(calendar)
        let scale = TaskTimeRulerScale(on: day, minuteInterval: 5, calendar: calendar)
        #expect(scale.clampedIndex(-1) == 0)
        #expect(scale.clampedIndex(288) == 287)
        #expect(scale.nearestIndex(to: date(calendar, hour: 23, minute: 59)) == 287)
        #expect(scale.times.allSatisfy { calendar.isDate($0, inSameDayAs: day) })
    }

    @Test func initialPositionDoesNotEnableAnUnsetTime() {
        let calendar = calendar()
        let day = date(calendar)
        let draft = ExistingTaskScheduleDraft(dueAt: day, hasExplicitTime: false, fallbackDate: day, calendar: calendar)
        let scale = TaskTimeRulerScale(on: day, minuteInterval: 5, calendar: calendar)
        #expect(scale.label(at: scale.nearestIndex(to: date(calendar, hour: 15, minute: 13))) == "15:15")
        #expect(draft.selectedTime == nil)
        #expect(draft.reminderOffset == nil)
    }

    @Test func openingPreservesAnExistingOffGridTime() {
        let calendar = calendar()
        let dueAt = date(calendar, hour: 15, minute: 13)
        let draft = ExistingTaskScheduleDraft(dueAt: dueAt, hasExplicitTime: true, fallbackDate: dueAt, calendar: calendar)
        let scale = TaskTimeRulerScale(on: dueAt, minuteInterval: 5, calendar: calendar)
        #expect(scale.label(at: scale.nearestIndex(to: dueAt)) == "15:15")
        #expect(scale.label(for: draft.selectedTime!) == "15:13")
        #expect(draft.selectedTime == dueAt)
    }

    @Test func selectionPreservesDateAndReminderLeadAndClearRemovesOnlyTimeAndReminder() {
        let calendar = calendar()
        let dueAt = date(calendar, hour: 15)
        var draft = ExistingTaskScheduleDraft(
            dueAt: dueAt, hasExplicitTime: true,
            remindAt: dueAt.addingTimeInterval(-900), fallbackDate: dueAt, calendar: calendar
        )
        let day = draft.selectedDate
        let scale = TaskTimeRulerScale(on: day, minuteInterval: 5, calendar: calendar)
        draft.selectTime(scale.times[181], calendar: calendar)
        #expect(scale.label(for: draft.selectedTime!) == "15:05")
        #expect(draft.reminderOffset == 900)
        #expect(draft.selectedDate == day)
        draft.setTimeEnabled(false, calendar: calendar)
        #expect(draft.selectedTime == nil)
        #expect(draft.reminderOffset == nil)
        #expect(draft.selectedDate == day)
        draft.selectTime(scale.times[182], calendar: calendar)
        #expect(draft.reminderOffset == nil)
    }

    @Test func springDayOmitsNonexistentWallClockTimes() {
        let calendar = calendar("America/Los_Angeles")
        let day = date(calendar, month: 3, day: 8)
        let scale = TaskTimeRulerScale(on: day, minuteInterval: 5, calendar: calendar)
        #expect(scale.times.count == 276)
        #expect(scale.label(at: 23) == "01:55")
        #expect(scale.label(at: 24) == "03:00")
        #expect(scale.times.allSatisfy { calendar.isDate($0, inSameDayAs: day) })
    }

    @Test func autumnDayDoesNotDuplicateAmbiguousWallClockLabels() {
        let calendar = calendar("America/Los_Angeles")
        let day = date(calendar, month: 11, day: 1)
        let scale = TaskTimeRulerScale(on: day, minuteInterval: 5, calendar: calendar)
        #expect(scale.times.count == 288)
        #expect(Set(scale.times.indices.map(scale.label(at:))).count == 288)
        #expect(scale.times.allSatisfy { calendar.isDate($0, inSameDayAs: day) })
    }
}
