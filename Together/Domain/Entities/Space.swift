import Foundation

enum SpaceType: String, CaseIterable, Hashable, Sendable, Codable {
    case single
}

enum SpaceStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case active
    case paused
    case archived
}

struct Space: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var type: SpaceType
    var displayName: String
    var ownerUserID: UUID
    var status: SpaceStatus
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}
