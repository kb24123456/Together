import Testing
import Foundation
import SwiftData
@testable import Together

@Suite("LocalUserProfileRepository — hydrateFromRemote")
struct LocalUserProfileHydrateTests {

    @Test("hydrate writes a new PersistentUserProfile when none exists")
    func hydrateNewRecord() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = MockDataFactory.makeCurrentUser()

        let hydrated = try await repository.hydrateFromRemote(
            for: user,
            displayName: "Cloud Alice",
            avatarBytes: nil,
            avatarAssetID: nil,
            avatarSystemName: "person.crop.circle.fill",
            avatarVersion: 4
        )

        #expect(hydrated.displayName == "Cloud Alice")
        #expect(hydrated.avatarVersion == 4)
        #expect(hydrated.avatarSystemName == "person.crop.circle.fill")
        #expect(hydrated.avatarPhotoFileName == nil)

        // Verify it persisted (mergedUser reads back from SwiftData)
        let merged = try #require(await repository.mergedUser(user))
        #expect(merged.displayName == "Cloud Alice")
        #expect(merged.avatarVersion == 4)
    }

    @Test("hydrate overwrites existing record without bumping version")
    func hydrateExistingRecord() async throws {
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = MockDataFactory.makeCurrentUser()

        // Seed an existing local record at version 1
        _ = try await repository.saveProfile(
            for: user,
            displayName: "Local Stale",
            avatarUpdate: .preserveExisting
        )

        // Hydrate from cloud at version 5
        let hydrated = try await repository.hydrateFromRemote(
            for: user,
            displayName: "From Cloud",
            avatarBytes: nil,
            avatarAssetID: nil,
            avatarSystemName: nil,
            avatarVersion: 5
        )

        #expect(hydrated.displayName == "From Cloud")
        // Version is preserved verbatim — does NOT bump (key invariant: prevents
        // redundant push next sync cycle).
        #expect(hydrated.avatarVersion == 5)

        let merged = try #require(await repository.mergedUser(user))
        #expect(merged.displayName == "From Cloud")
        #expect(merged.avatarVersion == 5)
    }

    @Test("hydrate with avatar bytes writes file + updates record")
    func hydrateWithAvatarBytes() async throws {
        #if canImport(UIKit)
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = MockDataFactory.makeCurrentUser()
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x10, 0x20, 0x30, 0x40])
        let assetID = UUID().uuidString

        let hydrated = try await repository.hydrateFromRemote(
            for: user,
            displayName: "Has Avatar",
            avatarBytes: bytes,
            avatarAssetID: assetID,
            avatarSystemName: nil,
            avatarVersion: 2
        )

        #expect(hydrated.avatarAssetID == assetID)
        let fileName = try #require(hydrated.avatarPhotoFileName)
        #expect(fileName == LocalUserAvatarMediaStore().cacheFileName(for: assetID))
        #expect(
            FileManager.default.fileExists(
                atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
            )
        )
        #else
        Issue.record("UIKit unavailable for avatar bytes hydrate test")
        #endif
    }

    @Test("hydrate with nil avatar bytes clears local avatarPhotoFileName")
    func hydrateClearsAvatarWhenBytesNil() async throws {
        #if canImport(UIKit)
        let persistence = PersistenceController(inMemory: true)
        let repository = LocalUserProfileRepository(container: persistence.container)
        let user = MockDataFactory.makeCurrentUser()

        // Seed avatar locally — synthetic bytes are fine; nothing validates JPEG
        // structure on the persistence path.
        let seedBytes = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 32))
        let saved = try await repository.saveProfile(
            for: user,
            displayName: user.displayName,
            avatarUpdate: .replacePhoto(seedBytes)
        )
        #expect(saved.avatarPhotoFileName != nil)

        // Hydrate with no bytes — should null out the avatar file ref
        let hydrated = try await repository.hydrateFromRemote(
            for: user,
            displayName: "Cleared Avatar",
            avatarBytes: nil,
            avatarAssetID: nil,
            avatarSystemName: "person.crop.circle.fill",
            avatarVersion: saved.avatarVersion + 1
        )

        #expect(hydrated.avatarPhotoFileName == nil)
        #expect(hydrated.avatarAssetID == nil)

        let merged = try #require(await repository.mergedUser(user))
        #expect(merged.avatarPhotoFileName == nil)
        #expect(merged.avatarAssetID == nil)
        #else
        Issue.record("UIKit unavailable for avatar clear hydrate test")
        #endif
    }
}
