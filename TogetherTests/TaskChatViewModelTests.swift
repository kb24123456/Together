import Foundation
import Testing
@testable import Together

@MainActor
struct TaskChatViewModelTests {
    @Test func timeline_sortsSystemNudgeThenCommentAtSameTimestamp() {
        let taskID = UUID()
        let actorID = UUID()
        let now = Date()
        let task = Self.makeTask(id: taskID, creatorID: actorID, createdAt: now)
        let nudge = TaskMessage(
            id: UUID(),
            taskID: taskID,
            senderID: actorID,
            type: .nudge,
            content: nil,
            createdAt: now
        )
        let comment = TaskMessage(
            id: UUID(),
            taskID: taskID,
            senderID: actorID,
            type: .comment,
            content: "买低脂的",
            createdAt: now
        )

        let entries = TaskChatTimelineBuilder.build(task: task, messages: [comment, nudge])

        #expect(entries.count == 3)
        if case .system = entries[0] {} else { Issue.record("first entry should be system") }
        if case .nudge = entries[1] {} else { Issue.record("second entry should be nudge") }
        if case .comment = entries[2] {} else { Issue.record("third entry should be comment") }
    }

    @Test func timeline_ignoresUnsupportedMessageTypes() {
        let taskID = UUID()
        let actorID = UUID()
        let now = Date()
        let task = Self.makeTask(id: taskID, creatorID: actorID, createdAt: now)
        let unsupportedMessages = [
            TaskMessage(
                id: UUID(),
                taskID: taskID,
                senderID: actorID,
                type: .rpsResult,
                content: nil,
                createdAt: now
            ),
            TaskMessage(
                id: UUID(),
                taskID: taskID,
                senderID: actorID,
                type: .unknown,
                content: "future",
                createdAt: now
            )
        ]

        let entries = TaskChatTimelineBuilder.build(task: task, messages: unsupportedMessages)

        #expect(entries.count == 1)
        if case .system = entries[0] {} else { Issue.record("only system entry should remain") }
    }

    @Test func load_buildsEntriesAndMarksLatestMessageRead() async throws {
        let taskID = UUID()
        let actorID = UUID()
        let task = Self.makeTask(id: taskID, creatorID: actorID)
        let repository = MockTaskMessageRepository()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let latestDate = oldDate.addingTimeInterval(60)
        try await repository.insertComment(
            messageID: UUID(),
            taskID: taskID,
            senderID: actorID,
            content: "第一条",
            createdAt: oldDate
        )
        try await repository.insertNudge(
            messageID: UUID(),
            taskID: taskID,
            senderID: actorID,
            createdAt: latestDate
        )
        let viewModel = makeViewModel(task: task, taskMessageRepository: repository)

        await viewModel.load()

        #expect(viewModel.entries.count == 3)
        let readState = try await repository.fetchReadState(taskID: taskID)
        #expect(readState?.lastReadMessageCreatedAt == latestDate)
        #expect(viewModel.errorText == nil)
    }

    @Test func send_trimsContentAppendsCommentAndMarksRead() async throws {
        let taskID = UUID()
        let actorID = MockDataFactory.currentUserID
        let task = Self.makeTask(id: taskID, creatorID: actorID)
        let repository = MockTaskMessageRepository()
        let service = CapturingTaskChatApplicationService()
        let sessionStore = Self.makeSessionStore(userID: actorID)
        let viewModel = TaskChatViewModel(
            task: task,
            taskApplicationService: service,
            taskMessageRepository: repository,
            sessionStore: sessionStore
        )
        viewModel.draftText = "  请确认  "

        await viewModel.send()

        #expect(viewModel.draftText.isEmpty)
        #expect(viewModel.entries.count == 1)
        let sent = await service.sentComments()
        #expect(sent.map(\.content) == ["请确认"])
        let message = try #require(sent.first?.message)
        let readState = try await repository.fetchReadState(taskID: taskID)
        #expect(readState?.lastReadMessageCreatedAt == message.createdAt)
        #expect(viewModel.errorText == nil)
    }

