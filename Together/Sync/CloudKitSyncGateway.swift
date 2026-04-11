import CloudKit
import Foundation

private nonisolated func extractRetryAfter(from error: Error) -> TimeInterval? {
    guard let ckError = error as? CKError else { return nil }
    if ckError.code == .requestRateLimited || ckError.code == .zoneBusy {
        return (ckError as NSError).userInfo[CKErrorRetryAfterKey] as? TimeInterval ?? 30
    }
    return nil
}

enum CloudKitSyncGatewayError: Error, Equatable {
    case missingConfiguration
    case unsupportedEntity(SyncEntityKind)
    case taskRecordNotFound(UUID)
    case rateLimited(retryAfter: TimeInterval)
    case spaceNotConfigured
}

/// Syncs `Item` (Task) records with CloudKit's **public** database (default zone).
///
/// Uses `CKQuery` filtered by `spaceID` for pull, since public DB does not support
/// custom zones or `CKFetchRecordZoneChangesOperation`.
///
/// Incremental sync uses `updatedAt > lastSyncDate` predicate.
actor CloudKitSyncGateway: CloudSyncGatewayProtocol {
    private let configuration: CloudKitSyncConfiguration
    private let itemRepository: ItemRepositoryProtocol
    private let container: CKContainer

    /// The space ID used to scope records in the public default zone.
    private var activeSpaceID: UUID?

    init(
        configuration: CloudKitSyncConfiguration,
        itemRepository: ItemRepositoryProtocol
    ) {
        self.configuration = configuration
        self.itemRepository = itemRepository
        self.container = CKContainer(identifier: configuration.containerIdentifier)
    }

    // MARK: - Configuration

    /// Configure the gateway for a specific pair space.
    func configure(spaceID: UUID) {
        self.activeSpaceID = spaceID
        #if DEBUG
        print("[SyncGateway] Configured for spaceID: \(spaceID.uuidString.prefix(8))")
        #endif
    }

    private var database: CKDatabase {
        container.publicCloudDatabase
    }

    /// Default zone — public DB only supports this.
    private var defaultZoneID: CKRecordZone.ID {
        CKRecordZone.default().zoneID
    }

    // MARK: - Push

    func push(changes: [SyncChange], for spaceID: UUID) async throws -> SyncPushResult {
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }
        guard activeSpaceID != nil else {
            throw CloudKitSyncGatewayError.spaceNotConfigured
        }

        let db = database
        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in changes {
            switch change.entityKind {
            case .task:
                switch change.operation {
                case .delete:
                    let recordID = CKRecord.ID(recordName: change.recordID.uuidString)
                    recordIDsToDelete.append(recordID)
                default:
                    guard let item = try? await itemRepository.fetchItem(itemID: change.recordID) else {
                        #if DEBUG
                        print("[Sync:Push] ⚠️ Item not found for recordID=\(change.recordID), skipping")
                        #endif
                        continue
                    }
                    let record = try CloudKitTaskRecordCodec.makeRecord(from: item)
                    recordsToSave.append(record)
                }
            case .memberProfile:
                // Profile records are pushed directly via pushProfile()
                break
            default:
                break
            }
        }

        if recordsToSave.isEmpty && recordIDsToDelete.isEmpty {
            #if DEBUG
            print("[Sync:Push] No records to push (changes=\(changes.count) but none are task upserts)")
            #endif
            return SyncPushResult(pushedCount: 0, cursor: nil)
        }

        #if DEBUG
        print("[Sync:Push] Pushing \(recordsToSave.count) saves, \(recordIDsToDelete.count) deletes to public DB")
        #endif

        let saveResults: [CKRecord.ID: Result<CKRecord, Error>]
        let deleteResults: [CKRecord.ID: Result<Void, Error>]
        do {
            (saveResults, deleteResults) = try await db.modifyRecords(
                saving: recordsToSave,
                deleting: recordIDsToDelete,
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            if let retryAfter = extractRetryAfter(from: error) {
                throw CloudKitSyncGatewayError.rateLimited(retryAfter: retryAfter)
            }
            throw error
        }

        var savedCount = 0
        for (recordID, result) in saveResults {
            switch result {
            case .success:
                savedCount += 1
            case .failure(let error):
                #if DEBUG
                print("[Sync:Push] ❌ Save failed for \(recordID.recordName): \(error)")
                #endif
                throw PairingError.cloudOperationFailed(error)
            }
        }

        let deletedCount = deleteResults.values.filter { (try? $0.get()) != nil }.count
        #if DEBUG
        print("[Sync:Push] ✅ Pushed: saved=\(savedCount) deleted=\(deletedCount)")
        #endif
        return SyncPushResult(pushedCount: savedCount + deletedCount, cursor: nil)
    }

    // MARK: - Profile Push

    /// 直接推送一个 MemberProfile 记录到公共库
    func pushProfile(_ payload: CloudKitProfileRecordCodec.MemberProfilePayload) async throws {
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }
        let record = CloudKitProfileRecordCodec.makeRecord(from: payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(op)
        }
        #if DEBUG
        print("[Sync:PushProfile] ✅ Pushed profile for userID=\(payload.userID.uuidString.prefix(8))")
        #endif
    }

    // MARK: - Profile Pull

    /// 拉取该空间中所有成员 profile 记录
    func pullProfiles(spaceID: UUID) async throws -> [CloudKitProfileRecordCodec.MemberProfilePayload] {
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }

        let predicate = NSPredicate(
            format: "spaceID == %@",
            spaceID.uuidString as NSString
        )
        let query = CKQuery(
            recordType: CloudKitProfileRecordCodec.recordType,
            predicate: predicate
        )

        var profiles: [CloudKitProfileRecordCodec.MemberProfilePayload] = []
        let (results, _) = try await database.records(
            matching: query,
            inZoneWith: nil,
            resultsLimit: 10
        )
        for (_, result) in results {
            if let record = try? result.get(),
               let profile = CloudKitProfileRecordCodec.decode(record: record) {
                profiles.append(profile)
            }
        }
        return profiles
    }

    // MARK: - Pull (CKQuery-based for public DB)

    func pull(spaceID: UUID, since cursor: SyncCursor?) async throws -> SyncPullResult {
        guard configuration.containerIdentifier.isEmpty == false else {
            throw CloudKitSyncGatewayError.missingConfiguration
        }
        guard activeSpaceID != nil else {
            throw CloudKitSyncGatewayError.spaceNotConfigured
        }

        let db = database

        // Build query predicate: always filter by spaceID
        // For incremental sync, also filter by updatedAt > lastSyncDate
        let predicate: NSPredicate
        if let lastSync = cursor?.updatedAt {
            // Leave a small overlap window (2 seconds) to avoid missing records
            let safeDate = lastSync.addingTimeInterval(-2)
            predicate = NSPredicate(
                format: "spaceID == %@ AND updatedAt > %@",
                spaceID.uuidString as NSString,
                safeDate as NSDate
            )
        } else {
            // Full pull — fetch all records for this space
            predicate = NSPredicate(
                format: "spaceID == %@",
                spaceID.uuidString as NSString
            )
        }

        let query = CKQuery(
            recordType: CloudKitTaskRecordCodec.recordType,
            predicate: predicate
        )
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var changedItems: [Item] = []
        var queryCursor: CKQueryOperation.Cursor?

        do {
            // First batch
            let (results, cursor) = try await db.records(
                matching: query,
                inZoneWith: nil,
                resultsLimit: CKQueryOperation.maximumResults
            )
            queryCursor = cursor

            for (_, result) in results {
                if let record = try? result.get(),
                   let item = try? CloudKitTaskRecordCodec.decode(record: record) {
                    changedItems.append(item)
                }
            }

            // Fetch remaining pages
            while let nextCursor = queryCursor {
                let (moreResults, moreCursor) = try await db.records(
                    continuingMatchFrom: nextCursor,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                queryCursor = moreCursor

                for (_, result) in moreResults {
                    if let record = try? result.get(),
                       let item = try? CloudKitTaskRecordCodec.decode(record: record) {
                        changedItems.append(item)
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[Sync:Pull] ❌ \(error)")
            #endif
            if let retryAfter = extractRetryAfter(from: error) {
                throw CloudKitSyncGatewayError.rateLimited(retryAfter: retryAfter)
            }
            throw error
        }

        // 同时拉取成员 Profile 更新
        let memberProfiles = (try? await pullProfiles(spaceID: spaceID)) ?? []

        #if DEBUG
        print("[Sync:Pull] spaceID=\(spaceID.uuidString.prefix(8)) tasks=\(changedItems.count) profiles=\(memberProfiles.count)")
        #endif

        let newCursor = SyncCursor(
            token: ISO8601DateFormatter().string(from: .now),
            updatedAt: .now,
            serverChangeTokenData: nil
        )

        let allIDs = changedItems.map(\.id)
        return SyncPullResult(
            cursor: newCursor,
            changedRecordIDs: allIDs,
            payload: RemoteSyncPayload(
                tasks: changedItems,
                deletedTaskIDs: [],
                memberProfiles: memberProfiles
            )
        )
    }
}
