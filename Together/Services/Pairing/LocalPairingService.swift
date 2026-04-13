import Foundation
import SwiftData

actor LocalPairingService: PairingServiceProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func currentPairingContext(for userID: UUID?) async -> PairingContext {
        guard let userID else {
            return PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        }

        let context = ModelContext(container)
        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        let pairSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
        let spaces = (try? context.fetch(FetchDescriptor<PersistentSpace>())) ?? []
        let invites = (try? context.fetch(FetchDescriptor<PersistentInvite>())) ?? []

        let pairSpaceIDs = Set(memberships.filter { $0.userID == userID }.map(\.pairSpaceID))
        let relatedPairSpace = pairSpaces.first { pairSpaceIDs.contains($0.id) && $0.endedAt == nil }
        // 清理过期的 pending 邀请 → 标记为 expired
        let now = Date.now
        var didExpire = false
        for invite in invites where invite.statusRawValue == InviteStatus.pending.rawValue {
            if invite.expiresAt < now {
                invite.statusRawValue = InviteStatus.expired.rawValue
                invite.respondedAt = now
                didExpire = true
            }
        }
        if didExpire { try? context.save() }

        let pendingInviteRecord = invites
            .filter { $0.statusRawValue == InviteStatus.pending.rawValue && $0.expiresAt > now }
            .sorted { $0.sentAt > $1.sentAt }
            .first { $0.inviterID == userID || $0.recipientUserID == userID }

        guard let relatedPairSpace else {
            let state: BindingState
            if let pendingInviteRecord {
                state = pendingInviteRecord.inviterID == userID ? .invitePending : .inviteReceived
            } else {
                state = .singleTrial
            }
            return PairingContext(
                state: state,
                pairSpaceSummary: nil,
                activeInvite: pendingInviteRecord?.domainModel
            )
        }

        let pairSummary = PairSpaceSummaryResolver.resolve(
            for: userID,
            spaces: spaces,
            pairSpaces: pairSpaces,
            memberships: memberships
        )
        guard pairSummary != nil else {
            return PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        }

        return PairingContext(
            state: relatedPairSpace.statusRawValue == PairSpaceStatus.active.rawValue ? .paired : .invitePending,
            pairSpaceSummary: pairSummary,
            activeInvite: pendingInviteRecord?.domainModel
        )
    }

    func createInvite(from inviterID: UUID, displayName: String) async throws -> Invite {
        let context = ModelContext(container)
        let invites = (try? context.fetch(FetchDescriptor<PersistentInvite>())) ?? []
        let now = Date.now
        // 将过期的 pending 邀请标记为 expired，避免复用
        for invite in invites where invite.inviterID == inviterID
            && invite.statusRawValue == InviteStatus.pending.rawValue
            && invite.expiresAt < now {
            invite.statusRawValue = InviteStatus.expired.rawValue
            invite.respondedAt = now
        }
        // 只复用未过期的 pending 邀请
        if let pending = invites
            .filter({ $0.inviterID == inviterID && $0.statusRawValue == InviteStatus.pending.rawValue && $0.expiresAt > now })
            .sorted(by: { $0.sentAt > $1.sentAt })
            .first
        {
            return pending.domainModel
        }

        let sharedSpace = Space(
            id: UUID(),
            type: .pair,
            displayName: PairSpace.defaultSharedSpaceDisplayName,
            ownerUserID: inviterID,
            status: .active,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        )
        let pairSpace = PairSpace(
            id: UUID(),
            sharedSpaceID: sharedSpace.id,
            status: .pendingAcceptance,
            memberA: PairMember(
                userID: inviterID,
                nickname: displayName,
                joinedAt: now
            ),
            memberB: nil,
            dataBoundaryToken: sharedSpace.id,
            createdAt: now,
            activatedAt: nil,
            endedAt: nil
        )
        let invite = Invite(
            id: UUID(),
            pairSpaceID: pairSpace.id,
            inviterID: inviterID,
            inviteCode: Self.generateNumericCode(digits: 6),
            status: .pending,
            sentAt: now,
            respondedAt: nil,
            expiresAt: now.addingTimeInterval(180) // 3 分钟有效期
        )

        context.insert(PersistentSpace(space: sharedSpace))
        context.insert(PersistentPairSpace(pairSpace: pairSpace))
        context.insert(
            PersistentPairMembership(
                pairSpaceID: pairSpace.id,
                userID: inviterID,
                nickname: displayName,
                joinedAt: now
            )
        )
        context.insert(PersistentInvite(invite: invite, recipientUserID: nil))
        try context.save()
        return invite
    }

    /// Called by CloudPairingService on Device B after getting remote invite details.
    func setupPairingFromRemote(
        pairSpaceID: UUID,
        sharedSpaceID: UUID,
        inviterUserID: UUID,
        inviterDisplayName: String,
        responderID: UUID,
        responderDisplayName: String
    ) async throws -> PairingContext {
        let context = ModelContext(container)
        let now = Date.now
        let placeholderTimestamp = Date(timeIntervalSince1970: 0)

        // Avoid duplicate setup
        let existing = try context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        )
        if existing.isEmpty {
            let sharedSpace = Space(
                id: sharedSpaceID,
                type: .pair,
                displayName: PairSpace.defaultSharedSpaceDisplayName,
                ownerUserID: inviterUserID,
                status: .active,
                createdAt: placeholderTimestamp,
                updatedAt: placeholderTimestamp,
                archivedAt: nil
            )
            let pairSpace = PairSpace(
                id: pairSpaceID,
                sharedSpaceID: sharedSpaceID,
                status: .active,
                memberA: PairMember(userID: inviterUserID, nickname: inviterDisplayName, joinedAt: now),
                memberB: PairMember(userID: responderID, nickname: responderDisplayName, joinedAt: now),
                dataBoundaryToken: sharedSpaceID,
                createdAt: placeholderTimestamp,
                activatedAt: placeholderTimestamp,
                endedAt: nil
            )
            context.insert(PersistentSpace(space: sharedSpace))
            context.insert(PersistentPairSpace(pairSpace: pairSpace))
            context.insert(PersistentPairMembership(
                pairSpaceID: pairSpaceID, userID: inviterUserID,
                nickname: inviterDisplayName, joinedAt: now
            ))
            context.insert(PersistentPairMembership(
                pairSpaceID: pairSpaceID, userID: responderID,
                nickname: responderDisplayName, joinedAt: now
            ))
            try context.save()
        }
        return await currentPairingContext(for: responderID)
    }

    /// Called by CloudPairingService on Device A after invite is accepted remotely.
    func finalizeAcceptedInvite(
        pairSpaceID: UUID,
        responderID: UUID,
        responderDisplayName: String
    ) async throws -> PairingContext {
        let context = ModelContext(container)
        let now = Date.now

        let pairSpaceRecords = try context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        )
        guard let pairRecord = pairSpaceRecords.first else {
            return await currentPairingContext(for: responderID)
        }

        pairRecord.statusRawValue = PairSpaceStatus.active.rawValue
        pairRecord.activatedAt = now

        let existingMemberships = try context.fetch(
            FetchDescriptor<PersistentPairMembership>(
                predicate: #Predicate<PersistentPairMembership> { $0.pairSpaceID == pairSpaceID }
            )
        )
        if existingMemberships.contains(where: { $0.userID == responderID }) == false {
            context.insert(PersistentPairMembership(
                pairSpaceID: pairSpaceID, userID: responderID,
                nickname: responderDisplayName, joinedAt: now
            ))
        }

        let invites = try context.fetch(
            FetchDescriptor<PersistentInvite>(
                predicate: #Predicate<PersistentInvite> { $0.pairSpaceID == pairSpaceID }
            )
        )
        invites.first?.statusRawValue = InviteStatus.accepted.rawValue
        invites.first?.respondedAt = now

        try context.save()

        let inviterID = existingMemberships.first(where: { $0.userID != responderID })?.userID ?? responderID
        return await currentPairingContext(for: inviterID)
    }

    func acceptInviteByCode(_ code: String, responderID: UUID, responderDisplayName: String) async throws -> PairingContext {
        // LocalPairingService only supports local invites — use CloudPairingService for cross-device.
        throw PairingError.crossDeviceNotSupported
    }

    func checkAndFinalizeIfAccepted(pairSpaceID: UUID, inviterID: UUID) async throws -> PairingContext? {
        // LocalPairingService has no remote awareness — CloudPairingService overrides this.
        return nil
    }

    func acceptInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        let context = ModelContext(container)
        guard let inviteRecord = try context.fetch(
            FetchDescriptor<PersistentInvite>(
                predicate: #Predicate<PersistentInvite> { $0.id == inviteID }
            )
        ).first else {
            return await currentPairingContext(for: responderID)
        }
        let pairSpaceID = inviteRecord.pairSpaceID
        guard let pairSpaceRecord = try context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        ).first else {
            return await currentPairingContext(for: responderID)
        }

        inviteRecord.statusRawValue = InviteStatus.accepted.rawValue
        inviteRecord.respondedAt = .now
        pairSpaceRecord.statusRawValue = PairSpaceStatus.active.rawValue
        pairSpaceRecord.activatedAt = .now

        let existingMemberships = try context.fetch(
            FetchDescriptor<PersistentPairMembership>(
                predicate: #Predicate<PersistentPairMembership> { $0.pairSpaceID == pairSpaceID }
            )
        )
        if existingMemberships.contains(where: { $0.userID == responderID }) == false {
            // Resolve display name from persisted profile, fall back gracefully
            let profiles = (try? context.fetch(FetchDescriptor<PersistentUserProfile>())) ?? []
            let responderName = profiles.first(where: { $0.userID == responderID })?.displayName ?? "伙伴"
            context.insert(
                PersistentPairMembership(
                    pairSpaceID: pairSpaceID,
                    userID: responderID,
                    nickname: responderName,
                    joinedAt: .now
                )
            )
        }

        try context.save()
        return await currentPairingContext(for: responderID)
    }

    func declineInvite(inviteID: UUID, responderID: UUID) async throws -> PairingContext {
        try await updateInvite(inviteID: inviteID, status: .declined, actorID: responderID)
    }

    func cancelInvite(inviteID: UUID, actorID: UUID) async throws -> PairingContext {
        try await updateInvite(inviteID: inviteID, status: .cancelled, actorID: actorID)
    }

    func cancelAllPendingInvites(for userID: UUID) async throws -> PairingContext {
        let context = ModelContext(container)
        let now = Date.now

        // 1. 取消该用户所有 pending 邀请
        let pendingRaw = InviteStatus.pending.rawValue
        let allInvites = try context.fetch(
            FetchDescriptor<PersistentInvite>(
                predicate: #Predicate<PersistentInvite> { $0.statusRawValue == pendingRaw }
            )
        )
        let userInvites = allInvites.filter { $0.inviterID == userID || $0.recipientUserID == userID }
        for invite in userInvites {
            invite.statusRawValue = InviteStatus.cancelled.rawValue
            invite.respondedAt = now
        }

        // 2. 清理该用户关联的所有 pendingAcceptance 状态的 PairSpace
        //    不仅仅是当前 pending 邀请关联的，也包括邀请已过期但 PairSpace 未清理的情况
        let pendingAcceptanceRaw = PairSpaceStatus.pendingAcceptance.rawValue
        let allPairSpaces = try context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.statusRawValue == pendingAcceptanceRaw }
            )
        )
        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        let userPairSpaceIDs = Set(memberships.filter { $0.userID == userID }.map(\.pairSpaceID))
        for pairSpace in allPairSpaces where userPairSpaceIDs.contains(pairSpace.id) {
            pairSpace.statusRawValue = PairSpaceStatus.ended.rawValue
            pairSpace.endedAt = now
        }

        try context.save()
        return await currentPairingContext(for: userID)
    }

    func updatePairSpaceDisplayName(pairSpaceID: UUID, displayName: String?) async {
        let context = ModelContext(container)
        guard let pairSpace = try? context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        ).first else { return }

        // SharedSpace.displayName is the authoritative source for pair workspace naming.
        let sharedSpaceID = pairSpace.sharedSpaceID
        if let space = try? context.fetch(
            FetchDescriptor<PersistentSpace>(
                predicate: #Predicate<PersistentSpace> { $0.id == sharedSpaceID }
            )
        ).first {
            space.displayName = displayName ?? PairSpace.defaultSharedSpaceDisplayName
            space.updatedAt = .now
        }

        try? context.save()
    }

    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        let context = ModelContext(container)
        let pairSpaces = try context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        )
        pairSpaces.first?.statusRawValue = PairSpaceStatus.ended.rawValue
        pairSpaces.first?.endedAt = .now
        try context.save()
        return await currentPairingContext(for: actorID)
    }

    /// 生成 N 位纯数字邀请码（如 "038471"）
    private static func generateNumericCode(digits: Int) -> String {
        (0..<digits).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    // MARK: - CloudKit Zone Metadata

    /// Updates the CloudKit zone metadata on a PairSpace record.
    func updateCloudKitMetadata(
        pairSpaceID: UUID,
        zoneName: String,
        ownerRecordID: String?,
        isZoneOwner: Bool
    ) async {
        let context = ModelContext(container)
        guard let record = try? context.fetch(
            FetchDescriptor<PersistentPairSpace>(
                predicate: #Predicate<PersistentPairSpace> { $0.id == pairSpaceID }
            )
        ).first else { return }

        record.cloudKitZoneName = zoneName
        if let ownerRecordID { record.ownerRecordID = ownerRecordID }
        record.isZoneOwner = isZoneOwner
        try? context.save()
    }

    // MARK: - Pairing History

    /// Records a pairing relationship for future same-couple detection.
    func recordPairingHistory(
        pairSpaceID: UUID,
        memberARecordID: String,
        memberBRecordID: String,
        zoneName: String,
        pairedAt: Date
    ) async {
        let context = ModelContext(container)
        let record = PersistentPairingHistory(
            pairSpaceID: pairSpaceID,
            memberARecordID: memberARecordID,
            memberBRecordID: memberBRecordID,
            zoneName: zoneName,
            pairedAt: pairedAt
        )
        context.insert(record)
        try? context.save()
    }

    /// Finds a historical pairing between two users (by iCloud record IDs).
    /// Returns the old pairSpaceID if found and not permanently deleted.
    func findHistoricalPairing(
        memberARecordID: String,
        memberBRecordID: String
    ) async -> UUID? {
        let context = ModelContext(container)
        let histories = (try? context.fetch(FetchDescriptor<PersistentPairingHistory>())) ?? []

        return histories.first { h in
            !h.isDeleted &&
            ((h.memberARecordID == memberARecordID && h.memberBRecordID == memberBRecordID) ||
             (h.memberARecordID == memberBRecordID && h.memberBRecordID == memberARecordID))
        }?.pairSpaceID
    }

    /// Marks a historical pairing as permanently deleted (owner chose to delete data).
    func markHistoricalPairingDeleted(pairSpaceID: UUID) async {
        let context = ModelContext(container)
        let histories = (try? context.fetch(FetchDescriptor<PersistentPairingHistory>())) ?? []
        if let record = histories.first(where: { $0.pairSpaceID == pairSpaceID }) {
            record.isDeleted = true
            record.endedAt = .now
            try? context.save()
        }
    }

    private func updateInvite(inviteID: UUID, status: InviteStatus, actorID: UUID) async throws -> PairingContext {
        let context = ModelContext(container)
        let invites = try context.fetch(
            FetchDescriptor<PersistentInvite>(
                predicate: #Predicate<PersistentInvite> { $0.id == inviteID }
            )
        )
        invites.first?.statusRawValue = status.rawValue
        invites.first?.respondedAt = .now
        try context.save()
        return await currentPairingContext(for: actorID)
    }
}
