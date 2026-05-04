import Foundation

enum TodayWidgetConstants {
    nonisolated static let appGroupIdentifier = "group.com.pigdog.together.shared"

    nonisolated static let focusWidgetKind = "com.pigdog.Together.widgets.today-focus"
    nonisolated static let listWidgetKind = "com.pigdog.Together.widgets.today-list"

    nonisolated static let snapshotFileName = "today-widget-snapshot.json"

    nonisolated static var todayDeepLink: URL {
        URL(string: "together://today")!
    }
}

struct TodayWidgetSnapshot: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case referenceDate
        case remainingCount
        case tasks
        case animatingCompletionTaskIDs
    }

    var generatedAt: Date
    var referenceDate: Date
    var remainingCount: Int
    var tasks: [TodayWidgetTaskSnapshot]
    var animatingCompletionTaskIDs: [UUID]

    nonisolated init(
        generatedAt: Date,
        referenceDate: Date,
        remainingCount: Int,
        tasks: [TodayWidgetTaskSnapshot],
        animatingCompletionTaskIDs: [UUID] = []
    ) {
        self.generatedAt = generatedAt
        self.referenceDate = referenceDate
        self.remainingCount = remainingCount
        self.tasks = tasks
        self.animatingCompletionTaskIDs = animatingCompletionTaskIDs
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
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(referenceDate, forKey: .referenceDate)
        try container.encode(remainingCount, forKey: .remainingCount)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(animatingCompletionTaskIDs, forKey: .animatingCompletionTaskIDs)
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

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueTimeText
        case sortIndex
    }

    let id: UUID
    var title: String
    var dueTimeText: String?
    var sortIndex: Int

    nonisolated init(id: UUID, title: String, dueTimeText: String?, sortIndex: Int) {
        self.id = id
        self.title = title
        self.dueTimeText = dueTimeText
        self.sortIndex = sortIndex
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueTimeText = try container.decodeIfPresent(String.self, forKey: .dueTimeText)
        sortIndex = try container.decode(Int.self, forKey: .sortIndex)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(dueTimeText, forKey: .dueTimeText)
        try container.encode(sortIndex, forKey: .sortIndex)
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
        snapshot.remainingCount = max(0, snapshot.remainingCount - 1)
        if snapshot.animatingCompletionTaskIDs.contains(taskID) == false {
            snapshot.animatingCompletionTaskIDs.append(taskID)
        }
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
