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
}
