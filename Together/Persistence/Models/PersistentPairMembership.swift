import Foundation
import SwiftData

@Model
final class PersistentPairMembership {
    var id: UUID
    var pairSpaceID: UUID
    var userID: UUID
    var nickname: String
    var joinedAt: Date

    init(
        id: UUID = UUID(),
        pairSpaceID: UUID,
        userID: UUID,
        nickname: String,
        joinedAt: Date
    ) {
        self.id = id
        self.pairSpaceID = pairSpaceID
        self.userID = userID
        self.nickname = nickname
        self.joinedAt = joinedAt
    }
}

extension PersistentPairMembership {
    var domainModel: PairMember {
        PairMember(userID: userID, nickname: nickname, joinedAt: joinedAt)
    }
}
