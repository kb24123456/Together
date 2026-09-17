import Foundation

/// A finite list of wall-clock times on the task's existing calendar day.
/// Missing daylight-saving times are omitted; repeated times use their first occurrence.
struct TaskTimeRulerScale {
    let times: [Date]
    let calendar: Calendar

    init(on day: Date, minuteInterval: Int, calendar: Calendar = .current) {
        self.calendar = calendar
        times = stride(from: 0, to: 24 * 60, by: minuteInterval).compactMap { minutes in
            guard let time = calendar.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: day,
                matchingPolicy: .strict,
                repeatedTimePolicy: .first
            ), calendar.isDate(time, inSameDayAs: day) else { return nil }
            return time
        }
    }

    func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), times.count - 1)
    }

    func nearestIndex(to time: Date) -> Int {
        let minutes = minuteOfDay(time)
        return times.indices.min {
            abs(minuteOfDay(times[$0]) - minutes) < abs(minuteOfDay(times[$1]) - minutes)
        } ?? 0
    }

    func label(at index: Int) -> String {
        label(for: times[clampedIndex(index)])
    }

    func label(for time: Date) -> String {
        let minutes = minuteOfDay(time)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    func showsLabel(at index: Int, every minutes: Int) -> Bool {
        minuteOfDay(times[index]).isMultiple(of: minutes)
    }

    private func minuteOfDay(_ time: Date) -> Int {
        calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)
    }
}
