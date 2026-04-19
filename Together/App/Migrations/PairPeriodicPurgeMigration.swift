import Foundation
import SwiftData
import os

enum PairPeriodicPurgeMigration {
    private static let flagKey = "migration_pair_periodic_purged_v1"
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "PairPeriodicPurge")

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let pairSpaceIDs: Set<UUID> = {
            let descriptor = FetchDescriptor<PersistentPairSpace>()
            guard let spaces = try? context.fetch(descriptor) else { return [] }
            return Set(spaces.map { $0.sharedSpaceID })
        }()

        if pairSpaceIDs.isEmpty {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        let descriptor = FetchDescriptor<PersistentPeriodicTask>()
        guard let allTasks = try? context.fetch(descriptor) else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }
        let orphans = allTasks.filter { task in
            guard let sid = task.spaceID else { return false }
            return pairSpaceIDs.contains(sid)
        }
        if !orphans.isEmpty {
            for task in orphans {
                context.delete(task)
            }
            do {
                try context.save()
                logger.info("purged \(orphans.count) pair-space periodic_tasks from local store")
            } catch {
                logger.error("purge save failed: \(error.localizedDescription)")
                return
            }
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
