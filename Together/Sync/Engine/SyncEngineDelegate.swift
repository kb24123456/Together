import CloudKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncEngineDelegate")

private struct MutationLookupKey: Hashable {
    let recordName: String
    let entityKindRawValue: String
}

/// CKSyncEngineDelegate that bridges CKSyncEngine events to SwiftData persistence.
///
/// Each instance is bound to the solo zone.
/// It provides pending local changes for push, and applies remote changes on pull.
/// Pair sync is handled separately by `PairSyncService` using CloudKit Public DB.
final class SyncEngineDelegate: CKSyncEngineDelegate {

    private let zoneID: CKRecordZone.ID
    private let modelContainer: ModelContainer
    private let codecRegistry: RecordCodecRegistry
    private let healthMonitor: SyncHealthMonitor

    /// Callback invoked when remote changes are applied, so the UI can refresh.
    var onRemoteChangesApplied: (@Sendable (_ appliedCount: Int) -> Void)?

    init(
        zoneID: CKRecordZone.ID,
        modelContainer: ModelContainer,
        codecRegistry: RecordCodecRegistry,
        healthMonitor: SyncHealthMonitor
    ) {
        self.zoneID = zoneID
        self.modelContainer = modelContainer
        self.codecRegistry = codecRegistry
        self.healthMonitor = healthMonitor
    }

    static func shouldApplyFetchedRecord(
        remoteUpdatedAt: Date,
        localUpdatedAt: Date,
        hasPendingLocalSave: Bool = false
    ) -> Bool {
        return remoteUpdatedAt >= localUpdatedAt
    }

    static func makeMemberProfilePayload(
        from persistent: PersistentUserProfile,
        sharedSpaceID: UUID
    ) -> MemberProfileRecordCodable.Profile {
        let avatarReference = persistent.avatarAssetID
        let avatarDeleted = avatarReference == nil

        return MemberProfileRecordCodable.Profile(
            userID: persistent.userID,
            spaceID: sharedSpaceID,
            displayName: persistent.displayName,
            avatarSystemName: persistent.avatarSystemName,
            avatarAssetID: avatarReference,
            avatarVersion: persistent.avatarVersion,
            avatarDeleted: avatarDeleted,
            updatedAt: persistent.updatedAt
        )
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            handleStateUpdate(stateUpdate)

        case .accountChange(let accountChange):
            handleAccountChange(accountChange)

        case .fetchedDatabaseChanges(let fetchedChanges):
            handleFetchedDatabaseChanges(fetchedChanges)

        case .fetchedRecordZoneChanges(let fetchedChanges):
            handleFetchedRecordZoneChanges(
                fetchedChanges,
                pendingLocalSaveRecordNames: pendingLocalSaveRecordNames(in: syncEngine)
            )

        case .sentRecordZoneChanges(let sentChanges):
            handleSentRecordZoneChanges(sentChanges)

        case .willFetchChanges:
            healthMonitor.updateZone(zoneID.zoneName) { $0.isSyncing = true }

        case .didFetchChanges:
            healthMonitor.updateZone(zoneID.zoneName) {
                $0.isSyncing = false
                $0.lastSuccessfulSync = .now
                $0.consecutiveFailures = 0
                $0.lastFetchError = nil
                $0.lastError = $0.lastSendError
            }

        case .willSendChanges:
            healthMonitor.updateZone(zoneID.zoneName) { $0.isSyncing = true }

        case .didSendChanges:
            healthMonitor.updateZone(zoneID.zoneName) {
                $0.isSyncing = false
                $0.lastSendError = nil
                $0.lastError = $0.lastFetchError
            }

        case .sentDatabaseChanges,
             .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges:
            break

        @unknown default:
            logger.info("[SyncDelegate] Unknown event for zone \(self.zoneID.zoneName)")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges
            .filter { pendingChange in
                switch pendingChange {
                case .saveRecord(let recordID):
                    return recordID.zoneID == zoneID
                case .deleteRecord(let recordID):
                    return recordID.zoneID == zoneID
                @unknown default:
                    return false
                }
            }

        guard !pendingChanges.isEmpty else { return nil }

        let batchRecordIDs = pendingChanges.compactMap { pendingChange -> CKRecord.ID? in
            switch pendingChange {
            case .saveRecord(let recordID):
                return recordID
            case .deleteRecord(let recordID):
                return recordID
            @unknown default:
                return nil
            }
        }
        markMutations(for: batchRecordIDs, state: .sending, attemptedAt: .now)

        let container = self.modelContainer

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            let modelContext = ModelContext(container)
            guard let uuid = UUID(uuidString: recordID.recordName) else { return nil }

            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .task, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .taskList, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .project, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .projectSubtask, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .periodicTask, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .space, context: modelContext) {
                return record
            }
            if let record = self.fetchAndEncode(uuid: uuid, entityKind: .memberProfile, context: modelContext) {
                return record
            }

