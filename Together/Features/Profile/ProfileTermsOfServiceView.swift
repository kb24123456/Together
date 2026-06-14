import SwiftUI

struct ProfileTermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                legalHeader

                termSection(
                    title: "一、服务说明",
                    content: """
                    Together 是一款以个人待办、清单、项目和日历管理为核心的效率应用。

                    使用本应用需要遵守适用法律、Apple 平台规则和本服务条款。
                    """
                )

                termSection(
                    title: "二、费用",
                    content: """
                    当前版本不提供付费解锁或应用外购买能力。
                    """
                )

                termSection(
                    title: "三、用户内容与责任",
                    content: """
                    您在本应用中创建或导入的任务、清单、项目、备注、头像和 OCR 识别内容归您所有。您授权我们在提供应用功能所必需的范围内在本地设备与 Apple iCloud/CloudKit 中存储和处理这些内容。

                    您不得上传违法、侵权或冒用身份的内容或行为。
                    """
                )

                termSection(
                    title: "四、服务变更与免责声明",
                    content: """
                    我们会尽力保障服务稳定，但不承诺服务永不中断。因 Apple、iCloud、网络、不可抗力或政策变化导致的中断或延迟，我们将在合理范围内处理。
                    """
                )

                legalLinks

                Text("更新日期：2026 年 5 月 4 日")
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
