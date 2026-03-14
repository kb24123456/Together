import Foundation

protocol SpaceServiceProtocol: Sendable {
    func currentSpaceContext(for userID: UUID?) async -> SpaceContext
}
