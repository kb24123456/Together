import Testing
import SwiftData
import Foundation
@testable import Together

/// Regression for the orphan-data bug observed during E2E:
/// after pair unbind, rows scoped to the old shared-space id were left behind,
/// so when a fresh pair created a new space id the UI saw an empty list.
/// These tests seed two independent pair spaces, call unbind on the first,
/// and assert only the unbinding space's rows are purged.
@Suite("LocalPairingService.unbind isolation")
struct LocalPairingServiceUnbindIsolationTests {

    @Test("current context prefers latest active pair over stale pending residue")
    @MainActor
    func currentContextPrefersLatestActivePair() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pairingService = LocalPairingService(container: persistence.container)
        let currentUserID = UUID()
        let oldPartnerID = UUID()
        let currentPartnerID = UUID()
        let oldPairSpaceID = UUID()
        let oldSharedSpaceID = UUID()
        let currentPairSpaceID = UUID()
        let currentSharedSpaceID = UUID()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let currentDate = oldDate.addingTimeInterval(3600)

        let context = ModelContext(persistence.container)
        context.insert(PersistentSpace(
            id: oldSharedSpaceID,
            typeRawValue: SpaceType.pair.rawValue,
            displayName: "旧双人空间",
            ownerUserID: oldPartnerID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: oldDate,
            updatedAt: oldDate,
            archivedAt: nil
        ))
        context.insert(PersistentPairSpace(
            id: oldPairSpaceID,
            sharedSpaceID: oldSharedSpaceID,
            statusRawValue: PairSpaceStatus.pendingAcceptance.rawValue,
            createdAt: oldDate,
            activatedAt: nil,
            endedAt: nil
        ))
        context.insert(PersistentPairMembership(
            pairSpaceID: oldPairSpaceID,
            userID: currentUserID,
            nickname: "Me",
            joinedAt: oldDate
        ))
        context.insert(PersistentPairMembership(
            pairSpaceID: oldPairSpaceID,
            userID: oldPartnerID,
            nickname: "Old Partner",
            joinedAt: oldDate
        ))

        context.insert(PersistentSpace(
            id: currentSharedSpaceID,
            typeRawValue: SpaceType.pair.rawValue,
            displayName: "当前双人空间",
            ownerUserID: currentUserID,
            statusRawValue: SpaceStatus.active.rawValue,
            createdAt: currentDate,
            updatedAt: currentDate,
            archivedAt: nil
        ))
        context.insert(PersistentPairSpace(
            id: currentPairSpaceID,
            sharedSpaceID: currentSharedSpaceID,
            statusRawValue: PairSpaceStatus.active.rawValue,
            createdAt: currentDate,
            activatedAt: currentDate,
            endedAt: nil
        ))
        context.insert(PersistentPairMembership(
            pairSpaceID: currentPairSpaceID,
            userID: currentUserID,
            nickname: "Me",
            joinedAt: currentDate
        ))
        context.insert(PersistentPairMembership(
            pairSpaceID: currentPairSpaceID,
            userID: currentPartnerID,
            nickname: "Current Partner",
            joinedAt: currentDate
        ))
        try context.save()

        let pairingContext = await pairingService.currentPairingContext(for: currentUserID)

