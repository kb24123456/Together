import Foundation
import Testing
@testable import Together

@Suite
struct LogbookPairSummaryTests {

    @Test func zeroCount_primaryIsStart_secondaryIsOnTheWay() {
        let summary = LogbookPairSummary(totalCount: 0, thisMonthCount: 0, firstItemTitle: nil, lastCompletedAt: nil)
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "一起开始记录")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "你们的第一件任务还在路上")
    }

    @Test func underTen_primaryIncludesCount_secondaryIncludesFirstTitle() {
        let summary = LogbookPairSummary(
            totalCount: 3, thisMonthCount: 2,
            firstItemTitle: "洗衣服", lastCompletedAt: .now
        )
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "我们一起完成了 3 件事")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "第一件：洗衣服")
    }

    @Test func underTen_missingTitle_fallsBackToOnTheWay() {
        let summary = LogbookPairSummary(totalCount: 1, thisMonthCount: 1, firstItemTitle: nil, lastCompletedAt: .now)
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "你们的第一件任务还在路上")
    }

    @Test func tenPlus_secondaryIncludesMonthAndRelativeTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let summary = LogbookPairSummary(
            totalCount: 42, thisMonthCount: 12,
            firstItemTitle: "旧事", lastCompletedAt: twoHoursAgo
        )
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "我们一起完成了 42 件事")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: now) == "本月 12 件 · 最近一次：2 小时前")
    }

    @Test func relativeTime_justNowBucket() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-30), now: now) == "刚刚")
    }

    @Test func relativeTime_minutesAndHoursAndDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-120), now: now) == "2 分钟前")
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-3600 * 5), now: now) == "5 小时前")
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-86400 * 3), now: now) == "3 天前")
    }

    @Test func relativeTime_sevenDaysPlus_fallsBackToMonthDay() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 20
        let now = calendar.date(from: components) ?? .now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let output = LogbookPairSummaryCopy.relativeTime(from: twoWeeksAgo, now: now)
        #expect(output.contains("4"))
        #expect(output.contains("6"))
    }
}
