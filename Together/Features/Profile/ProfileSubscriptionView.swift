import SwiftUI

/// Profile → Together Pro 入口的落地页。
///
/// - Free / unknown：内嵌 `UpsellContent`（局部 VM，`.generic` hero，成功后 pop nav）
/// - Pro / gracePeriod：Session A 仅占位文案，Session B 填订阅管理、续费日期、"在 App Store 管理订阅"
struct ProfileSubscriptionView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss
    @State private var localViewModel: PaywallViewModel?

    var body: some View {
        Group {
            // 用 isPremium 而非 status：让 DEBUG override 生效，并把 grace period 视作 Pro
            // （grace period UI 由 Session B 单独做横幅）。Spec § 4.4。
            if appContext.container.premiumGate.isPremium {
                proPlaceholder
            } else {
                freeState
            }
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("会员")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Free state: embed UpsellContent

    @ViewBuilder
    private var freeState: some View {
        if let vm = localViewModel {
            UpsellContent(displayKind: .generic, viewModel: vm)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    let vm = PaywallViewModel(
                        purchasing: appContext.paywallPurchasing,
                        premiumGate: appContext.container.premiumGate,
                        onFinished: { [dismiss] reason in
                            if reason == .purchasedOrRestored {
                                dismiss()
                            }
                            // userClosed / pendingApproval：停留在 Profile nav 内
                        }
                    )
                    localViewModel = vm
                    await vm.load()
                }
        }
    }

    // MARK: - Pro / grace placeholder (Session B 重写)

    private var proPlaceholder: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Image(systemName: "crown.fill")
                .font(AppTheme.typography.sized(48, weight: .semibold))
                .foregroundStyle(AppTheme.colors.pairAccent)
            Text("Together Pro 已激活")
                .font(AppTheme.typography.sized(20, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
            Text("感谢支持。订阅管理 / 续费详情将在后续版本上线。")
                .font(AppTheme.typography.sized(13))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