        #expect(pairingContext.state == .paired)
        #expect(pairingContext.pairSpaceSummary?.pairSpace.id == currentPairSpaceID)
        #expect(pairingContext.pairSpaceSummary?.sharedSpace.id == currentSharedSpaceID)
        #expect(pairingContext.pairSpaceSummary?.partner?.id == currentPartnerID)
    }

    @Test("unbind purges all pair-scoped entities for the leaving space only")
    @MainActor
    func unbindPurgesOnlyTargetSpace() async throws {
        let persistence = PersistenceController(inMemory: true)
        let pairingService = LocalPairingService(container: persistence.container)
        let actorID = UUID()

        let seedA = try await seedPairSpace(
            service: pairingService,
            persistence: persistence,
            actorID: actorID
        )
        let seedB = try await seedPairSpace(
            service: pairingService,
            persistence: persistence,
            actorID: UUID()
        )

        _ = try await pairingService.unbind(pairSpaceID: seedA.pairSpaceID, actorID: actorID)

        let context = ModelContext(persistence.container)

        let spaceA = seedA.sharedSpaceID
        let spaceB = seedB.sharedSpaceID

        #expect(try context.fetch(FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.spaceID == spaceA }
        )).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentItem>(
            predicate: #Predicate { $0.spaceID == spaceA }
        )).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate { $0.spaceID == spaceA }
        )).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentProject>(
            predicate: #Predicate { $0.spaceID == spaceA }
        )).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate { $0.spaceID == spaceA }
        )).isEmpty)

        let itemA = seedA.itemID
        #expect(try context.fetch(FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate { $0.taskID == itemA }
        )).isEmpty)

        #expect(try context.fetch(FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.spaceID == spaceB }
        )).count == 1)
        #expect(try context.fetch(FetchDescriptor<PersistentItem>(
            predicate: #Predicate { $0.spaceID == spaceB }
        )).count == 1)
        #expect(try context.fetch(FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate { $0.spaceID == spaceB }
        )).count == 1)
        #expect(try context.fetch(FetchDescriptor<PersistentProject>(
            predicate: #Predicate { $0.spaceID == spaceB }
        )).count == 1)
        #expect(try context.fetch(FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate { $0.spaceID == spaceB }
        )).count == 1)

        let itemB = seedB.itemID
        #expect(try context.fetch(FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate { $0.taskID == itemB }
        )).count == 1)
    }

    // MARK: - Seeding helpers

    private struct SeededSpace {
        let pairSpaceID: UUID
        let sharedSpaceID: UUID
        let itemID: UUID
    }

    private func seedPairSpace(
        service: LocalPairingService,
        persistence: PersistenceController,
        actorID: UUID
    ) async throws -> SeededSpace {
        _ = try await service.createInvite(from: actorID, displayName: "Tester")
        let ctx = await service.currentPairingContext(for: actorID)
        let pairSpaceID = try #require(ctx.pairSpaceSummary?.pairSpace.id)
        let sharedSpaceID = try #require(ctx.pairSpaceSummary?.sharedSpace.id)

        let modelContext = ModelContext(persistence.container)
        let itemID = UUID()
        modelContext.insert(PersistentImportantDate(
            id: UUID(),
            spaceID: sharedSpaceID,
            creatorID: actorID,
            kindRawValue: "anniversary",
            title: "纪念日-\(sharedSpaceID.uuidString.prefix(4))",
            dateValue: .now,
            recurrenceRawValue: "yearly"
        ))
        modelContext.insert(PersistentItem(item: Item(
            id: itemID,
            spaceID: sharedSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "共享任务",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .both,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .accepted,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )))
        modelContext.insert(PersistentTaskList(list: TaskList(
            id: UUID(),
            spaceID: sharedSpaceID,
            creatorID: actorID,
            name: "共享清单",
            kind: .custom,
            colorToken: nil,
            sortOrder: 0,
            isArchived: false,
            taskCount: 0,
            createdAt: .now,
            updatedAt: .now
        )))
        modelContext.insert(PersistentProject(project: Project(
            id: UUID(),
            spaceID: sharedSpaceID,
            creatorID: actorID,
            name: "共享项目",
            notes: nil,
            colorToken: nil,
            status: .active,
            targetDate: nil,
            remindAt: nil,
            taskCount: 0,
            subtasks: [],
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil
        )))
        modelContext.insert(PersistentPeriodicTask(task: PeriodicTask(
            id: UUID(),
            spaceID: sharedSpaceID,
            creatorID: actorID,
            title: "共享周期任务",
            notes: nil,
            cycle: .weekly,
            reminderRules: [],
            completions: [],
            sortOrder: 0,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )))
        modelContext.insert(PersistentTaskMessage(message: TaskMessage(
            id: UUID(),
            taskID: itemID,
            senderID: actorID,
            type: "nudge",
            createdAt: .now
        )))
        try modelContext.save()

        return SeededSpace(
            pairSpaceID: pairSpaceID,
            sharedSpaceID: sharedSpaceID,
            itemID: itemID
        )
    }

}
