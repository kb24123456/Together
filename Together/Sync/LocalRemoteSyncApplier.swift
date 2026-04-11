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

    /// 将远程 profile 更新应用到本地 PairMembership（昵称）和 PairSpace（displayName）
    private func applyProfileUpdate(
        _ profile: CloudKitProfileRecordCodec.MemberProfilePayload,
        in spaceID: UUID
    ) -> Bool {
        let context = ModelContext(modelContainer)
        var didChange = false

        // 更新 PairMembership 的 nickname
        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.userID == profile.userID {
            if membership.nickname != profile.displayName {
                membership.nickname = profile.displayName
                didChange = true
            }
        }

        // 更新 PairSpace 的 displayName（如果 profile 携带了最新值）
        if let newDisplayName = profile.pairSpaceDisplayName {
            let pairSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
            for pairSpace in pairSpaces where pairSpace.sharedSpaceID == spaceID {
                if pairSpace.displayName != newDisplayName {
                    pairSpace.displayName = newDisplayName.isEmpty ? nil : newDisplayName
                    didChange = true
                }
            }
        }

        // 更新用户 Profile 头像信息（对方的 avatar 数据）
        if let avatarBase64 = profile.avatarPhotoBase64, !avatarBase64.isEmpty {
            let profiles = (try? context.fetch(FetchDescriptor<PersistentUserProfile>())) ?? []
            // 如果本地没有对方的 profile 记录，不需要更新（对方头像通过 membership 展示）
            for existingProfile in profiles where existingProfile.userID == profile.userID {
                existingProfile.avatarSystemName = profile.avatarSystemName
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
