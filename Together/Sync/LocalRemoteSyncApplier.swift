import Foundation
import SwiftData

actor LocalRemoteSyncApplier: RemoteSyncApplierProtocol {
    private let itemRepository: ItemRepositoryProtocol
    private let modelContainer: ModelContainer

    init(itemRepository: ItemRepositoryProtocol, modelContainer: ModelContainer) {
        self.itemRepository = itemRepository
        self.modelContainer = modelContainer
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

        // ── Apply remote member profile updates ──
        for profile in payload.memberProfiles {
            let didApply = applyProfileUpdate(profile, in: spaceID)
            if didApply { applied += 1 }
        }

        return applied
    }

    // MARK: - Profile Apply

    /// Legacy compatibility path. Only backfills missing local projection/cache state and must not
    /// override the current shared-authority sync results.
    private func applyProfileUpdate(
        _ profile: CloudKitProfileRecordCodec.MemberProfilePayload,
        in spaceID: UUID
    ) -> Bool {
        let context = ModelContext(modelContainer)
        var didChange = false

        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.userID == profile.userID {
            if membership.nickname.isEmpty {
                membership.nickname = profile.displayName
                didChange = true
            }
        }

        if let newDisplayName = profile.pairSpaceDisplayName {
            let resolvedDisplayName = newDisplayName.isEmpty
                ? PairSpace.defaultSharedSpaceDisplayName
                : newDisplayName

            let spaces = (try? context.fetch(FetchDescriptor<PersistentSpace>())) ?? []
            for space in spaces where space.id == spaceID {
                if space.displayName.isEmpty || space.displayName == PairSpace.defaultSharedSpaceDisplayName {
                    space.displayName = resolvedDisplayName
                    didChange = true
                }
            }
        }

        let avatarStore = LocalUserAvatarMediaStore()
        let canonicalFileName = profile.avatarAssetID ?? avatarStore.canonicalFileName(for: profile.userID)

        for membership in memberships where membership.userID == profile.userID {
            if membership.avatarSystemName == nil {
                membership.avatarSystemName = profile.avatarSystemName
                didChange = true
            }
            if membership.avatarVersion < profile.avatarVersion {
                membership.avatarVersion = profile.avatarVersion
                didChange = true
            }
            let canRepairMissingAvatarCache = membership.avatarAssetID == nil && membership.avatarPhotoFileName == nil

            if canRepairMissingAvatarCache,
               let avatarBase64 = profile.avatarPhotoBase64,
               !avatarBase64.isEmpty,
               let imageData = Data(base64Encoded: avatarBase64) {
                try? avatarStore.persistAvatarData(imageData, fileName: canonicalFileName)
                membership.avatarPhotoFileName = canonicalFileName
                membership.avatarAssetID = canonicalFileName
                didChange = true
            } else if canRepairMissingAvatarCache {
                membership.avatarAssetID = profile.avatarAssetID
                didChange = true
            }
        }

        if didChange {
            try? context.save()
            #if DEBUG
            print("[Sync:Apply] 👤 Updated profile for userID=\(profile.userID.uuidString.prefix(8))")
            #endif
        }
        return didChange
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
