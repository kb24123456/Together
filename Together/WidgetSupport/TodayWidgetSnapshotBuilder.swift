import Foundation

struct TodayWidgetSnapshotBuilder: Sendable {
    private let calendar: Calendar

    nonisolated init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    nonisolated func build(
        items: [Item],
        referenceDate: Date,
        limit: Int = 3
    ) -> TodayWidgetSnapshot {
        let sorted = items
            .filter { isIncomplete($0, on: referenceDate) }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                let lhsDueAt = timelineSortDate(for: lhs, referenceDate: referenceDate)
                let rhsDueAt = timelineSortDate(for: rhs, referenceDate: referenceDate)
                if lhsDueAt != rhsDueAt {
                    return lhsDueAt < rhsDueAt
                }

                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }

        return TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: referenceDate,
            remainingCount: sorted.count,
            tasks: Array(sorted.prefix(max(limit, 1))).enumerated().map { index, item in
                TodayWidgetTaskSnapshot(
                    id: item.id,
                    title: item.title,
                    dueTimeText: dueTimeText(for: item, referenceDate: referenceDate),
                    sortIndex: index
                )
            }
        )
    }

    private nonisolated func isIncomplete(_ item: Item, on referenceDate: Date) -> Bool {
        item.isCompleted(on: referenceDate, calendar: calendar) == false && item.status != .completed
    }

    private nonisolated func timelineSortDate(for item: Item, referenceDate: Date) -> Date {
        item.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? item.dueAt ?? .distantFuture
    }

    private nonisolated func dueTimeText(for item: Item, referenceDate: Date) -> String? {
        let dueAt = item.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? item.dueAt
        guard let dueAt, item.hasExplicitTime else { return nil }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
