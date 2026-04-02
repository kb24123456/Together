import Foundation
import SwiftData

@Model
final class PersistentPairSpace {
    var id: UUID
    var sharedSpaceID: UUID
    var statusRawValue: String
    var createdAt: Date
    var activatedAt: Date?
    var endedAt: Date?

    init(
        id: UUID,
        sharedSpaceID: UUID,
        statusRawValue: String,
        createdAt: Date,
        activatedAt: Date?,
        endedAt: Date?
    ) {
        self.id = id
        self.sharedSpaceID = sharedSpaceID
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.activatedAt = activatedAt
        self.endedAt = endedAt
    }
}

extension PersistentPairSpace {
    convenience init(pairSpace: PairSpace) {
        self.init(
            id: pairSpace.id,
            sharedSpaceID: pairSpace.sharedSpaceID,
            statusRawValue: pairSpace.status.rawValue,
            createdAt: pairSpace.createdAt,
            activatedAt: pairSpace.activatedAt,
            endedAt: pairSpace.endedAt
        )
    }

    func domainModel(memberships: [PersistentPairMembership]) -> PairSpace? {
        let sortedMembers = memberships.sorted { $0.joinedAt < $1.joinedAt }
        guard let memberARecord = sortedMembers.first else { return nil }
        let memberBRecord = sortedMembers.dropFirst().first

        return PairSpace(
            id: id,
            sharedSpaceID: sharedSpaceID,
            status: PairSpaceStatus(rawValue: statusRawValue) ?? .pendingAcceptance,
            memberA: memberARecord.domainModel,
            memberB: memberBRecord?.domainModel,
            dataBoundaryToken: sharedSpaceID,
            createdAt: createdAt,
            activatedAt: activatedAt,
            endedAt: endedAt
        )
    }

    func update(from pairSpace: PairSpace) {
        sharedSpaceID = pairSpace.sharedSpaceID
        statusRawValue = pairSpace.status.rawValue
        createdAt = pairSpace.createdAt
        activatedAt = pairSpace.activatedAt
        endedAt = pairSpace.endedAt
    }
}
