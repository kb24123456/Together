import Foundation
import SwiftData

@MainActor
final class ProjectToTaskMigrationService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    @discardableResult
    func migrateLegacyProjectsToTasks(spaceID: UUID?) throws -> Int {
        let context = ModelContext(container)
        let projects = try legacyProjects(spaceID: spaceID, context: context)
        guard projects.isEmpty == false else { return 0 }

        var migratedCount = 0
        for project in projects {
            try migrate(project: project, context: context)
            migratedCount += 1
        }

        try context.save()
        return migratedCount
    }

    private func migrate(project: PersistentProject, context: ModelContext) throws {
        let now = Date.now
        let projectSubtasks = try projectSubtasks(projectID: project.id, context: context)
        let linkedTaskRecords = try linkedTaskRecords(projectID: project.id, context: context)
        let parentItem = try upsertParentItem(from: project, now: now, context: context)

        var desiredSubtasks: [TaskSubtask] = []
        desiredSubtasks.append(contentsOf: projectSubtasks.enumerated().map { index, subtask in
            TaskSubtask(
                id: subtask.id,
                itemID: project.id,
                creatorID: subtask.creatorID,
                title: subtask.title,
                isCompleted: subtask.isCompleted,
                sortOrder: index,
                updatedAt: subtask.updatedAt
            )
        })

        let linkedOffset = desiredSubtasks.count
        desiredSubtasks.append(contentsOf: linkedTaskRecords.enumerated().map { index, linkedTask in
            TaskSubtask(
                id: linkedTask.id,
                itemID: project.id,
                creatorID: linkedTask.creatorID,
                title: linkedTask.title,
                isCompleted: linkedTask.statusRawValue == ItemStatus.completed.rawValue || linkedTask.completedAt != nil,
                sortOrder: linkedOffset + index,
                updatedAt: linkedTask.updatedAt,
                sourceTaskID: linkedTask.id,
                sourceNotes: linkedTask.notes,
                sourceDueAt: linkedTask.dueAt,
                sourceHasExplicitTime: linkedTask.hasExplicitTime,
                sourceRemindAt: linkedTask.remindAt,
                sourceCreatedAt: linkedTask.createdAt,
                sourceCompletedAt: linkedTask.completedAt
            )
        })

        parentItem.updatedAt = max(parentItem.updatedAt, project.updatedAt)
        try replaceSubtasks(itemID: project.id, desiredSubtasks: desiredSubtasks, context: context)

        for subtask in projectSubtasks {
            subtask.isLocallyDeleted = true
            subtask.updatedAt = now
        }

        for linkedTask in linkedTaskRecords {
            linkedTask.isLocallyDeleted = true
            linkedTask.updatedAt = now
        }

        project.isLocallyDeleted = true
        project.updatedAt = now
    }

    private func legacyProjects(spaceID: UUID?, context: ModelContext) throws -> [PersistentProject] {
        let descriptor: FetchDescriptor<PersistentProject>
        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentProject> { project in
                    project.spaceID == spaceID && project.isLocallyDeleted == false
                },
                sortBy: [SortDescriptor(\PersistentProject.sortOrder, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentProject> { project in
                    project.isLocallyDeleted == false
                },
                sortBy: [SortDescriptor(\PersistentProject.sortOrder, order: .forward)]
            )
        }
        return try context.fetch(descriptor)
    }

    private func projectSubtasks(projectID: UUID, context: ModelContext) throws -> [PersistentProjectSubtask] {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { subtask in
                subtask.projectID == projectID && subtask.isLocallyDeleted == false
            },
            sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func linkedTaskRecords(projectID: UUID, context: ModelContext) throws -> [PersistentItem] {
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { item in
                item.projectID == projectID && item.isLocallyDeleted == false && item.id != projectID
            },
            sortBy: [
                SortDescriptor(\PersistentItem.sortOrder, order: .forward),
                SortDescriptor(\PersistentItem.createdAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor)
    }

    private func upsertParentItem(
        from project: PersistentProject,
        now: Date,
        context: ModelContext
    ) throws -> PersistentItem {
        if let existing = try itemRecord(itemID: project.id, context: context) {
            existing.spaceID = project.spaceID
            existing.projectID = nil
            existing.creatorID = project.creatorID
            existing.title = project.name
            existing.notes = project.notes
            existing.dueAt = project.targetDate
            existing.hasExplicitTime = false
            existing.remindAt = project.remindAt
            existing.statusRawValue = project.statusRawValue == ProjectStatus.completed.rawValue
                ? ItemStatus.completed.rawValue
                : ItemStatus.inProgress.rawValue
            existing.completedAt = project.completedAt
            existing.sortOrder = project.sortOrder
            existing.isPinned = false
            existing.isDraft = false
            existing.isArchived = project.statusRawValue == ProjectStatus.archived.rawValue
            existing.archivedAt = project.statusRawValue == ProjectStatus.archived.rawValue ? now : nil
            existing.repeatRuleData = nil
            existing.isLocallyDeleted = false
            existing.updatedAt = max(project.updatedAt, existing.updatedAt)
            return existing
        }

        let item = Item(
            id: project.id,
            spaceID: project.spaceID,
            listID: nil,
            projectID: nil,
            creatorID: project.creatorID,
            title: project.name,
            notes: project.notes,
            locationText: nil,
            dueAt: project.targetDate,
            hasExplicitTime: false,
            remindAt: project.remindAt,
            status: project.statusRawValue == ProjectStatus.completed.rawValue ? .completed : .inProgress,
            lastActionByUserID: project.creatorID,
            lastActionAt: project.updatedAt,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            completedAt: project.completedAt,
            sortOrder: project.sortOrder,
            isUrgent: false,
            isDraft: false,
            isArchived: project.statusRawValue == ProjectStatus.archived.rawValue,
            archivedAt: project.statusRawValue == ProjectStatus.archived.rawValue ? now : nil
        )
        let record = PersistentItem(item: item)
        context.insert(record)
        return record
    }

    private func itemRecord(itemID: UUID, context: ModelContext) throws -> PersistentItem? {
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.id == itemID }
        )
        return try context.fetch(descriptor).first
    }

    private func replaceSubtasks(
        itemID: UUID,
        desiredSubtasks: [TaskSubtask],
        context: ModelContext
    ) throws {
        let existingRecords = try taskSubtaskRecords(itemID: itemID, context: context)
        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let desiredIDs = Set(desiredSubtasks.map(\.id))

        for subtask in desiredSubtasks {
            if let record = existingByID[subtask.id] {
                record.update(from: subtask)
            } else {
                context.insert(PersistentTaskSubtask(subtask: subtask))
            }
        }

        for record in existingRecords where desiredIDs.contains(record.id) == false {
            record.isLocallyDeleted = true
            record.updatedAt = .now
        }
    }

    private func taskSubtaskRecords(itemID: UUID, context: ModelContext) throws -> [PersistentTaskSubtask] {
        let descriptor = FetchDescriptor<PersistentTaskSubtask>(
            predicate: #Predicate<PersistentTaskSubtask> { $0.itemID == itemID }
        )
        return try context.fetch(descriptor)
    }
}