    @Test func send_rejectsOversizedContentBeforeCallingService() async {
        let task = Self.makeTask(id: UUID(), creatorID: MockDataFactory.currentUserID)
        let service = CapturingTaskChatApplicationService()
        let viewModel = makeViewModel(task: task, taskApplicationService: service)
        viewModel.draftText = String(repeating: "a", count: 501)

        await viewModel.send()

        #expect(viewModel.errorText == "留言最多 500 字")
        #expect((await service.sentComments()).isEmpty)
    }

    private func makeViewModel(
        task: Item,
        taskApplicationService: TaskApplicationServiceProtocol? = nil,
        taskMessageRepository: TaskMessageRepositoryProtocol? = nil,
        sessionStore: SessionStore? = nil
    ) -> TaskChatViewModel {
        TaskChatViewModel(
            task: task,
            taskApplicationService: taskApplicationService ?? CapturingTaskChatApplicationService(),
            taskMessageRepository: taskMessageRepository ?? MockTaskMessageRepository(),
            sessionStore: sessionStore ?? Self.makeSessionStore(userID: MockDataFactory.currentUserID)
        )
    }

    private static func makeSessionStore(userID: UUID) -> SessionStore {
        let store = SessionStore()
        var user = MockDataFactory.makeCurrentUser()
        user = User(
            id: userID,
            appleUserID: user.appleUserID,
            displayName: user.displayName,
            avatarSystemName: user.avatarSystemName,
            avatarPhotoFileName: user.avatarPhotoFileName,
            avatarAssetID: user.avatarAssetID,
            avatarVersion: user.avatarVersion,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt,
            preferences: user.preferences
        )
        store.currentUser = user
        store.singleSpace = MockDataFactory.makeSingleSpace()
        return store
    }

    private static func makeTask(
        id: UUID,
        creatorID: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Item {
        Item(
            id: id,
            spaceID: MockDataFactory.singleSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: creatorID,
            title: "买牛奶",
            notes: nil,
            executionRole: .initiator,
            assigneeMode: .partner,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .pendingConfirmation,
            assignmentState: .pendingResponse,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: creatorID,
            lastActionAt: createdAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )
    }
}

private actor CapturingTaskChatApplicationService: TaskApplicationServiceProtocol {
    struct SentComment: Sendable {
        let spaceID: UUID
        let taskID: UUID
        let actorID: UUID
        let content: String
        let message: TaskMessage
    }

    private var sent: [SentComment] = []

    func sentComments() -> [SentComment] {
        sent
    }

    func sendTaskComment(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        content: String
    ) async throws -> TaskMessage? {
        let message = TaskMessage(
            id: UUID(),
            taskID: taskID,
            senderID: actorID,
            type: .comment,
            content: content,
            createdAt: Date()
        )
        sent.append(
            SentComment(
                spaceID: spaceID,
                taskID: taskID,
                actorID: actorID,
                content: content,
                message: message
            )
        )
        return message
    }

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] { throw RepositoryError.notFound }
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary { throw RepositoryError.notFound }
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { throw RepositoryError.notFound }
    func moveTask(in spaceID: UUID, taskID: UUID, actorID: UUID, listID: UUID?, projectID: UUID?) async throws -> Item { throw RepositoryError.notFound }
    func rescheduleTask(in spaceID: UUID, taskID: UUID, actorID: UUID, dueAt: Date?, remindAt: Date?) async throws -> Item { throw RepositoryError.notFound }
    func snoozeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, option: TaskSnoozeOption) async throws -> Item { throw RepositoryError.notFound }
    func toggleTaskCompletion(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item { throw RepositoryError.notFound }
    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item { throw RepositoryError.notFound }
    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { throw RepositoryError.notFound }
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
    func respondToTask(in spaceID: UUID, taskID: UUID, actorID: UUID, response: ItemResponseKind, message: String?) async throws -> Item { throw RepositoryError.notFound }
    func requeueDeclinedTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { throw RepositoryError.notFound }
    func appendAssignmentMessage(in spaceID: UUID, taskID: UUID, actorID: UUID, message: String) async throws -> Item { throw RepositoryError.notFound }
    func sendReminderToPartner(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { throw RepositoryError.notFound }
}
