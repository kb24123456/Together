import Testing
import Foundation
import SwiftData
@testable import Together

// MARK: - Capturing writer

private final class CapturingImportantDateWriter: ImportantDateWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var _captured: [ImportantDateDTO] = []
    var capturedDTOs: [ImportantDateDTO] {
        lock.lock(); defer { lock.unlock() }
        return _captured
    }
    func upsert(dto: ImportantDateDTO) async throws {
        lock.lock()
        _captured.append(dto)
        lock.unlock()
    }
}

// MARK: - Test helpers

private func makeInMemoryContainer() throws -> ModelContainer {
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

private func seedImportantDate(
    in container: ModelContainer,
    id: UUID,
    spaceID: UUID,
    title: String = "Test Birthday",
    kind: String = "birthday"
) throws {
    let context = ModelContext(container)
    context.insert(PersistentImportantDate(
        id: id,
        spaceID: spaceID,
        creatorID: UUID(),
        kindRawValue: kind,
        memberUserID: nil,
        title: title,
        dateValue: Date(timeIntervalSince1970: 1_700_000_000),
        recurrenceRawValue: "solarAnnual",
        notifyDaysBefore: 7,
        notifyOnDay: true,
        icon: "gift.fill",
        isPresetHoliday: false,
        presetHolidayIDRawValue: nil,
        createdAt: .now,
        updatedAt: .now
    ))
    try context.save()
}

// MARK: - Tests

@Suite("ImportantDate push")
struct ImportantDatePushTests {

    @Test("pushUpsert captures DTO with correct id/title/kind")
    func pushUpsertCallsWriter() async throws {
        let container = try makeInMemoryContainer()
        let writer = CapturingImportantDateWriter()
        let sut = SupabaseSyncService(
            modelContainer: container,
            avatarUploader: MockAvatarStorageUploader(),
            importantDateWriter: writer
        )
        let spaceID = UUID()
        let recordID = UUID()
        await sut.configure(spaceID: spaceID, myUserID: UUID(), myLocalUserID: UUID())
        try seedImportantDate(in: container, id: recordID, spaceID: spaceID, title: "妈生日")

        try await sut.pushUpsert(
            SyncChange(entityKind: .importantDate, operation: .upsert, recordID: recordID, spaceID: spaceID)
        )

        #expect(writer.capturedDTOs.count == 1)
        let dto = writer.capturedDTOs.first
        #expect(dto?.id == recordID)
        #expect(dto?.title == "妈生日")
        #expect(dto?.kind == "birthday")
        #expect(dto?.isRecurring == true)
        #expect(dto?.recurrenceRule == "solar_annual")
    }

    @Test("pushUpsert with no local row is a no-op (logs warning)")
    func pushUpsertMissingLocal() async throws {
        let container = try makeInMemoryContainer()
        let writer = CapturingImportantDateWriter()
        let sut = SupabaseSyncService(
            modelContainer: container,
            avatarUploader: MockAvatarStorageUploader(),
            importantDateWriter: writer
        )
        let spaceID = UUID()
        await sut.configure(spaceID: spaceID, myUserID: UUID(), myLocalUserID: UUID())

        try await sut.pushUpsert(
            SyncChange(entityKind: .importantDate, operation: .upsert, recordID: UUID(), spaceID: spaceID)
        )

        #expect(writer.capturedDTOs.isEmpty)
    }
}
