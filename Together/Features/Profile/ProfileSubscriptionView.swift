import SwiftUI

/// Profile → Together Pro 入口的落地页。
///
/// - Free / unknown：内嵌 `UpsellContent`（局部 VM，`.generic` hero，成功后 pop nav）
/// - Pro / gracePeriod：渲染 `ProfileSubscriptionDetailSection`（订阅管理 / 续费日期 / grace 续订）
///
/// pendingApproval 视觉由 `ProfileProEntryRow` 的 subtitle 承担（Session A 已就位），
/// 详情页本 view 不另作分支。
struct ProfileSubscriptionView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss
    @State private var localViewModel: PaywallViewModel?

    var body: some View {
        Group {
            // 用 isPremium 而非 status：让 DEBUG override 生效，并把 grace period 视作 Pro。
            if appContext.container.premiumGate.isPremium {
                ProfileSubscriptionDetailSection(
                    status: appContext.container.premiumGate.effectiveStatus,
                    onRequestRenewal: { daysRemaining in
                        appContext.rootPaywallPresentation.requestTrigger(
                            .graceExpiring(daysRemaining: daysRemaining)
                        )
                    }
                )
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
}
