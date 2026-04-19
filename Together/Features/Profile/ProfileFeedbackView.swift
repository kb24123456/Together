import SwiftUI

struct ProfileFeedbackView: View {
    @Environment(\.openURL) private var openURL

    private var deviceInfo: String {
        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "设备：\(device.model)  系统：\(device.systemName) \(device.systemVersion)  版本：\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing.xl) {
                Spacer()
                    .frame(height: 20)

                Image(systemName: "envelope.circle.fill")
                    .font(AppTheme.typography.sized(56))
                    .foregroundStyle(AppTheme.colors.accent)

                VStack(spacing: AppTheme.spacing.xs) {
                    Text("意见反馈")
                        .font(AppTheme.typography.sized(22, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("你的反馈对我们非常重要，将帮助我们持续改进 Together")
                        .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.spacing.lg)
                }

                // 发送邮件按钮
                Button {
                    HomeInteractionFeedback.selection()
                    sendFeedbackEmail()
                } label: {
                    HStack(spacing: AppTheme.spacing.sm) {
                        Image(systemName: "envelope")
                            .font(AppTheme.typography.sized(16, weight: .semibold))
                        Text("发送邮件反馈")
                            .font(AppTheme.typography.sized(16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                            .fill(AppTheme.colors.accent)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.spacing.xl)

                // 设备信息
                VStack(spacing: AppTheme.spacing.xs) {
                    Text("当前设备信息")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.textTertiary)

                    Text(deviceInfo)
                        .font(AppTheme.typography.sized(12, weight: .medium))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, AppTheme.spacing.sm)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendFeedbackEmail() {
        let subject = "Together 意见反馈"
        let body = "\n\n---\n\(deviceInfo)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:feedback@onetwotogether.xyz?subject=\(encodedSubject)&body=\(encodedBody)") {
            openURL(url)
        }
    }
}
