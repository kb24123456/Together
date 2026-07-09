import Foundation

actor MockRoutineAlarmService: RoutineAlarmServiceProtocol {
    var status: RoutineAlarmAuthorizationStatus
    private(set) var scheduled: [UUID: Date] = [:]

    init(status: RoutineAlarmAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> RoutineAlarmAuthorizationStatus { status }

    func requestAuthorization() async throws -> RoutineAlarmAuthorizationStatus { status }

    func schedule(id: UUID, title: String, at date: Date) async throws {
        guard status == .authorized else { throw RoutineAlarmServiceError.unauthorized }
        scheduled[id] = date
    }

    func cancel(id: UUID) async {
        scheduled[id] = nil
    }
}
