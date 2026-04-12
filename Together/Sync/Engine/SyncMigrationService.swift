import CloudKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncMigration")

/// Handles one-time migration of pair space data from the legacy CloudKit public database
/// to private database zones managed by CKSyncEngine.
///
/// ## Migration Strategy: "legacy task catch-up + local snapshot"
///
/// 1. **Legacy catch-up**: Full-pull all Task records from the public DB for the active
///    pair space and upsert them into local SwiftData. This ensures any partner changes
///    that the device missed (e.g. offline during last legacy sync) are captured.
/// 2. **Local snapshot**: Enumerate all local pair-space entities (tasks, lists, projects,
///    subtasks, periodic tasks) and record them as pending CKSyncEngine pushes.
/// 3. **Tracked completion**: The exact set of record IDs is persisted; migration is only
///    marked complete once CKSyncEngine confirms all records are pushed to the private zone.
///
/// > Note: The legacy public DB only stored Task records. TaskList, Project, ProjectSubtask,
/// > and PeriodicTask were never in the public DB — they are migrated from local data only.
///
/// This service runs **once** on the first app launch after the architecture update.
/// It is safe to run multiple times (idempotent via UserDefaults flags).
enum SyncMigrationService {

    private static let migrationCompletedKey = "SyncMigration.publicToPrivate.v1"
    private static let migrationPendingIDsKey = "SyncMigration.publicToPrivate.v1.pendingIDs"

    // MARK: - Migration Check

