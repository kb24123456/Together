import CloudKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "ZoneManager")

/// Manages custom CKRecordZone lifecycle for pair spaces.
///
/// Each pair space maps to one custom zone. The zone owner creates it in their
/// private database, and the participant mounts the same shared authority data
/// plane through CKShare.
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

    /// Creates a custom zone in the private database for a pair space.
    /// CKSyncEngine also ensures zone creation, but calling this explicitly
    /// during pairing guarantees the zone is ready before the first sync.
    @discardableResult
    func createZone(for pairSpaceID: UUID) async throws -> CKRecordZone {
        let zoneID = Self.zoneID(for: pairSpaceID)
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            let savedZone = try await container.privateCloudDatabase.save(zone)
            logger.info("[ZoneManager] ✅ Created private zone: \(zoneID.zoneName)")
            return savedZone
        } catch let error as CKError where error.code == .serverRejectedRequest || error.code == .zoneNotFound {
            // Zone might already exist, try fetching it
            logger.info("[ZoneManager] Zone creation rejected, may already exist: \(zoneID.zoneName)")
            if let existing = try? await fetchZone(for: pairSpaceID) {
                return existing
            }
            throw error
        }
    }

    /// Fetches an existing zone from the private database.
    func fetchZone(for pairSpaceID: UUID) async throws -> CKRecordZone? {
        let zoneID = Self.zoneID(for: pairSpaceID)

        do {
            let zone = try await container.privateCloudDatabase.recordZone(for: zoneID)
            return zone
        } catch let error as CKError where error.code == .zoneNotFound {
            return nil
        }
    }

    /// Deletes a zone and all its records from the private database.
    /// Called during permanent data deletion (not during normal unbind,
    /// since the user may want to keep their local copy).
    func deleteZone(for pairSpaceID: UUID) async throws {
        let zoneID = Self.zoneID(for: pairSpaceID)

        do {
            try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
            logger.info("[ZoneManager] 🗑️ Deleted private zone: \(zoneID.zoneName)")
        } catch let error as CKError where error.code == .zoneNotFound {
            logger.info("[ZoneManager] Zone already deleted: \(zoneID.zoneName)")
        }
    }
}
