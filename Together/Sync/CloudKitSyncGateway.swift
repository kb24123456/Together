import CloudKit
import Foundation

enum CloudKitSyncGatewayError: Error, Equatable {
    case missingConfiguration
    case transportNotEnabled
    case unsupportedEntity(SyncEntityKind)
    case taskRecordNotFound(UUID)
}

actor CloudKitSyncGateway: CloudSyncGatewayProtocol {
    private let configuration: CloudKitSyncConfiguration
    private let itemRepository: ItemRepositoryProtocol
    private let container: CKContainer

    init(
        configuration: CloudKitSyncConfiguration,
        itemRepository: ItemRepositoryProtocol
    ) {
        self.configuration = configuration
        self.itemRepository = itemRepository
        self.container = CKContainer(identifier: configuration.containerIdentifier)
    }

    func push(changes: [SyncChange], for spaceID: UUID) async throws -> SyncPushResult {
        _ = container
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }

        for change in changes {
            _ = try await preparedRecord(for: change)
        }

        throw CloudKitSyncGatewayError.transportNotEnabled
    }

    func pull(spaceID: UUID, since cursor: SyncCursor?) async throws -> SyncPullResult {
        _ = container
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }

        throw CloudKitSyncGatewayError.transportNotEnabled
    }

    private func preparedRecord(for change: SyncChange) async throws -> CKRecord {
        switch change.entityKind {
        case .task:
            guard let item = try await itemRepository.fetchItem(itemID: change.recordID) else {
                throw CloudKitSyncGatewayError.taskRecordNotFound(change.recordID)
            }
            return try CloudKitTaskRecordCodec.makeRecord(from: item)
        case .taskList, .project, .space:
            throw CloudKitSyncGatewayError.unsupportedEntity(change.entityKind)
        }
    }
}
