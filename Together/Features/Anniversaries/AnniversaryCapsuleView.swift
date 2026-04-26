import SwiftUI

struct AnniversaryCapsuleView: View {
    let nextEvent: ImportantDate?
    /// Supabase auth.uid of the viewer (cross-device unique). Birthday events
    /// whose memberUserID matches this render as "我的生日"; otherwise as
    /// "{partnerName}的生日". Pass nil before sync starts (rare; falls back to
    /// the stored creator-perspective title).
    var viewerSupabaseUserID: UUID? = nil
    /// Partner's display name shown in "{name}的生日". When nil/empty falls
    /// back to "伴侣生日".
    var partnerDisplayName: String? = nil
    let onTap: () -> Void

    @State private var isPeeking = false

    var body: some View {
        // Mirrors HomeView.overdueReminderCapsule sizing (build 8 baseline) —
        // sm spacing, 16pt semibold icon, 14pt semibold title, md horizontal
        // and vertical padding, capsule with rose tint at 12% opacity. Spec §3.3
        // uses "·" separator so display works regardless of title grammar.
        Button(action: onTap) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: icon)
                    .font(AppTheme.typography.sized(16, weight: .semibold))

                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))

                Spacer(minLength: 0)

                Text(metricText)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: metricText)
            }
            .foregroundStyle(AppTheme.colors.rose)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.rose.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        // Long-press peek (spec §3.2): only meaningful when both metrics
        // exist (anniversary or recurring custom). Birthday/holiday have
        // a single semantic — long-press is a no-op there.
        .onLongPressGesture(
            minimumDuration: 0.6,
            maximumDistance: 24,
            perform: {},
            onPressingChanged: { pressing in
                guard let event = nextEvent, event.hasPeekableAlternateMode else { return }
                if pressing {
                    HomeInteractionFeedback.selection()
                    isPeeking = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isPeeking = false
                    }
                }
            }
        )
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(metricText))
    }

    private var metricText: String {
        guard let event = nextEvent else { return "点击添加" }
        let mode = effectiveMode(for: event)
        switch mode {
        case .countdown:
            guard let target = countdownTarget(for: event) else { return "—" }
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: .now),
                                          to: cal.startOfDay(for: target)).day ?? 0
            return days <= 0 ? "· 今天" : "· 还有 \(days) 天"
        case .forwardCount:
            let days = event.daysSinceStart
            return days <= 0 ? "· 今天" : "· \(days) 天"
        }
    }

    /// Spec §2.5: for .holiday rows with a hardcoded HolidaySchedule, the
    /// countdown target is the 放假首日, not the festival's core day —
    /// users care about "距春节假期还有 N 天" (when can I rest?), not the
    /// abstract lunar-calendar marker. Falls back to nextOccurrence on the
    /// event's seed date when no schedule is available (year outside the
    /// 1.0 hardcoded 2026-2027 window — 1.0.1 OTA fetch will widen this).
    private func countdownTarget(for event: ImportantDate) -> Date? {
        if case .holiday = event.kind, let preset = event.presetHolidayID {
            let now = Date()
            let thisYear = Calendar.current.component(.year, from: now)
            if let s = HolidayScheduleData.lookup(preset: preset, year: thisYear),
               s.startDate > now {
                return s.startDate
            }
            if let s = HolidayScheduleData.lookup(preset: preset, year: thisYear + 1) {
                return s.startDate
            }
        }
        return event.nextOccurrence(after: .now)
    }

    private func effectiveMode(for event: ImportantDate) -> ImportantDate.DisplayMode {
        let base = event.selectMode()
        guard isPeeking, event.hasPeekableAlternateMode else { return base }
        return base == .forwardCount ? .countdown : .forwardCount
    }

    private var icon: String {
        guard let event = nextEvent else { return "sparkles" }
        return event.icon ?? defaultIcon(for: event.kind)
    }

    private var title: String {
        guard let event = nextEvent else { return "添加第一个纪念日" }
        return event.displayTitle(viewerSupabaseUserID: viewerSupabaseUserID, partnerDisplayName: partnerDisplayName)
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
