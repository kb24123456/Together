import ActivityKit
import AppIntents
import Foundation

nonisolated struct FollowedTaskSnapshot: Codable, Hashable, Identifiable, Sendable {
    let taskID: UUID
    let displayTitle: String
    let dueAt: Date?
    let hasExplicitTime: Bool

    var id: UUID { taskID }

    var deepLink: URL {
        URL(string: "together://task/\(taskID.uuidString)")!
    }
}

nonisolated struct TaskFollowActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        let visibleTasks: [FollowedTaskSnapshot]
        let totalFollowedCount: Int

        var remainingCount: Int {
            max(0, totalFollowedCount - visibleTasks.count)
        }

        var primaryTask: FollowedTaskSnapshot? {
            visibleTasks.first
        }
    }

    let sessionID: UUID
}

nonisolated protocol TaskFollowIntentHandling: Sendable {
    func completeTask(taskID: UUID) async
}

struct CompleteFollowedTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "完成关注任务"
    static let description = IntentDescription("从实时活动完成关注中的待办。")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background

    @Parameter(title: "任务 ID")
    var taskID: String

    @AppDependency private var handler: any TaskFollowIntentHandling

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID) else { return .result() }
        await handler.completeTask(taskID: taskID)
        return .result()
    }
}
