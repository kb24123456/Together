import Foundation

struct ItemResponse: Hashable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case responderID
        case kind
        case message
        case respondedAt
    }

    let responderID: UUID
    var kind: ItemResponseKind
    var message: String?
    var respondedAt: Date

    nonisolated init(
        responderID: UUID,
        kind: ItemResponseKind,
        message: String?,
        respondedAt: Date
    ) {
        self.responderID = responderID
        self.kind = kind
        self.message = message
        self.respondedAt = respondedAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        responderID = try container.decode(UUID.self, forKey: .responderID)
        kind = try container.decode(ItemResponseKind.self, forKey: .kind)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        respondedAt = try container.decode(Date.self, forKey: .respondedAt)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responderID, forKey: .responderID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(respondedAt, forKey: .respondedAt)
    }
}

struct ItemOccurrenceCompletion: Hashable, Sendable, Codable {
    var occurrenceDate: Date
    var completedAt: Date
}

struct Item: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var spaceID: UUID?
    var listID: UUID?
    var projectID: UUID?
    let creatorID: UUID
    var title: String
    var notes: String?
    var locationText: String? = nil
    var executionRole: ItemExecutionRole
    var priority: ItemPriority
    var dueAt: Date?
    var hasExplicitTime: Bool = false
    var remindAt: Date?
    var status: ItemStatus
    var latestResponse: ItemResponse?
    var responseHistory: [ItemResponse]
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var occurrenceCompletions: [ItemOccurrenceCompletion] = []
    var isPinned: Bool = false
    var isDraft: Bool
    var isArchived: Bool = false
    var archivedAt: Date? = nil
    var repeatRule: ItemRepeatRule? = nil
}
