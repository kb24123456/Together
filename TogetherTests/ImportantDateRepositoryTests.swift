import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("LocalImportantDateRepository")
struct ImportantDateRepositoryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self,
            PersistentTaskList.self, PersistentProject.self,
            PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self, PersistentSyncChange.self,
            PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }

    private func sampleEvent(spaceID: UUID = UUID()) -> ImportantDate {
        ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: UUID(),
            kind: .custom, title: "Test", dateValue: .now,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: nil, presetHolidayID: nil, updatedAt: .now
        )
    }

    @Test("save new event then fetchAll returns it")
    func saveAndFetch() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        let event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.count == 1)
        #expect(events.first?.id == event.id)
    }

    @Test("update existing event replaces fields")
    func updateExisting() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        var event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        event.title = "Updated"
        event.updatedAt = .now
        try await repo.save(event)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.count == 1)
        #expect(events.first?.title == "Updated")
    }

    @Test("delete tombstones the row (invisible to fetchAll)")
    func tombstone() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        let event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        try await repo.delete(id: event.id)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.isEmpty)
    }

    @Test("fetchAll scopes by spaceID")
    func spaceScoping() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceA = UUID()
        let spaceB = UUID()
        try await repo.save(sampleEvent(spaceID: spaceA))
        try await repo.save(sampleEvent(spaceID: spaceB))
        let eventsA = try await repo.fetchAll(spaceID: spaceA)
        let eventsB = try await repo.fetchAll(spaceID: spaceB)
        #expect(eventsA.count == 1)
        #expect(eventsB.count == 1)
    }
}
