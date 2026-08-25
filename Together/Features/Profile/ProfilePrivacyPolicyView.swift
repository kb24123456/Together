import SwiftUI

struct ProfilePrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                legalHeader

                policySection(
                    title: "一、我们收集的信息",
                    content: """
                    1. 本机生成的用户 ID：用于个人资料展示和数据归属。
                    2. 昵称与头像：用于个人资料展示。
                    3. 应用内创建的内容：任务、清单、项目、备注等，用于核心功能、同步与恢复。

                    当前版本不集成第三方广告、行为分析或崩溃分析 SDK；必要技术日志仅用于服务运行与安全，不用于广告追踪。
                    """
                )

                policySection(
                    title: "二、权限使用",
                    content: """
                    Together 仅在您主动拍摄头像或导入纸质笔记时请求相机权限；仅在您主动选择头像图片或待识别图片时访问所选照片。

                    当前版本不提供语音输入功能，不请求麦克风或语音识别权限；也不使用定位、通讯录、短信或通话记录。
                    """
                )

                policySection(
                    title: "三、数据存储与处理方",
                    content: """
                    本应用会在设备本地保存核心数据，并使用 Apple iCloud/CloudKit 在您的私人 iCloud 数据库中进行跨设备同步与恢复。

                    当前版本不提供付费购买、权益状态同步或第三方协作后端。
                    """
                )

                policySection(
                    title: "四、数据共享",
                    content: """
                    您的数据默认仅属于您个人使用。除 Apple iCloud/CloudKit 为同步与恢复所必需的处理外，我们不会出售、出租或用于广告追踪。
                    """
                )

                policySection(
                    title: "五、您的权利",
                    content: """
                    您可以在应用内查看、修改个人资料或删除全部数据。iCloud/CloudKit 数据由您的 Apple ID 与 iCloud 设置管理，Apple 平台数据按 Apple 政策处理。
                    """
                )

                legalLinks

                Text("更新日期：2026 年 7 月 11 日")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .padding(.top, AppTheme.spacing.sm)
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .applySoftScrollEdgeTransition()
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
