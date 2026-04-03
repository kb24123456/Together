import Foundation
import SwiftData

struct PersistenceController {
    let container: ModelContainer
    private static let legacyPeriodicDataCleanupKey = "didCleanupLegacyPeriodicData.v1"

    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    init(inMemory: Bool = false) {
        StartupTrace.mark("PersistenceController.init.begin inMemory=\(inMemory)")
        do {
            let resolvedContainer = try Self.makeContainer(inMemory: inMemory)
            StartupTrace.mark("PersistenceController.container.created")
            try Self.cleanupLegacyPeriodicDataIfNeeded(container: resolvedContainer, inMemory: inMemory)
            StartupTrace.mark("PersistenceController.legacyPeriodicCleanup.complete")
            try Self.seedIfNeeded(container: resolvedContainer)
            StartupTrace.mark("PersistenceController.seed.complete")
            self.container = resolvedContainer
        } catch {
            let storePath = inMemory ? "in-memory" : Self.persistentStoreURL.path(percentEncoded: false)
            fatalError("Failed to initialize persistence at \(storePath). Existing store was preserved. Error: \(error)")
        }
        StartupTrace.mark("PersistenceController.init.end")
    }

    private static func cleanupLegacyPeriodicDataIfNeeded(
        container: ModelContainer,
        inMemory: Bool
    ) throws {
        guard inMemory == false else { return }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: legacyPeriodicDataCleanupKey) == false else { return }

        let context = ModelContext(container)
        let periodicItems = try context.fetch(
            FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.repeatRuleData != nil }
            )
        )
        let periodicTemplates = try context.fetch(
            FetchDescriptor<PersistentTaskTemplate>(
                predicate: #Predicate<PersistentTaskTemplate> { $0.repeatRuleData != nil }
            )
        )

        for record in periodicItems {
            context.delete(record)
        }

        for record in periodicTemplates {
            context.delete(record)
        }

        if periodicItems.isEmpty == false || periodicTemplates.isEmpty == false {
            try context.save()
        }

        defaults.set(true, forKey: legacyPeriodicDataCleanupKey)
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("TogetherStore", url: persistentStoreURL)
        }

        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
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
    private static func seedIfNeeded(container: ModelContainer) throws {
        let context = ModelContext(container)
        let spaceCount = try context.fetchCount(FetchDescriptor<PersistentSpace>())

        guard spaceCount == 0 else { return }

        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))
        context.insert(PersistentSpace(space: MockDataFactory.makePairSharedSpace()))
        context.insert(PersistentPairSpace(pairSpace: MockDataFactory.makePairSpace()))
        context.insert(
            PersistentPairMembership(
                pairSpaceID: MockDataFactory.makePairSpace().id,
                userID: MockDataFactory.currentUserID,
                nickname: MockDataFactory.makeCurrentUser().displayName,
                joinedAt: MockDataFactory.now.addingTimeInterval(-86_400 * 120)
            )
        )
        context.insert(
            PersistentPairMembership(
                pairSpaceID: MockDataFactory.makePairSpace().id,
                userID: MockDataFactory.partnerUserID,
                nickname: MockDataFactory.makePartnerUser().displayName,
                joinedAt: MockDataFactory.now.addingTimeInterval(-86_400 * 115)
            )
        )

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
