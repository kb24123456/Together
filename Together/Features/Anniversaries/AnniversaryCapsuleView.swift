import SwiftUI

struct AnniversaryCapsuleView: View {
    let event: ImportantDate?
    let countMode: ImportantDateCapsuleCountMode
    let daysUntilOrToday: Int?
    let isToday: Bool
    /// Supabase auth.uid of the viewer (cross-device unique). Birthday events
    /// whose memberUserID matches this render as "我的生日"; otherwise as
    /// "{partnerName}的生日". Pass nil before sync starts (rare; falls back to
    /// the stored creator-perspective title).
    var viewerSupabaseUserID: UUID? = nil
    /// Partner's display name shown in "{name}的生日". When nil/empty falls
    /// back to "伴侣生日".
    var partnerDisplayName: String? = nil
    let onPrimaryTap: () -> Void
    let onCountTap: () -> Void

    var body: some View {
        // Mirrors HomeView.overdueReminderCapsule sizing — sm spacing,
        // 16pt semibold icon, 14pt semibold title, md horizontal/vertical
        // padding, capsule with tinted-rose fill at 12% opacity. This keeps
        // the anniversary pill visually consistent with the overdue and
        // periodic capsules elsewhere in the home feed; rose accent
        // distinguishes the romantic context from the alert-coral overdue
        // pill.
        content
            .contentShape(Capsule(style: .continuous))
    }

    private var content: some View {
        HStack(spacing: AppTheme.spacing.sm) {
            Button(action: onPrimaryTap) {
                HStack(spacing: AppTheme.spacing.sm) {
                    Image(systemName: icon)
                        .font(AppTheme.typography.sized(16, weight: .semibold))

                    Text(title)
                        .font(AppTheme.typography.sized(14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))

            Spacer(minLength: 0)

            Button(action: onCountTap) {
                AnniversaryCapsuleDetailText(display: detailDisplay)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(detailAccessibilityLabel))
            .accessibilityHint(canToggleCountMode ? Text("切换纪念日计数方式") : Text(""))
        }
        .foregroundStyle(AppTheme.colors.rose)
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.rose.opacity(0.12))
        )
    }

    private var icon: String {
        guard let event else { return "sparkles" }
        return event.icon ?? defaultIcon(for: event.kind)
    }

    private var title: String {
        guard let event else { return "添加第一个纪念日" }
        return event.displayTitle(viewerSupabaseUserID: viewerSupabaseUserID, partnerDisplayName: partnerDisplayName)
    }

    private var detailDisplay: AnniversaryCapsuleDetailDisplay {
        guard let event, let daysUntilOrToday else { return .staticText("点击添加") }
        if countMode == .elapsed, canShowElapsedDays(for: event) {
            return .numeric(prefix: "已经", value: max(0, event.daysSinceStart))
        }
        if isToday { return .staticText("今天") }
        return .numeric(prefix: "还有", value: max(0, daysUntilOrToday))
    }

    private var canToggleCountMode: Bool {
        guard let event else { return false }
        return canShowElapsedDays(for: event)
    }

    private func canShowElapsedDays(for event: ImportantDate) -> Bool {
        event.supportsElapsedDaysDisplay && event.showsElapsedDays
    }

    private var detailAccessibilityLabel: String {
        switch detailDisplay {
        case let .numeric(prefix, value):
            return "\(prefix) \(value) 天"
        case let .staticText(text):
            return text
        }
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

private enum AnniversaryCapsuleDetailDisplay: Equatable {
    case numeric(prefix: String, value: Int)
    case staticText(String)
}

private struct AnniversaryCapsuleDetailText: View {
    let display: AnniversaryCapsuleDetailDisplay

    var body: some View {
        switch display {
        case let .numeric(prefix, value):
            Text("\(prefix) \(value) 天")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .environment(\.contentTransitionAddsDrawingGroup, true)
                .animation(.snappy(duration: 0.34), value: display)
        case let .staticText(text):
            Text(text)
                .monospacedDigit()
                .contentTransition(.numericText())
                .environment(\.contentTransitionAddsDrawingGroup, true)
                .animation(.snappy(duration: 0.34), value: text)
        }
    }
}
