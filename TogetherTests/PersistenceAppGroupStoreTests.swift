import Foundation
import Testing
@testable import Together

@Suite("Persistence App Group Store")
struct PersistenceAppGroupStoreTests {
    @Test("uses injected app group container when available")
    func usesInjectedAppGroupContainer() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resolved = PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL: root)

        #expect(resolved == root.appending(path: "Together.store"))
    }

    @Test("falls back to legacy application support directory when app group unavailable")
    func fallsBackToLegacyDirectory() {
        let resolved = PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL: nil)

        #expect(resolved.lastPathComponent == "Together.store")
        #expect(resolved.path.contains("Together"))
    }

    @Test("migrates sqlite store artifacts into app group when destination is empty")
    func migratesStoreArtifactsIntoAppGroupWhenDestinationEmpty() throws {
        let legacyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let appGroupRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)

        let legacyStore = legacyRoot.appending(path: "Together.store")
        let groupStore = appGroupRoot.appending(path: "Together.store")
        try Data("store".utf8).write(to: legacyStore)
        try Data("wal".utf8).write(to: legacyStore.deletingPathExtension().appendingPathExtension("store-wal"))
        try Data("shm".utf8).write(to: legacyStore.deletingPathExtension().appendingPathExtension("store-shm"))
        let legacySupport = PersistenceController.persistentStoreSupportURL(for: legacyStore)
        try FileManager.default.createDirectory(at: legacySupport, withIntermediateDirectories: true)
        try Data("support".utf8).write(to: legacySupport.appending(path: "metadata"))

        try PersistenceController.migrateStoreArtifactsIfNeeded(
            legacyStoreURL: legacyStore,
            appGroupStoreURL: groupStore
        )

        #expect(FileManager.default.fileExists(atPath: groupStore.path))
        #expect(FileManager.default.fileExists(atPath: groupStore.deletingPathExtension().appendingPathExtension("store-wal").path))
        #expect(FileManager.default.fileExists(atPath: groupStore.deletingPathExtension().appendingPathExtension("store-shm").path))
        #expect(FileManager.default.fileExists(atPath: PersistenceController.persistentStoreSupportURL(for: groupStore).appending(path: "metadata").path))
    }

    @Test("does not overwrite existing app group store")
    func doesNotOverwriteExistingAppGroupStore() throws {
        let legacyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let appGroupRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)

        let legacyStore = legacyRoot.appending(path: "Together.store")
        let groupStore = appGroupRoot.appending(path: "Together.store")
        try Data("legacy".utf8).write(to: legacyStore)
        try Data("group".utf8).write(to: groupStore)

        try PersistenceController.migrateStoreArtifactsIfNeeded(
            legacyStoreURL: legacyStore,
            appGroupStoreURL: groupStore
        )

        let data = try Data(contentsOf: groupStore)
        #expect(String(decoding: data, as: UTF8.self) == "group")
    }
}
