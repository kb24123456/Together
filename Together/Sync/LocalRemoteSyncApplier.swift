import Foundation

actor LocalRemoteSyncApplier: RemoteSyncApplierProtocol {
    private let itemRepository: ItemRepositoryProtocol

    init(itemRepository: ItemRepositoryProtocol) {
        self.itemRepository = itemRepository
    }

    func apply(_ payload: RemoteSyncPayload, in spaceID: UUID) async throws -> Int {
        for task in payload.tasks {
            var taskToSave = task
            taskToSave.spaceID = spaceID
            _ = try await itemRepository.saveItem(taskToSave)
        }

        return payload.tasks.count
    }
}
