import Foundation
import SwiftData

actor LocalPairingService: PairingServiceProtocol {
    private let container: ModelContainer
    private let defaultInviterName = "云丰"
    private let defaultPartnerName = "沐晴"
    private let defaultPartnerUserID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

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
        let pendingInviteRecord = invites
            .filter { $0.statusRawValue == InviteStatus.pending.rawValue }
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

        let pairMemberships = memberships.filter { $0.pairSpaceID == relatedPairSpace.id }
        guard
            let pairSpace = relatedPairSpace.domainModel(memberships: pairMemberships),
            let sharedSpaceRecord = spaces.first(where: { $0.id == relatedPairSpace.sharedSpaceID })
        else {
            return PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        }

        let partnerMembership = pairMemberships.first(where: { $0.userID != userID })
        let partner = partnerMembership.map {
            User(
                id: $0.userID,
                appleUserID: nil,
                displayName: $0.nickname,
                avatarSystemName: "person.crop.circle.fill",
                createdAt: $0.joinedAt,
                updatedAt: $0.joinedAt,
                preferences: NotificationSettings(
                    taskReminderEnabled: true,
                    dailySummaryEnabled: true,
                    calendarReminderEnabled: true,
                    futureCollaborationInviteEnabled: true
                )
            )
        }

        return PairingContext(
            state: pairSpace.status == .active ? .paired : .invitePending,
            pairSpaceSummary: PairSpaceSummary(
                sharedSpace: sharedSpaceRecord.domainModel,
                pairSpace: pairSpace,
                partner: partner
            ),
            activeInvite: pendingInviteRecord?.domainModel
        )
    }

    func createInvite(from inviterID: UUID) async throws -> Invite {
        let context = ModelContext(container)
        let invites = (try? context.fetch(FetchDescriptor<PersistentInvite>())) ?? []
        if let pending = invites
            .filter({ $0.inviterID == inviterID && $0.statusRawValue == InviteStatus.pending.rawValue })
            .sorted(by: { $0.sentAt > $1.sentAt })
            .first
        {
            return pending.domainModel
        }

        let now = Date.now
        let sharedSpace = Space(
            id: UUID(),
            type: .pair,
            displayName: "一起的任务空间",
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
                nickname: defaultInviterName,
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
            inviteCode: "PAIR-\(pairSpace.id.uuidString.prefix(6))",
            status: .pending,
            sentAt: now,
            respondedAt: nil,
            expiresAt: now.addingTimeInterval(86_400 * 2)
        )

        context.insert(PersistentSpace(space: sharedSpace))
        context.insert(PersistentPairSpace(pairSpace: pairSpace))
        context.insert(
            PersistentPairMembership(
                pairSpaceID: pairSpace.id,
                userID: inviterID,
                nickname: defaultInviterName,
                joinedAt: now
            )
        )
        context.insert(PersistentInvite(invite: invite, recipientUserID: defaultPartnerUserID))
        try context.save()
        return invite
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
            context.insert(
                PersistentPairMembership(
                    pairSpaceID: pairSpaceID,
                    userID: responderID,
                    nickname: defaultPartnerName,
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
