import Foundation

/// 付费墙文案 + 格式化纯函数层。所有中文字符串集中在本文件，方便未来一处切 i18n。
enum UpsellCopy {

    // MARK: - Benefits

    enum Benefit: String, CaseIterable, Identifiable, Equatable, Sendable {
        case crossDeviceSync = "本人跨设备同步（iPhone / iPad）"
        case unlimitedAnniversaries = "无限纪念日"
        case unlimitedProjects = "无限项目"
        case fullLogbook = "全量 Logbook 历史"

        var id: String { rawValue }
        var displayText: String { rawValue }
    }

    /// 固定顺序（`.generic` / 无 trigger 走此序列）
    static let defaultBenefitOrder: [Benefit] = [
        .crossDeviceSync, .unlimitedAnniversaries, .unlimitedProjects, .fullLogbook
    ]

    /// 按 displayKind 把对应 benefit 提到首位，其余维持 `defaultBenefitOrder` 相对顺序
    static func benefits(highlightedBy displayKind: UpsellDisplayKind) -> [Benefit] {
        let priority: Benefit? = switch displayKind {
        case .trigger(.anniversaryQuota): .unlimitedAnniversaries
        case .trigger(.projectQuota): .unlimitedProjects
        case .trigger(.logbookHistory): .fullLogbook
        case .trigger(.crossDeviceSync): .crossDeviceSync
        case .trigger(.graceExpiring): nil
        case .lapse: .crossDeviceSync
        case .generic: nil
        }
        guard let priority else { return defaultBenefitOrder }
        return [priority] + defaultBenefitOrder.filter { $0 != priority }
    }

    // MARK: - Hero copy

    struct Hero: Equatable, Sendable {
        let title: String
        let subtitle: String
        /// 仅 `.lapse` 填值："订阅已到期 · 升级恢复同步"。其余 nil
        let lapseBanner: String?
    }

    static func hero(for displayKind: UpsellDisplayKind) -> Hero {
        switch displayKind {
        case .trigger(.anniversaryQuota):
            Hero(title: "记录所有重要的日子",
                 subtitle: "免费版最多 3 个纪念日",
                 lapseBanner: nil)
        case .trigger(.projectQuota):
            Hero(title: "让每个项目都有位置",
                 subtitle: "免费版最多 3 个项目",
                 lapseBanner: nil)
        case .trigger(.logbookHistory):
            Hero(title: "重温每一次完成",
                 subtitle: "免费版仅查看近 30 天记录",
                 lapseBanner: nil)
        case .trigger(.crossDeviceSync):
            Hero(title: "找回你在其他设备的数据",
                 subtitle: "开启 iPhone 与 iPad 同步",
                 lapseBanner: nil)
        case .trigger(.graceExpiring(let daysRemaining)):
            Hero(title: "续订 Together Pro，保留你的回忆",
                 subtitle: "你的订阅将在 \(daysRemaining) 天后彻底失效。续订后立即恢复完整体验。",
                 lapseBanner: nil)
        case .lapse:
            Hero(title: "找回你在其他设备的数据",
                 subtitle: "开启 iPhone 与 iPad 同步",
                 lapseBanner: "订阅已到期 · 升级恢复同步")
        case .generic:
            Hero(title: "升级 Together Pro",
                 subtitle: "解锁全部 Pro 功能",
                 lapseBanner: nil)
        }
    }

    // MARK: - Price / trial formatting

    /// "¥28 / 月" / "¥198 / 年" / "¥488"（终身 / 非订阅）
    static func formatPriceLine(_ pkg: PaywallPackage) -> String {
        guard let period = pkg.subscriptionPeriod else {
            return pkg.localizedPriceString
        }
        return "\(pkg.localizedPriceString)\(periodSuffix(period))"
    }

    /// "前 7 天免费" / "前 1 个月免费"；非免费试用（含 nil）返回 nil
    static func formatTrial(_ intro: PaywallIntroOffer?) -> String? {
        guard let intro, intro.isFreeTrial else { return nil }
        return "前 \(periodCountString(intro.period))免费"
    }

    // MARK: - Legal footer（spec § 2.11，Apple 3.1.2(a) 模板）

    static func legalBodyText(for pkg: PaywallPackage?) -> String {
        guard let p = pkg else {
            return "订阅将自动续费；可在 Apple ID 设置中随时管理或取消订阅。"
        }
        return """
        订阅 \(p.localizedTitle) · \(formatPriceLine(p))
        订阅将自动续费；可在 Apple ID 设置中随时管理或取消订阅，至少在当前周期结束前 24 小时取消。
        """
    }

    // MARK: - Timing

    /// `.succeeded` → `onFinished(.purchasedOrRestored)` 间的 hold duration 默认值
    static let paywallSuccessHoldDuration: Duration = .seconds(1.2)

    // MARK: - Private

    private static func periodSuffix(_ p: PaywallPeriod) -> String {
        switch p {
        case .day(let n): n == 1 ? " / 天" : " / \(n) 天"
        case .week(let n): n == 1 ? " / 周" : " / \(n) 周"
        case .month(let n):
            switch n {
            case 1: " / 月"
            case 3: " / 季度"
            case 6: " / 半年"
            default: " / \(n) 个月"
            }
        case .year(let n): n == 1 ? " / 年" : " / \(n) 年"
        }
    }

    private static func periodCountString(_ p: PaywallPeriod) -> String {
        switch p {
        case .day(let n): "\(n) 天"
        case .week(let n): "\(n) 周"
        case .month(let n): n == 1 ? "1 个月" : "\(n) 个月"
        case .year(let n): "\(n) 年"
        }
    }
}
