import SwiftUI

struct ProfilePrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                legalHeader

                policySection(
                    title: "一、我们收集的信息",
                    content: """
                    1. Apple Sign In 身份信息：用于账号识别和登录。
                    2. 昵称、头像、用户 ID：用于个人资料展示、双人协作识别和数据归属。
                    3. 应用内创建的内容：任务、纪念日、清单、项目、备注、留言等，用于核心功能、同步与恢复。
                    4. 订阅与会员状态：用于 Together Pro 权益判定。
                    5. 必要的设备与系统信息：用于兼容性适配、故障诊断和安全防护。
                    """
                )

                policySection(
                    title: "二、权限使用",
                    content: """
                    Together 仅在您主动拍摄头像时请求相机权限；仅在您主动选择头像图片时访问所选照片。

                    当前版本不提供语音输入功能，不请求麦克风或语音识别权限；也不使用定位、通讯录、短信或通话记录。
                    """
                )

                policySection(
                    title: "三、数据存储与处理方",
                    content: """
                    本应用会在设备本地保存核心数据，并使用 Supabase 处理身份认证、账号资料、配对关系、双人协作、跨设备恢复、会员状态和必要业务数据。

                    订阅购买由 Apple App Store 处理；订阅状态同步由 RevenueCat 协助完成。Apple、Supabase、RevenueCat 会分别按照其隐私政策处理必要数据。
                    """
                )

                policySection(
                    title: "四、数据共享",
                    content: """
                    双人模式下，您的昵称、头像和共享空间内容会对协作伙伴可见。除提供服务所必需的 Apple、Supabase、RevenueCat 处理外，我们不会出售、出租或用于广告追踪。
                    """
                )

                policySection(
                    title: "五、您的权利",
                    content: """
                    您可以在应用内查看、修改个人资料，解除配对，或通过账号注销删除账号与我们控制下的个人数据。注销后，我们将在 30 天内删除 Supabase、RevenueCat 等我们控制下的数据；Apple 平台数据按 Apple 政策处理。
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
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var legalHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            Text("Together 隐私政策")
                .font(AppTheme.typography.textStyle(.title3, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            Text("本页与正式法律文档保持同一口径；完整版本以线上文档为准。")
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)
        }
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Link("打开完整隐私政策", destination: LegalURLs.privacy)
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            Text("联系邮箱：billy357831193+together@gmail.com")
                .font(AppTheme.typography.textStyle(.footnote))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
        .padding(.top, AppTheme.spacing.sm)
    }

    private func policySection(title: String, content: String) -> some View {
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
