import Foundation

enum RoutineAlarmAuthorizationStatus: String, Hashable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

enum RoutineAlarmServiceError: Error {
    case unavailable
    case unauthorized
}

nonisolated protocol RoutineAlarmServiceProtocol: Sendable {
    func authorizationStatus() async -> RoutineAlarmAuthorizationStatus
    func requestAuthorization() async throws -> RoutineAlarmAuthorizationStatus
    func schedule(id: UUID, title: String, at date: Date) async throws
    func cancel(id: UUID) async
}
