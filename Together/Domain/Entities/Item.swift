import Foundation

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
    var dueAt: Date?
    var hasExplicitTime: Bool = false
    var remindAt: Date?
    var status: ItemStatus
    var lastActionByUserID: UUID?
    var lastActionAt: Date?
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    /// Authoritative actor who marked the task complete. Set exactly
    /// once on markCompleted and cleared on markIncomplete. Unlike
    /// `lastActionByUserID` (which drifts as the record receives other
    /// actions after completion), this stays pinned to the completer.
    /// Display code prefers this field; falls back to
    /// `lastActionByUserID` for pre-migration rows where it is nil.
    var completedByUserID: UUID? = nil
    var occurrenceCompletions: [ItemOccurrenceCompletion] = []
    var subtasks: [TaskSubtask] = []
    var sortOrder: Double = 0
    var isUrgent: Bool = false
    var isDraft: Bool
    var isArchived: Bool = false
    var archivedAt: Date? = nil
    var repeatRule: ItemRepeatRule? = nil
    var isFollowed: Bool = false
    var followedAt: Date? = nil
}
