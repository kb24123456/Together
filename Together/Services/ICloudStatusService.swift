import CloudKit
import Foundation

/// Checks iCloud account availability and reports status for UI gating.
enum ICloudStatus: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

enum ICloudStatusService {
    /// Checks the current iCloud account status.
    static func checkStatus(
        container: CKContainer = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
    ) async -> ICloudStatus {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .couldNotDetermine
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    /// Returns the current user's iCloud record ID, or nil if unavailable.
    static func currentUserRecordID(
        container: CKContainer = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
    ) async -> CKRecord.ID? {
        try? await container.userRecordID()
    }
}
