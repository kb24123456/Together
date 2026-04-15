import CloudKit
import Foundation

/// One-time schema seeder for CloudKit Development environment.
///
/// Saves one dummy record per Pair* record type to the public database,
/// which causes CloudKit to auto-create the record type and all fields.
/// After running once, delete the seeded records and configure indexes
/// and security roles in the Dashboard.
///
/// Usage: call `PairSchemaSeeder.seedIfNeeded(container:)` once at app startup.
enum PairSchemaSeeder {

    private static let seedKey = "PairSchemaSeeder.v1.completed"

    /// Seeds all Pair* record types if not already done.
    /// Retries up to 3 times with delay to handle early-launch network unavailability.
    static func seedIfNeeded(container: CKContainer) async {
        guard !UserDefaults.standard.bool(forKey: seedKey) else {
            #if DEBUG
            print("[SchemaSeeder] Already seeded, skipping")
            #endif
            return
        }

        // Wait for network — app launch often triggers this before connectivity is ready
        for attempt in 1...3 {
            #if DEBUG
            print("[SchemaSeeder] Attempt \(attempt)/3: seeding Pair* schema...")
            #endif
            let success = await performSeed(container: container)
            if success { return }
            #if DEBUG
            print("[SchemaSeeder] Attempt \(attempt) failed, retrying in 5s...")
            #endif
            try? await Task.sleep(for: .seconds(5))
        }
        #if DEBUG
        print("[SchemaSeeder] All attempts failed. Will retry next launch.")
        #endif
    }

