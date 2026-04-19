import SwiftUI

struct ProfileTermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                Text("欢迎使用 Together。请您在使用本应用前仔细阅读以下条款。使用本应用即表示您同意本协议的所有条款。")
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .regular))
                    .foregroundStyle(AppTheme.colors.body)
                    .lineSpacing(5)

                termSection(
                    title: "一、服务说明",
                    content: """
                    Together 是一款双人协作任务管理应用，提供以下核心功能：

                    1. 个人任务创建、管理和提醒
                    2. 双人共享任务空间和协作管理
                    3. 例行事务（周期性任务）管理
                    4. 项目和清单管理

                    本应用通过 Apple iCloud 实现数据同步，使用本应用需要有效的 Apple ID。
                    """
                )

                termSection(
                    title: "二、用户权利与义务",
                    content: """
                    1. 您有权使用本应用提供的各项功能
                    2. 您应妥善保管您的 Apple ID 账号信息
                    3. 您不得利用本应用从事违反法律法规的活动
                    4. 您对通过本应用创建的内容承担相应责任
                    5. 您不得对本应用进行反编译、反汇编或其他逆向工程操作
                    """
                )

                termSection(
                    title: "三、知识产权",
                    content: "本应用的所有内容（包括但不限于界面设计、图标、代码、文字说明）均受著作权法保护。未经书面许可，不得复制、修改或分发本应用的任何部分。"
                )

                termSection(
                    title: "四、免责声明",
                    content: """
                    1. 本应用依赖 Apple iCloud 服务进行数据同步，因 iCloud 服务中断导致的数据同步延迟或失败，我们不承担责任
                    2. 因不可抗力（包括但不限于自然灾害、网络故障、政策变更）导致的服务中断，我们不承担责任
                    3. 我们会尽力保障服务稳定，但不对服务的不间断性作出保证
                    """
                )

                termSection(
                    title: "五、协议终止",
                    content: """
                    1. 您可以随时停止使用本应用并注销账号
                    2. 如果您违反本协议条款，我们有权终止向您提供服务
                    3. 协议终止后，我们将按照隐私政策处理您的个人信息
                    """
                )

                termSection(
                    title: "六、协议变更",
                    content: "我们保留修改本协议的权利。修改后的协议将在应用内发布，您继续使用本应用即表示同意修改后的协议。"
                )

                termSection(
                    title: "七、争议解决",
                    content: "本协议的解释和适用以中华人民共和国法律为准。因本协议产生的争议，双方应友好协商解决；协商不成的，应提交开发者所在地有管辖权的人民法院诉讼解决。"
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
        .navigationTitle("用户协议")
        .navigationBarTitleDisplayMode(.inline)
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
