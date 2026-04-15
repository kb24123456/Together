import CloudKit
import Foundation
import SwiftData

/// Extracts `CKErrorRetryAfterKey` from a CloudKit error.
private nonisolated func pairSyncRetryAfter(from error: Error) -> TimeInterval? {
    guard let ckError = error as? CKError else { return nil }
    if ckError.code == .requestRateLimited || ckError.code == .zoneBusy {
        return (ckError as NSError).userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 30
    }
    return nil
}

/// Error types specific to pair sync.
enum PairSyncError: Error {
    case notConfigured
    case rateLimited(retryAfter: TimeInterval)
}

/// Core pair sync actor that pushes/pulls against the CloudKit **public** database.
///
/// Replaces the CKSyncEngine-based pair sync (SyncEngineCoordinator + PairSyncBridge)
/// with a simpler CKQuery polling approach. Solo sync via CKSyncEngine is untouched.
///
/// Reuses `PersistentSyncChange` for mutation lifecycle tracking and
/// `PersistentSyncState` for pull cursor storage.
actor PairSyncService {

    // MARK: - Dependencies

    private let ckContainer: CKContainer
    private let modelContainer: ModelContainer
    private typealias Codec = PairSyncCodecRegistry

    // MARK: - Active state

    /// The shared space ID (not pairSpaceID) — matches how PersistentSyncChange and
    /// PersistentItem store their spaceID.
    private var activeSpaceID: UUID?
    private var myUserID: UUID?

    private var database: CKDatabase { ckContainer.publicCloudDatabase }

    // MARK: - Init

    init(ckContainer: CKContainer, modelContainer: ModelContainer) {
        self.ckContainer = ckContainer
        self.modelContainer = modelContainer
    }

    func configure(spaceID: UUID, myUserID: UUID) {
        self.activeSpaceID = spaceID
        self.myUserID = myUserID
        #if DEBUG
        print("[PairSync] Configured for spaceID=\(spaceID.uuidString.prefix(8)) userID=\(myUserID.uuidString.prefix(8))")
        #endif
    }

    func teardown() {
        activeSpaceID = nil
        myUserID = nil
        #if DEBUG
        print("[PairSync] Teardown")
        #endif
    }

    // MARK: - Sync Cycle

    /// Performs one full push+pull cycle. Returns result for the poller.
    func syncOnce() async -> PollResult {
        guard activeSpaceID != nil else { return .noChange }
        do {
            let pushed = try await push()
            let pulled = try await pull()
            let total = pushed + pulled
            return total > 0 ? .changes(total) : .noChange
        } catch {
            #if DEBUG
            print("[PairSync] syncOnce error: \(error)")
            #endif
            return .failed(error)
        }
    }

    // MARK: - Push

    /// Reads pending `PersistentSyncChange` rows, encodes to CKRecords,
    /// pushes to public DB via `modifyRecords(.changedKeys)`.
    func push() async throws -> Int {
        guard let spaceID = activeSpaceID else { throw PairSyncError.notConfigured }

        let context = ModelContext(modelContainer)

        // 1. Fetch pending/failed changes for supported entity kinds
        let pendingRaw = SyncMutationLifecycleState.pending.rawValue
        let failedRaw = SyncMutationLifecycleState.failed.rawValue
        let supportedKinds = Codec.supportedEntityKinds.map(\.rawValue)

        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> {
                $0.spaceID == spaceID
                && ($0.lifecycleStateRawValue == pendingRaw || $0.lifecycleStateRawValue == failedRaw)
                && supportedKinds.contains($0.entityKindRawValue)
            },
            sortBy: [SortDescriptor(\PersistentSyncChange.changedAt, order: .forward)]
        )

        let changes: [PersistentSyncChange]
        do {
            changes = try context.fetch(descriptor)
        } catch {
            #if DEBUG
            print("[PairSync:Push] Failed to fetch pending changes: \(error)")
            #endif
            return 0
        }

        guard !changes.isEmpty else { return 0 }

        // 2. Mark as sending
        for change in changes {
            change.lifecycleState = .sending
            change.lastAttemptedAt = .now
        }
        try? context.save()

        // 3. Encode to CKRecords
        var recordsToSave: [CKRecord] = []
        var changesByRecordName: [String: PersistentSyncChange] = [:]

        for change in changes {
            let entityKind = SyncEntityKind(rawValue: change.entityKindRawValue) ?? .task
            let operation = SyncOperationKind(rawValue: change.operationRawValue) ?? .upsert

            switch operation {
            case .delete, .archive:
                // Permission check: only the creator can soft-delete
                if let creatorID = lookupCreatorID(entityKind: entityKind, recordID: change.recordID, context: context),
                   creatorID != myUserID {
                    #if DEBUG
                    print("[PairSync:Push] ⛔ Skipping unauthorized delete for \(entityKind) \(change.recordID.uuidString.prefix(8))")
                    #endif
                    change.lifecycleState = .confirmed
                    change.confirmedAt = .now
                    change.lastError = "Permission denied: not creator"
                    continue
                }
                if let record = Codec.encodeSoftDelete(
                    entityKind: entityKind,
                    recordID: change.recordID,
                    spaceID: spaceID,
                    at: change.changedAt
                ) {
                    recordsToSave.append(record)
                    changesByRecordName[record.recordID.recordName] = change
                }

            case .upsert, .complete:
                if let record = encodeEntityForPush(
                    entityKind: entityKind,
                    recordID: change.recordID,
                    spaceID: spaceID,
                    context: context
                ) {
                    recordsToSave.append(record)
                    changesByRecordName[record.recordID.recordName] = change
                } else {
                    #if DEBUG
                    print("[PairSync:Push] Entity not found: kind=\(entityKind) id=\(change.recordID), marking confirmed")
                    #endif
                    change.lifecycleState = .confirmed
                    change.confirmedAt = .now
                }
            }
        }

        guard !recordsToSave.isEmpty else {
            try? context.save()
            return 0
        }

        #if DEBUG
        print("[PairSync:Push] Pushing \(recordsToSave.count) records to public DB")
        #endif

        // 4. Push to CloudKit
        let saveResults: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            (saveResults, _) = try await database.modifyRecords(
                saving: recordsToSave,
                deleting: [],  // Never delete in public DB — soft-delete only
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            // Batch-level error (rate limit, network, etc.)
            if let retryAfter = pairSyncRetryAfter(from: error) {
                for change in changes { change.lifecycleState = .failed; change.lastError = "Rate limited" }
                try? context.save()
                throw PairSyncError.rateLimited(retryAfter: retryAfter)
            }
            for change in changes { change.lifecycleState = .failed; change.lastError = error.localizedDescription }
            try? context.save()
            throw error
        }

        // 5. Process per-record results
        var successCount = 0
        var retryRecords: [CKRecord] = []

        for (recordID, result) in saveResults {
            let change = changesByRecordName[recordID.recordName]
            switch result {
            case .success:
                successCount += 1
                change?.lifecycleState = .confirmed
                change?.confirmedAt = .now
                change?.lastError = nil

            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                    // Conflict: merge local changes onto server record and retry
                    if let serverRecord = ckError.serverRecord,
                       let clientRecord = recordsToSave.first(where: { $0.recordID == recordID }) {
                        let merged = mergeOntoServerRecord(client: clientRecord, server: serverRecord)
                        retryRecords.append(merged)
                    } else {
                        change?.lifecycleState = .failed
                        change?.lastError = "serverRecordChanged (no server record)"
                    }
                } else {
                    #if DEBUG
                    print("[PairSync:Push] Save failed for \(recordID.recordName): \(error)")
                    #endif
                    change?.lifecycleState = .failed
                    change?.lastError = error.localizedDescription
                }
            }
        }

        // 6. Retry conflicted records once
        if !retryRecords.isEmpty {
            #if DEBUG
            print("[PairSync:Push] Retrying \(retryRecords.count) conflicted records")
            #endif
            do {
                let (retrySaveResults, _) = try await database.modifyRecords(
                    saving: retryRecords,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
                for (recordID, result) in retrySaveResults {
                    let change = changesByRecordName[recordID.recordName]
                    switch result {
                    case .success:
                        successCount += 1
                        change?.lifecycleState = .confirmed
                        change?.confirmedAt = .now
                        change?.lastError = nil
                    case .failure(let error):
                        change?.lifecycleState = .failed
                        change?.lastError = "Retry failed: \(error.localizedDescription)"
                    }
                }
            } catch {
                for record in retryRecords {
                    changesByRecordName[record.recordID.recordName]?.lifecycleState = .failed
                    changesByRecordName[record.recordID.recordName]?.lastError = "Retry batch failed"
                }
            }
        }

        try? context.save()

        #if DEBUG
        print("[PairSync:Push] Done: \(successCount) succeeded")
        #endif
        return successCount
    }

    // MARK: - Pull

    /// Queries public DB for remote changes since last pull, merges into SwiftData.
    func pull() async throws -> Int {
        guard let spaceID = activeSpaceID else { throw PairSyncError.notConfigured }

        let context = ModelContext(modelContainer)

        // 1. Read last pull date from PersistentSyncState
        let lastPullDate = readLastPullDate(spaceID: spaceID, context: context)

        // 2. Build query with 2-second overlap window
        let predicate: NSPredicate
        if let lastPull = lastPullDate {
            let safeDate = lastPull.addingTimeInterval(-2)
            predicate = NSPredicate(
                format: "spaceID == %@ AND updatedAt > %@",
                spaceID.uuidString as NSString,
                safeDate as NSDate
            )
        } else {
            // First pull: fetch all non-deleted records for this space
            predicate = NSPredicate(
                format: "spaceID == %@",
                spaceID.uuidString as NSString
            )
        }

        // 3. Query each supported record type
        var appliedCount = 0
        for recordType in Codec.supportedRecordTypes {
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

            var records: [CKRecord] = []
            do {
                records = try await fetchAllRecords(matching: query)
            } catch {
                if let retryAfter = pairSyncRetryAfter(from: error) {
                    throw PairSyncError.rateLimited(retryAfter: retryAfter)
                }
                throw error
            }

            #if DEBUG
            if !records.isEmpty {
                print("[PairSync:Pull] \(recordType): \(records.count) records fetched")
            }
            #endif

            for record in records {
                let applied = applyRemoteRecord(record, spaceID: spaceID, context: context)
                if applied { appliedCount += 1 }
            }
        }

        // 4. Update pull cursor
        updatePullDate(spaceID: spaceID, context: context)
        try? context.save()

        #if DEBUG
        if appliedCount > 0 {
            print("[PairSync:Pull] Applied \(appliedCount) changes")
        }
        #endif
        return appliedCount
    }

    // MARK: - Private Helpers

    /// Merges client's changed fields onto the server record for conflict retry.
    private func mergeOntoServerRecord(client: CKRecord, server: CKRecord) -> CKRecord {
        for key in client.changedKeys() {
            server[key] = client[key]
        }
        return server
    }

    /// Fetches all matching records with pagination.
    private func fetchAllRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []

        let (firstResults, firstCursor) = try await database.records(
            matching: query,
            inZoneWith: nil,
            resultsLimit: CKQueryOperation.maximumResults
        )
        for (_, result) in firstResults {
            if let record = try? result.get() {
                allRecords.append(record)
            }
        }

        var cursor = firstCursor
        while let nextCursor = cursor {
            let (moreResults, moreCursor) = try await database.records(
                continuingMatchFrom: nextCursor,
                resultsLimit: CKQueryOperation.maximumResults
            )
            for (_, result) in moreResults {
                if let record = try? result.get() {
                    allRecords.append(record)
                }
            }
            cursor = moreCursor
        }

        return allRecords
    }

    /// Applies a single remote CKRecord to local SwiftData.
    /// Returns `true` if a change was actually applied.
    private func applyRemoteRecord(_ record: CKRecord, spaceID: UUID, context: ModelContext) -> Bool {
        let recordID = UUID(uuidString: record.recordID.recordName) ?? UUID()

        // Check if there's a pending local mutation for this record — skip if yes
        if hasPendingLocalMutation(recordID: recordID, spaceID: spaceID, context: context) {
            return false
        }

        // Decode the record
        guard let decoded = Codec.decode(record) else { return false }

        // Soft-delete handling — validate that the deleter is the creator
        if Codec.isSoftDeleted(record) {
            let remoteCreatorID = UUID(uuidString: (record["creatorID"] as? String) ?? "")
            let localCreatorID = lookupCreatorID(entityKind: decoded.entityKind, recordID: recordID, context: context)
            if let localCreatorID, let remoteCreatorID, localCreatorID != remoteCreatorID {
                #if DEBUG
                print("[PairSync:Pull] ⛔ Rejected unauthorized soft-delete for \(decoded.entityKind) \(recordID.uuidString.prefix(8))")
                #endif
                return false
            }
            return applySoftDelete(entityKind: decoded.entityKind, recordID: recordID, context: context)
        }

        // Apply by entity type
        switch decoded {
        case .task(let item):
            return upsertLocalItem(item, context: context)
        case .taskList(let list):
            return upsertLocalTaskList(list, context: context)
        case .project(let project):
            return upsertLocalProject(project, context: context)
        case .projectSubtask(let subtask):
            return upsertLocalProjectSubtask(subtask, context: context)
        case .periodicTask(let task):
            return upsertLocalPeriodicTask(task, context: context)
        case .space(let space):
            return upsertLocalSpace(space, context: context)
        case .memberProfile(let profile):
            return applyMemberProfile(profile, context: context)
        case .avatarAsset(let asset):
            return applyAvatarAsset(asset, context: context)
        }
    }

    /// Looks up the creatorID of a local entity by kind and record ID.
    private func lookupCreatorID(entityKind: SyncEntityKind, recordID: UUID, context: ModelContext) -> UUID? {
        switch entityKind {
        case .task:
            let d = FetchDescriptor<PersistentItem>(predicate: #Predicate<PersistentItem> { $0.id == recordID })
            return (try? context.fetch(d).first)?.creatorID
        case .taskList:
            let d = FetchDescriptor<PersistentTaskList>(predicate: #Predicate<PersistentTaskList> { $0.id == recordID })
            return (try? context.fetch(d).first)?.creatorID
        case .project:
            let d = FetchDescriptor<PersistentProject>(predicate: #Predicate<PersistentProject> { $0.id == recordID })
            return (try? context.fetch(d).first)?.creatorID
        case .periodicTask:
            let d = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate<PersistentPeriodicTask> { $0.id == recordID })
            return (try? context.fetch(d).first)?.creatorID
        default:
            return nil
        }
    }

    /// Checks whether the given recordID has an outstanding local mutation.
    private func hasPendingLocalMutation(recordID: UUID, spaceID: UUID, context: ModelContext) -> Bool {
        let pendingRaw = SyncMutationLifecycleState.pending.rawValue
        let sendingRaw = SyncMutationLifecycleState.sending.rawValue
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> {
                $0.recordID == recordID
                && $0.spaceID == spaceID
                && ($0.lifecycleStateRawValue == pendingRaw || $0.lifecycleStateRawValue == sendingRaw)
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Push Encoding (per entity type)

    private func encodeEntityForPush(
        entityKind: SyncEntityKind,
        recordID: UUID,
        spaceID: UUID,
        context: ModelContext
    ) -> CKRecord? {
        let targetID = recordID
        switch entityKind {
        case .task:
            let d = FetchDescriptor<PersistentItem>(predicate: #Predicate<PersistentItem> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairTaskRecordCodec.encode(p.domainModel())

        case .taskList:
            let d = FetchDescriptor<PersistentTaskList>(predicate: #Predicate<PersistentTaskList> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairTaskListRecordCodec.encode(p.domainModel(taskCount: 0), creatorID: myUserID ?? UUID())

        case .project:
            let d = FetchDescriptor<PersistentProject>(predicate: #Predicate<PersistentProject> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairProjectRecordCodec.encode(p.domainModel(taskCount: 0), creatorID: myUserID ?? UUID())

        case .projectSubtask:
            let d = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate<PersistentProjectSubtask> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairProjectSubtaskRecordCodec.encode(p.domainModel(), spaceID: spaceID, creatorID: myUserID ?? UUID())

        case .periodicTask:
            let d = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate<PersistentPeriodicTask> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairPeriodicTaskRecordCodec.encode(p.domainModel())

        case .space:
            let d = FetchDescriptor<PersistentSpace>(predicate: #Predicate<PersistentSpace> { $0.id == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairSpaceRecordCodec.encode(p.domainModel)

        case .memberProfile:
            let d = FetchDescriptor<PersistentPairMembership>(predicate: #Predicate<PersistentPairMembership> { $0.userID == targetID })
            guard let p = try? context.fetch(d).first else { return nil }
            return PairMemberProfileRecordCodec.encode(
                MemberProfileRecordCodable.Profile(
                    userID: p.userID,
                    spaceID: spaceID,
                    displayName: p.nickname,
                    avatarSystemName: p.avatarSystemName,
                    avatarAssetID: p.avatarAssetID,
                    avatarVersion: p.avatarVersion,
                    avatarDeleted: false,
                    updatedAt: .now
                )
            )

        case .avatarAsset:
            let assetIDString = targetID.uuidString.lowercased()
            let fileName = UserAvatarStorage.fileName(forAssetID: assetIDString)
            let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
            return PairAvatarAssetRecordCodec.encode(
                AvatarAssetRecordCodable.Asset(
                    assetID: targetID,
                    version: 0,
                    updatedAt: .now,
                    fileName: fileName,
                    data: nil
                ),
                spaceID: spaceID
            )
        }
    }

    // MARK: - Pull Upsert (per entity type)

    private func upsertLocalItem(_ item: Item, context: ModelContext) -> Bool {
        let itemID = item.id
        let d = FetchDescriptor<PersistentItem>(predicate: #Predicate<PersistentItem> { $0.id == itemID })
        if let existing = try? context.fetch(d).first {
            if item.updatedAt > existing.updatedAt {
                existing.update(from: item)
                return true
            }
            return false
        } else {
            context.insert(PersistentItem(item: item))
            return true
        }
    }

    private func upsertLocalTaskList(_ list: TaskList, context: ModelContext) -> Bool {
        let listID = list.id
        let d = FetchDescriptor<PersistentTaskList>(predicate: #Predicate<PersistentTaskList> { $0.id == listID })
        if let existing = try? context.fetch(d).first {
            if list.updatedAt > existing.updatedAt {
                existing.update(from: list)
                return true
            }
            return false
        } else {
            context.insert(PersistentTaskList(list: list))
            return true
        }
    }

    private func upsertLocalProject(_ project: Project, context: ModelContext) -> Bool {
        let projectID = project.id
        let d = FetchDescriptor<PersistentProject>(predicate: #Predicate<PersistentProject> { $0.id == projectID })
        if let existing = try? context.fetch(d).first {
            if project.updatedAt > existing.updatedAt {
                existing.update(from: project)
                return true
            }
            return false
        } else {
            context.insert(PersistentProject(project: project))
            return true
        }
    }

    private func upsertLocalProjectSubtask(_ subtask: ProjectSubtask, context: ModelContext) -> Bool {
        let subtaskID = subtask.id
        let d = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate<PersistentProjectSubtask> { $0.id == subtaskID })
        if let existing = try? context.fetch(d).first {
            existing.update(from: subtask)
            return true
        } else {
            context.insert(PersistentProjectSubtask(subtask: subtask))
            return true
        }
    }

    private func upsertLocalPeriodicTask(_ task: PeriodicTask, context: ModelContext) -> Bool {
        let taskID = task.id
        let d = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID })
        if let existing = try? context.fetch(d).first {
            if task.updatedAt > existing.updatedAt {
                existing.update(from: task)
                return true
            }
            return false
        } else {
            context.insert(PersistentPeriodicTask(task: task))
            return true
        }
    }

    private func upsertLocalSpace(_ space: Space, context: ModelContext) -> Bool {
        let spaceID = space.id
        let d = FetchDescriptor<PersistentSpace>(predicate: #Predicate<PersistentSpace> { $0.id == spaceID })
        if let existing = try? context.fetch(d).first {
            // Reject if remote tries to change the ownerUserID
            if space.ownerUserID != existing.ownerUserID {
                #if DEBUG
                print("[PairSync:Pull] ⛔ Rejected ownerUserID change for space \(spaceID.uuidString.prefix(8))")
                #endif
                return false
            }
            if space.updatedAt > existing.updatedAt {
                existing.update(from: space)
                return true
            }
            return false
        } else {
            context.insert(PersistentSpace(space: space))
            return true
        }
    }

    private func applyMemberProfile(_ profile: MemberProfileRecordCodable.Profile, context: ModelContext) -> Bool {
        let targetUserID = profile.userID
        let d = FetchDescriptor<PersistentPairMembership>(predicate: #Predicate<PersistentPairMembership> { $0.userID == targetUserID })
        if let existing = try? context.fetch(d).first {
            existing.nickname = profile.displayName
            existing.avatarSystemName = profile.avatarSystemName
            existing.avatarAssetID = profile.avatarAssetID
            existing.avatarVersion = profile.avatarVersion
            return true
        }
        // Membership record must already exist from pairing setup; skip if not found
        return false
    }

    private func applyAvatarAsset(_ asset: AvatarAssetRecordCodable.Asset, context: ModelContext) -> Bool {
        guard let data = asset.data, !data.isEmpty else { return false }
        let fileName = UserAvatarStorage.fileName(forAssetID: asset.assetID.uuidString.lowercased())
        let avatarStore = LocalUserAvatarMediaStore()
        do {
            try avatarStore.persistAvatarData(data, fileName: fileName)
            // Update membership avatar file reference
            let assetIDString = asset.assetID.uuidString.lowercased()
            let d = FetchDescriptor<PersistentPairMembership>(predicate: #Predicate<PersistentPairMembership> { $0.avatarAssetID == assetIDString })
            if let membership = try? context.fetch(d).first {
                membership.avatarPhotoFileName = fileName
            }
            return true
        } catch {
            #if DEBUG
            print("[PairSync:Pull] Failed to persist avatar asset: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Soft-Delete

    private func applySoftDelete(entityKind: SyncEntityKind, recordID: UUID, context: ModelContext) -> Bool {
        switch entityKind {
        case .task:
            let d = FetchDescriptor<PersistentItem>(predicate: #Predicate<PersistentItem> { $0.id == recordID })
            guard let item = try? context.fetch(d).first, !item.isArchived else { return false }
            item.isArchived = true
            item.archivedAt = .now
            item.updatedAt = .now
            return true
        case .taskList:
            let d = FetchDescriptor<PersistentTaskList>(predicate: #Predicate<PersistentTaskList> { $0.id == recordID })
            guard let list = try? context.fetch(d).first else { return false }
            context.delete(list)
            return true
        case .project:
            let d = FetchDescriptor<PersistentProject>(predicate: #Predicate<PersistentProject> { $0.id == recordID })
            guard let project = try? context.fetch(d).first else { return false }
            context.delete(project)
            return true
        case .projectSubtask:
            let d = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate<PersistentProjectSubtask> { $0.id == recordID })
            guard let subtask = try? context.fetch(d).first else { return false }
            context.delete(subtask)
            return true
        case .periodicTask:
            let d = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate<PersistentPeriodicTask> { $0.id == recordID })
            guard let task = try? context.fetch(d).first else { return false }
            context.delete(task)
            return true
        case .space, .memberProfile, .avatarAsset:
            return false  // These types are not soft-deleted
        }
    }

    /// Reads the last pull date from PersistentSyncState.
    private func readLastPullDate(spaceID: UUID, context: ModelContext) -> Date? {
        let descriptor = FetchDescriptor<PersistentSyncState>(
            predicate: #Predicate<PersistentSyncState> { $0.spaceID == spaceID }
        )
        return try? context.fetch(descriptor).first?.cursorUpdatedAt
    }

    /// Updates the pull cursor in PersistentSyncState.
    private func updatePullDate(spaceID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentSyncState>(
            predicate: #Predicate<PersistentSyncState> { $0.spaceID == spaceID }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.cursorUpdatedAt = .now
            existing.lastSyncedAt = .now
            existing.lastError = nil
            existing.retryCount = 0
            existing.updatedAt = .now
        } else {
            let state = SyncState(
                spaceID: spaceID,
                cursor: SyncCursor(token: "pairPull", updatedAt: .now),
                lastSyncedAt: .now,
                lastError: nil,
                retryCount: 0,
                updatedAt: .now
            )
            context.insert(PersistentSyncState(state: state))
        }
    }
}
