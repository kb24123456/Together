import Foundation

enum SpaceType: String, CaseIterable, Hashable, Sendable, Codable {
    case single
    case pair
    case multi
}

enum SpaceStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case active
    case paused
    case archived
}

struct Space: Identifiable, Hashable, Sendable {
    let id: UUID
    var type: SpaceType
    var displayName: String
    var ownerUserID: UUID
    var status: SpaceStatus
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}
