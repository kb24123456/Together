import Foundation

protocol TaskListRepositoryProtocol: Sendable {
    func fetchTaskLists(spaceID: UUID?) async throws -> [TaskList]
    func saveTaskList(_ list: TaskList) async throws -> TaskList
    func archiveTaskList(listID: UUID) async throws -> TaskList
}
