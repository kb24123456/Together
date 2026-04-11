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
    var displayName: String?
    var createdAt: Date
    var activatedAt: Date?
    var endedAt: Date?

    // MARK: - CloudKit Zone & Share

    /// The CKRecordZone name for this pair space (e.g. "pair-<uuid>").
    /// Set when the owner creates the zone after pairing.
    var cloudKitZoneName: String?

    /// The owner's iCloud user record ID (the person who created the invite).
    /// Used to determine which database to use (private vs shared).
    var ownerRecordID: String?

    /// Whether this user is the zone owner (inviter) or participant (responder).
    var isZoneOwner: Bool = false
}
