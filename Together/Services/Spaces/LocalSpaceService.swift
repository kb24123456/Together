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

        let activeSingleSpaceRecords = spaceRecords.filter {
            $0.typeRawValue == SpaceType.single.rawValue && $0.statusRawValue != SpaceStatus.archived.rawValue
        }
        let dataBearingSpaceIDs = Self.dataBearingSingleSpaceIDs(in: context)
        let selectedSingleSpaceRecord = activeSingleSpaceRecords.first { dataBearingSpaceIDs.contains($0.id) }
            ?? userID.flatMap { currentUserID in
                activeSingleSpaceRecords.first { $0.ownerUserID == currentUserID }
            }
            ?? activeSingleSpaceRecords.first

        if let selectedSingleSpaceRecord, let userID {
            Self.claimSingleSpaceIfNeeded(selectedSingleSpaceRecord, for: userID, context: context)
        }

        let singleSpace = selectedSingleSpaceRecord?.domainModel

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

    private static func dataBearingSingleSpaceIDs(in context: ModelContext) -> Set<UUID> {
        var spaceIDs = Set<UUID>()

        let items = (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? []
        for item in items where item.isLocallyDeleted == false && item.isArchived == false {
            if let spaceID = item.spaceID {
                spaceIDs.insert(spaceID)
            }
        }

        let lists = (try? context.fetch(FetchDescriptor<PersistentTaskList>())) ?? []
        for list in lists where list.isLocallyDeleted == false && list.isArchived == false {
            spaceIDs.insert(list.spaceID)
        }

        let projects = (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? []
        for project in projects where project.isLocallyDeleted == false {
            spaceIDs.insert(project.spaceID)
        }

        let periodicTasks = (try? context.fetch(FetchDescriptor<PersistentPeriodicTask>())) ?? []
        for task in periodicTasks where task.isLocallyDeleted == false && task.isActive {
            if let spaceID = task.spaceID {
                spaceIDs.insert(spaceID)
            }
        }

        return spaceIDs
    }

    private static func claimSingleSpaceIfNeeded(
        _ space: PersistentSpace,
        for userID: UUID,
        context: ModelContext
    ) {
        let oldOwnerID = space.ownerUserID
        guard oldOwnerID != userID else { return }

        space.ownerUserID = userID
        space.updatedAt = .now

        let items = (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? []
        for item in items where item.spaceID == space.id && item.creatorID == oldOwnerID {
            item.creatorID = userID
        }

        let lists = (try? context.fetch(FetchDescriptor<PersistentTaskList>())) ?? []
        for list in lists where list.spaceID == space.id && list.creatorID == oldOwnerID {
            list.creatorID = userID
        }

        let projects = (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? []
        var projectIDs = Set<UUID>()
        for project in projects where project.spaceID == space.id {
            projectIDs.insert(project.id)
            if project.creatorID == oldOwnerID {
                project.creatorID = userID
            }
        }

        let subtasks = (try? context.fetch(FetchDescriptor<PersistentProjectSubtask>())) ?? []
        for subtask in subtasks where projectIDs.contains(subtask.projectID) && subtask.creatorID == oldOwnerID {
            subtask.creatorID = userID
        }

        let periodicTasks = (try? context.fetch(FetchDescriptor<PersistentPeriodicTask>())) ?? []
        for task in periodicTasks where task.spaceID == space.id && task.creatorID == oldOwnerID {
            task.creatorID = userID
        }

        try? context.save()
    }
}
