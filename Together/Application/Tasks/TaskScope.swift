import Foundation

enum TaskScope: Hashable, Sendable {
    case all
    case pinned
    case today(referenceDate: Date)
    case list(UUID)
    case project(UUID)
    case scheduled(on: Date)
}
