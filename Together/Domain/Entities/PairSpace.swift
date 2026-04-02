import Foundation

enum PairSpaceStatus: String, Hashable, Sendable {
    case trial
    case pendingAcceptance
    case active
    case ended
}

struct PairMember: Hashable, Sendable {
    let userID: UUID
    var nickname: String
    var joinedAt: Date
}

struct PairSpace: Identifiable, Hashable, Sendable {
    let id: UUID
    var sharedSpaceID: UUID
    var status: PairSpaceStatus
    var memberA: PairMember
    var memberB: PairMember?
    var dataBoundaryToken: UUID
    var createdAt: Date
    var activatedAt: Date?
    var endedAt: Date?
}
