import Foundation

struct ItemResponse: Hashable, Sendable, Codable {
    let responderID: UUID
    var kind: ItemResponseKind
    var message: String?
    var respondedAt: Date
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
    var isPinned: Bool = false
    var isDraft: Bool
    var isArchived: Bool = false
    var archivedAt: Date? = nil
    var repeatRule: ItemRepeatRule? = nil
}
