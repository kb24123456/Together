import CloudKit
import Foundation
import Observation

/// Observable health state for all active sync engines and relay bridges.
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

    struct RelaySyncHealth: Sendable {
        var lastRelayPosted: Date?
        var lastRelayReceived: Date?
        var pendingRelayCount: Int = 0
        var consecutivePostFailures: Int = 0
        var needsManualRetry: Bool = false
    }

    // MARK: - State

    var engineStates: [String: ZoneSyncHealth] = [:]  // keyed by zone name
    var relayHealth: [UUID: RelaySyncHealth] = [:]     // keyed by pairSpaceID

    // MARK: - Convenience

    var soloHealth: ZoneSyncHealth? {
        engineStates["solo"]
    }

    func pairHealth(for pairSpaceID: UUID) -> ZoneSyncHealth? {
        engineStates["pair-\(pairSpaceID.uuidString)"]
    }

    var hasAnyError: Bool {
        engineStates.values.contains(where: { $0.consecutiveFailures > 0 }) ||
        relayHealth.values.contains(where: { $0.needsManualRetry })
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

    nonisolated func updateRelay(_ pairSpaceID: UUID, _ update: @Sendable @escaping (inout RelaySyncHealth) -> Void) {
        Task { @MainActor in
            var health = self.relayHealth[pairSpaceID] ?? RelaySyncHealth()
            update(&health)
            self.relayHealth[pairSpaceID] = health
        }
    }
}
