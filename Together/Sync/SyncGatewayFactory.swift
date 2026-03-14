import Foundation

enum SyncGatewayFactory {
    static func makeGateway(
        itemRepository: ItemRepositoryProtocol
    ) -> CloudSyncGatewayProtocol {
        guard
            let containerIdentifier = ProcessInfo.processInfo.environment["TOGETHER_CLOUDKIT_CONTAINER"],
            containerIdentifier.isEmpty == false
        else {
            return PlaceholderCloudSyncGateway()
        }

        return CloudKitSyncGateway(
            configuration: CloudKitSyncConfiguration(containerIdentifier: containerIdentifier),
            itemRepository: itemRepository
        )
    }
}
