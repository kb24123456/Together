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

    var isPairModeActive: Bool {
        sessionStore.activeMode == .pair
    }

    var currentUser: User? {
        sessionStore.currentUser
    }

    var partner: User? {
        sessionStore.pairSpaceSummary?.partner
    }

    var spaceSummary: String {
        sessionStore.currentSpace?.displayName ?? (isPairModeActive ? "双人空间" : "我的任务空间")
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
