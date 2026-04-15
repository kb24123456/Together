import Foundation

protocol TaskListRepositoryProtocol: Sendable {
    func fetchTaskLists(spaceID: UUID?) async throws -> [TaskList]
    func saveTaskList(_ list: TaskList, actorID: UUID) async throws -> TaskList
    func archiveTaskList(listID: UUID, actorID: UUID) async throws -> TaskList
}
