import Foundation

struct DecisionVote: Hashable, Sendable {
    let voterID: UUID
    var value: DecisionVoteValue
    var respondedAt: Date
}

struct Decision: Identifiable, Hashable, Sendable {
    let id: UUID
    var spaceID: UUID?
    let creatorID: UUID
    var template: DecisionTemplate
    var title: String
    var notes: String?
    var referenceLink: URL?
    var proposedTime: Date?
    var status: DecisionStatus
    var votes: [DecisionVote]
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var convertedItemID: UUID?
    var isDraft: Bool
}
