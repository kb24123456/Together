import Foundation

enum TodayWidgetConstants {
    nonisolated static let appGroupIdentifier = "group.com.pigdog.together.shared"

    nonisolated static let listWidgetKind = "com.pigdog.Together.widgets.today-list"
    nonisolated static let snapshotFileName = "today-widget-snapshot.json"

    nonisolated static var todayDeepLink: URL {
        URL(string: "together://today")!
    }

    nonisolated static func taskDeepLink(taskID: UUID) -> URL {
        URL(string: "together://task/\(taskID.uuidString)")!
    }
}

struct TodayWidgetSnapshot: Codable, Equatable {
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

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable {
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

struct TodayWidgetSnapshotStore {
    private let containerURL: URL?

    nonisolated init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.containerURL = containerURL
    }

    nonisolated func read() throws -> TodayWidgetSnapshot {
        guard let fileURL else { return .empty }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.todayWidget.decode(TodayWidgetSnapshot.self, from: data)
    }

    nonisolated func write(_ snapshot: TodayWidgetSnapshot) throws {
        guard let fileURL else { return }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder.todayWidget.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    nonisolated func markTaskCompletedForAnimation(taskID: UUID, completedAt: Date) throws {
        var snapshot = try read()
        let completedTask = snapshot.tasks.first { $0.id == taskID }
        snapshot.remainingCount = max(0, snapshot.remainingCount - 1)
        snapshot.completedTodayCount += 1
        if completedTask?.isOverdue == true {
            snapshot.overdueCount = max(0, snapshot.overdueCount - 1)
        }
        if snapshot.animatingCompletionTaskIDs.contains(taskID) == false {
            snapshot.animatingCompletionTaskIDs.append(taskID)
        }
        snapshot.appearingTaskIDs = []
        snapshot.generatedAt = completedAt
        try write(snapshot)
    }

    private nonisolated var fileURL: URL? {
        containerURL?.appending(path: TodayWidgetConstants.snapshotFileName)
    }
}

struct TodayWidgetSharedContext: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case spaceID
        case actorID
    }

    var spaceID: UUID
    var actorID: UUID

    nonisolated init(spaceID: UUID, actorID: UUID) {
        self.spaceID = spaceID
        self.actorID = actorID
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaceID = try container.decode(UUID.self, forKey: .spaceID)
        actorID = try container.decode(UUID.self, forKey: .actorID)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spaceID, forKey: .spaceID)
        try container.encode(actorID, forKey: .actorID)
    }
}

struct TodayWidgetSharedContextStore {
    private nonisolated(unsafe) let defaults: UserDefaults?
    private nonisolated let key = "today-widget-context"

    nonisolated init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
    }

    nonisolated func read() -> TodayWidgetSharedContext? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder.todayWidget.decode(TodayWidgetSharedContext.self, from: data)
    }
}

private extension JSONEncoder {
    nonisolated static var todayWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var todayWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
