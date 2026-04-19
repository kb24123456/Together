import SwiftUI

struct ProfilePrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                policySection(
                    title: "一、个人信息处理者",
                    content: "Together（以下简称「我们」）是本应用的开发者和个人信息处理者。如您对本隐私政策有任何疑问，请通过应用内「意见反馈」功能与我们联系。"
                )

                policySection(
                    title: "二、我们收集的信息",
                    content: """
                    我们在提供服务过程中，可能会收集以下个人信息：

                    1. Apple ID 标识符：用于账号创建和登录验证
                    2. 昵称和头像：用于个人资料展示和双人协作识别
                    3. 任务数据：包括您创建的任务标题、备注、截止时间等内容
                    4. 设备信息：用于应用适配和问题排查

                    我们不会收集您的位置信息、通讯录、短信或通话记录等敏感个人信息。
                    """
                )

                policySection(
                    title: "三、信息使用目的",
                    content: """
                    我们收集的个人信息仅用于以下目的：

                    1. 提供核心任务管理功能
                    2. 实现双人协作数据同步（通过 Apple iCloud）
                    3. 发送任务提醒通知（需您授权）
                    4. 改善应用体验和修复问题
                    """
                )

                policySection(
                    title: "四、信息存储与安全",
                    content: """
                    1. 您的数据存储在本设备及 Apple iCloud 云端（如启用同步功能）
                    2. 双人协作数据通过 Apple CloudKit 技术进行端到端同步
                    3. 我们不运营独立服务器，不会将您的数据存储在第三方服务器上
                    4. 我们采取合理的技术措施保护您的个人信息安全
                    """
                )

                policySection(
                    title: "五、信息共享与披露",
                    content: """
                    1. 双人模式下，您的昵称、头像和共享任务数据将对协作伙伴可见
                    2. 除上述情况外，我们不会向任何第三方出售、出租或共享您的个人信息
                    3. 法律法规要求或政府部门依法要求时，我们可能会依法披露相关信息
                    """
                )

                policySection(
                    title: "六、您的权利",
                    content: """
                    根据《中华人民共和国个人信息保护法》，您享有以下权利：

                    1. 查阅权：您可以在应用内查看您的个人资料和任务数据
                    2. 更正权：您可以随时修改您的昵称和头像
                    3. 删除权：您可以通过「账号注销」功能删除所有个人信息
                    4. 撤回同意权：您可以在系统设置中关闭通知权限

                    行使上述权利，请通过应用内「意见反馈」功能联系我们。
                    """
                )

                policySection(
                    title: "七、信息保存期限",
                    content: "我们在您使用本应用期间保存您的个人信息。当您注销账号后，我们将在 14 天内删除您的所有个人信息和相关数据。"
                )

                policySection(
                    title: "八、未成年人保护",
                    content: "本应用不面向 14 岁以下的未成年人。如果我们发现在未获得家长或监护人同意的情况下收集了未成年人的个人信息，我们将尽快删除相关数据。"
                )

                policySection(
                    title: "九、隐私政策更新",
                    content: "我们可能会不时更新本隐私政策。更新后的政策将在应用内发布，重大变更时我们会通过应用内通知告知您。"
                )

                Text("更新日期：2025 年 1 月 1 日")
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
