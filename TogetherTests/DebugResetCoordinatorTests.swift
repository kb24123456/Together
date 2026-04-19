#if DEBUG
import Foundation
import Testing
@testable import Together

@Suite("DebugResetCoordinator")
struct DebugResetCoordinatorTests {
    private let suiteName = "DebugResetCoordinatorTests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("scheduleLocalNuke sets pending flag")
    func scheduleLocalNukeSetsFlag() {
        defer { cleanup() }
        DebugResetCoordinator.scheduleLocalNuke(defaults: defaults)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == true)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }

    @Test("scheduleLocalPlusCloudWipe sets both flags")
    func scheduleBothSetsBothFlags() {
        defer { cleanup() }
        DebugResetCoordinator.scheduleLocalPlusCloudWipe(defaults: defaults)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == true)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == true)
    }

    @Test("applyPendingNukeIfNeeded no-op when no flag set")
    func applyNoFlags() {
        defer { cleanup() }
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { Issue.record("should not delete") },
            clearMigrationFlags: { Issue.record("should not clear") },
            wipeCloudZone: { Issue.record("should not wipe") }
        )
        #expect(result == .noop)
    }

    @Test("applyPendingNukeIfNeeded clears flags after local-only nuke")
    func applyLocalOnly() {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        var deleteCalled = 0
        var clearFlagsCalled = 0
        var wipeCalled = 0
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { deleteCalled += 1 },
            clearMigrationFlags: { clearFlagsCalled += 1 },
            wipeCloudZone: { wipeCalled += 1 }
        )
        #expect(result == .localOnly)
        #expect(deleteCalled == 1)
        #expect(clearFlagsCalled == 1)
        #expect(wipeCalled == 0)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == false)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }

    @Test("applyPendingNukeIfNeeded runs both wipes when both flags set")
    func applyBoth() {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        defaults.set(true, forKey: DebugResetCoordinator.pendingCloudWipeKey)
        var deleteCalled = 0
        var wipeCalled = 0
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { deleteCalled += 1 },
            clearMigrationFlags: {},
            wipeCloudZone: { wipeCalled += 1 }
        )
        #expect(result == .localAndCloud)
        #expect(deleteCalled == 1)
        #expect(wipeCalled == 1)
    }

    @Test("applyPendingNukeIfNeeded clears flags even when cloud wipe closure silently fails")
    func applyClearsFlagsOnCloudFailure() {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        defaults.set(true, forKey: DebugResetCoordinator.pendingCloudWipeKey)
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: {},
            clearMigrationFlags: {},
            wipeCloudZone: {
                // Closure is best-effort; coordinator treats failure as swallowed.
            }
        )
        #expect(result == .localAndCloud)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == false)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }
}
#endif