    /// Returns true if the migration has been fully completed (all records pushed).
    static var isMigrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: migrationCompletedKey)
    }

    /// Returns true if the migration records have been enqueued but not yet all confirmed.
    static var isMigrationInProgress: Bool {
        guard let ids = UserDefaults.standard.array(forKey: migrationPendingIDsKey) as? [String] else {
            return false
        }
        return !ids.isEmpty
    }

    /// Marks the migration as fully completed.
    private static func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: migrationPendingIDsKey)
        logger.info("[Migration] ✅ Public-to-private migration marked as completed")
    }

    /// Called by the sync engine callback when records are confirmed pushed.
    /// Only removes IDs that belong to the migration batch; ignores unrelated pushes.
    static func confirmPushedRecords(recordNames: [String]) {
        guard !isMigrationCompleted else { return }
        guard var pendingIDs = UserDefaults.standard.array(forKey: migrationPendingIDsKey) as? [String],
              !pendingIDs.isEmpty else { return }

        let before = pendingIDs.count
        let confirmedSet = Set(recordNames)
        pendingIDs.removeAll { confirmedSet.contains($0) }

        guard pendingIDs.count != before else { return }

        logger.info("[Migration] Confirmed \(before - pendingIDs.count) migration records, \(pendingIDs.count) remaining")

        if pendingIDs.isEmpty {
            markMigrationCompleted()
        } else {
            UserDefaults.standard.set(pendingIDs, forKey: migrationPendingIDsKey)
        }
    }

    // MARK: - Migrate

    /// Performs the public-to-private migration for an active pair space.
    ///
    /// - Parameters:
    ///   - pairSpaceID: The pair space being migrated.
    ///   - sharedSpaceID: The shared space ID used for filtering local data / public DB query.
    ///   - coordinator: The sync engine coordinator to record changes into.
    ///   - ckContainer: The CloudKit container for legacy public DB full pull.
    ///   - modelContainer: SwiftData container for reading/writing local data.
    static func migrateIfNeeded(
        pairSpaceID: UUID,
        sharedSpaceID: UUID,
        coordinator: SyncEngineCoordinator,
        ckContainer: CKContainer,
        modelContainer: ModelContainer
    ) async {
        guard !isMigrationCompleted else {
            logger.info("[Migration] Already completed, skipping")
            return
        }

        guard !isMigrationInProgress else {
            let remaining = (UserDefaults.standard.array(forKey: migrationPendingIDsKey) as? [String])?.count ?? 0
            logger.info("[Migration] Already in progress, waiting for push confirmations (\(remaining) pending)")
            return
        }

        logger.info("[Migration] Starting public-to-private migration for space \(pairSpaceID.uuidString.prefix(8))")

        // ── Step 1: Legacy catch-up — full pull Tasks from public DB ──
        let catchUpCount = await performLegacyTaskCatchUp(
            spaceID: sharedSpaceID,
            ckContainer: ckContainer,
            modelContainer: modelContainer
        )
        logger.info("[Migration] Legacy catch-up: \(catchUpCount) task(s) merged from public DB")

        // ── Step 2: Local snapshot — enqueue all pair entities for private zone push ──
        do {
            let context = ModelContext(modelContainer)
            var migrationIDs: [String] = []

            // Tasks
            let tasks = try context.fetch(FetchDescriptor<PersistentItem>())
            let pairTasks = tasks.filter { $0.spaceID == sharedSpaceID && !$0.isArchived }
            for task in pairTasks {
                await coordinator.recordChange(
                    SyncChange(entityKind: .task, operation: .upsert, recordID: task.id, spaceID: pairSpaceID)
                )
                migrationIDs.append(task.id.uuidString)
            }

            // Task lists
            let lists = try context.fetch(FetchDescriptor<PersistentTaskList>())
            let pairLists = lists.filter { $0.spaceID == sharedSpaceID }
            for list in pairLists {
                await coordinator.recordChange(
                    SyncChange(entityKind: .taskList, operation: .upsert, recordID: list.id, spaceID: pairSpaceID)
                )
                migrationIDs.append(list.id.uuidString)
            }

            // Projects
            let projects = try context.fetch(FetchDescriptor<PersistentProject>())
            let pairProjects = projects.filter { $0.spaceID == sharedSpaceID }
            for project in pairProjects {
                await coordinator.recordChange(
                    SyncChange(entityKind: .project, operation: .upsert, recordID: project.id, spaceID: pairSpaceID)
                )
                migrationIDs.append(project.id.uuidString)
            }

            // Project subtasks
            let subtasks = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
            let pairSubtasks = subtasks.filter { subtask in
                pairProjects.contains { $0.id == subtask.projectID }
            }
            for subtask in pairSubtasks {
                await coordinator.recordChange(
                    SyncChange(entityKind: .projectSubtask, operation: .upsert, recordID: subtask.id, spaceID: pairSpaceID)
                )
                migrationIDs.append(subtask.id.uuidString)
            }

            // Periodic tasks
            let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
            let pairPeriodicTasks = periodicTasks.filter { $0.spaceID == sharedSpaceID }
            for periodicTask in pairPeriodicTasks {
                await coordinator.recordChange(
                    SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: periodicTask.id, spaceID: pairSpaceID)
                )
                migrationIDs.append(periodicTask.id.uuidString)
            }

            logger.info("[Migration] Queued \(migrationIDs.count) entities for private zone push")

            if migrationIDs.isEmpty {
                markMigrationCompleted()
            } else {
                UserDefaults.standard.set(migrationIDs, forKey: migrationPendingIDsKey)
                logger.info("[Migration] Tracking \(migrationIDs.count) record IDs for push confirmation")
            }

        } catch {
            logger.error("[Migration] ❌ Migration failed: \(error)")
        }
    }

    // MARK: - Legacy Catch-Up

    /// Pulls all Task records from the legacy public DB for this space and upserts into SwiftData.
    /// Returns the number of tasks merged.
    private static func performLegacyTaskCatchUp(
        spaceID: UUID,
        ckContainer: CKContainer,
        modelContainer: ModelContainer
    ) async -> Int {
        let db = ckContainer.publicCloudDatabase

        // Full pull: no date filter → fetch all tasks for this space
        let predicate = NSPredicate(
            format: "spaceID == %@",
            spaceID.uuidString as NSString
        )
        let query = CKQuery(
            recordType: CloudKitTaskRecordCodec.recordType,
            predicate: predicate
        )
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

        var pulledItems: [Item] = []
        do {
            // First page
            let (results, cursor) = try await db.records(
                matching: query,
                inZoneWith: nil,
                resultsLimit: CKQueryOperation.maximumResults
            )
            for (_, result) in results {
                if let record = try? result.get(),
                   let item = try? CloudKitTaskRecordCodec.decode(record: record) {
                    pulledItems.append(item)
                }
            }

            // Remaining pages
            var nextCursor = cursor
            while let currentCursor = nextCursor {
                let (moreResults, moreCursor) = try await db.records(
                    continuingMatchFrom: currentCursor,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                nextCursor = moreCursor
                for (_, result) in moreResults {
                    if let record = try? result.get(),
                       let item = try? CloudKitTaskRecordCodec.decode(record: record) {
                        pulledItems.append(item)
                    }
                }
            }
        } catch {
            // Network failure is non-fatal — proceed with local snapshot (best effort)
            logger.warning("[Migration] Legacy catch-up failed (non-fatal, proceeding with local data): \(error)")
            return 0
        }

        guard !pulledItems.isEmpty else { return 0 }

        // Merge into local SwiftData: upsert (remote wins if newer)
        let context = ModelContext(modelContainer)
        var mergedCount = 0

        for item in pulledItems {
            let itemID = item.id
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.id == itemID }
            )

            if let existing = try? context.fetch(descriptor).first {
                if item.updatedAt > existing.updatedAt {
                    existing.update(from: item)
                    mergedCount += 1
                }
            } else {
                context.insert(PersistentItem(item: item))
                mergedCount += 1
            }
        }

        if mergedCount > 0 {
            do {
                try context.save()
                logger.info("[Migration] Merged \(mergedCount) task(s) from legacy public DB")
            } catch {
                logger.error("[Migration] Failed to save legacy catch-up: \(error)")
                return 0
            }
        }

        return mergedCount
    }

    // MARK: - Reset

    /// Resets the migration flag so it re-runs on next launch.
    /// Exposed via Settings UI as a manual recovery mechanism.
    static func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: migrationPendingIDsKey)
        logger.info("[Migration] Migration flag reset")
    }
}
