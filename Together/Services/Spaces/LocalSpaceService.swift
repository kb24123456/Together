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

        var singleSpace = spaceRecords
            .map(\.domainModel)
            .first { space in
                guard space.type == .single, space.status != .archived else { return false }
                guard let userID else { return true }
                return space.ownerUserID == userID
            }

        // If no matching single space found but an orphaned single space exists,
        // claim it for the current user (fixes seed-data ownerUserID mismatch).
        if singleSpace == nil, let userID {
            if let orphanedRecord = spaceRecords.first(where: {
                $0.domainModel.type == .single && $0.domainModel.status != .archived
            }) {
                orphanedRecord.ownerUserID = userID
                orphanedRecord.updatedAt = .now
                try? context.save()
                singleSpace = orphanedRecord.domainModel
            }
        }

        let pairSummary = userID.flatMap {
            PairSpaceSummaryResolver.resolve(
                for: $0,
                spaces: spaceRecords,
                pairSpaces: pairSpaceRecords,
                memberships: membershipRecords
            )
        }

        let availableModes: [AppMode] = pairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
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
