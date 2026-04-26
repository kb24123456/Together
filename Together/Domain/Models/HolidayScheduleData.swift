import Foundation

/// Hardcoded 2026-2027 法定节假日 schedules per State Council 公告.
///
/// **Maintenance:** State Council typically publishes next year's 放假安排
/// in early November. After publication, append the new year's entries
/// here in startDate order and ship in the next app release. 1.0.1 will
/// add OTA fetch from holiday-cn (NateScarlet/holiday-cn GitHub repo)
/// so users see new years without app upgrade — until then, this file
/// is the single source of truth.
///
/// Source: 国务院办公厅关于 2026/2027 年部分节假日安排的通知.
enum HolidayScheduleData {
    static let all: [HolidaySchedule] = build()

    static func lookup(preset: PresetHolidayID, year: Int) -> HolidaySchedule? {
        all.first { schedule in
            schedule.preset == preset
                && Calendar.current.component(.year, from: schedule.startDate) == year
        }
    }

    static func nextUpcoming(now: Date = .now) -> [HolidaySchedule] {
        guard let firstUpcomingIdx = all.firstIndex(where: { $0.endDate >= now }) else {
            return []
        }
        return Array(all[firstUpcomingIdx...])
    }

    private static func build() -> [HolidaySchedule] {
        var out: [HolidaySchedule] = []

        // ===== 2026 =====
        out.append(.init(name: "2026 元旦", startDate: date(2026, 1, 1), endDate: date(2026, 1, 1), offDays: 1, preset: .newYear))
        out.append(.init(name: "2026 春节", startDate: date(2026, 2, 16), endDate: date(2026, 2, 22), offDays: 7, preset: .springFestival))
        out.append(.init(name: "2026 清明", startDate: date(2026, 4, 4), endDate: date(2026, 4, 6), offDays: 3, preset: .qingming))
        out.append(.init(name: "2026 劳动节", startDate: date(2026, 5, 1), endDate: date(2026, 5, 5), offDays: 5, preset: .laborDay))
        out.append(.init(name: "2026 端午节", startDate: date(2026, 6, 19), endDate: date(2026, 6, 21), offDays: 3, preset: .dragonBoat))
        out.append(.init(name: "2026 中秋节", startDate: date(2026, 9, 25), endDate: date(2026, 9, 27), offDays: 3, preset: .midAutumn))
        out.append(.init(name: "2026 国庆节", startDate: date(2026, 10, 1), endDate: date(2026, 10, 8), offDays: 8, preset: .nationalDay))

        // ===== 2027 (initial draft — VERIFY against 国务院公告 when published) =====
        out.append(.init(name: "2027 元旦", startDate: date(2027, 1, 1), endDate: date(2027, 1, 3), offDays: 3, preset: .newYear))
        out.append(.init(name: "2027 春节", startDate: date(2027, 2, 6), endDate: date(2027, 2, 12), offDays: 7, preset: .springFestival))
        out.append(.init(name: "2027 清明", startDate: date(2027, 4, 3), endDate: date(2027, 4, 5), offDays: 3, preset: .qingming))
        out.append(.init(name: "2027 劳动节", startDate: date(2027, 5, 1), endDate: date(2027, 5, 5), offDays: 5, preset: .laborDay))
        out.append(.init(name: "2027 端午节", startDate: date(2027, 6, 9), endDate: date(2027, 6, 11), offDays: 3, preset: .dragonBoat))
        out.append(.init(name: "2027 中秋节", startDate: date(2027, 9, 15), endDate: date(2027, 9, 19), offDays: 5, preset: .midAutumn))
        out.append(.init(name: "2027 国庆节", startDate: date(2027, 10, 1), endDate: date(2027, 10, 7), offDays: 7, preset: .nationalDay))

        return out
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
