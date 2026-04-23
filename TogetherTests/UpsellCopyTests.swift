import Testing
import Foundation
@testable import Together

// MARK: - Hero

@Suite
struct UpsellCopyHeroTests {
    @Test func anniversaryQuotaHero() {
        let hero = UpsellCopy.hero(for: .trigger(.anniversaryQuota))
        #expect(hero.title == "记录所有重要的日子")
        #expect(hero.subtitle == "免费版最多 5 个纪念日")
        #expect(hero.lapseBanner == nil)
    }

    @Test func projectQuotaHero() {
        let hero = UpsellCopy.hero(for: .trigger(.projectQuota))
        #expect(hero.title == "让每个项目都有位置")
        #expect(hero.subtitle == "免费版最多 3 个项目")
        #expect(hero.lapseBanner == nil)
    }

    @Test func logbookHistoryHero() {
        let hero = UpsellCopy.hero(for: .trigger(.logbookHistory))
        #expect(hero.title == "重温每一次完成")
        #expect(hero.subtitle == "免费版仅查看近 30 天记录")
        #expect(hero.lapseBanner == nil)
    }

    @Test func crossDeviceSyncHero() {
        let hero = UpsellCopy.hero(for: .trigger(.crossDeviceSync))
        #expect(hero.title == "找回你在其他设备的数据")
        #expect(hero.subtitle == "开启 iPhone 与 iPad 同步")
        #expect(hero.lapseBanner == nil)
    }

    @Test func lapseHeroReusesCrossDeviceCopyPlusBanner() {
        let lapse = PremiumLapseNotice(
            entitlementExpiredAt: Date(timeIntervalSince1970: 1_000_000),
            detectedAt: Date(timeIntervalSince1970: 1_100_000),
            dedupKey: "lapse:1000000"
        )
        let hero = UpsellCopy.hero(for: .lapse(lapse))
        #expect(hero.title == "找回你在其他设备的数据")
        #expect(hero.subtitle == "开启 iPhone 与 iPad 同步")
        #expect(hero.lapseBanner == "订阅已到期 · 升级恢复同步")
    }

    @Test func genericHero() {
        let hero = UpsellCopy.hero(for: .generic)
        #expect(hero.title == "升级 Together Pro")
        #expect(hero.subtitle == "解锁全部 Pro 功能")
        #expect(hero.lapseBanner == nil)
    }
}

// MARK: - Benefits

@Suite
struct UpsellCopyBenefitsTests {
    @Test func anniversaryTriggerPromotesUnlimitedAnniversaries() {
        let benefits = UpsellCopy.benefits(highlightedBy: .trigger(.anniversaryQuota))
        #expect(benefits.first == .unlimitedAnniversaries)
        #expect(benefits.count == UpsellCopy.defaultBenefitOrder.count)
        #expect(Set(benefits) == Set(UpsellCopy.defaultBenefitOrder))
    }

    @Test func projectTriggerPromotesUnlimitedProjects() {
        let benefits = UpsellCopy.benefits(highlightedBy: .trigger(.projectQuota))
        #expect(benefits.first == .unlimitedProjects)
    }

    @Test func logbookTriggerPromotesFullLogbook() {
        let benefits = UpsellCopy.benefits(highlightedBy: .trigger(.logbookHistory))
        #expect(benefits.first == .fullLogbook)
    }

    @Test func crossDeviceTriggerPromotesCrossDeviceSync() {
        let benefits = UpsellCopy.benefits(highlightedBy: .trigger(.crossDeviceSync))
        #expect(benefits.first == .crossDeviceSync)
    }

    @Test func lapsePromotesCrossDeviceSync() {
        let lapse = PremiumLapseNotice(
            entitlementExpiredAt: nil,
            detectedAt: Date(),
            dedupKey: "k"
        )
        let benefits = UpsellCopy.benefits(highlightedBy: .lapse(lapse))
        #expect(benefits.first == .crossDeviceSync)
    }

