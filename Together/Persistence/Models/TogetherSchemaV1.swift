import SwiftData
import TogetherCore

typealias TogetherSchemaV1 = TogetherCore.TogetherSchemaV1
typealias PersistentUserProfile = TogetherCore.PersistentUserProfile
typealias PersistentSpace = TogetherCore.PersistentSpace
typealias PersistentTaskList = TogetherCore.PersistentTaskList
typealias PersistentProject = TogetherCore.PersistentProject
typealias PersistentProjectSubtask = TogetherCore.PersistentProjectSubtask
typealias PersistentItem = TogetherCore.PersistentItem
typealias PersistentTaskFollow = TogetherCore.PersistentTaskFollow
typealias PersistentTaskSubtask = TogetherCore.PersistentTaskSubtask
typealias PersistentItemOccurrenceCompletion = TogetherCore.PersistentItemOccurrenceCompletion
// Historical V1 migration input only. Runtime V2 excludes this entity.
private typealias LegacyPersistentTaskTemplate = TogetherCore.PersistentTaskTemplate
typealias PersistentPeriodicTask = TogetherCore.PersistentPeriodicTask

enum TogetherSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentTaskSubtask.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentPeriodicTask.self,
        ]
    }
}

enum TogetherSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        TogetherSchemaV2.models + [PersistentTaskFollow.self]
    }
}

enum TogetherMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TogetherSchemaV1.self, TogetherSchemaV2.self, TogetherSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: TogetherSchemaV1.self,
                toVersion: TogetherSchemaV2.self,
                willMigrate: { context in
                    let templates = try context.fetch(FetchDescriptor<LegacyPersistentTaskTemplate>())
                    templates.forEach(context.delete)
                    try context.save()
                },
                didMigrate: nil
            ),
            MigrationStage.lightweight(
                fromVersion: TogetherSchemaV2.self,
                toVersion: TogetherSchemaV3.self
            ),
        ]
    }
}
