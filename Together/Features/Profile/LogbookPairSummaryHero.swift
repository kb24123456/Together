import SwiftUI

/// Stats snapshot for the pair-mode Logbook hero.
/// Aggregated once per load from completed items in the pair space.
struct LogbookPairSummary: Equatable, Sendable {
    let totalCount: Int
    let thisMonthCount: Int
    let firstItemTitle: String?
    let lastCompletedAt: Date?
}

/// Copy rules for the Logbook hero. Pulled out of the View to keep the
/// tier logic unit-testable without UIHosting scaffolding.
enum LogbookPairSummaryCopy {
    static func primaryText(for summary: LogbookPairSummary) -> String {
        if summary.totalCount == 0 {
            return "一起开始记录"
        }
        return "我们一起完成了 \(summary.totalCount) 件事"
    }

    static func secondaryText(for summary: LogbookPairSummary, now: Date) -> String {
        if summary.totalCount == 0 {
            return "你们的第一件任务还在路上"
        }

        if summary.totalCount < 10 {
            if let firstTitle = summary.firstItemTitle, firstTitle.isEmpty == false {
                return "第一件：\(firstTitle)"
            }
            return "你们的第一件任务还在路上"
        }

        let lastText: String
        if let lastCompletedAt = summary.lastCompletedAt {
            lastText = relativeTime(from: lastCompletedAt, now: now)
        } else {
            lastText = "暂无"
        }
        return "本月 \(summary.thisMonthCount) 件 · 最近一次：\(lastText)"
    }

    /// Converts a past date into a compact Chinese relative label.
    /// Buckets: <60s → 刚刚; <1h → N 分钟前; <1d → N 小时前;
    /// <7d → N 天前; >=7d → M 月 D 日
    static func relativeTime(from date: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))

        if interval < 60 {
            return "刚刚"
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) 分钟前"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) 小时前"
        }
        if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days) 天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}

/// Pair-mode Logbook hero. Rendered as the first cell inside the
/// CompletedHistoryView List. No card background — sits on the page's
/// warm off-white with a 1px hairline divider at the bottom.
struct LogbookPairSummaryHero: View {
    let summary: LogbookPairSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Text(LogbookPairSummaryCopy.primaryText(for: summary))
                .font(AppTheme.typography.displayLight(20))
                .tracking(0.2)
                .foregroundStyle(AppTheme.colors.title)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: summary.totalCount)

            Text(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now))
                .font(AppTheme.typography.sized(13, weight: .regular))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.lg)
        .padding(.top, AppTheme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.colors.hairline)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.spacing.md)
        }
        .accessibilityElement(children: .combine)
    }
}
