import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct ImportantDatesViewModelCapsuleTests {
    @Test func loadKeepsStoredRecordsAndPublishesEvents() async {
        let spaceID = UUID()
        let creatorID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 100)
        let anniversary = makeEvent(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            kind: .anniversary,
            title: "Capsule anchor",
            showsElapsedDays: true
        )
        let custom = makeEvent(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            kind: .custom,
            title: "Secondary date",
            showsElapsedDays: false
        )
        let records = [
            ImportantDateStoredRecord(event: anniversary, createdAt: createdAt),
            ImportantDateStoredRecord(event: custom, createdAt: createdAt.addingTimeInterval(60))
        ]
        let repository = StoredRecordsSpyRepository(records: records)
        let viewModel = ImportantDatesViewModel(
            sessionStore: SessionStore(),
            premiumGate: makePremiumGate(),
            repository: repository
        )

        viewModel.configure(spaceID: spaceID)
        await viewModel.load()

        #expect(await repository.fetchAllStoredRecordsCallCount == 1)
        #expect(await repository.fetchAllCallCount == 0)
        #expect(viewModel.storedRecords == records)
        #expect(viewModel.events == records.map(\.event))
    }

    private func makeEvent(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID,
        kind: ImportantDateKind,
        title: String,
        showsElapsedDays: Bool
    ) -> ImportantDate {
        ImportantDate(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            kind: kind,
            title: title,
            dateValue: Date(timeIntervalSinceReferenceDate: 50),
            recurrence: .solarAnnual,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            showsElapsedDays: showsElapsedDays,
            updatedAt: Date(timeIntervalSinceReferenceDate: 75)
        )
    }

    private func makePremiumGate() -> PremiumGate {
        let dateProvider = SystemDateProvider()
        return PremiumGate(
            rcClient: StubRCClient(),
            grantsLoader: StubGrantsLoader(),
            cache: PremiumStatusCache(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                dateProvider: dateProvider
            ),
            dateProvider: dateProvider
        )
    }
}

private actor StoredRecordsSpyRepository: ImportantDateRepositoryProtocol {
    private let records: [ImportantDateStoredRecord]
    private(set) var fetchAllCallCount = 0
    private(set) var fetchAllStoredRecordsCallCount = 0

    init(records: [ImportantDateStoredRecord]) {
        self.records = records
    }

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        fetchAllCallCount += 1
        return [
            ImportantDate(
                id: UUID(),
                spaceID: spaceID,
                creatorID: UUID(),
                kind: .custom,
                title: "Wrong source",
                dateValue: Date(),
                recurrence: .none,
                notifyDaysBefore: 7,
                notifyOnDay: true,
                icon: nil,
                presetHolidayID: nil,
                updatedAt: Date()
            )
        ]
    }

    func fetchAllStoredRecords(spaceID _: UUID) async throws -> [ImportantDateStoredRecord] {
        fetchAllStoredRecordsCallCount += 1
        return records
    }

    func fetch(id _: UUID) async throws -> ImportantDate? {
        nil
    }

    func save(_ event: ImportantDate) async throws {}

    func delete(id: UUID) async throws {}

    func hardDelete(id: UUID) async throws {}
}
