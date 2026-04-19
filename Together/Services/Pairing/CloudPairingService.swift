import Foundation
import os

protocol PairJoinObserver: AnyObject, Sendable {
    func onSuccessfulPairJoin() async
}

private let cloudPairingLogger = Logger(subsystem: "com.pigdog.Together", category: "CloudPairing")

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
        // 1. 在销毁本地状态前拿到 Supabase space UUID
        let context = await localPairing.currentPairingContext(for: actorID)
        let supabaseSpaceID: UUID? = {
            guard let zone = context.pairSpaceSummary?.pairSpace.cloudKitZoneName else { return nil }
            return UUID(uuidString: zone)
        }()

        // 2. 先 teardown Supabase sync（停 Realtime、冲完最后一批 push）
        await onPairSyncTeardown?(pairSpaceID)

        // 3. Supabase 端离开 space_members；若最后一人离开则归档 space。
        //    best-effort，不阻断本地解绑；失败记录日志以便事后排查。
        if let supabaseSpaceID, let myID = await supabaseAuth.currentUserID {
            do {
                try await inviteGateway.leaveSpace(spaceID: supabaseSpaceID, userID: myID)
            } catch {
                cloudPairingLogger.error("leaveSpace failed for space=\(supabaseSpaceID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            let remaining = (try? await inviteGateway.remainingMemberCount(spaceID: supabaseSpaceID)) ?? -1
            if remaining == 0 {
                do {
                    try await inviteGateway.archiveSpace(spaceID: supabaseSpaceID)
                } catch {
                    cloudPairingLogger.error("archiveSpace failed for space=\(supabaseSpaceID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            } else if remaining < 0 {
                cloudPairingLogger.notice("skipping archive for space=\(supabaseSpaceID.uuidString, privacy: .public): member count unknown")
            }
        } else {
            let authed = await supabaseAuth.currentUserID != nil
            cloudPairingLogger.notice("skipping Supabase unbind cleanup: supabaseSpaceID=\(supabaseSpaceID?.uuidString ?? "nil", privacy: .public) authed=\(authed, privacy: .public)")
        }

        // 4. 本地解绑（删除本地共享数据 + membership）
        return try await localPairing.unbind(pairSpaceID: pairSpaceID, actorID: actorID)
    }

    private weak var pairJoinObserver: PairJoinObserver?

    func setPairJoinObserver(_ observer: PairJoinObserver?) {
        pairJoinObserver = observer
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

        // 2. 先在 Supabase 创建 space（获取统一 UUID）
        // 注意：space.display_name 是"空间名"（如"我们的小家"），不是用户昵称。
        // 之前误把 inviter 的 displayName（昵称）写成了 space 名 → 对方拉到看到对方昵称作为空间名
        let supabaseSpaceID = try await inviteGateway.createSpace(
            ownerID: supabaseUserID,
            displayName: PairSpace.defaultSharedSpaceDisplayName
        )

        // 3. 将自己加入 space 作为 owner
        try await inviteGateway.joinSpace(
            spaceID: supabaseSpaceID,
            userID: supabaseUserID,
            displayName: displayName,
            role: "owner"
        )

        // 4. 创建 Supabase 邀请（携带 inviter 本地身份）
        let supabaseInvite = try await inviteGateway.createInvite(
            spaceID: supabaseSpaceID,
            inviterID: supabaseUserID,
            inviterLocalUserID: inviterID,
            inviterDisplayName: displayName
        )

        // 5. 创建本地 invite + pair space（使用 Supabase space UUID 作为 sharedSpaceID）
        let invite = try await localPairing.createInvite(
            from: inviterID,
            displayName: displayName,
            sharedSpaceID: supabaseSpaceID
        )

        // 6. 更新本地元数据（zoneName 与 sharedSpace.id 现在一致）
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: invite.pairSpaceID,
            zoneName: supabaseSpaceID.uuidString,
            ownerRecordID: supabaseUserID.uuidString,
            isZoneOwner: true
        )

        // 7. 用 Supabase 邀请码更新本地 invite（UI 从本地读取码）
        await localPairing.updateInviteCode(
            pairSpaceID: invite.pairSpaceID,
            newCode: supabaseInvite.inviteCode
        )

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

        // 5. 获取 inviter 身份信息（从邀请记录 + space_members fallback）
        let inviterLocalUserID = supabaseInvite.inviterLocalUserId ?? UUID()
        var inviterName = supabaseInvite.inviterDisplayName ?? ""
        if inviterName.isEmpty {
            // fallback: 从 space_members 查 inviter 的显示名
            if let member = try? await inviteGateway.getPartnerMember(
                spaceID: supabaseInvite.spaceId,
                excludeUserID: supabaseUserID
            ) {
                inviterName = member.displayName
            }
        }

        // 6. 设置本地 SwiftData 状态
        _ = try await localPairing.setupPairingFromRemote(
            pairSpaceID: supabaseInvite.spaceId,
            sharedSpaceID: supabaseInvite.spaceId,
            inviterUserID: inviterLocalUserID,
            inviterDisplayName: inviterName,
            responderID: responderID,
            responderDisplayName: responderDisplayName
        )

        // 7. 更新本地元数据
        await localPairing.updateCloudKitMetadata(
            pairSpaceID: supabaseInvite.spaceId,
            zoneName: supabaseInvite.spaceId.uuidString,
            ownerRecordID: supabaseInvite.inviterId.uuidString,
            isZoneOwner: false
        )

        let context = await localPairing.currentPairingContext(for: responderID)
        await pairJoinObserver?.onSuccessfulPairJoin()
        return context
    }

    // MARK: - 轮询（Device A）

    func checkAndFinalizeIfAccepted(
        pairSpaceID: UUID,
        inviterID: UUID
    ) async throws -> PairingContext? {
        // 获取本地 PairSpace 中存储的 Supabase space ID
        let localContext = await localPairing.currentPairingContext(for: inviterID)
        guard let pairSpace = localContext.pairSpaceSummary?.pairSpace,
              let supabaseSpaceIDString = pairSpace.cloudKitZoneName,
              !supabaseSpaceIDString.isEmpty,
              let supabaseSpaceID = UUID(uuidString: supabaseSpaceIDString) else {
            return nil
        }

        // 查询 Supabase 邀请状态
        guard let invite = try await inviteGateway.pollInviteStatus(spaceID: supabaseSpaceID) else {
            return nil
        }

        guard invite.status == "accepted" else {
            return nil
        }

        // 从 space_members 获取接受方信息
        guard let supabaseUserID = await supabaseAuth.currentUserID else {
            return nil
        }

        let partnerMember = try? await inviteGateway.getPartnerMember(
            spaceID: supabaseSpaceID,
            excludeUserID: supabaseUserID
        )

        guard let partnerMember else { return nil }

        // 生成一个本地 UUID 给对方（iPad 端的本地 ID 我们不知道，用随机 UUID 代表）
        let responderLocalID = UUID()
        let responderName = partnerMember.displayName

        // 调用 localPairing 完成本地状态转换
        let context = try await localPairing.finalizeAcceptedInvite(
            pairSpaceID: pairSpaceID,
            responderID: responderLocalID,
            responderDisplayName: responderName
        )

        await pairJoinObserver?.onSuccessfulPairJoin()
        return context
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
