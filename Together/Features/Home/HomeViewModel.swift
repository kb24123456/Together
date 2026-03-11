import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let calendar = Calendar.current

    var selectedDate: Date = MockDataFactory.now

    init(
        sessionStore: SessionStore,
        itemRepository: ItemRepositoryProtocol,
        anniversaryRepository: AnniversaryRepositoryProtocol
    ) {}

    var selectedDateTitle: String {
        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    var weekDates: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 86_400 * 7)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
    }

    func isSelectedDate(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return ""
        }
    }
}
