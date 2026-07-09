import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

actor LocalRoutineAlarmService: RoutineAlarmServiceProtocol {
    func authorizationStatus() async -> RoutineAlarmAuthorizationStatus {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return Self.status(from: AlarmManager.shared.authorizationState)
        }
        #endif
        return .unavailable
    }

    func requestAuthorization() async throws -> RoutineAlarmAuthorizationStatus {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return Self.status(from: try await AlarmManager.shared.requestAuthorization())
        }
        #endif
        return .unavailable
    }

    func schedule(id: UUID, title: String, at date: Date) async throws {
        guard date > .now else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard AlarmManager.shared.authorizationState == .authorized else {
                throw RoutineAlarmServiceError.unauthorized
            }

            let presentation = AlarmPresentation(
                alert: AlarmPresentation.Alert(
                    title: "\(title)",
                    stopButton: AlarmButton(
                        text: "停止",
                        textColor: .white,
                        systemImageName: "stop.fill"
                    )
                )
            )
            let attributes = AlarmAttributes<RoutineAlarmMetadata>(
                presentation: presentation,
                metadata: RoutineAlarmMetadata(taskID: id),
                tintColor: .blue
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(date),
                attributes: attributes
            )
            try? AlarmManager.shared.cancel(id: id)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return
        }
        #endif
        throw RoutineAlarmServiceError.unavailable
    }

    func cancel(id: UUID) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    nonisolated private static func status(
        from state: AlarmManager.AuthorizationState
    ) -> RoutineAlarmAuthorizationStatus {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct RoutineAlarmMetadata: AlarmMetadata {
    let taskID: UUID
}
#endif
