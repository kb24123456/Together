import Foundation

struct CloudKitSyncConfiguration: Hashable, Sendable {
    let containerIdentifier: String
    let environment: String

    init(
        containerIdentifier: String,
        environment: String = "private"
    ) {
        self.containerIdentifier = containerIdentifier
        self.environment = environment
    }
}
