import CloudKit
import Foundation

enum SyncGatewayFactory {
    static func makeGateway(
        itemRepository: ItemRepositoryProtocol
    ) -> CloudKitSyncGateway {
        CloudKitSyncGateway(
            configuration: CloudKitSyncConfiguration(),
            itemRepository: itemRepository
        )
    }

    static func makeContainer() -> CKContainer {
        CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
    }
}
