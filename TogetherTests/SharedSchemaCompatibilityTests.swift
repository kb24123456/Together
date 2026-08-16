import Foundation
import SwiftData
import Testing
import TogetherCore
@testable import Together

@Suite("iPhone shared SwiftData schema compatibility", .serialized)
struct SharedSchemaCompatibilityTests {
    @Test("Production schema uses V3 with task-follow state and without templates")
    @MainActor
    func productionSchemaUsesSharedV1() {
        let productionSchema = Schema(versionedSchema: Together.TogetherSchemaV3.self)
        #expect(Set(productionSchema.entities.map(\.name)) == [
            "PersistentUserProfile",
            "PersistentSpace",
            "PersistentTaskList",
            "PersistentProject",
            "PersistentProjectSubtask",
            "PersistentItem",
            "PersistentTaskFollow",
            "PersistentTaskSubtask",
            "PersistentItemOccurrenceCompletion",
            "PersistentPeriodicTask",
        ])
    }

    @Test("Existing V1 iPhone store migrates through V3 without data loss")
    @MainActor
    func existingStoreReopensWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TogetherIPhoneSchemaCompatibility-\(UUID().uuidString)", directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Together.store", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemID = UUID()
        let userID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = Data("iphone-schema-compatibility".utf8)

        do {
            let legacySchema = Schema(TogetherSchemaV1.models)
            let configuration = ModelConfiguration(
                "LegacyIPhoneStore",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: legacySchema, configurations: configuration)
            let context = ModelContext(container)
            context.insert(PersistentItem(
                id: itemID,
                spaceID: nil,
                listID: nil,
                projectID: nil,
                creatorID: userID,
                title: "iPhone 兼容性任务",
                notes: "unversioned -> TogetherCore V1",
                locationText: nil,
                dueAt: now,
                hasExplicitTime: false,
                remindAt: nil,
                statusRawValue: "inProgress",
                lastActionByUserID: nil,
                lastActionAt: nil,
                createdAt: now,
                updatedAt: now,
                completedAt: nil,
                isPinned: false,
                isDraft: false,
                isArchived: false,
                archivedAt: nil,
                repeatRuleData: payload
            ))
            context.insert(TogetherCore.PersistentTaskTemplate(
                id: UUID(),
                spaceID: nil,
                title: "迁移后应删除",
                notes: nil,
                listID: nil,
                projectID: nil,
                isPinned: false,
                hasExplicitTime: false,
                timeData: nil,
                reminderOffset: nil,
                repeatRuleData: nil,
                subtasksData: nil,
                createdAt: now,
                updatedAt: now
            ))
            try context.save()
        }

        do {
            let sharedSchema = Schema(versionedSchema: Together.TogetherSchemaV3.self)
            let configuration = ModelConfiguration(
                "TogetherStore",
                schema: sharedSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: sharedSchema,
                migrationPlan: Together.TogetherMigrationPlan.self,
                configurations: configuration
            )
            let context = ModelContext(container)
            let item = try #require(try context.fetch(FetchDescriptor<PersistentItem>()).first)

            #expect(item.id == itemID)
            #expect(item.creatorID == userID)
            #expect(item.title == "iPhone 兼容性任务")
            #expect(item.notes == "unversioned -> TogetherCore V1")
            #expect(item.dueAt == now)
            #expect(item.repeatRuleData == payload)
            #expect(sharedSchema.entities.contains { $0.name == "PersistentTaskTemplate" } == false)
            #expect(sharedSchema.entities.contains { $0.name == "PersistentTaskFollow" })
            #expect(try context.fetchCount(FetchDescriptor<PersistentTaskFollow>()) == 0)
        }
    }

    @Test("App Group store path remains Together.store")
    func appGroupStorePathIsStable() {
        let appGroupURL = FileManager.default.temporaryDirectory
            .appending(path: "TogetherAppGroup-\(UUID().uuidString)", directoryHint: .isDirectory)

        #expect(
            PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL: appGroupURL)
                == appGroupURL.appending(path: "Together.store")
        )
        #expect(CloudKitSyncConfiguration.defaultContainerIdentifier == "iCloud.com.pigdog.Together")
        try? FileManager.default.removeItem(at: appGroupURL)
    }
}
