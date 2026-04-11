import CloudKit
import Foundation

/// Manages CKShare lifecycle for pair spaces.
///
/// After the owner creates a zone, this manager creates a CKShare on that zone
/// so the partner can access it via their shared database.
actor CloudKitShareManager {
    private let container: CKContainer

    init(container: CKContainer) {
        self.container = container
    }

    // MARK: - Share Creation

    /// Creates a zone-wide CKShare for the given pair space zone.
    /// The share allows the partner readWrite access to all records in the zone.
    func createShare(
        for pairSpaceID: UUID,
        ownerName: String?
    ) async throws -> CKShare {
        let zoneID = CloudKitZoneManager.zoneID(for: pairSpaceID)
        let db = container.privateCloudDatabase

        // Check if a share already exists for this zone
        if let existingShare = try? await fetchShare(for: pairSpaceID) {
            #if DEBUG
            print("[ShareManager] Share already exists for zone: \(zoneID.zoneName)")
            #endif
            return existingShare
        }

        // Create a new zone-wide share
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Together 共享空间" as CKRecordValue
        share.publicPermission = .readWrite // Anyone with the URL (shared via invite code) can participate

        let (saveResults, _) = try await db.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )

        // Extract the saved share
        for (_, result) in saveResults {
            if let savedRecord = try? result.get(), let savedShare = savedRecord as? CKShare {
                #if DEBUG
                print("[ShareManager] ✅ Created share for zone: \(zoneID.zoneName)")
                #endif
                return savedShare
            }
        }

        throw CloudKitShareError.shareCreationFailed
    }

    // MARK: - Participant Management

    /// Adds a participant to the share via share URL.
    /// In the CKShare model, the participant accepts the share on their device
    /// using the CKShare.Metadata provided by the system.
    /// This method returns the share URL that should be sent to the partner.
    func shareURL(for pairSpaceID: UUID) async throws -> URL? {
        let share = try await fetchShareOrThrow(for: pairSpaceID)
        return share.url
    }

    /// Accepts a CKShare on behalf of the current user (Device B / participant).
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
        #if DEBUG
        print("[ShareManager] ✅ Accepted share")
        #endif
    }

    /// Fetches CKShare.Metadata from a share URL and accepts it.
    /// Used during invite code acceptance (Device B) where the system never calls
    /// `userDidAcceptCloudKitShareWith` because the user entered a code rather than tapping a link.
    func acceptShareFromURL(_ url: URL) async throws {
        let metadata = try await fetchShareMetadata(for: url)
        try await container.accept(metadata)
        #if DEBUG
        print("[ShareManager] ✅ Accepted share from URL: \(url)")
        #endif
    }

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = false
            var didResume = false
            operation.perShareMetadataResultBlock = { _, result in
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let metadata):
                    continuation.resume(returning: metadata)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                // Only fire if perShareMetadataResultBlock didn't already resume
                guard !didResume else { return }
                didResume = true
                if case .failure(let error) = result {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: CloudKitShareError.shareNotFound)
                }
            }
            container.add(operation)
        }
    }

    // MARK: - Share Retrieval

    /// Fetches the CKShare for a given pair space zone, returns nil if not found.
    func fetchShare(for pairSpaceID: UUID) async throws -> CKShare? {
        let zoneID = CloudKitZoneManager.zoneID(for: pairSpaceID)
        let db = container.privateCloudDatabase

        // Fetch all record zones and check for shares
        do {
            let zone = try await db.recordZone(for: zoneID)
            // Try to find the share record in this zone
            let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)
            let shareRecord = try await db.record(for: shareRecordID)
            return shareRecord as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Stops sharing the zone — removes all participants.
    func stopSharing(for pairSpaceID: UUID) async throws {
        guard let share = try? await fetchShare(for: pairSpaceID) else { return }

        // Remove all non-owner participants
        for participant in share.participants where participant.role != .owner {
            share.removeParticipant(participant)
        }

        let db = container.privateCloudDatabase
        _ = try await db.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
        #if DEBUG
        print("[ShareManager] ⏹️ Stopped sharing for zone: pair-\(pairSpaceID.uuidString.prefix(8))")
        #endif
    }

    // MARK: - Helpers

    private func fetchShareOrThrow(for pairSpaceID: UUID) async throws -> CKShare {
        guard let share = try await fetchShare(for: pairSpaceID) else {
            throw CloudKitShareError.shareNotFound
        }
        return share
    }
}

// MARK: - Errors

enum CloudKitShareError: Error, LocalizedError {
    case shareCreationFailed
    case shareNotFound
    case shareUpdateFailed
    case participantLookupFailed

    var errorDescription: String? {
        switch self {
        case .shareCreationFailed: "无法创建共享空间"
        case .shareNotFound: "共享空间不存在"
        case .shareUpdateFailed: "无法更新共享空间"
        case .participantLookupFailed: "无法查找用户"
        }
    }
}
