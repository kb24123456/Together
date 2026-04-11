import Foundation
import SwiftData

/// Tracks historical pairing relationships for same-couple re-pairing detection.
///
/// When two users unpair, a record is kept so that if they re-pair later,
/// the old zone can be restored (re-shared) instead of creating a new one.
@Model
final class PersistentPairingHistory {
    var id: UUID
    /// The pair space ID that was created for this pairing.
    var pairSpaceID: UUID
    /// iCloud user record ID of member A (owner / inviter).
    var memberARecordID: String
    /// iCloud user record ID of member B (participant / responder).
    var memberBRecordID: String
    /// The CKRecordZone name for this pairing.
    var zoneName: String
    /// When the pairing was originally created.
    var pairedAt: Date
    /// When the pairing was ended (unbind). Nil if still active.
    var endedAt: Date?
    /// Whether the owner has permanently deleted this pairing's data.
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        pairSpaceID: UUID,
        memberARecordID: String,
        memberBRecordID: String,
        zoneName: String,
        pairedAt: Date,
        endedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.pairSpaceID = pairSpaceID
        self.memberARecordID = memberARecordID
        self.memberBRecordID = memberBRecordID
        self.zoneName = zoneName
        self.pairedAt = pairedAt
        self.endedAt = endedAt
        self.isDeleted = isDeleted
    }
}
