import Foundation
import Testing
@testable import Together

@MainActor
struct TogetherTests {
    @Test func itemStateMachineCompletesInProgressTask() async throws {
        let next = ItemStateMachine.nextStatus(
            from: .inProgress,
            isCompletion: true
        )

        #expect(next == .completed)
    }

    @Test func sessionStoreBootstrapsSingleSpaceOnly() async throws {
        let sessionStore = SessionStore()

        await sessionStore.bootstrap(
            authService: MockAuthService(),
            spaceService: MockSpaceService()
        )

        #expect(sessionStore.authState == .signedIn)
        #expect(sessionStore.currentSpace?.type == .single)
        #expect(sessionStore.availableModeStates == [.single])
        #expect(sessionStore.activeMode == .single)
    }

    @Test func ocrParserCreatesTaskDraftsFromPlainLines() {
        let draft = OCRImportDraftParser.parse(rawText: """
        - 买牛奶
        2. 整理周报
        □ 给房东发消息
        """)

        #expect(draft.status == .needsReview)
        #expect(draft.projectDrafts.isEmpty)
        #expect(draft.taskDrafts.map(\.title) == ["买牛奶", "整理周报", "给房东发消息"])
    }

    @Test func ocrParserCreatesProjectDraftFromHeadingAndBullets() {
        let draft = OCRImportDraftParser.parse(rawText: """
        搬家准备:
        - 预约搬家公司
        - 打包厨房
        """)

        #expect(draft.taskDrafts.isEmpty)
        #expect(draft.projectDrafts.count == 1)
        #expect(draft.projectDrafts.first?.name == "搬家准备")
        #expect(draft.projectDrafts.first?.taskDrafts.map(\.title) == ["预约搬家公司", "打包厨房"])
    }

    @Test func homeSnoozeUsesTomorrowInsteadOfConfiguredMinutes() async throws {
        var user = MockDataFactory.makeCurrentUser()
        user.preferences.defaultSnoozeMinutes = 5

        let sessionStore = SessionStore()
        sessionStore.seedMock(currentUser: user, singleSpace: MockDataFactory.makeSingleSpace())

        let taskApplicationService = CapturingTaskApplicationService()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: taskApplicationService,
            itemRepository: MockItemRepository(),
            taskTemplateRepository: MockTaskTemplateRepository()
        )

        let itemID = MockDataFactory.makeItems()[0].id
        await viewModel.snoozeItem(itemID)

        #expect(taskApplicationService.capturedSnoozeOption == .tomorrow)
    }
}

@MainActor
private final class CapturingTaskApplicationService: TaskApplicationServiceProtocol, @unchecked Sendable {
    var capturedSnoozeOption: TaskSnoozeOption?

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] {
        []
    }

    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(
            referenceDate: referenceDate,
            actionableCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            completedTodayCount: 0,
            pinnedCount: 0
        )
    }

    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        throw RepositoryError.notFound
    }

    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item {
        throw RepositoryError.notFound
    }

    func moveTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        listID: UUID?,
        projectID: UUID?
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func rescheduleTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        dueAt: Date?,
        remindAt: Date?
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func snoozeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        option: TaskSnoozeOption
    ) async throws -> Item {
        capturedSnoozeOption = option
        return MockDataFactory.makeItems()[0]
    }

    func toggleTaskCompletion(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func completeTask(
        in spaceID: UUID,
        taskID: UUID,
        actorID: UUID,
        referenceDate: Date
    ) async throws -> Item {
        throw RepositoryError.notFound
    }

    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item {
        throw RepositoryError.notFound
    }

    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
}
