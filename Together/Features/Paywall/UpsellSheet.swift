import SwiftUI

/// Sheet 包装：`UpsellContent` + 右上关闭 + 成功 overlay + in-flight 防下滑关。
struct UpsellSheet: View {
    let displayKind: UpsellDisplayKind
    @State private var viewModel: PaywallViewModel

    init(
        displayKind: UpsellDisplayKind,
        purchasing: PaywallPurchasingProtocol,
        gate: PremiumGate,
        onFinished: @escaping @MainActor (PaywallFinishReason) -> Void,
        successHoldDuration: Duration = UpsellCopy.paywallSuccessHoldDuration
    ) {
        self.displayKind = displayKind
        _viewModel = State(initialValue: PaywallViewModel(
            purchasing: purchasing,
            premiumGate: gate,
            onFinished: onFinished,
            successHoldDuration: successHoldDuration
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            UpsellContent(displayKind: displayKind, viewModel: viewModel)

            Button { viewModel.requestClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTheme.typography.sized(28))
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.8))
                    .padding(AppTheme.spacing.md)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isInFlight)
            .accessibilityLabel("关闭付费墙")
        }
        .interactiveDismissDisabled(viewModel.isInFlight)
        .task { await viewModel.load() }
        .overlay {
            if case .succeeded = viewModel.state {
                successOverlay
            }
        }
    }

    private var successOverlay: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.colors.background.opacity(0.94))
                .ignoresSafeArea()
            VStack(spacing: AppTheme.spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTheme.typography.sized(72, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.pairAccent)
                Text("已解锁 Together Pro")
                    .font(AppTheme.typography.sized(20, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                Text("感谢支持，继续使用吧")
                    .font(AppTheme.typography.sized(14))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }
        }
        .transition(.opacity)
        .accessibilityLabel("已解锁 Together Pro")
    }
}

#if DEBUG
#Preview("Quota sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UpsellSheet(
            displayKind: .trigger(.projectQuota),
            purchasing: StubPaywallPurchasing(),
            gate: PremiumGate.preview(),
            onFinished: { _ in }
        )
    }
}
#endif
