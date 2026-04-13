import Foundation

enum PairSpaceSummaryResolver {
    static func resolve(
        for userID: UUID,
        spaces: [PersistentSpace],
        pairSpaces: [PersistentPairSpace],
        memberships: [PersistentPairMembership]
    ) -> PairSpaceSummary? {
        let pairSpaceIDs = Set(memberships.filter { $0.userID == userID }.map(\.pairSpaceID))
        guard let pairRecord = pairSpaces.first(where: { pairSpaceIDs.contains($0.id) && $0.endedAt == nil }),
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
}
