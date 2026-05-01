import Foundation
import SwiftData

@Model
final class PersistentTaskChatReadState {
    var taskID: UUID
    var lastReadMessageCreatedAt: Date
    var updatedAt: Date

    init(taskID: UUID, lastReadMessageCreatedAt: Date, updatedAt: Date) {
        self.taskID = taskID
        self.lastReadMessageCreatedAt = lastReadMessageCreatedAt
        self.updatedAt = updatedAt
    }
}
