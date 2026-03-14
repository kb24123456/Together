import Foundation
import SwiftData

actor LocalSpaceService: SpaceServiceProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func currentSpaceContext(for userID: UUID?) async -> SpaceContext {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentSpace>(
            sortBy: [SortDescriptor(\PersistentSpace.updatedAt, order: .reverse)]
        )

        let records = (try? context.fetch(descriptor)) ?? []
        let availableSpaces = records
            .map(\.domainModel)
            .filter { space in
                if let userID {
                    return space.ownerUserID == userID && space.status != .archived
                }
                return space.status != .archived
            }

        let currentSpace = availableSpaces.first(where: { $0.status == .active }) ?? availableSpaces.first
        return SpaceContext(currentSpace: currentSpace, availableSpaces: availableSpaces)
    }
}
