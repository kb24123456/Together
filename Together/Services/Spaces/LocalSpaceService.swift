import Foundation
import SwiftData

actor LocalSpaceService: SpaceServiceProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func currentSpaceContext(for userID: UUID?) async -> SpaceContext {
        let context = ModelContext(container)
        let spaceRecords = (try? context.fetch(
            FetchDescriptor<PersistentSpace>(
                sortBy: [SortDescriptor(\PersistentSpace.updatedAt, order: .reverse)]
            )
        )) ?? []
        let pairSpaceRecords = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
        let membershipRecords = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []

        let singleSpace = spaceRecords
            .map(\.domainModel)
            .first { space in
                guard space.type == .single, space.status != .archived else { return false }
                guard let userID else { return true }
                return space.ownerUserID == userID
            }

        let pairSummary: PairSpaceSummary? = {
            guard let userID else { return nil }
            let pairSpaceIDs = Set(membershipRecords.filter { $0.userID == userID }.map(\.pairSpaceID))
            guard
                let pairRecord = pairSpaceRecords.first(where: { pairSpaceIDs.contains($0.id) && $0.endedAt == nil }),
                let pairSpace = pairRecord.domainModel(
                    memberships: membershipRecords.filter { $0.pairSpaceID == pairRecord.id }
                ),
                let sharedSpaceRecord = spaceRecords.first(where: { $0.id == pairRecord.sharedSpaceID })
            else {
                return nil
            }

            let partnerMembership = membershipRecords.first { $0.pairSpaceID == pairRecord.id && $0.userID != userID }
            let partner = partnerMembership.map {
                User(
                    id: $0.userID,
                    appleUserID: nil,
                    displayName: $0.nickname,
                    avatarSystemName: $0.avatarSystemName ?? "person.crop.circle.fill",
                    avatarPhotoFileName: $0.avatarPhotoFileName,
                    createdAt: $0.joinedAt,
                    updatedAt: $0.joinedAt,
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
        }()

        let availableModes: [AppMode] = pairSummary == nil ? [.single] : [.single, .pair]
        return SpaceContext(
            singleSpace: singleSpace,
            pairSpaceSummary: pairSummary,
            activeMode: .single,
            availableModes: availableModes
        )
    }

    func createSingleSpace(for userID: UUID) async throws -> Space {
        let context = ModelContext(container)
        let now = Date.now
        let space = Space(
            id: UUID(),
            type: .single,
            displayName: "我的空间",
            ownerUserID: userID,
            status: .active,
            createdAt: now,
            updatedAt: now
        )
        context.insert(PersistentSpace(space: space))
        try context.save()
        return space
    }
}
