import Foundation

struct TodayWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var referenceDate: Date
    var remainingCount: Int
    var tasks: [TodayWidgetTaskSnapshot]

    static var empty: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 0,
            tasks: []
        )
    }
}

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var dueTimeText: String?
    var sortIndex: Int
}
