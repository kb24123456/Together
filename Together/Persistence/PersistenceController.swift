import Foundation
import SwiftData

struct PersistenceController {
    let container: ModelContainer

    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    init(inMemory: Bool = false) {
        var resolvedContainer: ModelContainer

        do {
            resolvedContainer = try Self.makeContainer(inMemory: inMemory)
            try Self.seedIfNeeded(container: resolvedContainer)
        } catch {
            guard inMemory == false else {
                fatalError("Failed to initialize in-memory persistence: \(error)")
            }

            do {
                try Self.resetPersistentStore()
                resolvedContainer = try Self.makeContainer(inMemory: false)
                try Self.seedIfNeeded(container: resolvedContainer)
            } catch {
                fatalError("Failed to initialize persistence after reset: \(    error)")
            }
        }

        self.container = resolvedContainer
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("TogetherStore", url: persistentStoreURL)
        }

        return try ModelContainer(
            for: PersistentSpace.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            configurations: configuration
        )
    }

    private static var persistentStoreURL: URL {
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

    private static func resetPersistentStore() throws {
        let storeURL = persistentStoreURL
        let sidecarURLs = [
            storeURL,
            storeURL.appendingPathExtension("sqlite"),
            storeURL.appendingPathExtension("sqlite-shm"),
            storeURL.appendingPathExtension("sqlite-wal"),
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]

        for url in sidecarURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func seedIfNeeded(container: ModelContainer) throws {
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

        for item in MockDataFactory.makeItems() {
            context.insert(PersistentItem(item: item))
        }

        try context.save()
    }
}
