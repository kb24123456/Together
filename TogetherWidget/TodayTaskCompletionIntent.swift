import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct TodayTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "完成今日任务"
    static var description = IntentDescription("从今日小组件完成任务。")
    static var openAppWhenRun = false

    @Parameter(title: "任务 ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard let taskUUID = UUID(uuidString: taskID) else {
            throw TodayWidgetCompletionError.invalidTaskID
        }

        let completedAt = Date.now
        try TodayWidgetCompletionStore().complete(taskID: taskUUID, referenceDate: completedAt)
        try? TodayWidgetSnapshotStore().markTaskCompletedForAnimation(taskID: taskUUID, completedAt: completedAt)

        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
        return .result()
    }
}

private enum TodayWidgetCompletionError: Error {
    case invalidTaskID
    case missingContext
    case missingStore
    case taskNotFound
    case permissionDenied
}

private struct TodayWidgetCompletionStore {
    private nonisolated let calendar = Calendar.current

    nonisolated init() {}

    nonisolated func complete(taskID: UUID, referenceDate: Date) throws {
        guard let sharedContext = TodayWidgetSharedContextStore().read() else {
            throw TodayWidgetCompletionError.missingContext
        }
        guard let storeURL = Self.storeURL() else {
            throw TodayWidgetCompletionError.missingStore
        }

        let container = try makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        let targetSpaceID: UUID? = sharedContext.spaceID
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { item in
                item.id == taskID
                && item.spaceID == targetSpaceID
                && item.isArchived == false
                && item.isLocallyDeleted == false
            }
        )

        guard let record = try context.fetch(descriptor).first else {
            throw TodayWidgetCompletionError.taskNotFound
        }
        guard canComplete(record: record, actorID: sharedContext.actorID) else {
            throw TodayWidgetCompletionError.permissionDenied
        }

        let now = Date.now
        if record.repeatRuleData == nil {
            record.assignmentStateRawValue = "completed"
            record.statusRawValue = "completed"
            record.completedAt = now
        } else {
            try upsertOccurrenceCompletion(itemID: taskID, referenceDate: referenceDate, completedAt: now, context: context)
            record.completedAt = nil
        }

        record.lastActionByUserID = sharedContext.actorID
        record.lastActionAt = now
        record.completedByUserID = sharedContext.actorID
        record.isArchived = false
        record.archivedAt = nil
        record.updatedAt = now

        context.insert(
            PersistentSyncChange(
                entityKindRawValue: "task",
                operationRawValue: "complete",
                recordID: taskID,
                spaceID: sharedContext.spaceID,
                changedAt: now
            )
        )

        try context.save()
    }

    private nonisolated func makeContainer(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TogetherStore",
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentSyncChange.self,
            configurations: configuration
        )
    }

    private nonisolated func canComplete(record: PersistentItem, actorID: UUID) -> Bool {
        if record.assigneeModeRawValue == "partner" {
            return record.creatorID != actorID
        }
        return true
    }

    private nonisolated func upsertOccurrenceCompletion(
        itemID: UUID,
        referenceDate: Date,
        completedAt: Date,
        context: ModelContext
    ) throws {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        let descriptor = FetchDescriptor<PersistentItemOccurrenceCompletion>(
            predicate: #Predicate<PersistentItemOccurrenceCompletion> { completion in
                completion.itemID == itemID
            }
        )
        let existing = try context.fetch(descriptor)
            .first { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) }

        if let existing {
            existing.completedAt = completedAt
            existing.updatedAt = completedAt
        } else {
            context.insert(
                PersistentItemOccurrenceCompletion(
                    itemID: itemID,
                    occurrenceDate: occurrenceDate,
                    completedAt: completedAt,
                    createdAt: completedAt,
                    updatedAt: completedAt
                )
            )
        }
    }

    private nonisolated static func storeURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier)?
            .appending(path: "Together.store")
    }
}

@Model
private final class PersistentItem {
    var id: UUID
    var spaceID: UUID?
    var listID: UUID?
    var projectID: UUID?
    var creatorID: UUID
    var title: String
    var notes: String?
    var locationText: String?
    var executionRoleRawValue: String
    var assigneeModeRawValue: String
    var dueAt: Date?
    var hasExplicitTime: Bool
    var remindAt: Date?
    var statusRawValue: String
    var assignmentStateRawValue: String
    var latestResponseData: Data?
    var responseHistoryData: Data
    var assignmentMessagesData: Data
    var lastActionByUserID: UUID?
    var lastActionAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var completedByUserID: UUID?
    var sortOrder: Double
    var isPinned: Bool
    var isDraft: Bool
    var isArchived: Bool
    var archivedAt: Date?
    var repeatRuleData: Data?
    var reminderRequestedAt: Date?
    var isLocallyDeleted: Bool

    init(
        id: UUID,
        spaceID: UUID?,
        listID: UUID?,
        projectID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        locationText: String?,
        executionRoleRawValue: String,
        assigneeModeRawValue: String,
        dueAt: Date?,
        hasExplicitTime: Bool,
        remindAt: Date?,
        statusRawValue: String,
        assignmentStateRawValue: String,
        latestResponseData: Data?,
        responseHistoryData: Data,
        assignmentMessagesData: Data,
        lastActionByUserID: UUID?,
        lastActionAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        completedByUserID: UUID?,
        sortOrder: Double,
        isPinned: Bool,
        isDraft: Bool,
        isArchived: Bool,
        archivedAt: Date?,
        repeatRuleData: Data?,
        reminderRequestedAt: Date?,
        isLocallyDeleted: Bool
    ) {
        self.id = id
        self.spaceID = spaceID
        self.listID = listID
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.locationText = locationText
        self.executionRoleRawValue = executionRoleRawValue
        self.assigneeModeRawValue = assigneeModeRawValue
        self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime
        self.remindAt = remindAt
        self.statusRawValue = statusRawValue
        self.assignmentStateRawValue = assignmentStateRawValue
        self.latestResponseData = latestResponseData
        self.responseHistoryData = responseHistoryData
        self.assignmentMessagesData = assignmentMessagesData
        self.lastActionByUserID = lastActionByUserID
        self.lastActionAt = lastActionAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.completedByUserID = completedByUserID
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.repeatRuleData = repeatRuleData
        self.reminderRequestedAt = reminderRequestedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}

@Model
private final class PersistentItemOccurrenceCompletion {
    var id: UUID
    var itemID: UUID
    var occurrenceDate: Date
    var completedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        occurrenceDate: Date,
        completedAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.occurrenceDate = occurrenceDate
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
private final class PersistentSyncChange {
    var id: UUID
    var entityKindRawValue: String
    var operationRawValue: String
    var recordID: UUID
    var spaceID: UUID
    var changedAt: Date
    var lifecycleStateRawValue: String
    var lastAttemptedAt: Date?
    var confirmedAt: Date?
    var lastError: String?

    init(
        id: UUID = UUID(),
        entityKindRawValue: String,
        operationRawValue: String,
        recordID: UUID,
        spaceID: UUID,
        changedAt: Date
    ) {
        self.id = id
        self.entityKindRawValue = entityKindRawValue
        self.operationRawValue = operationRawValue
        self.recordID = recordID
        self.spaceID = spaceID
        self.changedAt = changedAt
        self.lifecycleStateRawValue = "pending"
        self.lastAttemptedAt = nil
        self.confirmedAt = nil
        self.lastError = nil
    }
}
