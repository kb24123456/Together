import Foundation

struct SoloSyncDiagnosticSnapshot: Hashable, Sendable {
    var userID: UUID
    var spaceID: UUID?
    var platform: SoloDevicePlatform
    var gateDecision: SoloSyncGateDecision
    var localTaskCount: Int
    var remoteTaskCount: Int
    var pendingMutationCount: Int
    var failedMutationCount: Int
    var lastPulledAt: Date?
    var lastPushedAt: Date?
    var migrationCompletedAt: Date?
    var lastError: String?
}
