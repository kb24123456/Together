import CloudKit
import Foundation

/// Cross-device pairing service that combines:
/// - `LocalPairingService` for persisting state in SwiftData on the current device
/// - `CloudKitInviteGateway` for exchanging invite codes via CloudKit Public Database
/// - `CloudKitZoneManager` for creating/managing private zones
/// - `CloudKitShareManager` for CKShare lifecycle
///
/// Flow overview:
///   Device A (inviter/owner):
///     createInvite → create Zone → create CKShare → publishInvite → shows invite code
///   Device B (responder/participant):
///     acceptInviteByCode → lookupInvite → acceptInvite → setupPairingFromRemote
///   Device A (inviter):
///     checkAndFinalizeIfAccepted → pollInviteStatus → finalizeAcceptedInvite → add participant to share
actor CloudPairingService: PairingServiceProtocol {

    private let localPairing: LocalPairingService
    private let inviteGateway: CloudKitInviteGateway
    private let zoneManager: CloudKitZoneManager
    private let shareManager: CloudKitShareManager
    private let container: CKContainer

    init(
        localPairing: LocalPairingService,
        inviteGateway: CloudKitInviteGateway,
        zoneManager: CloudKitZoneManager,
        shareManager: CloudKitShareManager,
        container: CKContainer
    ) {
        self.localPairing = localPairing
        self.inviteGateway = inviteGateway
        self.zoneManager = zoneManager
        self.shareManager = shareManager
        self.container = container
    }

    // MARK: - Pass-through methods (no cloud involvement)

    func currentPairingContext(for userID: UUID?) async -> PairingContext {
        await localPairing.currentPairingContext(for: userID)
    }

    func acceptInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        try await localPairing.acceptInvite(inviteID: inviteID, responderID: responderID)
    }

    func declineInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        try await localPairing.declineInvite(inviteID: inviteID, responderID: responderID)
    }

    func cancelInvite(inviteID: UUID, actorID: UUID) async throws -> PairingContext {
        try await localPairing.cancelInvite(inviteID: inviteID, actorID: actorID)
    }

    func cancelAllPendingInvites(for userID: UUID) async throws -> PairingContext {
        try await localPairing.cancelAllPendingInvites(for: userID)
    }

    func updatePairSpaceDisplayName(pairSpaceID: UUID, displayName: String?) async {
        await localPairing.updatePairSpaceDisplayName(pairSpaceID: pairSpaceID, displayName: displayName)
    }

    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        // Stop CKShare (remove partner from shared zone)
        try? await shareManager.stopSharing(for: pairSpaceID)

        // Record in pairing history via localPairing
        let context = try await localPairing.unbind(pairSpaceID: pairSpaceID, actorID: actorID)

        return context
    }

    // MARK: - Cloud-aware invite creation (Device A / Owner)

    func createInvite(from inviterID: UUID, displayName: String) async throws -> Invite {
        // 1. Check iCloud availability
        let status = await ICloudStatusService.checkStatus(container: container)
        guard status == .available else {
            throw PairingError.cloudKitUnavailable
        }

        // Get owner's iCloud record ID
        guard let ownerRecordID = try? await container.userRecordID() else {
            throw PairingError.cloudKitUnavailable
        }

        // 2. Check for existing historical pairing with the same partner
        //    (This will be resolved after Device B accepts)

        // 3. Create local invite + pair space skeleton
        let invite = try await localPairing.createInvite(from: inviterID, displayName: displayName)

        // 4. Look up the shared space ID
        let context = await localPairing.currentPairingContext(for: inviterID)
        guard let sharedSpaceID = context.pairSpaceSummary?.sharedSpace.id else {
            throw PairingError.cloudOperationFailed(
                NSError(domain: "CloudPairingService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "共享空间创建失败，请重试"])
            )
        }

        // 5. Create CloudKit custom zone in public database for this pair space
        _ = try await zoneManager.createZone(for: invite.pairSpaceID)

        // 6. Update local PairSpace with zone metadata (both devices are "owners" in public DB)
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: invite.pairSpaceID,
            zoneName: CloudKitZoneManager.zoneName(for: invite.pairSpaceID),
            ownerRecordID: ownerRecordID.recordName,
            isZoneOwner: true
        )

        // 7. Publish invite to CloudKit public DB (for Device B discovery)
        try await inviteGateway.publishInvite(
            code: invite.inviteCode,
            inviterUserUUID: inviterID,
            inviterDisplayName: displayName,
            pairSpaceID: invite.pairSpaceID,
            sharedSpaceID: sharedSpaceID,
            expiresAt: invite.expiresAt,
            shareURL: nil
        )

        return invite
    }

    // MARK: - Cross-device accept (Device B / Participant)

    func acceptInviteByCode(
        _ code: String,
        responderID: UUID,
        responderDisplayName: String
    ) async throws -> PairingContext {
        // 1. Check iCloud availability
        let status = await ICloudStatusService.checkStatus(container: container)
        guard status == .available else {
            throw PairingError.cloudKitUnavailable
        }

        // 2. Fetch invite details from CloudKit public DB
        guard let details = try await inviteGateway.lookupInvite(byCode: code) else {
            throw PairingError.inviteNotFound
        }

        guard details.status != "accepted" else {
            throw PairingError.inviteAlreadyAccepted
        }

        guard details.expiresAt > Date.now else {
            throw PairingError.inviteExpired
        }

        // 3. Mark as accepted in CloudKit public DB
        try await inviteGateway.acceptInvite(
            pairSpaceID: details.pairSpaceID,
            responderUserUUID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 4. Set up local SwiftData state on Device B
        let context = try await localPairing.setupPairingFromRemote(
            pairSpaceID: details.pairSpaceID,
            sharedSpaceID: details.sharedSpaceID,
            inviterUserID: details.inviterUserUUID,
            inviterDisplayName: details.inviterDisplayName,
            responderID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 5. Store zone metadata locally — both devices use publicCloudDatabase,
        //    so isZoneOwner = true for both (no CKShare needed).
        let zoneName = CloudKitZoneManager.zoneName(for: details.pairSpaceID)
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: details.pairSpaceID,
            zoneName: zoneName,
            ownerRecordID: nil,
            isZoneOwner: true
        )

        return context
    }

    // MARK: - Polling (Device A)

    func checkAndFinalizeIfAccepted(
        pairSpaceID: UUID,
        inviterID: UUID
    ) async throws -> PairingContext? {
        guard let details = try? await inviteGateway.pollInviteStatus(pairSpaceID: pairSpaceID) else {
            return nil
        }

        guard details.status == "accepted",
              let responderID = details.responderUserUUID,
              let responderDisplayName = details.responderDisplayName else {
            return nil
        }

        // Finalize local state on Device A
        let context = try await localPairing.finalizeAcceptedInvite(
            pairSpaceID: pairSpaceID,
            responderID: responderID,
            responderDisplayName: responderDisplayName
        )

        // Add partner as participant to CKShare
        // We need to discover their iCloud user record ID
        // For now, the partner will be able to access via sharedCloudDatabase
        // once they accept the share metadata
        #if DEBUG
        print("[CloudPairing] ✅ Pairing finalized, partner: \(responderDisplayName)")
        #endif

        return context
    }

    // MARK: - Historical Pairing Lookup

    /// Checks if two users have been paired before and returns the old pairSpaceID if found.
    func findHistoricalPairing(
        memberARecordID: String,
        memberBRecordID: String
    ) async -> UUID? {
        await localPairing.findHistoricalPairing(
            memberARecordID: memberARecordID,
            memberBRecordID: memberBRecordID
        )
    }

    /// Restores a previously ended pairing by re-sharing the old zone.
    func restoreHistoricalPairing(
        pairSpaceID: UUID,
        ownerName: String
    ) async throws {
        // Re-create the CKShare on the existing zone
        _ = try await shareManager.createShare(for: pairSpaceID, ownerName: ownerName)
    }

    // MARK: - Owner Data Deletion

    /// Permanently deletes the zone and all its data. Called by the owner.
    func permanentlyDeletePairData(pairSpaceID: UUID) async throws {
        try await zoneManager.deleteZone(for: pairSpaceID)
        await localPairing.markHistoricalPairingDeleted(pairSpaceID: pairSpaceID)
    }
}
