import Testing
import Foundation
import SwiftData
@testable import Together

// MARK: - Stub ImportantDateReader

private final class StubImportantDateReader: ImportantDateReader, @unchecked Sendable {
    private let lock = NSLock()
    private var _rows: [ImportantDateDTO] = []

    func setRows(_ rows: [ImportantDateDTO]) {
        lock.lock(); defer { lock.unlock() }
        _rows = rows
    }

    func fetchRows(spaceID: UUID, since: String) async throws -> [ImportantDateDTO] {
        lock.lock(); defer { lock.unlock() }
        return _rows
    }
}

// MARK: - Harness

private final class ImportantDatePullHarness {
    let container: ModelContainer
    let sut: SupabaseSyncService
    let reader: StubImportantDateReader
    let spaceID: UUID

    init() async throws {
        self.spaceID = UUID()
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(
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
        let reader = StubImportantDateReader()
        self.reader = reader
        self.sut = SupabaseSyncService(
            modelContainer: container,
            avatarUploader: MockAvatarStorageUploader(),
            importantDateReader: reader
        )
        await sut.configure(spaceID: spaceID, myUserID: UUID(), myLocalUserID: UUID())
    }

    func localRows() throws -> [PersistentImportantDate] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<PersistentImportantDate>())
    }
}

private func makeDTO(
    id: UUID = UUID(),
    spaceID: UUID,
    title: String = "Test",
    updatedAt: Date = .now,
    isDeleted: Bool = false
) -> ImportantDateDTO {
    ImportantDateDTO(
        id: id,
        spaceId: spaceID,
        creatorId: UUID(),
        kind: "custom",
        title: title,
        dateValue: Date(timeIntervalSince1970: 1_700_000_000),
        isRecurring: true,
        recurrenceRule: "solar_annual",
        notifyDaysBefore: 7,
        notifyOnDay: true,
        icon: nil,
        memberUserId: nil,
        isPresetHoliday: false,
        presetHolidayId: nil,
        createdAt: .now,
        updatedAt: updatedAt,
        isDeleted: isDeleted,
        deletedAt: isDeleted ? .now : nil
    )
}

// MARK: - Tests

@Suite("ImportantDate pull")
struct ImportantDatePullTests {

    @Test("pull inserts new rows into local store")
    func pullInserts() async throws {
        let h = try await ImportantDatePullHarness()
        let id = UUID()
        h.reader.setRows([makeDTO(id: id, spaceID: h.spaceID, title: "新建")])

        try await h.sut.pullImportantDatesForTesting(spaceID: h.spaceID)

        let rows = try h.localRows()
        #expect(rows.count == 1)
        #expect(rows.first?.id == id)
        #expect(rows.first?.title == "新建")
    }

    @Test("pull updates existing when remote updated_at is newer")
    func pullUpdates() async throws {
        let h = try await ImportantDatePullHarness()
        let id = UUID()

        // Seed existing row with old updatedAt
        let ctx = ModelContext(h.container)
        ctx.insert(PersistentImportantDate(
            id: id,
            spaceID: h.spaceID,
            creatorID: UUID(),
            kindRawValue: "custom",
            title: "旧",
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            recurrenceRawValue: "solarAnnual",
            notifyDaysBefore: 7,
            notifyOnDay: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try ctx.save()

        h.reader.setRows([makeDTO(
            id: id,
            spaceID: h.spaceID,
            title: "新",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )])

        try await h.sut.pullImportantDatesForTesting(spaceID: h.spaceID)

        let rows = try h.localRows()
        #expect(rows.count == 1)
        #expect(rows.first?.title == "新")
    }

    @Test("pull marks tombstone when remote is_deleted=true")
    func pullTombstones() async throws {
        let h = try await ImportantDatePullHarness()
        let id = UUID()

        let ctx = ModelContext(h.container)
        ctx.insert(PersistentImportantDate(
            id: id,
            spaceID: h.spaceID,
            creatorID: UUID(),
            kindRawValue: "custom",
            title: "to delete",
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            recurrenceRawValue: "none",
            notifyDaysBefore: 7,
            notifyOnDay: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try ctx.save()

        h.reader.setRows([makeDTO(
            id: id,
            spaceID: h.spaceID,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isDeleted: true
        )])

        try await h.sut.pullImportantDatesForTesting(spaceID: h.spaceID)

        let rows = try h.localRows()
        #expect(rows.count == 1)
        #expect(rows.first?.isLocallyDeleted == true)
    }
}
