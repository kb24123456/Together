import Foundation
import Observation

/// Result of a single sync cycle, used by `PairSyncPoller` to adjust intervals.
enum PollResult: Sendable {
    case changes(Int)
    case noChange
    case failed(Error)
}

/// Adaptive polling timer that drives pair sync via `PairSyncService.syncOnce()`.
///
/// **Key invariant: polling never self-destructs.** Only an explicit `stop()` call
/// ends the loop. Transient errors or empty results merely adjust the interval.
///
/// Adaptive strategy:
/// - changes detected  → 5s
/// - 3 consecutive no-change → 15s
/// - 6 consecutive no-change → 30s
/// - failure → exponential backoff up to 120s
/// - `nudge()` → immediate sync + reset to 5s
@MainActor
@Observable
final class PairSyncPoller {

    // MARK: - Observable state

    private(set) var isActive = false
    private(set) var currentInterval: TimeInterval = 5
    private(set) var consecutiveNoChange = 0
    private(set) var consecutiveFailures = 0

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Error>?
    private var syncAction: (@Sendable () async -> PollResult)?

    // MARK: - Public API

    /// Starts the adaptive polling loop.
    ///
    /// - Parameter syncAction: Closure that performs one push+pull cycle and returns
    ///   a `PollResult`. Typically calls `PairSyncService.syncOnce()`.
    func start(syncAction: @escaping @Sendable () async -> PollResult) {
        guard !isActive else { return }

        self.syncAction = syncAction
        isActive = true
        currentInterval = 5
        consecutiveNoChange = 0
        consecutiveFailures = 0

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Execute one sync cycle
                let result: PollResult
                if let action = self.syncAction {
                    result = await action()
                } else {
                    result = .noChange
                }

                guard !Task.isCancelled else { break }

                // Adjust interval based on result
                self.adjustInterval(for: result)

                // Sleep until next cycle (cancellable by nudge/stop)
                let interval = self.currentInterval
                self.sleepTask = Task<Void, Error> {
                    try await Task.sleep(for: .seconds(interval))
                }
                _ = try? await self.sleepTask?.value
            }
        }
    }

    /// Stops the polling loop. This is the ONLY way to end polling.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        sleepTask?.cancel()
        sleepTask = nil
        syncAction = nil
        isActive = false
        currentInterval = 5
        consecutiveNoChange = 0
        consecutiveFailures = 0
    }

    /// Triggers an immediate sync cycle and resets the interval to 5s.
    ///
    /// Called when:
    /// - CloudKit push notification arrives
    /// - App returns to foreground
    /// - Local mutation is recorded
    func nudge() {
        guard isActive else { return }
        // Cancel the current sleep so the loop immediately proceeds to sync
        sleepTask?.cancel()
        sleepTask = nil
        // Reset to fast polling
        currentInterval = 5
        consecutiveNoChange = 0
    }

    // MARK: - Private

    private func adjustInterval(for result: PollResult) {
        switch result {
        case .changes:
            consecutiveNoChange = 0
            consecutiveFailures = 0
            currentInterval = 5
        case .noChange:
            consecutiveNoChange += 1
            consecutiveFailures = 0
            if consecutiveNoChange >= 6 {
                currentInterval = 30
            } else if consecutiveNoChange >= 3 {
                currentInterval = 15
            } else {
                currentInterval = 5
            }
        case .failed:
            consecutiveFailures += 1
            consecutiveNoChange = 0
            currentInterval = min(5 * pow(2.0, Double(consecutiveFailures)), 120)
        }
    }
}
