import Foundation

protocol TodayWidgetSnapshotWriting: Sendable {
    func refreshTodayWidgetSnapshot() async throws
}

enum TodayWidgetCompletionError: Error, Equatable {
    case missingSpace
    case missingActor
}

struct TodayWidgetTaskCompletionGateway: Sendable {
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let snapshotWriter: TodayWidgetSnapshotWriting
    private let spaceIDProvider: @Sendable () -> UUID?
    private let actorIDProvider: @Sendable () -> UUID?

    init(
        taskApplicationService: TaskApplicationServiceProtocol,
        snapshotWriter: TodayWidgetSnapshotWriting,
        spaceIDProvider: @escaping @Sendable () -> UUID?,
        actorIDProvider: @escaping @Sendable () -> UUID?
    ) {
        self.taskApplicationService = taskApplicationService
        self.snapshotWriter = snapshotWriter
        self.spaceIDProvider = spaceIDProvider
        self.actorIDProvider = actorIDProvider
    }

    func complete(taskID: UUID, referenceDate: Date) async throws {
        guard let spaceID = spaceIDProvider() else {
            throw TodayWidgetCompletionError.missingSpace
        }
        guard let actorID = actorIDProvider() else {
            throw TodayWidgetCompletionError.missingActor
        }

        _ = try await taskApplicationService.completeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
        try await snapshotWriter.refreshTodayWidgetSnapshot()
    }
}
