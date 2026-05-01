import Foundation
import Observation

@MainActor
@Observable
final class TaskChatViewModel {
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskMessageRepository: TaskMessageRepositoryProtocol
    private let sessionStore: SessionStore

    private(set) var task: Item
    private(set) var entries: [TaskChatTimelineEntry] = []
    var draftText = ""
    var isSending = false
    var errorText: String?

    var canSend: Bool {
        task.status != .completed
            && task.assignmentState != .completed
            && task.isArchived == false
    }

    init(
        task: Item,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskMessageRepository: TaskMessageRepositoryProtocol,
        sessionStore: SessionStore
    ) {
        self.task = task
        self.taskApplicationService = taskApplicationService
        self.taskMessageRepository = taskMessageRepository
        self.sessionStore = sessionStore
    }

    func load() async {
        do {
            errorText = nil
            let messages = try await taskMessageRepository.fetchMessages(taskID: task.id, limit: 50, before: nil)
            entries = TaskChatTimelineBuilder.build(task: task, messages: messages)
            if let last = messages.last {
                try await taskMessageRepository.markRead(taskID: task.id, through: last.createdAt)
            }
        } catch {
            errorText = "消息暂时无法加载"
        }
    }

    func send() async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isSending == false else { return }
        guard trimmed.count <= 500 else {
            errorText = "留言最多 500 字"
            return
        }
        guard canSend else { return }
        guard let spaceID = sessionStore.currentSpace?.id,
              let actorID = sessionStore.currentUser?.id else {
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            errorText = nil
            if let message = try await taskApplicationService.sendTaskComment(
                in: spaceID,
                taskID: task.id,
                actorID: actorID,
                content: trimmed
            ) {
                entries.append(.comment(message))
                draftText = ""
                try await taskMessageRepository.markRead(taskID: task.id, through: message.createdAt)
            }
        } catch {
            errorText = "发送失败，请重试"
        }
    }
}
