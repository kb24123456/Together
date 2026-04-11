import Foundation

protocol SpaceServiceProtocol: Sendable {
    func currentSpaceContext(for userID: UUID?) async -> SpaceContext
    func createSingleSpace(for userID: UUID) async throws -> Space
}
