import CloudKit
import Foundation
import Observation

/// Observable health state for all active sync engines.
///
/// Exposed in the UI to show sync status indicators.
@MainActor
@Observable
final class SyncHealthMonitor {

    // MARK: - Per-Zone Health

    struct ZoneSyncHealth: Sendable {
        var lastSuccessfulSync: Date?
        var pendingChangeCount: Int = 0
        var consecutiveFailures: Int = 0
        var lastError: String?
        var isSyncing: Bool = false
    }

    // MARK: - State

    var engineStates: [String: ZoneSyncHealth] = [:]  // keyed by zone name

    // MARK: - Convenience

    var soloHealth: ZoneSyncHealth? {
        engineStates["solo"]
    }

    func pairHealth(for pairSpaceID: UUID) -> ZoneSyncHealth? {
        engineStates["pair-\(pairSpaceID.uuidString)"]
    }

    var hasAnyError: Bool {
        engineStates.values.contains(where: { $0.consecutiveFailures > 0 })
    }

    var isAnySyncing: Bool {
        engineStates.values.contains(where: \.isSyncing)
    }

    // MARK: - Updates (called from SyncEngineCoordinator)

    nonisolated func updateZone(_ zoneName: String, _ update: @Sendable @escaping (inout ZoneSyncHealth) -> Void) {
        Task { @MainActor in
            var health = self.engineStates[zoneName] ?? ZoneSyncHealth()
            update(&health)
            self.engineStates[zoneName] = health
        }
    }
}
