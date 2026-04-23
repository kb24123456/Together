import SwiftUI

/// 付费墙 sheet 的挂点 modifier。需要在 AppRootView **两处**挂：
///
/// 1. AppRoot 本身 — Profile 未打开时 sheet 在这里响应
/// 2. Profile 的 `.fullScreenCover` 内 — 否则 Profile 可见时 AppRoot 的 sheet 被遮住看不见
///
/// 两处监听同一个 `rootPaywallPresentation.presenting`；`dismissCurrent` / `paywallDidDismiss`
/// 都是幂等的，两处响应不会互相干扰：fullScreenCover 可见时它的 sheet 先响应（在 Profile 之上
/// 展示）；不可见时 AppRoot 的 sheet 响应。
struct PaywallRootSheetModifier: ViewModifier {
    let appContext: AppContext

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { appContext.rootPaywallPresentation.presenting },
                set: { new in
                    if new == nil {
                        appContext.rootPaywallPresentation.dismissCurrent()
                    }
                }
            )) { kind in
                UpsellSheet(
                    displayKind: kind.toDisplayKind(),
                    purchasing: appContext.paywallPurchasing,
                    gate: appContext.container.premiumGate,
                    onFinished: { _ in
                        appContext.rootPaywallPresentation.dismissCurrent()
                    }
                )
            }
            .onChange(of: appContext.rootPaywallPresentation.presenting) { oldKind, _ in
                guard appContext.rootPaywallPresentation.presenting == nil,
                      let dismissed = oldKind else { return }
                appContext.paywallDidDismiss(kind: dismissed)
            }
    }
}

extension View {
    /// 付费墙 sheet 挂点。详见 `PaywallRootSheetModifier`。
    func paywallRootSheet(_ appContext: AppContext) -> some View {
        modifier(PaywallRootSheetModifier(appContext: appContext))
    }
}
