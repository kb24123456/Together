import XCTest
@testable import Together

final class HolidayScheduleDataTests: XCTestCase {
    func test_lookup_2026_springFestival_returnsSchedule() throws {
        let schedule = try XCTUnwrap(HolidayScheduleData.lookup(preset: .springFestival, year: 2026))
        XCTAssertEqual(schedule.name, "2026 春节")
        // 2026 春节放假为 2/16 (周一) ~ 2/22 (周日)，7 天
        XCTAssertEqual(Calendar.current.component(.month, from: schedule.startDate), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: schedule.startDate), 16)
        XCTAssertEqual(schedule.offDays, 7)
        XCTAssertEqual(schedule.preset, .springFestival)
    }

    func test_lookup_unsupportedYear_returnsNil() {
        XCTAssertNil(HolidayScheduleData.lookup(preset: .springFestival, year: 2099))
    }

    func test_lookup_unsupportedPreset_returnsNil() {
        // valentines is in PresetHolidayID but not officially a 法定节假日 — we
        // intentionally don't ship a schedule for it. Lookup returns nil.
        XCTAssertNil(HolidayScheduleData.lookup(preset: .valentines, year: 2026))
    }

    func test_nextUpcoming_excludesPastSchedules() {
        let future = Calendar.current.date(byAdding: .year, value: 100, to: .now)!
        let upcoming = HolidayScheduleData.nextUpcoming(now: future)
        XCTAssertTrue(upcoming.isEmpty, "All hardcoded schedules should be in the past relative to year 2126")
    }

    func test_all_isSortedByStartDate() {
        let starts = HolidayScheduleData.all.map { $0.startDate }
        XCTAssertEqual(starts, starts.sorted(), "HolidayScheduleData.all must be in ascending startDate order for nextUpcoming() to short-circuit")
    }
}
