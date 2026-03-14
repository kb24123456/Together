import Foundation

struct TaskTodaySummary: Hashable, Sendable {
    let referenceDate: Date
    let actionableCount: Int
    let overdueCount: Int
    let dueTodayCount: Int
    let completedTodayCount: Int
    let pinnedCount: Int
}
