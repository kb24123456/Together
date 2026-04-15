import Foundation
import SwiftData

@Model
final class PersistentTaskList {
    var id: UUID
    var spaceID: UUID
    var creatorID: UUID = UUID()
    var name: String
    var kindRawValue: String
    var colorToken: String?
    var sortOrder: Double
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID = UUID(),
        name: String,
        kindRawValue: String,
        colorToken: String?,
        sortOrder: Double,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.name = name
        self.kindRawValue = kindRawValue
        self.colorToken = colorToken
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PersistentTaskList {
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
