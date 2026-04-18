import Testing
import Foundation
import SwiftData
@testable import Together

// MARK: - In-memory avatar media store

private final class InMemoryAvatarMediaStore: UserAvatarMediaStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    nonisolated func canonicalFileName(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())-avatar.jpg"
    }

    nonisolated func cacheFileName(for assetID: String) -> String {
        "asset-\(assetID.lowercased()).jpg"
    }

    nonisolated func partnerCacheFileName(for assetID: String, version: Int) -> String {
        "asset-\(assetID.lowercased())-v\(version).jpg"
    }

    nonisolated func avatarData(named fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = storage[fileName] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[fileName] = data
    }

    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let data = storage[sourceFileName] else { return }
        storage[destinationFileName] = data
        storage.removeValue(forKey: sourceFileName)
    }

    nonisolated func removeAvatar(named fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: fileName)
    }

    nonisolated func fileExists(named fileName: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[fileName] != nil
    }
}

// MARK: - Capturing SpaceMemberWriter

final class CapturingSpaceMemberWriter: SpaceMemberWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var _captured: [SpaceMemberUpdateDTO] = []
    var capturedDTOs: [SpaceMemberUpdateDTO] {
        lock.lock(); defer { lock.unlock() }
        return _captured
    }

    func updateMember(spaceID: UUID, userID: UUID, dto: SpaceMemberUpdateDTO) async throws {
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
        configurations: config
    )
}

/// Builds a SupabaseSyncService wired for push tests with mock uploader, capturing writer, and in-memory media store.
/// Returns (sut, mediaStore) so the caller can seed avatar bytes independently.
private func makeSyncServiceForPushTests(
    uploader: MockAvatarStorageUploader,
    writer: CapturingSpaceMemberWriter,
    userID: UUID,
    spaceID: UUID,
    mySupabaseUserID: UUID? = nil
) async throws -> (sut: SupabaseSyncService, mediaStore: InMemoryAvatarMediaStore) {
    let container = try makeInMemoryContainer()
    let mediaStore = InMemoryAvatarMediaStore()
    let sut = SupabaseSyncService(
        modelContainer: container,
        avatarUploader: uploader,
        avatarMediaStore: mediaStore,
        spaceMemberWriter: writer
    )
    // Configure synchronously on the actor so .memberProfile push can resolve myUserID.
    let supabaseUserID = mySupabaseUserID ?? userID
    await sut.configure(spaceID: spaceID, myUserID: supabaseUserID, myLocalUserID: userID)
    return (sut, mediaStore)
}

/// Seeds a PersistentUserProfile and optional avatar bytes into the service's ModelContainer.
private func seedProfile(
    in container: ModelContainer,
    mediaStore: InMemoryAvatarMediaStore,
    userID: UUID,
    avatarAssetID: String?,
    avatarPhotoFileName: String?,
    avatarSystemName: String?,
    avatarVersion: Int,
    avatarBytes: Data?
) throws {
    let context = ModelContext(container)
    let profile = PersistentUserProfile(
        userID: userID,
        displayName: "Test User",
        avatarSystemName: avatarSystemName,
        avatarPhotoFileName: avatarPhotoFileName,
        avatarAssetID: avatarAssetID,
        avatarVersion: avatarVersion,
        avatarPhotoData: nil,
        taskReminderEnabled: false,
        dailySummaryEnabled: false,
        calendarReminderEnabled: false,
        futureCollaborationInviteEnabled: false,
        taskUrgencyWindowMinutes: 30,
        defaultSnoozeMinutes: 15,
        quickTimePresetMinutes: [15, 30, 60],
        completedTaskAutoArchiveEnabled: false,
        completedTaskAutoArchiveDays: 7,
        updatedAt: .now
    )
    context.insert(profile)
    try context.save()

    if let fileName = avatarPhotoFileName, let bytes = avatarBytes {
        try mediaStore.persistAvatarData(bytes, fileName: fileName)
    }
}

// MARK: - Tests

@Suite("Avatar asset push")
struct AvatarAssetPushTests {

    @Test("avatarAsset then memberProfile uploads bytes and DTO carries signed URL")
    func avatarAssetThenMemberProfile() async throws {
        let uploader = MockAvatarStorageUploader()
        let writer = CapturingSpaceMemberWriter()
        let stubbedURL = URL(string: "https://example.test/avatars/signed.jpg?sig=xyz")!
        uploader.stubbedURL = stubbedURL

        let userID = UUID()
        let spaceID = UUID()
        // Asset UUID is what AppContext passes as recordID for .avatarAsset.
        let assetIDString = UUID().uuidString.lowercased()
        let assetUUID = UUID(uuidString: assetIDString)!

        let (sut, mediaStore) = try await makeSyncServiceForPushTests(
            uploader: uploader,
            writer: writer,
            userID: userID,
            spaceID: spaceID
        )
        try await seedProfile(
            in: sut.modelContainer,
            mediaStore: mediaStore,
            userID: userID,
            avatarAssetID: assetIDString,
            avatarPhotoFileName: "\(assetIDString).jpg",
            avatarSystemName: nil,
            avatarVersion: 5,
            avatarBytes: Data([0xFF, 0xD8, 0xFF])
        )

        try await sut.pushUpsert(
            SyncChange(entityKind: .avatarAsset, operation: .upsert, recordID: assetUUID, spaceID: spaceID)
        )
        #expect(uploader.uploads.count == 1)
        #expect(uploader.uploads.first?.version == 5)
        #expect(uploader.uploads.first?.spaceID == spaceID)
        #expect(uploader.uploads.first?.userID == userID)

        try await sut.pushUpsert(
            SyncChange(entityKind: .memberProfile, operation: .upsert, recordID: userID, spaceID: spaceID)
        )
        #expect(writer.capturedDTOs.count == 1)
        let dto = writer.capturedDTOs.first
        #expect(dto?.avatarUrl == stubbedURL.absoluteString)
        #expect(dto?.avatarAssetID == assetIDString)
        #expect(dto?.avatarSystemName == nil)
        #expect(dto?.avatarVersion == 5)
    }

    @Test("memberProfile alone sends nil avatar_url when no preceding avatarAsset push")
    func memberProfileWithoutAvatarAsset() async throws {
        let uploader = MockAvatarStorageUploader()
        let writer = CapturingSpaceMemberWriter()

        let userID = UUID()
        let spaceID = UUID()

        let (sut, mediaStore) = try await makeSyncServiceForPushTests(
            uploader: uploader,
            writer: writer,
            userID: userID,
            spaceID: spaceID
        )
        try await seedProfile(
            in: sut.modelContainer,
            mediaStore: mediaStore,
            userID: userID,
            avatarAssetID: nil,
            avatarPhotoFileName: nil,
            avatarSystemName: "person.circle.fill",
            avatarVersion: 2,
            avatarBytes: nil
        )

        try await sut.pushUpsert(
            SyncChange(entityKind: .memberProfile, operation: .upsert, recordID: userID, spaceID: spaceID)
        )
        #expect(writer.capturedDTOs.count == 1)
        let dto = writer.capturedDTOs.first
        #expect(dto?.avatarUrl == nil)
        #expect(dto?.avatarSystemName == "person.circle.fill")
        #expect(dto?.avatarVersion == 2)
    }
}
