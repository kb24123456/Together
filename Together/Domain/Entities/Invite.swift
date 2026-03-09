import Foundation

enum InviteStatus: String, Hashable, Sendable {
    case pending
    case accepted
    case declined
    case expired
    case cancelled
    case revoked
}

struct Invite: Identifiable, Hashable, Sendable {
    let id: UUID
    let pairSpaceID: UUID
    let inviterID: UUID
    var inviteCode: String
    var status: InviteStatus
    var sentAt: Date
    var respondedAt: Date?
    var expiresAt: Date
}
