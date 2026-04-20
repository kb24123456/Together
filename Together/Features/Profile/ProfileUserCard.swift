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

/// Identity card at the top of Profile. Vertical layout: avatars on top,
/// name below, subtitle under name. In solo mode shows a single 64pt
/// avatar; in pair mode shows two 56pt avatars overlapping ~30% with
/// self on the left (bottom z-order) and partner on the right (top).
///
/// The card has NO background — it sits directly on the page's warm
/// off-white and is separated from the first group by a hairline divider.
struct ProfileUserCard: View {
    private let soloAvatarDiameter: CGFloat = 112
    private let pairAvatarDiameter: CGFloat = 92
    /// Amount (in pt) the two pair avatars overlap each other horizontally.
    /// At 20pt on 92pt diameter, ~22% overlap — the two circles read as a
    /// joined pair without one dominating the other.
    private let pairAvatarOverlap: CGFloat = 20
    private let nameTopGap: CGFloat = AppTheme.spacing.md
    private let subtitleTopGap: CGFloat = AppTheme.spacing.xxs

    let primaryName: String
    let secondaryName: String?
    let primaryAvatar: ProfileCardAvatar
    let secondaryAvatarState: ProfileCardSecondaryAvatarState
    /// Subtitle displayed beneath the name. E.g. "独立工作空间" or
    /// "我们的小家 · 配对 124 天".
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            avatarCluster
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

    // MARK: - Avatar cluster

    @ViewBuilder
    private var avatarCluster: some View {
        if case .user(let partnerAvatar) = secondaryAvatarState, secondaryName != nil {
            pairAvatars(partner: partnerAvatar)
        } else {
            singleAvatar
        }
    }

    private var singleAvatar: some View {
        avatarBadge(primaryAvatar, diameter: soloAvatarDiameter, fillColor: AppTheme.colors.avatarWarm)
    }

    private func pairAvatars(partner: ProfileCardAvatar) -> some View {
        let selfBadge = avatarBadge(primaryAvatar, diameter: pairAvatarDiameter, fillColor: AppTheme.colors.avatarWarm)
        let partnerBadge = avatarBadge(partner, diameter: pairAvatarDiameter, fillColor: AppTheme.colors.avatarNeutral)

        // HStack with negative spacing overlaps the two avatars by
        // pairAvatarOverlap. HStack's intrinsic content size (2 * D − overlap)
        // lets the parent VStack center the pair as a balanced unit. Self has
        // higher zIndex so its full circle renders above partner in the
        // overlap region — this device's user owns the visual foreground.
        return HStack(spacing: -pairAvatarOverlap) {
            selfBadge
                .zIndex(2)
            partnerBadge
                .zIndex(1)
        }
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
        if let secondaryName {
            return "\(primaryName) & \(secondaryName)"
        }
        return primaryName
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if let secondaryName {
            let suffix = subtitle.isEmpty ? "" : "，\(subtitle)"
            return "\(primaryName) 和 \(secondaryName)\(suffix)"
        }
        let suffix = subtitle.isEmpty ? "" : "，\(subtitle)"
        return "\(primaryName)\(suffix)"
    }

    private var accessibilityHint: String {
        secondaryName == nil ? "编辑个人资料" : "编辑双人资料"
    }
}