            logger.warning("[SyncDelegate] No local entity found for recordID=\(recordID.recordName.prefix(8))")
            return nil
        }
    }

    // MARK: - Event Handlers

    private func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        // Persist the serialized state so CKSyncEngine can resume from where it left off.
        let stateData: Data
        do {
            stateData = try JSONEncoder().encode(stateUpdate.stateSerialization)
        } catch {
            logger.error("[SyncDelegate] Failed to archive state: \(error)")
            return
        }

        let context = ModelContext(modelContainer)
        let zoneName = zoneID.zoneName
        let fetchDescriptor = FetchDescriptor<PersistentSyncState>(
            predicate: #Predicate<PersistentSyncState> { $0.cursorToken == zoneName }
        )

        do {
            let existing = try context.fetch(fetchDescriptor)
            if let state = existing.first {
                state.serverChangeTokenData = stateData
                state.updatedAt = .now
            } else {
                // Create a new PersistentSyncState keyed by zone name
                let syncState = SyncState(
                    spaceID: zoneIDToSpaceID(),
                    cursor: SyncCursor(token: zoneName, updatedAt: .now, serverChangeTokenData: stateData),
                    updatedAt: .now
                )
                let newState = PersistentSyncState(state: syncState)
                context.insert(newState)
            }
            try context.save()
        } catch {
            logger.error("[SyncDelegate] Failed to persist state: \(error)")
        }
    }

    private func handleAccountChange(_ accountChange: CKSyncEngine.Event.AccountChange) {
        logger.info("[SyncDelegate] Account change: \(String(describing: accountChange.changeType))")
        // The SyncEngineCoordinator will handle resetting engines on account change.
    }

    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // Database-level changes (zone creations/deletions) — log for now.
        for modification in changes.modifications {
            logger.info("[SyncDelegate] Zone modified: \(modification.zoneID.zoneName)")
        }
        for deletion in changes.deletions {
            logger.info("[SyncDelegate] Zone deleted: \(deletion.zoneID.zoneName)")
        }
    }

    private func handleFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges,
        pendingLocalSaveRecordNames: Set<String>
    ) {
        let context = ModelContext(modelContainer)
        let mutationStates = localMutationStateByRecordName(
            for: changes.modifications.map(\.record)
        )
        var appliedCount = 0

        // Apply modifications
        for modification in changes.modifications {
            let record = modification.record
            guard codecRegistry.canDecode(record.recordType) else {
                // 静默掉 cloudkit.share —— 旧 CKShare 残留，对当前 Supabase pair sync 无用，会刷屏
                if record.recordType != "cloudkit.share" {
                    logger.warning("[SyncDelegate] Unknown record type: \(record.recordType)")
                }
                continue
            }

            do {
                let entity = try codecRegistry.decode(record)
                applyEntity(
                    entity,
                    hasPendingLocalSave: pendingLocalSaveRecordNames.contains(record.recordID.recordName)
                        || shouldPreserveLocalMutation(for: mutationStates[record.recordID.recordName]),
                    context: context
                )
                appliedCount += 1
            } catch {
                logger.error("[SyncDelegate] Decode failed: \(error)")
            }
        }

        // Apply deletions
        for deletion in changes.deletions {
            guard let uuid = UUID(uuidString: deletion.recordID.recordName) else { continue }
            archiveLocalRecord(uuid: uuid, recordType: deletion.recordType, context: context)
            appliedCount += 1
        }

        if appliedCount > 0 {
            do {
                try context.save()
                logger.info("[SyncDelegate] Applied \(appliedCount) remote changes in zone \(self.zoneID.zoneName)")
                onRemoteChangesApplied?(appliedCount)
            } catch {
                logger.error("[SyncDelegate] Failed to save remote changes: \(error)")
            }
        }
    }

    private func handleSentRecordZoneChanges(_ sentChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        var savedRecords: [CKRecord] = []

        // Process successful saves
        for savedRecord in sentChanges.savedRecords {
            savedRecords.append(savedRecord)
            logger.debug("[SyncDelegate] ✅ Pushed: \(savedRecord.recordType)/\(savedRecord.recordID.recordName.prefix(8))")
        }

        // Process failures with conflict resolution
        for failedSave in sentChanges.failedRecordSaves {
            let error = failedSave.error
            if error.code == .serverRecordChanged,
               let serverRecord = error.serverRecord {
                // Conflict — resolve by taking the server version for now
                // TODO: Implement field-level merge in a future phase
                logger.info("[SyncDelegate] Conflict for \(failedSave.record.recordID.recordName.prefix(8)), accepting server version")
                let context = ModelContext(modelContainer)
                if let entity = try? codecRegistry.decode(serverRecord) {
                    applyEntity(entity, hasPendingLocalSave: false, context: context)
                    try? context.save()
                }
                markMutations(
                    for: [failedSave.record.recordID],
                    state: .failed,
                    attemptedAt: .now,
                    errorMessage: error.localizedDescription
                )
            } else {
                logger.error("[SyncDelegate] ❌ Push failed: \(error)")
                markMutations(
                    for: [failedSave.record.recordID],
                    state: .failed,
                    attemptedAt: .now,
                    errorMessage: error.localizedDescription
                )
                healthMonitor.updateZone(zoneID.zoneName) {
                    $0.consecutiveFailures += 1
                    $0.lastSendError = error.localizedDescription
                    $0.lastError = error.localizedDescription
                }
            }
        }

        if !savedRecords.isEmpty {
            markMutations(
                for: savedRecords.map(\.recordID),
                state: .confirmed,
                confirmedAt: .now,
                errorMessage: nil
            )
            healthMonitor.updateZone(zoneID.zoneName) {
                $0.pendingChangeCount = max(0, $0.pendingChangeCount - savedRecords.count)
                $0.lastSendError = nil
                $0.lastError = $0.lastFetchError
                $0.consecutiveFailures = 0
                $0.lastSuccessfulSync = .now
            }
        }

        for deletedID in sentChanges.deletedRecordIDs {
            markMutations(
                for: [deletedID],
                state: .confirmed,
                confirmedAt: .now,
                errorMessage: nil
            )
            logger.debug("[SyncDelegate] 🗑️ Deleted from server: \(deletedID.recordName.prefix(8))")
        }
    }

    // MARK: - Entity Application

    private func applyEntity(
        _ entity: any RecordCodable,
        hasPendingLocalSave: Bool,
        context: ModelContext
    ) {
        switch entity {
        case let itemCodable as ItemRecordCodable:
            applyItem(itemCodable.item, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let listCodable as TaskListRecordCodable:
            applyTaskList(listCodable.taskList, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let projectCodable as ProjectRecordCodable:
            applyProject(projectCodable.project, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let subtaskCodable as ProjectSubtaskRecordCodable:
            applyProjectSubtask(subtaskCodable.subtask, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let periodicCodable as PeriodicTaskRecordCodable:
            applyPeriodicTask(periodicCodable.periodicTask, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let spaceCodable as SpaceRecordCodable:
            applySpace(spaceCodable.space, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let memberProfileCodable as MemberProfileRecordCodable:
            applyMemberProfile(memberProfileCodable.profile, hasPendingLocalSave: hasPendingLocalSave, context: context)
        case let avatarAssetCodable as AvatarAssetRecordCodable:
            applyAvatarAsset(avatarAssetCodable.asset, hasPendingLocalSave: hasPendingLocalSave, context: context)
        default:
            logger.warning("[SyncDelegate] Unhandled entity type during apply")
        }
    }

    private func applyItem(_ item: Item, hasPendingLocalSave: Bool, context: ModelContext) {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.id == itemID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if Self.shouldApplyFetchedRecord(
                remoteUpdatedAt: item.updatedAt,
                localUpdatedAt: existing.updatedAt,
                hasPendingLocalSave: hasPendingLocalSave
            ) {
                existing.update(from: item)
            }
        } else {
            context.insert(PersistentItem(item: item))
        }
    }

    private func applyTaskList(_ list: TaskList, hasPendingLocalSave: Bool, context: ModelContext) {
        let listID = list.id
        let descriptor = FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate<PersistentTaskList> { $0.id == listID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if Self.shouldApplyFetchedRecord(
                remoteUpdatedAt: list.updatedAt,
                localUpdatedAt: existing.updatedAt,
                hasPendingLocalSave: hasPendingLocalSave
            ) {
                existing.update(from: list)
            }
        } else {
            context.insert(PersistentTaskList(list: list))
        }
    }

    private func applyProject(_ project: Project, hasPendingLocalSave: Bool, context: ModelContext) {
        let projectID = project.id
        let descriptor = FetchDescriptor<PersistentProject>(
            predicate: #Predicate<PersistentProject> { $0.id == projectID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if Self.shouldApplyFetchedRecord(
                remoteUpdatedAt: project.updatedAt,
                localUpdatedAt: existing.updatedAt,
                hasPendingLocalSave: hasPendingLocalSave
            ) {
                existing.update(from: project)
            }
        } else {
            context.insert(PersistentProject(project: project))
        }
    }

    private func applyProjectSubtask(
        _ subtask: ProjectSubtask,
        hasPendingLocalSave: Bool,
        context: ModelContext
    ) {
        let subtaskID = subtask.id
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.id == subtaskID }
        )
        if let existing = try? context.fetch(descriptor).first {
            guard hasPendingLocalSave == false else { return }
            existing.title = subtask.title
            existing.isCompleted = subtask.isCompleted
            existing.sortOrder = subtask.sortOrder
        } else {
            context.insert(PersistentProjectSubtask(subtask: subtask))
        }
    }

    private func applyPeriodicTask(_ task: PeriodicTask, hasPendingLocalSave: Bool, context: ModelContext) {
        let taskID = task.id
        let descriptor = FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if Self.shouldApplyFetchedRecord(
                remoteUpdatedAt: task.updatedAt,
                localUpdatedAt: existing.updatedAt,
                hasPendingLocalSave: hasPendingLocalSave
            ) {
                existing.update(from: task)
            }
        } else {
            context.insert(PersistentPeriodicTask(task: task))
        }
    }

    private func applySpace(_ space: Space, hasPendingLocalSave: Bool, context: ModelContext) {
        let spaceID = space.id
        let descriptor = FetchDescriptor<PersistentSpace>(
            predicate: #Predicate<PersistentSpace> { $0.id == spaceID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if Self.shouldApplyFetchedRecord(
                remoteUpdatedAt: space.updatedAt,
                localUpdatedAt: existing.updatedAt,
                hasPendingLocalSave: hasPendingLocalSave
            ) {
                existing.update(from: space)
            }
        } else {
            context.insert(PersistentSpace(space: space))
        }

    }

    private func applyMemberProfile(
        _ profile: MemberProfileRecordCodable.Profile,
        hasPendingLocalSave: Bool,
        context: ModelContext
    ) {
        guard hasPendingLocalSave == false else { return }
        let store = LocalUserAvatarMediaStore()

        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.userID == profile.userID {
            membership.nickname = profile.displayName
            membership.avatarSystemName = profile.avatarSystemName
            membership.avatarVersion = profile.avatarVersion

            if profile.avatarDeleted {
                if let fileName = membership.avatarPhotoFileName {
                    try? store.removeAvatar(named: fileName)
                }
                membership.avatarPhotoFileName = nil
                membership.avatarAssetID = nil
            } else if let avatarAssetID = profile.avatarAssetID {
                let cacheFileName = store.cacheFileName(for: avatarAssetID)
                if store.fileExists(named: cacheFileName) {
                    membership.avatarPhotoFileName = cacheFileName
                } else if membership.avatarAssetID != avatarAssetID,
                          membership.avatarPhotoFileName != cacheFileName {
                    membership.avatarPhotoFileName = nil
                }
                membership.avatarAssetID = avatarAssetID
            }
        }

        let profiles = (try? context.fetch(FetchDescriptor<PersistentUserProfile>())) ?? []
        for userProfile in profiles where userProfile.userID == profile.userID {
            userProfile.displayName = profile.displayName
            userProfile.avatarSystemName = profile.avatarSystemName
            userProfile.avatarVersion = profile.avatarVersion
            if profile.avatarDeleted {
                userProfile.avatarPhotoFileName = nil
                userProfile.avatarAssetID = nil
                userProfile.avatarPhotoData = nil
            } else if let avatarAssetID = profile.avatarAssetID {
                let cacheFileName = store.cacheFileName(for: avatarAssetID)
                if store.fileExists(named: cacheFileName) {
                    userProfile.avatarPhotoFileName = cacheFileName
                } else if userProfile.avatarAssetID != avatarAssetID,
                          userProfile.avatarPhotoFileName != cacheFileName {
                    userProfile.avatarPhotoFileName = nil
                    userProfile.avatarPhotoData = nil
                }
                userProfile.avatarAssetID = avatarAssetID
            }
            userProfile.updatedAt = profile.updatedAt
        }
    }

    private func applyAvatarAsset(
        _ asset: AvatarAssetRecordCodable.Asset,
        hasPendingLocalSave: Bool,
        context: ModelContext
    ) {
        guard hasPendingLocalSave == false else { return }
        guard let data = asset.data else { return }

        let store = LocalUserAvatarMediaStore()
        let cacheFileName = store.cacheFileName(for: asset.assetID.uuidString.lowercased())
        try? store.persistAvatarData(data, fileName: cacheFileName)

        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.avatarAssetID == asset.assetID.uuidString.lowercased() {
            membership.avatarPhotoFileName = cacheFileName
            membership.avatarVersion = max(membership.avatarVersion, asset.version)
        }

        let profiles = (try? context.fetch(FetchDescriptor<PersistentUserProfile>())) ?? []
        for userProfile in profiles where userProfile.avatarAssetID == asset.assetID.uuidString.lowercased() {
            userProfile.avatarPhotoFileName = cacheFileName
            userProfile.avatarVersion = max(userProfile.avatarVersion, asset.version)
            userProfile.updatedAt = max(userProfile.updatedAt, asset.updatedAt)
        }
    }

    private func archiveLocalRecord(uuid: UUID, recordType: String, context: ModelContext) {
        if recordType == ItemRecordCodable.ckRecordType {
            // Items use archive semantics
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.id == uuid }
            )
            if let item = try? context.fetch(descriptor).first, !item.isArchived {
                item.isArchived = true
                item.archivedAt = .now
                item.updatedAt = .now
            }
        } else if recordType == TaskListRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentTaskList>(
                predicate: #Predicate<PersistentTaskList> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == ProjectRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentProject>(
                predicate: #Predicate<PersistentProject> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == ProjectSubtaskRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentProjectSubtask>(
                predicate: #Predicate<PersistentProjectSubtask> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == PeriodicTaskRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == SpaceRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentSpace>(
                predicate: #Predicate<PersistentSpace> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                entity.statusRawValue = SpaceStatus.archived.rawValue
                entity.archivedAt = .now
                entity.updatedAt = .now
            }
        } else if recordType == MemberProfileRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentPairMembership>(
                predicate: #Predicate<PersistentPairMembership> { $0.userID == uuid }
            )
            let memberships = (try? context.fetch(descriptor)) ?? []
            let store = LocalUserAvatarMediaStore()
            for membership in memberships {
                if let fileName = membership.avatarPhotoFileName {
                    try? store.removeAvatar(named: fileName)
                }
                membership.avatarPhotoFileName = nil
            }
        } else if recordType == AvatarAssetRecordCodable.ckRecordType {
            let store = LocalUserAvatarMediaStore()
            let cacheFileName = store.cacheFileName(for: uuid.uuidString.lowercased())
            try? store.removeAvatar(named: cacheFileName)
        }
    }

    private func pendingLocalSaveRecordNames(in syncEngine: CKSyncEngine) -> Set<String> {
        Set(
            syncEngine.state.pendingRecordZoneChanges.compactMap { change in
                guard case .saveRecord(let recordID) = change, recordID.zoneID == zoneID else { return nil }
                return recordID.recordName
            }
        )
    }

    private func localMutationStateByRecordName(
        for records: [CKRecord]
    ) -> [String: SyncMutationLifecycleState] {
        let requested = records.compactMap { record -> (String, SyncEntityKind)? in
            guard
                let recordID = UUID(uuidString: record.recordID.recordName),
                let entityKind = SyncEntityKind(ckRecordType: record.recordType)
            else {
                return nil
            }
            return (recordID.uuidString, entityKind)
        }
        guard requested.isEmpty == false else { return [:] }

        let context = ModelContext(modelContainer)
        let recordIDs = requested.map { UUID(uuidString: $0.0)! }
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> { recordIDs.contains($0.recordID) }
        )

        guard let records = try? context.fetch(descriptor), records.isEmpty == false else { return [:] }

        let recordsByCompoundKey = Dictionary(
            grouping: records,
            by: {
                MutationLookupKey(
                    recordName: $0.recordID.uuidString,
                    entityKindRawValue: $0.entityKindRawValue
                )
            }
        )

        var result: [String: SyncMutationLifecycleState] = [:]
        for (recordName, entityKind) in requested {
            guard let matchingRecords = recordsByCompoundKey[
                MutationLookupKey(
                    recordName: recordName,
                    entityKindRawValue: entityKind.rawValue
                )
            ] else {
                continue
            }
            let latest = matchingRecords.max { lhs, rhs in
                if lhs.changedAt == rhs.changedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.changedAt < rhs.changedAt
            }
            result[recordName] = latest?.lifecycleState
        }
        return result
    }

    private func shouldPreserveLocalMutation(
        for lifecycleState: SyncMutationLifecycleState?
    ) -> Bool {
        switch lifecycleState {
        case .pending, .sending, .failed:
            return true
        case .confirmed, .none:
            return false
        }
    }

    private func markMutations(
        for recordIDs: [CKRecord.ID],
        state: SyncMutationLifecycleState,
        attemptedAt: Date? = nil,
        confirmedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        guard recordIDs.isEmpty == false else { return }

        let uuids = recordIDs.compactMap { UUID(uuidString: $0.recordName) }
        guard uuids.isEmpty == false else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> { uuids.contains($0.recordID) }
        )

        guard let records = try? context.fetch(descriptor), records.isEmpty == false else { return }

        for record in records {
            record.lifecycleState = state
            if let attemptedAt {
                record.lastAttemptedAt = attemptedAt
            }
            if let confirmedAt {
                record.confirmedAt = confirmedAt
            }
            record.lastError = errorMessage
        }

        try? context.save()
    }

    // MARK: - Helpers

    private func fetchAndEncode(uuid: UUID, entityKind: SyncEntityKind, context: ModelContext) -> CKRecord? {
        switch entityKind {
        case .task:
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            let item = persistent.domainModel()
            return ItemRecordCodable(item: item).toCKRecord(in: zoneID)

        case .taskList:
            let descriptor = FetchDescriptor<PersistentTaskList>(
                predicate: #Predicate<PersistentTaskList> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            let list = persistent.domainModel(taskCount: 0)
            return TaskListRecordCodable(taskList: list).toCKRecord(in: zoneID)

        case .project:
            let descriptor = FetchDescriptor<PersistentProject>(
                predicate: #Predicate<PersistentProject> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            let project = persistent.domainModel(taskCount: 0)
            return ProjectRecordCodable(project: project).toCKRecord(in: zoneID)

        case .projectSubtask:
            let descriptor = FetchDescriptor<PersistentProjectSubtask>(
                predicate: #Predicate<PersistentProjectSubtask> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            let subtask = persistent.domainModel()
            return ProjectSubtaskRecordCodable(subtask: subtask).toCKRecord(in: zoneID)

        case .periodicTask:
            let descriptor = FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            let task = persistent.domainModel()
            return PeriodicTaskRecordCodable(periodicTask: task).toCKRecord(in: zoneID)

        case .space:
            let descriptor = FetchDescriptor<PersistentSpace>(
                predicate: #Predicate<PersistentSpace> { $0.id == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }
            return SpaceRecordCodable(space: persistent.domainModel).toCKRecord(in: zoneID)

        case .memberProfile:
            let descriptor = FetchDescriptor<PersistentUserProfile>(
                predicate: #Predicate<PersistentUserProfile> { $0.userID == uuid }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }

            let memberships = (try? context.fetch(
                FetchDescriptor<PersistentPairMembership>(
                    predicate: #Predicate<PersistentPairMembership> { $0.userID == uuid }
                )
            )) ?? []
            let pairSpaceIDs = Set(memberships.map(\.pairSpaceID))
            let pairSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
            guard let activePairSpace = pairSpaces.first(where: { pairSpaceIDs.contains($0.id) && $0.endedAt == nil }) else {
                return nil
            }

            let profile = Self.makeMemberProfilePayload(from: persistent, sharedSpaceID: activePairSpace.sharedSpaceID)
            return MemberProfileRecordCodable(profile: profile).toCKRecord(in: zoneID)

        case .avatarAsset:
            let assetID = uuid.uuidString.lowercased()
            let descriptor = FetchDescriptor<PersistentUserProfile>(
                predicate: #Predicate<PersistentUserProfile> { $0.avatarAssetID == assetID }
            )
            guard let persistent = try? context.fetch(descriptor).first else { return nil }

            let store = LocalUserAvatarMediaStore()
            let fileName = persistent.avatarPhotoFileName ?? store.cacheFileName(for: assetID)
            guard store.fileExists(named: fileName) else { return nil }

            let asset = AvatarAssetRecordCodable.Asset(
                assetID: uuid,
                version: persistent.avatarVersion,
                updatedAt: persistent.updatedAt,
                fileName: fileName,
                data: nil
            )
            return AvatarAssetRecordCodable(asset: asset).toCKRecord(in: zoneID)

        case .taskMessage:
            return nil // Not synced via CloudKit; Supabase-only event log

        case .importantDate:
            return nil // CloudKit encoding handled in a later task
        }
    }

    private func zoneIDToSpaceID() -> UUID {
        // Extract spaceID from zone name: "solo" → a fixed UUID, "pair-<uuid>" → that UUID
        if zoneID.zoneName == "solo" {
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        }
        let prefix = "pair-"
        if zoneID.zoneName.hasPrefix(prefix) {
            let uuidString = String(zoneID.zoneName.dropFirst(prefix.count))
            return UUID(uuidString: uuidString) ?? UUID()
        }
        return UUID()
    }
}

#if DEBUG
extension SyncEngineDelegate {
    func buildRecordForTesting(uuid: UUID, entityKind: SyncEntityKind) -> CKRecord? {
        let context = ModelContext(modelContainer)
        return fetchAndEncode(uuid: uuid, entityKind: entityKind, context: context)
    }
}
#endif
