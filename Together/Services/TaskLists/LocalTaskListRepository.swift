import Foundation
import SwiftData

actor LocalTaskListRepository: TaskListRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchTaskLists(spaceID: UUID?) async throws -> [TaskList] {
        let context = ModelContext(container)
        let listDescriptor: FetchDescriptor<PersistentTaskList>

        if let spaceID {
            listDescriptor = FetchDescriptor(
                predicate: #Predicate<PersistentTaskList> { $0.spaceID == spaceID },
                sortBy: [SortDescriptor(\PersistentTaskList.sortOrder)]
            )
        } else {
            listDescriptor = FetchDescriptor(
                sortBy: [SortDescriptor(\PersistentTaskList.sortOrder)]
            )
        }

        let lists = try context.fetch(listDescriptor)
        let itemCounts = try taskCountsByList(in: context, spaceID: spaceID)

        return lists
            .map { $0.domainModel(taskCount: itemCounts[$0.id, default: 0]) }
            .sorted { lhs, rhs in
                if lhs.kind == rhs.kind {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return rank(for: lhs.kind) < rank(for: rhs.kind)
            }
    }

    func saveTaskList(_ list: TaskList) async throws -> TaskList {
        let context = ModelContext(container)
        var savedList = list
        savedList.updatedAt = .now

        if let record = try fetchRecord(listID: list.id, context: context) {
            record.update(from: savedList)
        } else {
            context.insert(PersistentTaskList(list: savedList))
        }

        try context.save()
        let count = try taskCountsByList(in: context, spaceID: savedList.spaceID)[savedList.id, default: 0]
        return savedList.withTaskCount(count)
    }

    func archiveTaskList(listID: UUID) async throws -> TaskList {
        let context = ModelContext(container)
        guard let record = try fetchRecord(listID: listID, context: context) else {
            throw RepositoryError.notFound
        }

        record.isArchived = true
        record.updatedAt = .now
        try context.save()

        let count = try taskCountsByList(in: context, spaceID: record.spaceID)[record.id, default: 0]
        return record.domainModel(taskCount: count)
    }

    private func fetchRecord(listID: UUID, context: ModelContext) throws -> PersistentTaskList? {
        let descriptor = FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate<PersistentTaskList> { $0.id == listID }
        )
        return try context.fetch(descriptor).first
    }

    private func taskCountsByList(in context: ModelContext, spaceID: UUID?) throws -> [UUID: Int] {
        let descriptor: FetchDescriptor<PersistentItem>

        if let spaceID {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.spaceID == spaceID && $0.isArchived == false }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<PersistentItem> { $0.isArchived == false }
            )
        }

        return try context.fetch(descriptor).reduce(into: [:]) { result, item in
            guard let listID = item.listID else { return }
            result[listID, default: 0] += 1
        }
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

private extension TaskList {
    nonisolated func withTaskCount(_ count: Int) -> TaskList {
        TaskList(
            id: id,
            spaceID: spaceID,
            name: name,
            kind: kind,
            colorToken: colorToken,
            sortOrder: sortOrder,
            isArchived: isArchived,
            taskCount: count,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
