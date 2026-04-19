import SwiftUI
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

enum ProfileCardSecondaryAvatarState: Hashable {
    case placeholder
    case user(ProfileCardAvatar)
}

struct ProfileUserCard: View {
    private let avatarDiameter: CGFloat = 84
    private let cardHeight: CGFloat = 116
    private let avatarLeadingInset: CGFloat = 18
    private let avatarRevealWidth: CGFloat = 32
    private let avatarTextGap: CGFloat = 14

    let primaryName: String
    let secondaryName: String?
    let primaryAvatar: ProfileCardAvatar
    let secondaryAvatarState: ProfileCardSecondaryAvatarState

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            avatarGroup

            textColumn
                .padding(.leading, avatarTextGap)
                .padding(.trailing, AppTheme.spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
        .shadow(color: AppTheme.colors.shadow.opacity(0.2), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var avatarGroup: some View {
        ZStack(alignment: .leading) {
            switch secondaryAvatarState {
            case .placeholder:
                placeholderBadge
                    .offset(x: secondaryAvatarOffset)
            case .user(let avatar):
                avatarBadge(avatar, fillColor: AppTheme.colors.avatarNeutral)
                    .offset(x: secondaryAvatarOffset)
            }

            avatarBadge(primaryAvatar, fillColor: AppTheme.colors.avatarWarm)
        }
        .frame(width: avatarTrackWidth, height: cardHeight, alignment: .leading)
        .padding(.leading, avatarLeadingInset)
    }

    private func avatarBadge(_ avatar: ProfileCardAvatar, fillColor: Color) -> some View {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: avatarDiameter,
            fillColor: fillColor,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(28, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
            .overlay {
                Circle()
                    .stroke(AppTheme.colors.surfaceElevated.opacity(0.94), lineWidth: 2)
            }
            .shadow(color: AppTheme.colors.shadow.opacity(0.18), radius: 8, y: 4)
            .accessibilityLabel(avatar.displayName)
            .zIndex(2)
    }

    private var placeholderBadge: some View {
        ZStack {
            Circle()
                .fill(AppTheme.colors.surface.opacity(0.01))

            Circle()
                .stroke(
                    AppTheme.colors.outlineStrong.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                )

            Image(systemName: "plus")
                .font(AppTheme.typography.sized(24, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.68))
        }
        .frame(width: avatarDiameter, height: avatarDiameter)
        .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 6, y: 3)
        .accessibilityLabel("等待另一位加入")
        .zIndex(1)
    }

    private var secondaryAvatarOffset: CGFloat {
        avatarDiameter - avatarRevealWidth
    }

    private var avatarTrackWidth: CGFloat {
        avatarDiameter + secondaryAvatarOffset
    }

    @ViewBuilder
    private var textColumn: some View {
        if let secondaryName {
            VStack(alignment: .center, spacing: 0) {
                Text(primaryName)
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("&")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                    .lineLimit(1)

                Text(secondaryName)
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Text(primaryName)
                .font(AppTheme.typography.sized(22, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var accessibilityLabel: String {
        if let secondaryName {
            return "\(primaryName) 和 \(secondaryName)"
        }
        return primaryName
    }
}
