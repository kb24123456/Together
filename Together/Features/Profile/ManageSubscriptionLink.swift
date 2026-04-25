import SwiftUI
import StoreKit

/// 唤起 Apple "管理订阅" 系统 sheet（StoreKit 2 原生 modifier，iOS 15+）。
/// 不离开 app；用户在系统 sheet 内取消 / 升降级订阅由 Apple 处理。
/// Sandbox 测试时 sheet 行为不稳定属 Apple 已知问题，TestFlight / 正式环境验证。
struct ManageSubscriptionLink: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("在 App Store 管理订阅", systemImage: "creditcard")
        }
        .manageSubscriptionsSheet(isPresented: $isPresented)
        .accessibilityLabel("在 App Store 管理订阅")
        .accessibilityHint("双击打开 Apple 订阅管理")
    }
}

#if DEBUG
#Preview {
    ManageSubscriptionLink()
        .padding()
}
#endif
