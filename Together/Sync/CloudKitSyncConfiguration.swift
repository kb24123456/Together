import Foundation

struct CloudKitSyncConfiguration: Hashable, Sendable {
    /// The default container for Together. Used by both invite and task sync.
    nonisolated static let defaultContainerIdentifier = "iCloud.com.pigdog.Together"

    let containerIdentifier: String

    /// Database environment: "private" for pair task sync, "public" for invite discovery.
    let environment: String

    /// Fallback polling interval in seconds (used when subscription push is delayed).
    let fallbackPollingInterval: TimeInterval

    /// Maximum backoff interval for consecutive failures.
    let maxBackoffInterval: TimeInterval

    init(
        containerIdentifier: String = CloudKitSyncConfiguration.defaultContainerIdentifier,
        environment: String = "private",
        fallbackPollingInterval: TimeInterval = 30,
        maxBackoffInterval: TimeInterval = 120
    ) {
        self.containerIdentifier = containerIdentifier
        self.environment = environment
        self.fallbackPollingInterval = fallbackPollingInterval
        self.maxBackoffInterval = maxBackoffInterval
    }
}
