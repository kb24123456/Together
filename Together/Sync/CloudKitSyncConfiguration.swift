import Foundation

struct CloudKitSyncConfiguration: Hashable, Sendable {
    /// The default CloudKit container for Together personal task sync.
    nonisolated static let defaultContainerIdentifier = "iCloud.com.pigdog.Together"

    let containerIdentifier: String

    /// Database environment for the user's private CloudKit sync.
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
