import Foundation
import Observation
import CloudKit

/// Sync scheduler that combines:
/// - **Subscription-driven sync**: triggered by CKDatabaseSubscription silent push
/// - **Fallback polling**: 30-second interval as safety net when push is delayed/lost
/// - **App lifecycle awareness**: stops polling in background, syncs on foreground
@MainActor
@Observable
final class SyncScheduler {
    private let syncOrchestrator: SyncOrchestratorProtocol
    private var pollTask: Task<Void, Never>?
    private var activeSpaceID: UUID?
    private var consecutiveFailures: Int = 0

    private let baseInterval: TimeInterval = 30
    private let maxInterval: TimeInterval = 120

    var isSyncing: Bool = false
    var lastSyncedAt: Date?
    var lastSyncError: String?

    /// Callback invoked after each sync cycle. pulledCount > 0 means new data arrived.
    var onSyncCompleted: ((SyncRunResult) -> Void)?

    init(syncOrchestrator: SyncOrchestratorProtocol) {
        self.syncOrchestrator = syncOrchestrator
    }

    // MARK: - Polling

    /// Starts fallback polling with 30-second interval (subscription push is primary).
    func startPolling(spaceID: UUID, interval: TimeInterval = 30) {
        if activeSpaceID == spaceID, pollTask != nil { return }

        stopPolling()
        activeSpaceID = spaceID

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.performSync(spaceID: spaceID)

                let backoffInterval: TimeInterval
                if self.consecutiveFailures > 0 {
                    let exponential = self.baseInterval * pow(2.0, Double(self.consecutiveFailures))
                    backoffInterval = min(exponential, self.maxInterval)
                } else {
                    backoffInterval = self.baseInterval
                }

                try? await Task.sleep(for: .seconds(backoffInterval))
            }
        }
    }

    /// Stops fallback polling.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        activeSpaceID = nil
    }

    // MARK: - Subscription-Driven Sync

    /// Called when a CloudKit subscription silent push arrives.
    /// Triggers an immediate sync regardless of polling timer.
    func handleSubscriptionNotification() async {
        guard let spaceID = activeSpaceID else { return }
        #if DEBUG
        print("[SyncScheduler] 📩 Subscription notification received, syncing immediately")
        #endif
        await performSync(spaceID: spaceID)
    }

    // MARK: - Manual Sync

    /// Triggers an immediate sync (e.g., on app foreground or after mutation).
    func syncNow(spaceID: UUID) async {
        await performSync(spaceID: spaceID)
    }

    // MARK: - Internal

    private func performSync(spaceID: UUID) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastSyncError = nil

        do {
            let result = try await syncOrchestrator.sync(spaceID: spaceID)
            lastSyncedAt = .now
            consecutiveFailures = 0
            #if DEBUG
            if result.pushedCount > 0 || result.pulledCount > 0 {
                print("[SyncScheduler] spaceID=\(spaceID.uuidString.prefix(8)) pushed=\(result.pushedCount) pulled=\(result.pulledCount)")
            }
            #endif
            onSyncCompleted?(result)
        } catch {
            consecutiveFailures += 1
            lastSyncError = String(describing: error)
            #if DEBUG
            print("[SyncScheduler] sync error (failures=\(consecutiveFailures)): \(error)")
            #endif
        }

        isSyncing = false
    }
}
