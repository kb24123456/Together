#if DEBUG
import Foundation

/// `#Preview` 专用 stub。main target `#if DEBUG`，避免跨 test target 引用。
/// 用 `final class + @unchecked Sendable` 够用——Preview 不做并发。
final class PreviewRCClient: RCClientProtocol, @unchecked Sendable {
    nonisolated var isConfigured: Bool { true }
    nonisolated func configure(publicSDKKey: String, appUserID: String) {}
    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot {
        RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)
    }
    func logIn(appUserID: String) async throws {}
    func logOut() async throws {}
}

final class PreviewGrantsLoader: GrantsLoaderProtocol, @unchecked Sendable {
    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] { [] }
}

extension PremiumGate {
    /// Preview 专用工厂。不启动真 RC；`status` 参数可选强制某状态用于 UI 预览。
    @MainActor
    static func preview(status: PremiumStatus? = nil) -> PremiumGate {
        let cache = PremiumStatusCache(
            defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!,
            dateProvider: FixedDateProvider(fixed: Date())
        )
        let gate = PremiumGate(
            rcClient: PreviewRCClient(),
            grantsLoader: PreviewGrantsLoader(),
            cache: cache,
            dateProvider: FixedDateProvider(fixed: Date())
        )
        if let status { gate.overrideStatus = status }
        return gate
    }
}
#endif
