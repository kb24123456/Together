import CloudKit
import Foundation

/// Manages custom CKRecordZone lifecycle for pair spaces.
///
/// Each pair space maps to one custom zone in the **owner's private database**.
/// Zone naming convention: `"pair-<pairSpaceID>"`.
actor CloudKitZoneManager {
    private let container: CKContainer

    init(container: CKContainer) {
        self.container = container
    }

    // MARK: - Zone Naming

    nonisolated static func zoneName(for pairSpaceID: UUID) -> String {
        "pair-\(pairSpaceID.uuidString)"
    }

    nonisolated static func zoneID(for pairSpaceID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: pairSpaceID))
    }

    // MARK: - Zone CRUD

    /// Public DB does not support custom zones. Returns the default zone.
    /// Zone name is still used locally to identify the pair space in sync metadata.
    func createZone(for pairSpaceID: UUID) async throws -> CKRecordZone {
        #if DEBUG
        print("[ZoneManager] Using default zone for public DB (pair: \(pairSpaceID.uuidString.prefix(8)))")
        #endif
        return CKRecordZone.default()
    }

    func fetchZone(for pairSpaceID: UUID) async -> CKRecordZone? {
        CKRecordZone.default()
    }

    func deleteZone(for pairSpaceID: UUID) async throws {
        // No-op: public DB uses default zone; records are deleted individually.
    }
}
