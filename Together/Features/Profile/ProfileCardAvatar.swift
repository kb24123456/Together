#if canImport(UIKit)
import UIKit
#endif

struct ProfileCardAvatar: Hashable {
    let displayName: String
    let avatarAsset: UserAvatarAsset
    let overrideImage: UIImage?

    static func == (lhs: ProfileCardAvatar, rhs: ProfileCardAvatar) -> Bool {
        lhs.displayName == rhs.displayName && lhs.avatarAsset == rhs.avatarAsset
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(displayName)
        hasher.combine(avatarAsset)
    }
}
