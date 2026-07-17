import Foundation
import TogetherCore

nonisolated extension PersistentTaskList {
    convenience init(list: TaskList) {
        self.init(
            id: list.id,
            spaceID: list.spaceID,
            creatorID: list.creatorID,
            name: list.name,
            kindRawValue: list.kind.rawValue,
            colorToken: list.colorToken,
            sortOrder: list.sortOrder,
            isArchived: list.isArchived,
            createdAt: list.createdAt,
            updatedAt: list.updatedAt
        )
    }

    func domainModel(taskCount: Int) -> TaskList {
        TaskList(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            name: name,
            kind: TaskListKind(rawValue: kindRawValue) ?? .custom,
            colorToken: colorToken,
            sortOrder: sortOrder,
            isArchived: isArchived,
            taskCount: taskCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from list: TaskList) {
        spaceID = list.spaceID
        creatorID = list.creatorID
        name = list.name
        kindRawValue = list.kind.rawValue
        colorToken = list.colorToken
        sortOrder = list.sortOrder
        isArchived = list.isArchived
        updatedAt = list.updatedAt
    }
}