    private static func performSeed(container: CKContainer) async -> Bool {

        let db = container.publicCloudDatabase
        let dummySpaceID = UUID().uuidString
        let dummyUserID = UUID().uuidString
        let now = Date.now

        // Build one dummy record per type with ALL fields populated
        var records: [CKRecord] = []

        // 1. PairTask (31 fields)
        let task = CKRecord(recordType: "PairTask", recordID: CKRecord.ID(recordName: UUID().uuidString))
        task["spaceID"] = dummySpaceID as CKRecordValue
        task["listID"] = "" as CKRecordValue
        task["projectID"] = "" as CKRecordValue
        task["creatorID"] = dummyUserID as CKRecordValue
        task["title"] = "__schema_seed__" as CKRecordValue
        task["notes"] = "" as CKRecordValue
        task["locationText"] = "" as CKRecordValue
        task["executionRole"] = "initiator" as CKRecordValue
        task["assigneeMode"] = "self" as CKRecordValue
        task["status"] = "pendingConfirmation" as CKRecordValue
        task["assignmentState"] = "active" as CKRecordValue
        task["dueAt"] = now as CKRecordValue
        task["hasExplicitTime"] = (0 as Int64) as CKRecordValue
        task["remindAt"] = now as CKRecordValue
        task["createdAt"] = now as CKRecordValue
        task["updatedAt"] = now as CKRecordValue
        task["completedAt"] = now as CKRecordValue
        task["isPinned"] = (0 as Int64) as CKRecordValue
        task["isDraft"] = (0 as Int64) as CKRecordValue
        task["isArchived"] = (0 as Int64) as CKRecordValue
        task["archivedAt"] = now as CKRecordValue
        task["isDeleted"] = (0 as Int64) as CKRecordValue
        task["deletedAt"] = now as CKRecordValue
        task["repeatRuleJSON"] = "" as CKRecordValue
        task["latestResponseJSON"] = "" as CKRecordValue
        task["responseHistoryJSON"] = "[]" as CKRecordValue
        task["assignmentMessagesJSON"] = "[]" as CKRecordValue
        task["occurrenceCompletionsJSON"] = "[]" as CKRecordValue
        task["lastActionByUserID"] = "" as CKRecordValue
        task["lastActionAt"] = now as CKRecordValue
        task["reminderRequestedAt"] = now as CKRecordValue
        records.append(task)

        // 2. PairTaskList (11 fields)
        let list = CKRecord(recordType: "PairTaskList", recordID: CKRecord.ID(recordName: UUID().uuidString))
        list["spaceID"] = dummySpaceID as CKRecordValue
        list["creatorID"] = dummyUserID as CKRecordValue
        list["name"] = "__schema_seed__" as CKRecordValue
        list["kind"] = "custom" as CKRecordValue
        list["colorToken"] = "" as CKRecordValue
        list["sortOrder"] = (0.0 as Double) as CKRecordValue
        list["isArchived"] = (0 as Int64) as CKRecordValue
        list["createdAt"] = now as CKRecordValue
        list["updatedAt"] = now as CKRecordValue
        list["isDeleted"] = (0 as Int64) as CKRecordValue
        list["deletedAt"] = now as CKRecordValue
        records.append(list)

        // 3. PairProject (13 fields)
        let project = CKRecord(recordType: "PairProject", recordID: CKRecord.ID(recordName: UUID().uuidString))
        project["spaceID"] = dummySpaceID as CKRecordValue
        project["creatorID"] = dummyUserID as CKRecordValue
        project["name"] = "__schema_seed__" as CKRecordValue
        project["notes"] = "" as CKRecordValue
        project["colorToken"] = "" as CKRecordValue
        project["status"] = "active" as CKRecordValue
        project["targetDate"] = now as CKRecordValue
        project["remindAt"] = now as CKRecordValue
        project["createdAt"] = now as CKRecordValue
        project["updatedAt"] = now as CKRecordValue
        project["completedAt"] = now as CKRecordValue
        project["isDeleted"] = (0 as Int64) as CKRecordValue
        project["deletedAt"] = now as CKRecordValue
        records.append(project)

        // 4. PairProjectSubtask (9 fields)
        let subtask = CKRecord(recordType: "PairProjectSubtask", recordID: CKRecord.ID(recordName: UUID().uuidString))
        subtask["projectID"] = UUID().uuidString as CKRecordValue
        subtask["spaceID"] = dummySpaceID as CKRecordValue
        subtask["creatorID"] = dummyUserID as CKRecordValue
        subtask["title"] = "__schema_seed__" as CKRecordValue
        subtask["isCompleted"] = (0 as Int64) as CKRecordValue
        subtask["sortOrder"] = (0 as Int64) as CKRecordValue
        subtask["updatedAt"] = now as CKRecordValue
        subtask["isDeleted"] = (0 as Int64) as CKRecordValue
        subtask["deletedAt"] = now as CKRecordValue
        records.append(subtask)

        // 5. PairPeriodicTask (13 fields)
        let periodic = CKRecord(recordType: "PairPeriodicTask", recordID: CKRecord.ID(recordName: UUID().uuidString))
        periodic["spaceID"] = dummySpaceID as CKRecordValue
        periodic["creatorID"] = dummyUserID as CKRecordValue
        periodic["title"] = "__schema_seed__" as CKRecordValue
        periodic["notes"] = "" as CKRecordValue
        periodic["cycle"] = "weekly" as CKRecordValue
        periodic["sortOrder"] = (0.0 as Double) as CKRecordValue
        periodic["isActive"] = (1 as Int64) as CKRecordValue
        periodic["createdAt"] = now as CKRecordValue
        periodic["updatedAt"] = now as CKRecordValue
        periodic["reminderRulesJSON"] = "[]" as CKRecordValue
        periodic["completionsJSON"] = "[]" as CKRecordValue
        periodic["isDeleted"] = (0 as Int64) as CKRecordValue
        periodic["deletedAt"] = now as CKRecordValue
        records.append(periodic)

        // 6. PairSpace (8 fields)
        let space = CKRecord(recordType: "PairSpace", recordID: CKRecord.ID(recordName: UUID().uuidString))
        space["spaceID"] = dummySpaceID as CKRecordValue
        space["type"] = "pair" as CKRecordValue
        space["displayName"] = "__schema_seed__" as CKRecordValue
        space["ownerUserID"] = dummyUserID as CKRecordValue
        space["status"] = "active" as CKRecordValue
        space["createdAt"] = now as CKRecordValue
        space["updatedAt"] = now as CKRecordValue
        space["archivedAt"] = now as CKRecordValue
        records.append(space)

        // 7. PairMemberProfile (8 fields)
        let profile = CKRecord(recordType: "PairMemberProfile", recordID: CKRecord.ID(recordName: UUID().uuidString))
        profile["userID"] = dummyUserID as CKRecordValue
        profile["spaceID"] = dummySpaceID as CKRecordValue
        profile["displayName"] = "__schema_seed__" as CKRecordValue
        profile["avatarSystemName"] = "" as CKRecordValue
        profile["avatarAssetID"] = "" as CKRecordValue
        profile["avatarVersion"] = (0 as Int64) as CKRecordValue
        profile["avatarDeleted"] = (0 as Int64) as CKRecordValue
        profile["updatedAt"] = now as CKRecordValue
        records.append(profile)

        // 8. PairAvatarAsset (5 fields — avatarData/Asset skipped, auto-created on first real upload)
        let avatar = CKRecord(recordType: "PairAvatarAsset", recordID: CKRecord.ID(recordName: UUID().uuidString))
        avatar["assetID"] = UUID().uuidString as CKRecordValue
        avatar["spaceID"] = dummySpaceID as CKRecordValue
        avatar["version"] = (0 as Int64) as CKRecordValue
        avatar["updatedAt"] = now as CKRecordValue
        // Note: avatarData (CKAsset) field will be auto-created on first real avatar upload.
        // We skip it here because CKAsset requires a real file.
        records.append(avatar)

        // Save all records in one batch
        do {
            let (saveResults, _) = try await db.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )

            var successCount = 0
            var failCount = 0
            for (recordID, result) in saveResults {
                switch result {
                case .success:
                    successCount += 1
                case .failure(let error):
                    failCount += 1
                    #if DEBUG
                    print("[SchemaSeeder] Failed to seed \(recordID.recordName): \(error)")
                    #endif
                }
            }

            #if DEBUG
            print("[SchemaSeeder] Done: \(successCount) succeeded, \(failCount) failed")
            #endif

            if failCount == 0 {
                UserDefaults.standard.set(true, forKey: seedKey)

                // Clean up seed records after a short delay
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await cleanupSeedRecords(db: db, records: records)
                }
                return true
            }
            return false
        } catch {
            #if DEBUG
            print("[SchemaSeeder] Batch save failed: \(error)")
            #endif
            return false
        }
    }

    /// Deletes the dummy seed records after schema is created.
    private static func cleanupSeedRecords(db: CKDatabase, records: [CKRecord]) async {
        let ids = records.map(\.recordID)
        do {
            let (_, deleteResults) = try await db.modifyRecords(
                saving: [],
                deleting: ids,
                savePolicy: .allKeys,
                atomically: false
            )
            let deleted = deleteResults.values.filter { (try? $0.get()) != nil }.count
            #if DEBUG
            print("[SchemaSeeder] Cleaned up \(deleted)/\(ids.count) seed records")
            #endif
        } catch {
            #if DEBUG
            print("[SchemaSeeder] Cleanup failed (non-critical): \(error)")
            #endif
        }
    }

    /// Resets the seed flag so it will run again next launch. For debugging only.
    static func resetSeedFlag() {
        UserDefaults.standard.removeObject(forKey: seedKey)
    }
}
