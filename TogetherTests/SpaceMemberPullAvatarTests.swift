import Testing
import Foundation
import SwiftData
@testable import Together

// MARK: - In-memory avatar media store (pull tests)

private final class InMemoryAvatarMediaStore: UserAvatarMediaStoreProtocol, @unchecked Sendable {
    struct Saved { let fileName: String; let data: Data }
    private let lock = NSLock()
    private var _saved: [Saved] = []
    private let onPersist: (@Sendable (String) -> Void)?

    /// Stream that emits a fileName each time `persistAvatarData` is called.
    let persistedStream: AsyncStream<String>
    private let persistedContinuation: AsyncStream<String>.Continuation

    init(onPersist: (@Sendable (String) -> Void)? = nil) {
        self.onPersist = onPersist
        var cont: AsyncStream<String>.Continuation!
        self.persistedStream = AsyncStream { cont = $0 }
        self.persistedContinuation = cont
    }

    var savedFiles: [Saved] {
        lock.lock(); defer { lock.unlock() }
        return _saved
    }

    nonisolated func canonicalFileName(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())-avatar.jpg"
    }

    nonisolated func cacheFileName(for assetID: String) -> String {
        UserAvatarStorage.fileName(forAssetID: assetID)
    }

    nonisolated func partnerCacheFileName(for assetID: String, version: Int) -> String {
        UserAvatarStorage.partnerFileName(forAssetID: assetID, version: version)
    }

    nonisolated func avatarData(named fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let saved = _saved.first(where: { $0.fileName == fileName }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return saved.data
    }

    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws {
        lock.lock()
        _saved.append(Saved(fileName: fileName, data: data))
        lock.unlock()
        persistedContinuation.yield(fileName)
        onPersist?(fileName)
    }

    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws {}

    nonisolated func removeAvatar(named fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        _saved.removeAll { $0.fileName == fileName }
    }

    nonisolated func fileExists(named fileName: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _saved.contains { $0.fileName == fileName }
    }
}

// MARK: - Stub SpaceMemberReader

private final class StubSpaceMemberReader: SpaceMemberReader, @unchecked Sendable {
    private let lock = NSLock()
    private var _rows: [SpaceMemberDTO] = []

    func setRows(_ rows: [SpaceMemberDTO]) {
        lock.lock(); defer { lock.unlock() }
        _rows = rows
    }

    func fetchMembers(spaceID: UUID, since: String) async throws -> [SpaceMemberDTO] {
        lock.lock(); defer { lock.unlock() }
        return _rows
    }
}

// MARK: - PullTestHarness

private final class PullTestHarness {
    let container: ModelContainer
    let sut: SupabaseSyncService
    let store: InMemoryAvatarMediaStore
    let reader: StubSpaceMemberReader

    let spaceID: UUID
    let mySupabaseUserID: UUID
    let myLocalUserID: UUID
    let partnerSupabaseUserID: UUID
    let partnerLocalUserID: UUID
    let pairSpaceLocalID: UUID

    init(uploader: MockAvatarStorageUploader, store: InMemoryAvatarMediaStore) async throws {
        self.store = store
        self.spaceID = UUID()
        self.mySupabaseUserID = UUID()
        self.myLocalUserID = UUID()
        self.partnerSupabaseUserID = UUID()
        self.partnerLocalUserID = UUID()
        self.pairSpaceLocalID = UUID()

        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )

        let reader = StubSpaceMemberReader()
        self.reader = reader

        self.sut = SupabaseSyncService(
            modelContainer: container,
            avatarUploader: uploader,
            avatarMediaStore: store,
            spaceMemberReader: reader
        )
        await sut.configure(
            spaceID: spaceID,
            myUserID: mySupabaseUserID,
            myLocalUserID: myLocalUserID
        )

        // Seed a PersistentPairSpace so pullSpaceMembers can find it
        let ctx = ModelContext(container)
        let pairSpace = PersistentPairSpace(
            id: pairSpaceLocalID,
            sharedSpaceID: spaceID,
            statusRawValue: "active",
            createdAt: .now,
            activatedAt: .now,
            endedAt: nil
        )
        ctx.insert(pairSpace)

