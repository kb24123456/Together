import Foundation

enum HomeTaskFilterOption: String, CaseIterable, Hashable, Sendable {
    case urgent
    case overdue
    case unscheduled
    case hasReminder

    var title: String {
        switch self {
        case .urgent: "紧急"
        case .overdue: "已逾期"
        case .unscheduled: "无日期"
        case .hasReminder: "有提醒"
        }
    }

    var systemImage: String {
        switch self {
        case .urgent: "flag.fill"
        case .overdue: "clock.badge.exclamationmark"
        case .unscheduled: "calendar.badge.minus"
        case .hasReminder: "bell.fill"
        }
    }
}

struct HomeTaskFilter: Equatable, Sendable {
    var searchText = ""
    var selectedOptions: Set<HomeTaskFilterOption> = []

    var isActive: Bool {
        normalizedSearchText.isEmpty == false || selectedOptions.isEmpty == false
    }

    func matches(
        _ item: Item,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard matchesSearch(item) else { return false }

        for option in selectedOptions {
            switch option {
            case .urgent:
                guard item.isUrgent else { return false }
            case .overdue:
                guard item.isOverdue(on: referenceDate, calendar: calendar) else { return false }
            case .unscheduled:
                guard item.dueAt == nil else { return false }
            case .hasReminder:
                guard item.remindAt != nil else { return false }
            }
        }

        return true
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ item: Item) -> Bool {
        let query = normalizedSearchText
        guard query.isEmpty == false else { return true }

        if item.title.localizedStandardContains(query) { return true }
        if item.notes?.localizedStandardContains(query) == true { return true }
        return item.subtasks.contains { $0.title.localizedStandardContains(query) }
    }
}
