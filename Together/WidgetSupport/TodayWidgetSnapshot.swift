import Foundation

struct TodayWidgetSnapshot: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case referenceDate
        case remainingCount
        case tasks
        case animatingCompletionTaskIDs
        case appearingTaskIDs
    }

    var generatedAt: Date
    var referenceDate: Date
    var remainingCount: Int
    var tasks: [TodayWidgetTaskSnapshot]
    var animatingCompletionTaskIDs: [UUID]
    var appearingTaskIDs: [UUID]

    nonisolated init(
        generatedAt: Date,
        referenceDate: Date,
        remainingCount: Int,
        tasks: [TodayWidgetTaskSnapshot],
        animatingCompletionTaskIDs: [UUID] = [],
        appearingTaskIDs: [UUID] = []
    ) {
        self.generatedAt = generatedAt
        self.referenceDate = referenceDate
        self.remainingCount = remainingCount
        self.tasks = tasks
        self.animatingCompletionTaskIDs = animatingCompletionTaskIDs
        self.appearingTaskIDs = appearingTaskIDs
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        referenceDate = try container.decode(Date.self, forKey: .referenceDate)
        remainingCount = try container.decode(Int.self, forKey: .remainingCount)
        tasks = try container.decode([TodayWidgetTaskSnapshot].self, forKey: .tasks)
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
        try container.encode(tasks, forKey: .tasks)
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
}

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var dueTimeText: String?
    var sortIndex: Int
}
