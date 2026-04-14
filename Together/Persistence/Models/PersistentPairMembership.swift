import Foundation
import SwiftData

@Model
final class PersistentPairMembership {
    var id: UUID
    var pairSpaceID: UUID
    var userID: UUID
    var nickname: String
    var joinedAt: Date
    var avatarSystemName: String?
    var avatarPhotoFileName: String?
    var avatarAssetID: String?
    var avatarVersion: Int = 0

    init(
        id: UUID = UUID(),
        pairSpaceID: UUID,
        userID: UUID,
        nickname: String,
        joinedAt: Date,
        avatarSystemName: String? = nil,
        avatarPhotoFileName: String? = nil,
        avatarAssetID: String? = nil,
        avatarVersion: Int = 0
    ) {
        self.id = id
        self.pairSpaceID = pairSpaceID
        self.userID = userID
        self.nickname = nickname
        self.joinedAt = joinedAt
        self.avatarSystemName = avatarSystemName
        self.avatarPhotoFileName = avatarPhotoFileName
        self.avatarAssetID = avatarAssetID
        self.avatarVersion = avatarVersion
    }
}

extension PersistentPairMembership {
    var domainModel: PairMember {
        PairMember(userID: userID, nickname: nickname, joinedAt: joinedAt)
    }
}
