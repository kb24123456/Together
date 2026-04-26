import SwiftUI

struct AnniversaryCapsuleView: View {
    let nextEvent: ImportantDate?
    /// Local User.id of the device's currentUser — birthday events whose
    /// memberUserID matches this render as "我的生日"; otherwise as
    /// "{partnerName}的生日". Pass nil if not signed in (rare; falls back to
    /// stored title which is whatever the creator typed).
    var viewerLocalUserID: UUID? = nil
    /// Partner's display name shown in "{name}的生日". When nil/empty falls
    /// back to "伴侣生日".
    var partnerDisplayName: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: icon)
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Spacer()
                Text(detail)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        guard let event = nextEvent else { return "sparkles" }
        return event.icon ?? defaultIcon(for: event.kind)
    }

    private var title: String {
        guard let event = nextEvent else { return "添加第一个纪念日" }
        return event.displayTitle(viewerLocalUserID: viewerLocalUserID, partnerDisplayName: partnerDisplayName)
    }

    private var detail: String {
        guard let event = nextEvent,
              let days = event.daysUntilNext() else { return "点击添加" }
        if days == 0 { return "今天" }
        return "还有 \(days) 天"
    }

    private func defaultIcon(for kind: ImportantDateKind) -> String {
        switch kind {
        case .birthday: return "gift.fill"
        case .anniversary: return "heart.fill"
        case .holiday: return "sparkles"
        case .custom: return "star.fill"
        }
    }
}
