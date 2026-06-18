import Foundation
import SwiftData

struct PersistenceController {
    let container: ModelContainer

    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    init(inMemory: Bool = false) {
        StartupTrace.mark("PersistenceController.init.begin inMemory=\(inMemory)")

        var firstError = ""

        // First attempt: open the existing store normally.
        if let resolved = Self.attemptFullInit(inMemory: inMemory, errorOut: &firstError) {
            self.container = resolved
            StartupTrace.mark("PersistenceController.init.end")
            return
        }

        StartupTrace.mark("PersistenceController.firstAttemptFailed=\(firstError)")

        guard inMemory == false else {
            fatalError("[Persistence] In-memory store failed: \(firstError)")
        }

        Self.deleteStoreFiles()
        var resetError = ""
        if let reset = Self.attemptFullInit(inMemory: false, errorOut: &resetError) {
            self.container = reset
            StartupTrace.mark("PersistenceController.init.end.afterStoreReset")
            return
        }

        let storePath = Self.persistentStoreURL.path(percentEncoded: false)
        fatalError("[Persistence] Store reset failed.\npath: \(storePath)\n1st: \(firstError)\nreset: \(resetError)")
    }

    /// Creates the container AND exercises it (seed + cleanup) so that any lazy-load
    /// error (migration, corruption) is caught here rather than surfacing later.
    private static func attemptFullInit(inMemory: Bool, errorOut: inout String) -> ModelContainer? {
        let container: ModelContainer
        do {
            container = try makeContainer(inMemory: inMemory)
        } catch {
            errorOut = "makeContainer: \(error)"
            return nil
        }

        do {
            let probeContext = ModelContext(container)
            _ = try probeContext.fetchCount(FetchDescriptor<PersistentSpace>())
        } catch {
            errorOut = "probeStore: \(error)"
            return nil
        }

        do {
            try seedIfNeeded(container: container, includeMockData: inMemory)
        } catch {
            errorOut = "seedIfNeeded: \(error)"
            return nil
        }

        return container
    }

    /// Removes all SQLite artefacts for the persistent store.
    static func deleteStoreFiles() {
        let storeURL = persistentStoreURL
        let base = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent)
        for suffix in ["store", "store-shm", "store-wal"] {
            let url = base.appendingPathExtension(suffix)
            try? FileManager.default.removeItem(at: url)
        }
        // External-storage support directory (used by @Attribute(.externalStorage))
        let supportURL = URL(fileURLWithPath: storeURL.path + "_SUPPORT")
        try? FileManager.default.removeItem(at: supportURL)
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "TogetherStore",
                url: persistentStoreURL,
                cloudKitDatabase: .private(CloudKitSyncConfiguration.defaultContainerIdentifier)
            )
        }

        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentTaskSubtask.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentPeriodicTask.self,
            configurations: configuration
        )
    }

    static var persistentStoreURL: URL {
        resolvedPersistentStoreURL(
            appGroupContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
            )
        )
    }

    static func resolvedPersistentStoreURL(appGroupContainerURL: URL?) -> URL {
        if let appGroupContainerURL {
            if FileManager.default.fileExists(atPath: appGroupContainerURL.path) == false {
                try? FileManager.default.createDirectory(at: appGroupContainerURL, withIntermediateDirectories: true)
            }
            return appGroupContainerURL.appending(path: "Together.store")
        }

        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        let directory = applicationSupportDirectory.appendingPathComponent("Together", isDirectory: true)

        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("Together.store")
    }

    static var persistentStoreSupportURL: URL {
        persistentStoreSupportURL(for: persistentStoreURL)
    }

    static func persistentStoreSupportURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + "_SUPPORT")
    }

    static func storeArtifactURLs() -> [URL] {
        storeArtifactURLs(for: persistentStoreURL)
    }

    static func storeArtifactURLs(for storeURL: URL) -> [URL] {
        let base = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent)
        return ["store", "store-shm", "store-wal"].map { base.appendingPathExtension($0) }
            + [persistentStoreSupportURL(for: storeURL)]
    }

    /// Seeds mock fixtures (spaces, lists, projects, subtasks, items) on an empty store.
    ///
    /// - Parameter includeMockData: When `true`, inserts the full mock dataset from
    ///   `MockDataFactory` (used by in-memory tests and SwiftUI previews). Production
    ///   passes `false`, in which case this function is a no-op — the real store starts
    ///   completely empty, and `AppContext.bootstrapIfNeeded` creates the user's single
    ///   space on first sign-in. Default lists / projects / items are created by the user.
    private static func seedIfNeeded(container: ModelContainer, includeMockData: Bool) throws {
        guard includeMockData else { return }

        let context = ModelContext(container)
        let spaceCount = try context.fetchCount(FetchDescriptor<PersistentSpace>())

        guard spaceCount == 0 else { return }

        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))

        for list in MockDataFactory.makeTaskLists() {
            context.insert(PersistentTaskList(list: list))
        }

        for project in MockDataFactory.makeProjects() {
            context.insert(PersistentProject(project: project))
        }

        for subtask in MockDataFactory.makeProjectSubtasks() {
            context.insert(PersistentProjectSubtask(subtask: subtask))
        }

        for item in MockDataFactory.makeItems() {
            context.insert(PersistentItem(item: item))
        }

        try context.save()
    }
}
