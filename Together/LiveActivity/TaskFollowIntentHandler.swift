import AppIntents
import Foundation
import WidgetKit

final class TaskFollowIntentHandler: TaskFollowIntentHandling, @unchecked Sendable {
    private let container: AppContainer
    private let coordinator: TaskFollowActivityCoordinator
    private let contextStore = TodayWidgetSharedContextStore()

    @MainActor
    init() throws {
        let container = try LocalServiceFactory.makeContainer()
        self.container = container
        self.coordinator = TaskFollowActivityCoordinator(itemRepository: container.itemRepository)
    }

    @MainActor
    static func make() throws -> TaskFollowIntentHandler {
        try TaskFollowIntentHandler()
    }

    func completeTask(taskID: UUID) async {
        guard let sharedContext = contextStore.read() else { return }

        if let item = try? await container.itemRepository.fetchItem(itemID: taskID),
           item.status != .completed,
           item.completedAt == nil {
            _ = try? await container.taskApplicationService.completeTask(
                in: sharedContext.spaceID,
                taskID: taskID,
                actorID: sharedContext.actorID,
                referenceDate: .now
            )
        }

        _ = await coordinator.reconcile(
            spaceID: sharedContext.spaceID,
            reason: .dataChanged
        )
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
    }
}
