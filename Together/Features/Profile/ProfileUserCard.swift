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

struct ProfileUserCard: View {
    private let soloAvatarDiameter: CGFloat = 112
    private let nameTopGap: CGFloat = AppTheme.spacing.md
    private let subtitleTopGap: CGFloat = AppTheme.spacing.xxs

    let primaryName: String
    let primaryAvatar: ProfileCardAvatar
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            singleAvatar
                .padding(.bottom, nameTopGap)

            Text(displayTitle)
                .font(AppTheme.typography.sized(22, weight: .regular))
                .tracking(0.2)
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing.lg)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            if subtitle.isEmpty == false {
                Text(subtitle)
                    .font(AppTheme.typography.textStyle(.footnote, weight: .regular))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, subtitleTopGap)
                    .padding(.horizontal, AppTheme.spacing.lg)
            }
        }
        .padding(.top, AppTheme.spacing.xl)
        .padding(.bottom, AppTheme.spacing.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var singleAvatar: some View {
        avatarBadge(primaryAvatar, diameter: soloAvatarDiameter, fillColor: AppTheme.colors.avatarWarm)
    }

    private func avatarBadge(_ avatar: ProfileCardAvatar, diameter: CGFloat, fillColor: Color) -> some View {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: diameter,
            fillColor: fillColor,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(diameter * 0.38, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
        .overlay {
            Circle()
                .strokeBorder(AppTheme.colors.background, lineWidth: 2)
        }
    }

    // MARK: - Derived copy

    private var displayTitle: String {
        return primaryName
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let suffix = subtitle.isEmpty ? "" : "，\(subtitle)"
        return "\(primaryName)\(suffix)"
    }

    private var accessibilityHint: String {
        "编辑个人资料"
    }
}
