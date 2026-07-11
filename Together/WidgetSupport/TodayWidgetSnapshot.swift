import Foundation

struct TodayWidgetSnapshot: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case referenceDate
        case remainingCount
        case completedTodayCount
        case overdueCount
        case tasks
        case nextUpcomingTask
        case animatingCompletionTaskIDs
        case appearingTaskIDs
    }

    var generatedAt: Date
    var referenceDate: Date
    var remainingCount: Int
    var completedTodayCount: Int
    var overdueCount: Int
    var tasks: [TodayWidgetTaskSnapshot]
    var nextUpcomingTask: TodayWidgetTaskSnapshot?
    var animatingCompletionTaskIDs: [UUID]
    var appearingTaskIDs: [UUID]

    nonisolated init(
        generatedAt: Date,
        referenceDate: Date,
        remainingCount: Int,
        completedTodayCount: Int = 0,
        overdueCount: Int = 0,
        tasks: [TodayWidgetTaskSnapshot],
        nextUpcomingTask: TodayWidgetTaskSnapshot? = nil,
        animatingCompletionTaskIDs: [UUID] = [],
        appearingTaskIDs: [UUID] = []
    ) {
        self.generatedAt = generatedAt
        self.referenceDate = referenceDate
        self.remainingCount = remainingCount
        self.completedTodayCount = completedTodayCount
        self.overdueCount = overdueCount
        self.tasks = tasks
        self.nextUpcomingTask = nextUpcomingTask
        self.animatingCompletionTaskIDs = animatingCompletionTaskIDs
        self.appearingTaskIDs = appearingTaskIDs
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        referenceDate = try container.decode(Date.self, forKey: .referenceDate)
        remainingCount = try container.decode(Int.self, forKey: .remainingCount)
        completedTodayCount = try container.decodeIfPresent(Int.self, forKey: .completedTodayCount) ?? 0
        overdueCount = try container.decodeIfPresent(Int.self, forKey: .overdueCount) ?? 0
        tasks = try container.decode([TodayWidgetTaskSnapshot].self, forKey: .tasks)
        nextUpcomingTask = try container.decodeIfPresent(TodayWidgetTaskSnapshot.self, forKey: .nextUpcomingTask)
        animatingCompletionTaskIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .animatingCompletionTaskIDs
        ) ?? []
        appearingTaskIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .appearingTaskIDs
        ) ?? []
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(referenceDate, forKey: .referenceDate)
        try container.encode(remainingCount, forKey: .remainingCount)
        try container.encode(completedTodayCount, forKey: .completedTodayCount)
        try container.encode(overdueCount, forKey: .overdueCount)
        try container.encode(tasks, forKey: .tasks)
        try container.encodeIfPresent(nextUpcomingTask, forKey: .nextUpcomingTask)
        try container.encode(animatingCompletionTaskIDs, forKey: .animatingCompletionTaskIDs)
        try container.encode(appearingTaskIDs, forKey: .appearingTaskIDs)
    }

    nonisolated static var empty: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 0,
            tasks: []
        )
    }

    nonisolated var totalTodayCount: Int {
        completedTodayCount + remainingCount
    }

    nonisolated var completionProgress: Double {
        guard totalTodayCount > 0 else { return 1 }
        return Double(completedTodayCount) / Double(totalTodayCount)
    }
}

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueTimeText
        case sortIndex
        case isOverdue
    }

    let id: UUID
    var title: String
    var dueTimeText: String?
    var sortIndex: Int
    var isOverdue: Bool

    nonisolated init(
        id: UUID,
        title: String,
        dueTimeText: String?,
        sortIndex: Int,
        isOverdue: Bool = false
    ) {
        self.id = id
        self.title = title
        self.dueTimeText = dueTimeText
        self.sortIndex = sortIndex
        self.isOverdue = isOverdue
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueTimeText = try container.decodeIfPresent(String.self, forKey: .dueTimeText)
        sortIndex = try container.decode(Int.self, forKey: .sortIndex)
        isOverdue = try container.decodeIfPresent(Bool.self, forKey: .isOverdue) ?? false
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(dueTimeText, forKey: .dueTimeText)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(isOverdue, forKey: .isOverdue)
    }
}
