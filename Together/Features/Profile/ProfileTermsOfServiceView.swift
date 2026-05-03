import SwiftUI

struct ProfileTermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                legalHeader

                termSection(
                    title: "一、服务说明",
                    content: """
                    Together 是一款双人协作任务管理应用，提供个人与共享任务、纪念日、清单、项目、提醒、留言和同步恢复等功能。

                    使用本应用需要遵守适用法律、Apple 平台规则和本服务条款。
                    """
                )

                termSection(
                    title: "二、订阅与自动续订",
                    content: """
                    Together Pro 通过 App Store 提供月度订阅、年度订阅和终身权益。自动续订订阅会在当前周期结束前 24 小时内由 Apple 扣款，您可以在 iOS 设置的订阅页面管理或取消。

                    退款由 Apple 处理，请前往 reportaproblem.apple.com 提交。
                    """
                )

                termSection(
                    title: "三、宽限期",
                    content: """
                    若订阅续期失败进入 Grace 期，您仍可访问 Logbook 全量历史，避免短暂支付异常导致历史记录立即不可见。

                    Grace 期不等于完整 Pro 权益；跨设备同步、超额创建、无限纪念日 / 项目等完整 Pro 功能会按 Free 版限制执行。重新订阅后可恢复完整 Pro 体验。
                    """
                )

                termSection(
                    title: "四、会员赠送与白名单",
                    content: """
                    我们可能基于早期用户感谢、TestFlight 测试、开发者亲友、问题补偿或支持场景授予临时或永久会员权益。

                    赠送权益不构成商品购买，不可转让、不可兑换现金，也不会作为 App 外部销售、公开兑换码或绕过 App Store 内购的付费渠道。
                    """
                )

                termSection(
                    title: "五、用户内容与责任",
                    content: """
                    您在本应用中创建、上传、共享的任务、纪念日、清单、备注、留言、头像等内容归您所有。您授权我们在提供服务所必需的范围内存储、传输和处理这些内容。

                    您不得上传违法、侵权、冒用身份或绕过付费限制的内容或行为。
                    """
                )

                termSection(
                    title: "六、服务变更与免责声明",
                    content: """
                    我们会尽力保障服务稳定，但不承诺服务永不中断。因 Apple、Supabase、RevenueCat、网络、不可抗力或政策变化导致的中断或延迟，我们将在合理范围内处理。
                    """
                )

                legalLinks

                Text("更新日期：2026 年 5 月 3 日")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .padding(.top, AppTheme.spacing.sm)
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("用户协议")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var legalHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Text("Together 服务条款")
                .font(AppTheme.typography.textStyle(.title3, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            Text("本页与正式法律文档保持同一口径；完整版本以线上文档为准。")
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)
        }
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Link("打开完整服务条款", destination: LegalURLs.terms)
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            Text("联系邮箱：billy357831193+together@gmail.com")
                .font(AppTheme.typography.textStyle(.footnote))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
        .padding(.top, AppTheme.spacing.sm)
    }

    private func termSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Text(title)
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            Text(content)
                .font(AppTheme.typography.textStyle(.subheadline, weight: .regular))
                .foregroundStyle(AppTheme.colors.body)
                .lineSpacing(5)
        }
    }
}
