import Foundation
import Observation

@MainActor
@Observable
final class ListsViewModel {
    private let sessionStore: SessionStore
    private let taskListRepository: TaskListRepositoryProtocol

    var loadState: LoadableState = .idle
    var taskLists: [TaskList] = []

    init(sessionStore: SessionStore, taskListRepository: TaskListRepositoryProtocol) {
        self.sessionStore = sessionStore
        self.taskListRepository = taskListRepository
    }

    var systemLists: [TaskList] {
        taskLists.filter { $0.kind != .custom }
    }

    var customLists: [TaskList] {
        taskLists.filter { $0.kind == .custom }
    }

    func load() async {
        loadState = .loading

        do {
            taskLists = try await taskListRepository.fetchTaskLists(spaceID: sessionStore.currentSpace?.id)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
