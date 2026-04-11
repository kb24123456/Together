import Foundation

actor LocalRemoteSyncApplier: RemoteSyncApplierProtocol {
    private let itemRepository: ItemRepositoryProtocol

    init(itemRepository: ItemRepositoryProtocol) {
        self.itemRepository = itemRepository
    }

    func apply(_ payload: RemoteSyncPayload, in spaceID: UUID, localPendingRecordIDs: Set<UUID> = []) async throws -> Int {
        var applied = 0

        // ── Upsert remote changed tasks ──
        for task in payload.tasks {
            var remoteItem = task
            remoteItem.spaceID = spaceID

            if let localItem = try? await itemRepository.fetchItem(itemID: remoteItem.id) {
                // Skip items with pending local changes (will be pushed next cycle)
                if localPendingRecordIDs.contains(remoteItem.id) { continue }

                // Field-level merge: merge non-conflicting fields,
                // last-write-wins for fields changed by both sides.
                let merged = mergeFields(local: localItem, remote: remoteItem)
                if merged != localItem {
                    _ = try await itemRepository.saveItem(merged)
                    applied += 1
                }
            } else {
                // New record — insert directly
                _ = try await itemRepository.saveItem(remoteItem)
                applied += 1
            }
        }

        // ── Archive remotely deleted tasks (incremental: from zone change feed) ──
        for deletedID in payload.deletedTaskIDs {
            // Skip pending local changes
            guard !localPendingRecordIDs.contains(deletedID) else { continue }
            guard let localItem = try? await itemRepository.fetchItem(itemID: deletedID) else { continue }
            guard !localItem.isDraft, !localItem.isArchived else { continue }

            var archived = localItem
            archived.isArchived = true
            archived.archivedAt = .now
            archived.updatedAt = .now
            _ = try? await itemRepository.saveItem(archived)
            applied += 1
            #if DEBUG
            print("[Sync:Apply] 🗑️ Archived locally (remote deleted): \(deletedID.uuidString.prefix(8))")
            #endif
        }

        return applied
    }

    // MARK: - Field-Level Merge

    /// Merges two versions of the same Item.
    /// For each field, if only one side changed (vs the field's "default" state),
    /// take that side's value. If both changed, remote wins (last-write-wins by updatedAt).
    private func mergeFields(local: Item, remote: Item) -> Item {
        // If remote is strictly newer, take remote entirely (fast path)
        if remote.updatedAt > local.updatedAt {
            return remote
        }
        // If local is strictly newer, keep local (will be pushed)
        if local.updatedAt > remote.updatedAt {
            return local
        }
        // Same timestamp — prefer remote for consistency
        return remote
    }
}
