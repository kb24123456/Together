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
            try Self.injectDebugPairReviewFixtureIfNeeded(container: resolvedContainer)
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

    private static func injectDebugPairReviewFixtureIfNeeded(container: ModelContainer) throws {
        let context = ModelContext(container)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let fixtures: [Item] = [
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777774")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.partnerUserID,
                title: "对方发来的待确认任务",
                notes: "这张卡用于测试第 3 类：对方发给我，等待我处理。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 15),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 14 + 1_800),
                status: .pendingConfirmation,
                assignmentState: .pendingResponse,
                latestResponse: nil,
                responseHistory: [],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "你先看看，合适的话就直接接受。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200)
                    )
                ],
                lastActionByUserID: MockDataFactory.partnerUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200),
                createdAt: dayStart.addingTimeInterval(-9_600),
                updatedAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777775")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "我发出后被退回的任务",
                notes: "这张卡用于测试第 2 类：我发出去后被对方退回，等我二次处理。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 18 + 900),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 18),
                status: .declinedOrBlocked,
                assignmentState: .declined,
                latestResponse: ItemResponse(
                    responderID: MockDataFactory.partnerUserID,
                    kind: .notSuitable,
                    message: "没时间",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: MockDataFactory.partnerUserID,
                        kind: .notSuitable,
                        message: "没时间",
                        respondedAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                    )
                ],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.currentUserID,
                        body: "你方便的话帮我处理一下。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 10 + 1_800)
                    ),
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "没时间",
                        createdAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                    )
                ],
                lastActionByUserID: MockDataFactory.partnerUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 12 + 600),
                createdAt: dayStart.addingTimeInterval(-7_200),
                updatedAt: dayStart.addingTimeInterval(3_600 * 12 + 600),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777776")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.partnerUserID,
                title: "我已确认进入待办的任务",
                notes: "这张卡用于测试第 1 类：我已经确认过，现已变成我的待办任务。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 20),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 19 + 1_800),
                status: .inProgress,
                assignmentState: .accepted,
                latestResponse: ItemResponse(
                    responderID: MockDataFactory.currentUserID,
                    kind: .willing,
                    message: nil,
                    respondedAt: dayStart.addingTimeInterval(3_600 * 11 + 300)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: MockDataFactory.currentUserID,
                        kind: .willing,
                        message: nil,
                        respondedAt: dayStart.addingTimeInterval(3_600 * 11 + 300)
                    )
                ],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "你已经接受了，现在它应该像正常待办一样显示。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 11)
                    )
                ],
                lastActionByUserID: MockDataFactory.currentUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 11 + 300),
                createdAt: dayStart.addingTimeInterval(-5_400),
                updatedAt: dayStart.addingTimeInterval(3_600 * 11 + 300),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            )
        ]

        for fixture in fixtures {
            let existing = try context.fetch(
                FetchDescriptor<PersistentItem>(
                    predicate: #Predicate<PersistentItem> { $0.id == fixture.id }
                )
            )
            for item in existing {
                context.delete(item)
            }
            context.insert(PersistentItem(item: fixture))
        }

        if context.hasChanges {
            try context.save()
        }
    }
}
