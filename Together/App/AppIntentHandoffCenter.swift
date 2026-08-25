import Foundation
import Observation

nonisolated struct TaskCreationIntentRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String?

    init(id: UUID = UUID(), title: String?) {
        self.id = id
        self.title = TaskCreationIntentTitle.normalized(title)
    }
}

nonisolated enum TaskCreationIntentTitle {
    static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

@MainActor
@Observable
final class AppIntentHandoffCenter {
    static let shared = AppIntentHandoffCenter()

    private var taskCreationRequests: [TaskCreationIntentRequest] = []
    private(set) var taskCreationRequestRevision: UInt = 0

    var pendingTaskCreationCount: Int {
        taskCreationRequests.count
    }

    var nextTaskCreationRequestID: UUID? {
        taskCreationRequests.first?.id
    }

    init() {}

    @discardableResult
    func enqueueTaskCreation(title: String?) -> TaskCreationIntentRequest {
        let request = TaskCreationIntentRequest(title: title)
        taskCreationRequests.append(request)
        taskCreationRequestRevision &+= 1
        return request
    }

    func consumeNextTaskCreation() -> TaskCreationIntentRequest? {
        guard taskCreationRequests.isEmpty == false else { return nil }
        return taskCreationRequests.removeFirst()
    }
}
