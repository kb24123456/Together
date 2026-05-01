import Foundation

enum TaskChatTimelineEntry: Identifiable, Hashable, Sendable {
    case system(key: String, text: String, createdAt: Date)
    case nudge(TaskMessage)
    case comment(TaskMessage)

    var id: String {
        switch self {
        case .system(let key, _, _):
            "system-\(key)"
        case .nudge(let message):
            "nudge-\(message.id.uuidString)"
        case .comment(let message):
            "comment-\(message.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case .system(_, _, let createdAt):
            createdAt
        case .nudge(let message), .comment(let message):
            message.createdAt
        }
    }
}

enum TaskChatTimelineBuilder {
    static func build(task: Item, messages: [TaskMessage]) -> [TaskChatTimelineEntry] {
        var entries: [TaskChatTimelineEntry] = [
            .system(
                key: "\(task.id.uuidString)-assigned",
                text: "任务已指派",
                createdAt: task.createdAt
            )
        ]

        for response in task.responseHistory {
            let text = response.kind == .willing ? "已接受任务" : "已拒绝任务"
            entries.append(
                .system(
                    key: "\(task.id.uuidString)-response-\(response.respondedAt.timeIntervalSince1970)",
                    text: text,
                    createdAt: response.respondedAt
                )
            )
        }

        if let completedAt = task.completedAt {
            entries.append(
                .system(
                    key: "\(task.id.uuidString)-completed",
                    text: "任务已完成",
                    createdAt: completedAt
                )
            )
        }

        for message in messages {
            switch message.type {
            case .comment:
                entries.append(.comment(message))
            case .nudge:
                entries.append(.nudge(message))
            case .rpsResult, .unknown:
                break
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return sortRank(lhs) < sortRank(rhs)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func sortRank(_ entry: TaskChatTimelineEntry) -> Int {
        switch entry {
        case .system:
            0
        case .nudge:
            1
        case .comment:
            2
        }
    }
}
