import Foundation

struct TaskMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID
    let senderID: UUID
    let type: String  // "nudge" for now; "comment" / "rps_result" reserved
    let createdAt: Date
}
