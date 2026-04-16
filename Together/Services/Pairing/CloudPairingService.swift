import Foundation

/// 配对服务（Supabase 版）
/// 组合 LocalPairingService（本地 SwiftData 状态）+ SupabaseInviteGateway（远程配对操作）
///
/// 配对流程：
///   Device A (邀请方):
///     createInvite → Supabase 创建 space + 邀请码 → 显示邀请码
///   Device B (接受方):
///     acceptInviteByCode → 查询邀请码 → 接受邀请 → 加入 space
///   Device A (邀请方):
///     checkAndFinalizeIfAccepted → 轮询邀请状态 → 配对完成
actor CloudPairingService: PairingServiceProtocol {

    private let localPairing: LocalPairingService
    private let inviteGateway: SupabaseInviteGateway
    private let supabaseAuth: SupabaseAuthService

    init(
        localPairing: LocalPairingService,
        inviteGateway: SupabaseInviteGateway,
        supabaseAuth: SupabaseAuthService
    ) {
        self.localPairing = localPairing
        self.inviteGateway = inviteGateway
        self.supabaseAuth = supabaseAuth
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
        await onPairSyncTeardown?(pairSpaceID)
        let context = try await localPairing.unbind(pairSpaceID: pairSpaceID, actorID: actorID)
        // TODO: Supabase 端解绑操作（UPDATE spaces SET status = 'archived'）
        return context
    }

    private var onPairSyncTeardown: (@Sendable (UUID) async -> Void)?

    func setOnPairSyncTeardown(_ callback: @escaping @Sendable (UUID) async -> Void) {
        onPairSyncTeardown = callback
    }

    // MARK: - Supabase 邀请创建（Device A / Owner）

    func createInvite(from inviterID: UUID, displayName: String) async throws -> Invite {
        // 1. 确保 Supabase 已登录
        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            throw PairingError.cloudKitUnavailable // 复用已有错误类型
        }

        // 2. 创建本地 invite + pair space 骨架
        let invite = try await localPairing.createInvite(from: inviterID, displayName: displayName)

        // 3. 获取 shared space ID
        let context = await localPairing.currentPairingContext(for: inviterID)
        guard context.pairSpaceSummary?.sharedSpace.id != nil else {
            throw PairingError.cloudOperationFailed(
                NSError(domain: "CloudPairingService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "共享空间创建失败，请重试"])
            )
        }

        // 4. 在 Supabase 创建 space
        let supabaseSpaceID = try await inviteGateway.createSpace(
            ownerID: supabaseUserID,
            displayName: displayName
        )

        // 5. 将自己加入 space 作为 owner
        try await inviteGateway.joinSpace(
            spaceID: supabaseSpaceID,
            userID: supabaseUserID,
            displayName: displayName,
            role: "owner"
        )

        // 6. 创建 Supabase 邀请
        let supabaseInvite = try await inviteGateway.createInvite(
            spaceID: supabaseSpaceID,
            inviterID: supabaseUserID
        )

        // 7. 更新本地元数据（使用 Supabase space ID）
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: invite.pairSpaceID,
            zoneName: supabaseSpaceID.uuidString, // 复用字段存储 Supabase space ID
            ownerRecordID: supabaseUserID.uuidString,
            isZoneOwner: true
        )

        // 8. 返回带有 Supabase 邀请码的本地 invite
        var updatedInvite = invite
        updatedInvite.inviteCode = supabaseInvite.inviteCode
        return updatedInvite
    }

    // MARK: - 跨设备接受邀请（Device B）

    func acceptInviteByCode(
        _ code: String,
        responderID: UUID,
        responderDisplayName: String
    ) async throws -> PairingContext {
        // 1. 确保 Supabase 已登录
        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            throw PairingError.cloudKitUnavailable
        }

        // 2. 从 Supabase 查找邀请
        guard let supabaseInvite = try await inviteGateway.lookupInvite(code: code) else {
            throw PairingError.inviteNotFound
        }

        guard supabaseInvite.status == "pending" else {
            throw PairingError.inviteAlreadyAccepted
        }

        guard supabaseInvite.expiresAt > Date.now else {
            throw PairingError.inviteExpired
        }

        // 3. 接受邀请
        _ = try await inviteGateway.acceptInvite(
            inviteID: supabaseInvite.id,
            acceptedBy: supabaseUserID
        )

        // 4. 加入 space 作为 member
        try await inviteGateway.joinSpace(
            spaceID: supabaseInvite.spaceId,
            userID: supabaseUserID,
            displayName: responderDisplayName
        )

        // 5. 设置本地 SwiftData 状态
        _ = try await localPairing.setupPairingFromRemote(
            pairSpaceID: supabaseInvite.spaceId, // 使用 Supabase space ID 作为 pairSpaceID
            sharedSpaceID: supabaseInvite.spaceId,
            inviterUserID: responderID, // 本地 userID（非 Supabase ID）
            inviterDisplayName: "", // 将通过 Realtime 更新
            responderID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 6. 更新本地元数据
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: supabaseInvite.spaceId,
            zoneName: supabaseInvite.spaceId.uuidString,
            ownerRecordID: supabaseInvite.inviterId.uuidString,
            isZoneOwner: false
        )

        return await localPairing.currentPairingContext(for: responderID)
    }

    // MARK: - 轮询（Device A）

    func checkAndFinalizeIfAccepted(
        pairSpaceID: UUID,
        inviterID: UUID
    ) async throws -> PairingContext? {
        // Supabase 使用 Realtime 监听，这个方法可以简化
        // 但保留轮询作为后备
        return nil
    }

    // MARK: - Historical Pairing Lookup

    func findHistoricalPairing(
        memberARecordID: String,
        memberBRecordID: String
    ) async -> UUID? {
        await localPairing.findHistoricalPairing(
            memberARecordID: memberARecordID,
            memberBRecordID: memberBRecordID
        )
    }

    func restoreHistoricalPairing(
        pairSpaceID: UUID,
        ownerName: String
    ) async throws {
        // Supabase 版不支持恢复历史配对
    }

    func permanentlyDeletePairData(pairSpaceID: UUID) async throws {
        await localPairing.markHistoricalPairingDeleted(pairSpaceID: pairSpaceID)
    }
}
