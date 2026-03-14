import Foundation

@MainActor
final class MockTaskListRepository: TaskListRepositoryProtocol {
    private var taskLists: [TaskList] = MockDataFactory.makeTaskLists()

    func fetchTaskLists(spaceID: UUID?) async throws -> [TaskList] {
        taskLists
            .filter { $0.spaceID == spaceID }
            .sorted { lhs, rhs in
                if lhs.kind == rhs.kind {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return rank(for: lhs.kind) < rank(for: rhs.kind)
            }
    }

    func saveTaskList(_ list: TaskList) async throws -> TaskList {
        if let index = taskLists.firstIndex(where: { $0.id == list.id }) {
            taskLists[index] = list
        } else {
            taskLists.append(list)
        }
        return list
    }

    func archiveTaskList(listID: UUID) async throws -> TaskList {
        guard let index = taskLists.firstIndex(where: { $0.id == listID }) else {
            throw RepositoryError.notFound
        }

        taskLists[index].isArchived = true
        taskLists[index].updatedAt = MockDataFactory.now
        return taskLists[index]
    }

    private func rank(for kind: TaskListKind) -> Int {
        switch kind {
        case .systemInbox:
            return 0
        case .systemToday:
            return 1
        case .systemUpcoming:
            return 2
        case .custom:
            return 3
        }
    }
}
