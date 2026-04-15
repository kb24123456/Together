import CloudKit
import Foundation

/// Zone naming utilities for pair spaces.
///
/// The zone CRUD operations have been removed — pair sync now uses CloudKit
/// Public DB directly via `PairSyncService`. These naming helpers are retained
/// for any code that still references zone names (e.g., `SyncEngineDelegate`
/// state persistence keyed by zone name).
enum CloudKitZoneManager {

    nonisolated static func zoneName(for pairSpaceID: UUID) -> String {
        "pair-\(pairSpaceID.uuidString)"
    }

    nonisolated static func zoneID(for pairSpaceID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: pairSpaceID))
    }

    nonisolated static func zoneID(
        for pairSpaceID: UUID,
        ownerRecordID: String?,
        isZoneOwner: Bool
    ) -> CKRecordZone.ID {
        let zoneName = zoneName(for: pairSpaceID)
        guard isZoneOwner == false, let ownerRecordID, ownerRecordID.isEmpty == false else {
            return CKRecordZone.ID(zoneName: zoneName)
        }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerRecordID)
    }
}
