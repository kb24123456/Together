import Foundation

enum PairSpaceSummaryResolver {
    static func resolve(
        for userID: UUID,
        spaces: [PersistentSpace],
        pairSpaces: [PersistentPairSpace],
        memberships: [PersistentPairMembership]
    ) -> PairSpaceSummary? {
        guard let pairRecord = bestPairSpace(
            for: userID,
            pairSpaces: pairSpaces,
            memberships: memberships
        ),
              let sharedSpaceRecord = spaces.first(where: { $0.id == pairRecord.sharedSpaceID }) else {
            return nil
        }
        guard let pairSpace = pairRecord.domainModel(
            memberships: memberships.filter { $0.pairSpaceID == pairRecord.id },
            ownerUserID: sharedSpaceRecord.ownerUserID
        ) else {
            return nil
        }

        let partnerMembership = memberships.first { $0.pairSpaceID == pairRecord.id && $0.userID != userID }
        let partner = partnerMembership.map { membership in
            User(
                id: membership.userID,
                appleUserID: nil,
                displayName: membership.nickname,
                avatarSystemName: membership.avatarSystemName ?? "person.crop.circle.fill",
                avatarPhotoFileName: membership.avatarPhotoFileName,
                avatarAssetID: membership.avatarAssetID,
                avatarVersion: membership.avatarVersion,
                createdAt: membership.joinedAt,
                updatedAt: membership.joinedAt,
                preferences: NotificationSettings(
                    taskReminderEnabled: true,
                    dailySummaryEnabled: true,
                    calendarReminderEnabled: true,
                    futureCollaborationInviteEnabled: true
                )
            )
        }

        return PairSpaceSummary(
            sharedSpace: sharedSpaceRecord.domainModel,
            pairSpace: pairSpace,
            partner: partner
        )
    }

    static func bestPairSpace(
        for userID: UUID,
        pairSpaces: [PersistentPairSpace],
        memberships: [PersistentPairMembership]
    ) -> PersistentPairSpace? {
        let pairSpaceIDs = Set(memberships.filter { $0.userID == userID }.map(\.pairSpaceID))
        return pairSpaces
            .filter { pairSpaceIDs.contains($0.id) && $0.endedAt == nil }
            .sorted(by: isHigherPriorityPairSpace)
            .first
    }

    private static func isHigherPriorityPairSpace(
        _ lhs: PersistentPairSpace,
        than rhs: PersistentPairSpace
    ) -> Bool {
        let lhsIsActive = lhs.statusRawValue == PairSpaceStatus.active.rawValue
        let rhsIsActive = rhs.statusRawValue == PairSpaceStatus.active.rawValue
        if lhsIsActive != rhsIsActive {
            return lhsIsActive
        }

        let lhsDate = lhs.activatedAt ?? lhs.createdAt
        let rhsDate = rhs.activatedAt ?? rhs.createdAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
