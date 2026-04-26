import Foundation

/// One year's worth of statutory holiday schedule (放假安排), including
/// any 调休 days the State Council bundles into the contiguous 放假 range.
/// Spec §2.4.
///
/// Display layer maps a user-created ImportantDate (kind == .holiday with
/// presetHolidayID) to the matching HolidaySchedule for the current year
/// to show "距春节假期还有 N 天". When no schedule exists for the year
/// (user is past the hardcoded 2026-2027 window before they update the
/// app), display falls back to ImportantDate.nextOccurrence on the
/// holiday's seed month/day.
struct HolidaySchedule: Hashable, Sendable {
    /// Display name including year, e.g. "2026 春节".
    let name: String
    /// First day of the contiguous off-period (i.e. start of 放假).
    let startDate: Date
    /// Last day of the off-period (inclusive).
    let endDate: Date
    /// Total days off (含调休补班后的实际放假天数).
    let offDays: Int
    /// Link back to PresetHolidayID so display layer can map a user's
    /// ImportantDate row to its matching year-specific schedule.
    let preset: PresetHolidayID?
}
