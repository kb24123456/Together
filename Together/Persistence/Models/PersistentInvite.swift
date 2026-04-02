import Foundation
import SwiftData

@Model
final class PersistentInvite {
    var id: UUID
    var pairSpaceID: UUID
    var inviterID: UUID
    var recipientUserID: UUID?
    var inviteCode: String
    var statusRawValue: String
    var sentAt: Date
    var respondedAt: Date?
    var expiresAt: Date

    init(
        id: UUID,
        pairSpaceID: UUID,
        inviterID: UUID,
        recipientUserID: UUID?,
        inviteCode: String,
        statusRawValue: String,
        sentAt: Date,
        respondedAt: Date?,
        expiresAt: Date
    ) {
        self.id = id
        self.pairSpaceID = pairSpaceID
        self.inviterID = inviterID
        self.recipientUserID = recipientUserID
        self.inviteCode = inviteCode
        self.statusRawValue = statusRawValue
        self.sentAt = sentAt
        self.respondedAt = respondedAt
        self.expiresAt = expiresAt
    }
}

extension PersistentInvite {
    convenience init(invite: Invite, recipientUserID: UUID?) {
        self.init(
            id: invite.id,
            pairSpaceID: invite.pairSpaceID,
            inviterID: invite.inviterID,
            recipientUserID: recipientUserID,
            inviteCode: invite.inviteCode,
            statusRawValue: invite.status.rawValue,
            sentAt: invite.sentAt,
            respondedAt: invite.respondedAt,
            expiresAt: invite.expiresAt
        )
    }

    var domainModel: Invite {
        Invite(
            id: id,
            pairSpaceID: pairSpaceID,
            inviterID: inviterID,
            inviteCode: inviteCode,
            status: InviteStatus(rawValue: statusRawValue) ?? .pending,
            sentAt: sentAt,
            respondedAt: respondedAt,
            expiresAt: expiresAt
        )
    }
}
