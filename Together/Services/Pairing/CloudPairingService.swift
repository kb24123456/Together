import CloudKit
import Foundation

/// Cross-device pairing service that combines:
/// - `LocalPairingService` for persisting state in SwiftData on the current device
/// - `CloudKitInviteGateway` for exchanging invite codes via CloudKit Public Database
///
/// Pair sync uses CloudKit Public DB directly — no zones or CKShare needed.
///
/// Flow overview:
///   Device A (inviter/owner):
///     createInvite → publishInvite → shows invite code
///   Device B (responder/participant):
///     acceptInviteByCode → lookupInvite → acceptInvite → setupPairingFromRemote
///   Device A (inviter):
///     checkAndFinalizeIfAccepted → pollInviteStatus → finalizeAcceptedInvite
actor CloudPairingService: PairingServiceProtocol {

    private let localPairing: LocalPairingService
    private let inviteGateway: CloudKitInviteGateway
    private let container: CKContainer

    init(
        localPairing: LocalPairingService,
        inviteGateway: CloudKitInviteGateway,
        container: CKContainer
    ) {
        self.localPairing = localPairing
        self.inviteGateway = inviteGateway
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

    func updatePairSpaceDisplayName(pairSpaceID: UUID, displayName: String?, actorID: UUID) async {
        await localPairing.updatePairSpaceDisplayName(pairSpaceID: pairSpaceID, displayName: displayName, actorID: actorID)
    }

    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        // Notify the sync coordinator to tear down the shared-authority pair sync.
        await onPairSyncTeardown?(pairSpaceID)

        // Record in pairing history via localPairing
        let context = try await localPairing.unbind(pairSpaceID: pairSpaceID, actorID: actorID)

        return context
    }

    /// Callback invoked during unbind to tear down pair sync for a pair space.
    /// Set by AppContext during wiring.
    private var onPairSyncTeardown: (@Sendable (UUID) async -> Void)?

    func setOnPairSyncTeardown(_ callback: @escaping @Sendable (UUID) async -> Void) {
        onPairSyncTeardown = callback
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

        // 5. Update local PairSpace with owner metadata
        // No zone/CKShare needed — pair sync uses public DB directly.
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: invite.pairSpaceID,
            zoneName: "",
            ownerRecordID: ownerRecordID.recordName,
            isZoneOwner: true
        )

        // 6. Publish invite to public DB (no shareURL — public DB approach)
        try await inviteGateway.publishInvite(
            code: invite.inviteCode,
            inviterUserUUID: inviterID,
            inviterDisplayName: displayName,
            ownerRecordID: ownerRecordID.recordName,
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
        // No CKShare acceptance needed — pair sync uses public DB directly.
        try await inviteGateway.acceptInvite(
            pairSpaceID: details.pairSpaceID,
            responderUserUUID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 4. Set up local SwiftData state on Device B
        _ = try await localPairing.setupPairingFromRemote(
            pairSpaceID: details.pairSpaceID,
            sharedSpaceID: details.sharedSpaceID,
            inviterUserID: details.inviterUserUUID,
            inviterDisplayName: details.inviterDisplayName,
            responderID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 5. Store metadata locally (no zone — public DB approach).
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: details.pairSpaceID,
            zoneName: "",
            ownerRecordID: details.ownerRecordID,
            isZoneOwner: false
        )

        return await localPairing.currentPairingContext(for: responderID)
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

    /// Restores a previously ended pairing.
    func restoreHistoricalPairing(
        pairSpaceID: UUID,
        ownerName: String
    ) async throws {
        // No-op for public DB approach — pairing state is local only.
    }

    // MARK: - Owner Data Deletion

    /// Marks pair data as deleted locally. Public DB records use soft-delete.
    func permanentlyDeletePairData(pairSpaceID: UUID) async throws {
        await localPairing.markHistoricalPairingDeleted(pairSpaceID: pairSpaceID)
    }
}
