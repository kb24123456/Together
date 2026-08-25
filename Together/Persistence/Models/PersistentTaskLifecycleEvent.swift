import Foundation
import SwiftData

@Model
final class PersistentTaskLifecycleEvent {
    #Index<PersistentTaskLifecycleEvent>([\.taskID], [\.taskID, \.occurredAt])

    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var spaceID: UUID?
    var kindRawValue: String = ""
    var occurredAt: Date = Date.now
    var oldDueAt: Date?
    var newDueAt: Date?
    var oldHasExplicitTime: Bool?
    var newHasExplicitTime: Bool?
    var incompleteSubtaskCount: Int?
    var schemaVersion: Int = 1

    init(
        id: UUID = UUID(),
        taskID: UUID,
        spaceID: UUID?,
        kindRawValue: String,
        occurredAt: Date,
        oldDueAt: Date? = nil,
        newDueAt: Date? = nil,
        oldHasExplicitTime: Bool? = nil,
        newHasExplicitTime: Bool? = nil,
        incompleteSubtaskCount: Int? = nil,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.taskID = taskID
        self.spaceID = spaceID
        self.kindRawValue = kindRawValue
        self.occurredAt = occurredAt
        self.oldDueAt = oldDueAt
        self.newDueAt = newDueAt
        self.oldHasExplicitTime = oldHasExplicitTime
        self.newHasExplicitTime = newHasExplicitTime
        self.incompleteSubtaskCount = incompleteSubtaskCount
        self.schemaVersion = schemaVersion
    }
}
