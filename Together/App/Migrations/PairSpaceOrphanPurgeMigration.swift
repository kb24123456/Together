import Foundation
import SwiftData
import os

/// One-shot cleanup for pair-scoped local rows whose `spaceID` no longer
/// matches any existing `PersistentSpace` — i.e. rows left behind by an
/// earlier unbind path that forgot to purge them (notably
/// PersistentImportantDate and PersistentTaskMessage, which the pre-fix
/// LocalPairingService.unbind did not delete).
///
/// Runs once per install (UserDefaults flag). Dev-phase hard delete is
/// acceptable; prod would want a soft-delete audit trail first.
enum PairSpaceOrphanPurgeMigration {
    private static let flagKey = "migration_pair_space_orphan_purged_v1"
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "PairSpaceOrphanPurge")

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let spaces = (try? context.fetch(FetchDescriptor<PersistentSpace>())) ?? []
        let validSpaceIDs = Set(spaces.map(\.id))

        // Fresh install / signed-out: nothing to compare against. Still mark
        // done so we don't re-scan every launch.
        guard validSpaceIDs.isEmpty == false else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        var deletedCounts: [String: Int] = [:]

        // Required spaceID — delete rows whose id doesn't resolve.
        deletedCounts["ImportantDate"] = purgeRows(
            FetchDescriptor<PersistentImportantDate>(),
            in: context
        ) { !validSpaceIDs.contains($0.spaceID) }
        deletedCounts["TaskList"] = purgeRows(
            FetchDescriptor<PersistentTaskList>(),
            in: context
        ) { !validSpaceIDs.contains($0.spaceID) }
        deletedCounts["Project"] = purgeRows(
            FetchDescriptor<PersistentProject>(),
            in: context
        ) { !validSpaceIDs.contains($0.spaceID) }

        // Optional spaceID — skip nil (solo-unscoped rows are legitimate).
        deletedCounts["Item"] = purgeRows(
            FetchDescriptor<PersistentItem>(),
            in: context
        ) { row in
            guard let sid = row.spaceID else { return false }
            return !validSpaceIDs.contains(sid)
        }
        deletedCounts["PeriodicTask"] = purgeRows(
            FetchDescriptor<PersistentPeriodicTask>(),
            in: context
        ) { row in
            guard let sid = row.spaceID else { return false }
            return !validSpaceIDs.contains(sid)
        }

        // Project subtasks follow their parent project's lifecycle. Re-read
        // projects after the space-scoped pass so dangling subtasks of
        // purged projects are also swept.
        let remainingProjectIDs: Set<UUID> = {
            let projects = (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? []
            return Set(projects.map(\.id))
        }()
        deletedCounts["ProjectSubtask"] = purgeRows(
            FetchDescriptor<PersistentProjectSubtask>(),
            in: context
        ) { !remainingProjectIDs.contains($0.projectID) }

        // Task messages key off taskID; purge those whose item is gone.
        let remainingItemIDs: Set<UUID> = {
            let items = (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? []
            return Set(items.map(\.id))
        }()
        deletedCounts["TaskMessage"] = purgeRows(
            FetchDescriptor<PersistentTaskMessage>(),
            in: context
        ) { !remainingItemIDs.contains($0.taskID) }

        let totalDeleted = deletedCounts.values.reduce(0, +)
        if totalDeleted > 0 {
            do {
                try context.save()
                let summary = deletedCounts
                    .filter { $0.value > 0 }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                logger.info("purged orphan rows: \(summary, privacy: .public)")
            } catch {
                logger.error("save failed, leaving orphan rows in place: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    private static func purgeRows<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        in context: ModelContext,
        shouldDelete: (Model) -> Bool
    ) -> Int {
        guard let rows = try? context.fetch(descriptor) else { return 0 }
        var count = 0
        for row in rows where shouldDelete(row) {
            context.delete(row)
            count += 1
        }
        return count
    }
}
