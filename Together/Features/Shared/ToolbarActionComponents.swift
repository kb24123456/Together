import SwiftUI
import UIKit

struct ToolbarTextActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body)
            .fontWeight(.regular)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(minWidth: 54, minHeight: 34)
            .contentShape(Capsule(style: .continuous))
    }
}

struct ToolbarIconActionLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct ToolbarAvatarActionLabel: View {
    let avatarAsset: UserAvatarAsset
    let displayName: String
    let overrideImage: UIImage?

    init(
        avatarAsset: UserAvatarAsset,
        displayName: String,
        overrideImage: UIImage? = nil
    ) {
        self.avatarAsset = avatarAsset
        self.displayName = displayName
        self.overrideImage = overrideImage
    }

    var body: some View {
        UserAvatarView(
            avatarAsset: avatarAsset,
            displayName: displayName,
            size: 28,
            fillColor: AppTheme.colors.avatarWarm,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(15, weight: .semibold),
            overrideImage: overrideImage
        )
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }
}
