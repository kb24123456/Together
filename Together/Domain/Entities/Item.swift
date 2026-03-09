import Foundation

struct ItemResponse: Hashable, Sendable {
    let responderID: UUID
    var kind: ItemResponseKind
    var message: String?
    var respondedAt: Date
}

struct Item: Identifiable, Hashable, Sendable {
    let id: UUID
    var relationshipID: UUID?
    let creatorID: UUID
    let title: String
    var notes: String?
    var executionRole: ItemExecutionRole
    var priority: ItemPriority
    var dueAt: Date?
    var remindAt: Date?
    var status: ItemStatus
    var latestResponse: ItemResponse?
    var responseHistory: [ItemResponse]
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isDraft: Bool
}
