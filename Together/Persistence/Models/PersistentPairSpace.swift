import Foundation
import SwiftData

@Model
final class PersistentPairSpace {
    var id: UUID
    var sharedSpaceID: UUID
    var statusRawValue: String
    var displayName: String?
    var createdAt: Date
    var activatedAt: Date?
    var endedAt: Date?

    // CloudKit zone & share metadata
    var cloudKitZoneName: String?
    var ownerRecordID: String?
    var isZoneOwner: Bool

    init(
        id: UUID,
        sharedSpaceID: UUID,
        statusRawValue: String,
        displayName: String? = nil,
        createdAt: Date,
        activatedAt: Date?,
        endedAt: Date?,
        cloudKitZoneName: String? = nil,
        ownerRecordID: String? = nil,
        isZoneOwner: Bool = false
    ) {
        self.id = id
        self.sharedSpaceID = sharedSpaceID
        self.statusRawValue = statusRawValue
        self.displayName = displayName
        self.createdAt = createdAt
        self.activatedAt = activatedAt
        self.endedAt = endedAt
        self.cloudKitZoneName = cloudKitZoneName
        self.ownerRecordID = ownerRecordID
        self.isZoneOwner = isZoneOwner
    }
}

extension PersistentPairSpace {
    convenience init(pairSpace: PairSpace) {
        self.init(
            id: pairSpace.id,
            sharedSpaceID: pairSpace.sharedSpaceID,
            statusRawValue: pairSpace.status.rawValue,
            displayName: pairSpace.displayName,
            createdAt: pairSpace.createdAt,
            activatedAt: pairSpace.activatedAt,
            endedAt: pairSpace.endedAt,
            cloudKitZoneName: pairSpace.cloudKitZoneName,
            ownerRecordID: pairSpace.ownerRecordID,
            isZoneOwner: pairSpace.isZoneOwner
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
            displayName: displayName,
            createdAt: createdAt,
            activatedAt: activatedAt,
            endedAt: endedAt,
            cloudKitZoneName: cloudKitZoneName,
            ownerRecordID: ownerRecordID,
            isZoneOwner: isZoneOwner
        )
    }

    func update(from pairSpace: PairSpace) {
        sharedSpaceID = pairSpace.sharedSpaceID
        statusRawValue = pairSpace.status.rawValue
        displayName = pairSpace.displayName
        createdAt = pairSpace.createdAt
        activatedAt = pairSpace.activatedAt
        endedAt = pairSpace.endedAt
        cloudKitZoneName = pairSpace.cloudKitZoneName
        ownerRecordID = pairSpace.ownerRecordID
        isZoneOwner = pairSpace.isZoneOwner
    }
}