    @Test func genericUsesDefaultOrder() {
        let benefits = UpsellCopy.benefits(highlightedBy: .generic)
        #expect(benefits == UpsellCopy.defaultBenefitOrder)
    }

    @Test func promotedBenefitDoesNotDuplicate() {
        let benefits = UpsellCopy.benefits(highlightedBy: .trigger(.projectQuota))
        // unlimitedProjects 应只出现一次（被提首位，不重复在原位）
        #expect(benefits.filter { $0 == .unlimitedProjects }.count == 1)
    }
}

// MARK: - Price / Trial formatting

@Suite
struct UpsellCopyPriceFormattingTests {
    private func makePkg(
        period: PaywallPeriod? = nil,
        intro: PaywallIntroOffer? = nil,
        priceString: String = "¥28"
    ) -> PaywallPackage {
        PaywallPackage(
            id: "test",
            productID: "com.test.monthly",
            localizedTitle: "月度 Pro",
            localizedPriceString: priceString,
            price: 28,
            currencyCode: "CNY",
            subscriptionPeriod: period,
            introductoryOffer: intro
        )
    }

    @Test func monthlyPriceLine() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .month(1)))
        #expect(line == "¥28 / 月")
    }

    @Test func yearlyPriceLine() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .year(1), priceString: "¥198"))
        #expect(line == "¥198 / 年")
    }

    @Test func weeklyPriceLine() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .week(1), priceString: "¥8"))
        #expect(line == "¥8 / 周")
    }

    @Test func quarterlyPriceLine() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .month(3), priceString: "¥78"))
        #expect(line == "¥78 / 季度")
    }

    @Test func halfYearPriceLine() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .month(6), priceString: "¥128"))
        #expect(line == "¥128 / 半年")
    }

    @Test func multiMonthUnusualUnitUsesExplicitCount() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: .month(2), priceString: "¥50"))
        #expect(line == "¥50 / 2 个月")
    }

    @Test func lifetimePurchaseUsesBarePriceString() {
        let line = UpsellCopy.formatPriceLine(makePkg(period: nil, priceString: "¥488"))
        #expect(line == "¥488")
    }

    @Test func freeTrialIsFormatted() {
        let intro = PaywallIntroOffer(period: .day(7), price: 0)
        #expect(UpsellCopy.formatTrial(intro) == "前 7 天免费")
    }

    @Test func monthTrialIsFormattedWithSingular() {
        let intro = PaywallIntroOffer(period: .month(1), price: 0)
        #expect(UpsellCopy.formatTrial(intro) == "前 1 个月免费")
    }

    @Test func nonFreeIntroOfferReturnsNil() {
        let intro = PaywallIntroOffer(period: .month(1), price: 10)
        #expect(UpsellCopy.formatTrial(intro) == nil)
    }

    @Test func nilIntroOfferReturnsNil() {
        #expect(UpsellCopy.formatTrial(nil) == nil)
    }
}

// MARK: - Legal footer

@Suite
struct UpsellCopyLegalTests {
    @Test func legalTextWithPackageIncludesProductTitleAndPrice() {
        let pkg = PaywallPackage(
            id: "annual",
            productID: "com.test.annual",
            localizedTitle: "年度 Pro",
            localizedPriceString: "¥198",
            price: 198,
            currencyCode: "CNY",
            subscriptionPeriod: .year(1),
            introductoryOffer: nil
        )
        let text = UpsellCopy.legalBodyText(for: pkg)
        #expect(text.contains("年度 Pro"))
        #expect(text.contains("¥198 / 年"))
        #expect(text.contains("Apple ID"))
        #expect(text.contains("当前周期结束前 24 小时取消"))
    }

    @Test func legalTextWithoutPackageFallsBackToShortForm() {
        let text = UpsellCopy.legalBodyText(for: nil)
        #expect(text.contains("订阅将自动续费"))
        #expect(!text.contains("订阅 "))  // 无 "订阅 {title}" 前缀
    }
}