        // Seed my own membership (excluded by myLocalUserID)
        let myMembership = PersistentPairMembership(
            id: UUID(),
            pairSpaceID: pairSpaceLocalID,
            userID: myLocalUserID,
            nickname: "Me",
            joinedAt: .now
        )
        ctx.insert(myMembership)
        try ctx.save()
    }

    func seedPartnerMembership(avatarVersion: Int, avatarAssetID: String?) throws {
        let ctx = ModelContext(container)
        let membership = PersistentPairMembership(
            id: UUID(),
            pairSpaceID: pairSpaceLocalID,
            userID: partnerLocalUserID,
            nickname: "Partner",
            joinedAt: .now,
            avatarAssetID: avatarAssetID,
            avatarVersion: avatarVersion
        )
        ctx.insert(membership)
        try ctx.save()
    }

    func setRemoteRow(
        avatarVersion: Int,
        avatarURL: String?,
        avatarAssetID: String?,
        avatarSystemName: String?
    ) {
        let dto = SpaceMemberDTO(
            id: UUID(),
            spaceId: spaceID,
            userId: partnerSupabaseUserID,
            displayName: "Partner",
            avatarUrl: avatarURL,
            avatarAssetID: avatarAssetID,
            avatarSystemName: avatarSystemName,
            avatarVersion: avatarVersion,
            role: nil,
            joinedAt: nil,
            updatedAt: nil
        )
        reader.setRows([dto])
    }

    func runPullSpaceMembers() async throws {
        try await sut.pullSpaceMembersForTesting(spaceID: spaceID)
    }

    func loadPartnerMembership() throws -> PersistentPairMembership {
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<PersistentPairMembership>())
        guard let partner = all.first(where: { $0.userID == partnerLocalUserID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return partner
    }
}

// MARK: - Tests

@Suite("Space member pull — avatar")
struct SpaceMemberPullAvatarTests {

    @Test("Pull downloads bytes when remote version > local")
    func pullDownloadsBytesOnVersionBump() async throws {
        let uploader = MockAvatarStorageUploader()
        uploader.stubbedDownloadBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])

        let store = InMemoryAvatarMediaStore()
        let harness = try await PullTestHarness(uploader: uploader, store: store)
        try harness.seedPartnerMembership(avatarVersion: 1, avatarAssetID: "asset-old")
        harness.setRemoteRow(
            avatarVersion: 3,
            avatarURL: "https://example.test/sig.jpg",
            avatarAssetID: "asset-new",
            avatarSystemName: nil
        )

        try await harness.runPullSpaceMembers()

        let partner = try harness.loadPartnerMembership()
        #expect(partner.avatarVersion == 3)
        #expect(partner.avatarAssetID == "asset-new")
        let expected = store.partnerCacheFileName(for: "asset-new", version: 3)
        #expect(partner.avatarPhotoFileName == expected)

        // Await the detached download by consuming from the async stream
        var persistedFileName: String?
        for await fileName in store.persistedStream.prefix(1) {
            persistedFileName = fileName
        }
        #expect(persistedFileName == expected)
        #expect(store.savedFiles.contains { $0.fileName == expected })
    }

    @Test("Pull skips download when remote version == local && asset_id unchanged")
    func pullSkipsWhenFullyInSync() async throws {
        let uploader = MockAvatarStorageUploader()
        let store = InMemoryAvatarMediaStore()
        let harness = try await PullTestHarness(uploader: uploader, store: store)
        try harness.seedPartnerMembership(avatarVersion: 5, avatarAssetID: "asset-same")
        harness.setRemoteRow(
            avatarVersion: 5,
            avatarURL: "https://example.test/any.jpg",
            avatarAssetID: "asset-same",
            avatarSystemName: nil
        )

        try await harness.runPullSpaceMembers()

        try await Task.sleep(for: .milliseconds(300))
        #expect(store.savedFiles.isEmpty)
        let partner = try harness.loadPartnerMembership()
        #expect(partner.avatarAssetID == "asset-same")
        #expect(partner.avatarVersion == 5)
    }

    @Test("Pull refreshes when remote version regresses (reinstall scenario)")
    func pullRefreshesOnVersionRegression() async throws {
        let uploader = MockAvatarStorageUploader()
        uploader.stubbedDownloadBytes = Data([0xAA, 0xBB])
        let store = InMemoryAvatarMediaStore()
        let harness = try await PullTestHarness(uploader: uploader, store: store)
        try harness.seedPartnerMembership(avatarVersion: 6, avatarAssetID: "asset-same")
        harness.setRemoteRow(
            avatarVersion: 2,
            avatarURL: "https://example.test/regressed.jpg",
            avatarAssetID: "asset-same",
            avatarSystemName: nil
        )

        try await harness.runPullSpaceMembers()

        let partner = try harness.loadPartnerMembership()
        #expect(partner.avatarVersion == 2)
        let expected = store.partnerCacheFileName(for: "asset-same", version: 2)
        #expect(partner.avatarPhotoFileName == expected)

        var persisted: String?
        for await name in store.persistedStream.prefix(1) { persisted = name }
        #expect(persisted == expected)
    }

    @Test("Pull refreshes when remote version equal but asset_id differs")
    func pullOnAssetIdChangeAtSameVersion() async throws {
        let uploader = MockAvatarStorageUploader()
        let store = InMemoryAvatarMediaStore()
        let harness = try await PullTestHarness(uploader: uploader, store: store)
        try harness.seedPartnerMembership(avatarVersion: 3, avatarAssetID: "asset-a")
        harness.setRemoteRow(
            avatarVersion: 3,
            avatarURL: "https://example.test/b.jpg",
            avatarAssetID: "asset-b",
            avatarSystemName: nil
        )

        try await harness.runPullSpaceMembers()

        let partner = try harness.loadPartnerMembership()
        #expect(partner.avatarAssetID == "asset-b")
    }
}
