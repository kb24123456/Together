import Foundation
import Testing
@testable import Together

@Suite("SoloSyncMetadataStore")
struct SoloSyncMetadataStoreTests {
    @Test("stores migration completion per space")
    func migrationCompletionPersistsPerSpace() {
        let suiteName = "SoloSyncMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SoloSyncMetadataStore(defaults: defaults)
        let spaceID = UUID()
        let otherSpaceID = UUID()
        let date = Date(timeIntervalSince1970: 100)

        #expect(store.migrationCompletedAt(spaceID: spaceID) == nil)
        store.markMigrationCompleted(spaceID: spaceID, at: date, build: "13")

        #expect(store.migrationCompletedAt(spaceID: spaceID) == date)
        #expect(store.migrationBuild(spaceID: spaceID) == "13")
        #expect(store.migrationCompletedAt(spaceID: otherSpaceID) == nil)
        #expect(store.migrationBuild(spaceID: otherSpaceID) == nil)
    }

    @Test("stores pull and push cursors separately")
    func storesPullAndPushCursors() {
        let suiteName = "SoloSyncMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SoloSyncMetadataStore(defaults: defaults)
        let spaceID = UUID()
        let pull = Date(timeIntervalSince1970: 200)
        let push = Date(timeIntervalSince1970: 300)

        store.setLastPulledAt(pull, spaceID: spaceID)
        store.setLastPushedAt(push, spaceID: spaceID)

        #expect(store.lastPulledAt(spaceID: spaceID) == pull)
        #expect(store.lastPushedAt(spaceID: spaceID) == push)
    }
}
