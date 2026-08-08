import Foundation
import SwiftData
import TogetherCore

enum PersonalDataDeletionResult: Equatable {
    case completed(newUser: User, newSpace: Space)
    case failed(message: String)
}

@MainActor
protocol PersonalDataFileCleaning {
    func clearPersonalFiles() throws
}

@MainActor
struct LivePersonalDataFileCleaner: PersonalDataFileCleaning {
    private let fileManager: FileManager
    private let appGroupContainerURL: URL?

    init(
        fileManager: FileManager = .default,
        appGroupContainerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.fileManager = fileManager
        self.appGroupContainerURL = appGroupContainerURL
    }

    func clearPersonalFiles() throws {
        let avatarDirectory = UserAvatarStorage.fileURL(fileName: "placeholder")
            .deletingLastPathComponent()
        if fileManager.fileExists(atPath: avatarDirectory.path) {
            try fileManager.removeItem(at: avatarDirectory)
        }

        try TodayWidgetSnapshotStore(containerURL: appGroupContainerURL).clear()
        if let legacyAnniversaryURL = appGroupContainerURL?.appending(
            path: "anniversary-widget-snapshot.json"
        ), fileManager.fileExists(atPath: legacyAnniversaryURL.path) {
            try fileManager.removeItem(at: legacyAnniversaryURL)
        }
        TodayWidgetSharedContextStore().clear()
    }
}

@MainActor
final class PersonalDataDeletionService {
    private let container: ModelContainer
    private let reminderScheduler: ReminderSchedulerProtocol
    private let fileCleaner: PersonalDataFileCleaning
    private let defaults: UserDefaults

    init(
        container: ModelContainer,
        reminderScheduler: ReminderSchedulerProtocol,
        fileCleaner: PersonalDataFileCleaning? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.container = container
        self.reminderScheduler = reminderScheduler
        self.fileCleaner = fileCleaner ?? LivePersonalDataFileCleaner()
        self.defaults = defaults
    }

    func deleteAllData() async -> PersonalDataDeletionResult {
        let manifest: PersonalDataDeletionManifest
        do {
            manifest = try PersonalDataDeletionManifest.read(from: container)
        } catch {
            return .failed(message: "无法读取待删除数据，请重试。")
        }

        await cancelReminders(in: manifest)

        do {
            try deleteManifestFromStore()
        } catch {
            return .failed(message: "本机数据删除失败，请重试。")
        }

        do {
            try fileCleaner.clearPersonalFiles()
        } catch {
            return .failed(message: "本机文件清理失败，请重试。")
        }

        do {
            guard try PersonalDataDeletionManifest.read(from: container).isEmpty else {
                return .failed(message: "仍有数据未删除，请重试。")
            }
        } catch {
            return .failed(message: "无法验证删除结果，请重试。")
        }

        clearPersonalDefaults(spaceIDs: manifest.spaceIDs)

        do {
            let identityService = PersonalIdentityService(container: container, defaults: defaults)
            let resolution = try identityService.startLocally()
            defaults.removeObject(forKey: PersonalIdentityService.provisionalSpaceIDKey)
            guard case let .ready(user, space) = resolution else {
                return .failed(message: "空白个人空间创建失败，请重试。")
            }
            return .completed(newUser: user, newSpace: space)
        } catch {
            return .failed(message: "空白个人空间创建失败，请重试。")
        }
    }

    private func cancelReminders(in manifest: PersonalDataDeletionManifest) async {
        for itemID in manifest.itemIDs {
            await reminderScheduler.removeTaskReminder(for: itemID)
        }
        for projectID in manifest.projectIDs {
            await reminderScheduler.removeProjectReminder(for: projectID)
        }
        for taskID in manifest.periodicTaskIDs {
            await reminderScheduler.removePeriodicTaskReminder(for: taskID)
        }
        for spaceID in manifest.spaceIDs {
            await reminderScheduler.syncDailySummary(for: spaceID, tasks: [])
        }
    }

    private func deleteManifestFromStore() throws {
        let context = ModelContext(container)
        for value in try context.fetch(FetchDescriptor<PersistentItemOccurrenceCompletion>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentTaskSubtask>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentProjectSubtask>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentItem>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentPeriodicTask>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentTaskList>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentProject>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentSpace>()) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<PersistentUserProfile>()) { context.delete(value) }
        try context.save()
    }

    private func clearPersonalDefaults(spaceIDs: Set<UUID>) {
        let explicitKeys = [
            "together.appLockEnabled",
            "together.routines.visibleCycles.v2",
            "together.routines.visibleOptionalCycles",
            PersonalIdentityService.provisionalSpaceIDKey
        ]
        for key in explicitKeys {
            defaults.removeObject(forKey: key)
        }

        for spaceID in spaceIDs {
            let prefix = "together.soloSync.\(spaceID.uuidString)."
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private struct PersonalDataDeletionManifest {
    let itemIDs: Set<UUID>
    let periodicTaskIDs: Set<UUID>
    let projectIDs: Set<UUID>
    let spaceIDs: Set<UUID>
    let totalObjectCount: Int

    var isEmpty: Bool { totalObjectCount == 0 }

    @MainActor
    static func read(from container: ModelContainer) throws -> PersonalDataDeletionManifest {
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        let projects = try context.fetch(FetchDescriptor<PersistentProject>())
        let spaces = try context.fetch(FetchDescriptor<PersistentSpace>())
        let counts = [
            items.count,
            periodicTasks.count,
            projects.count,
            spaces.count,
            try context.fetchCount(FetchDescriptor<PersistentUserProfile>()),
            try context.fetchCount(FetchDescriptor<PersistentTaskSubtask>()),
            try context.fetchCount(FetchDescriptor<PersistentItemOccurrenceCompletion>()),
            try context.fetchCount(FetchDescriptor<PersistentTaskList>()),
            try context.fetchCount(FetchDescriptor<PersistentProjectSubtask>())
        ]
        return PersonalDataDeletionManifest(
            itemIDs: Set(items.map(\.id)),
            periodicTaskIDs: Set(periodicTasks.map(\.id)),
            projectIDs: Set(projects.map(\.id)),
            spaceIDs: Set(spaces.map(\.id)),
            totalObjectCount: counts.reduce(0, +)
        )
    }
}
