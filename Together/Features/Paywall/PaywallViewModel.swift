import Foundation
import Observation
import OSLog

/// 付费墙状态机。spec § 2.3。每次 sheet 显示创建新实例（§ 2.15）。
@MainActor
@Observable
final class PaywallViewModel {

    // MARK: - ViewState

    enum ViewState: Equatable {
        case idle
        case loadingOfferings
        case ready(PaywallOffering)
        case purchasing(packageID: String)
        case restoring
        case pendingApproval
        case succeeded
        case failed(PaywallError)
    }

    // MARK: - Observable state

    private(set) var state: ViewState = .idle
    private(set) var selectedPackageID: String?

    /// 便于 UpsellContent 在 `.failed` / 错误 inline 时仍渲染 packages + CTA 禁用；
    /// 也用于 `.purchasing` / `.restoring` / `.failed` 返回 ready 时恢复 offering。
    private(set) var cachedOffering: PaywallOffering?

    /// 选中的 package；供 legal footer 变量插值 + CTA 文案。
    var selectedPackage: PaywallPackage? {
        guard let id = selectedPackageID, let offering = cachedOffering else { return nil }
        return offering.package(id: id)
    }

    /// 阻止下滑关 sheet / 禁用 close button。§ 2.9。
    var isInFlight: Bool {
        switch state {
        case .purchasing, .restoring, .succeeded: true
        default: false
        }
    }

    // MARK: - Dependencies

    private let purchasing: PaywallPurchasingProtocol
    private let premiumGate: PremiumGate
    private let onFinished: @MainActor (PaywallFinishReason) -> Void
    private let successHoldDuration: Duration
    private let logger: Logger

    /// 一次性闸门。close / success / pending 任一先到都会关闭后续 finish 回调。§ 2.3 R59。
    private var hasFinished = false

    init(
        purchasing: PaywallPurchasingProtocol,
        premiumGate: PremiumGate,
        onFinished: @escaping @MainActor (PaywallFinishReason) -> Void,
        successHoldDuration: Duration = UpsellCopy.paywallSuccessHoldDuration,
        logger: Logger = premiumLogger
    ) {
        self.purchasing = purchasing
        self.premiumGate = premiumGate
        self.onFinished = onFinished
        self.successHoldDuration = successHoldDuration
        self.logger = logger
    }

    // MARK: - Public API

    func load() async {
        state = .loadingOfferings
        do {
            let offering = try await purchasing.loadOfferings()
            cachedOffering = offering
            if selectedPackageID == nil {
                selectedPackageID = autoSelectPackageID(in: offering)
            }
            logger.info(
                "paywall.offerings.loaded offeringID=\(offering.offeringID, privacy: .public) count=\(offering.packages.count)"
            )
            state = .ready(offering)
        } catch {
            let mapped = mapError(error)
            logger.error("paywall.offerings.failed error=\(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    func selectPackage(_ id: String) {
        selectedPackageID = id
    }

    func purchaseSelected() async {
        guard case .ready(let offering) = state, let id = selectedPackageID else { return }
        state = .purchasing(packageID: id)
        logger.info("paywall.purchase.start packageID=\(id, privacy: .public)")

        do {
            let outcome = try await purchasing.purchase(packageID: id)
            await handlePurchaseOutcome(outcome, packageID: id, fallbackOffering: offering)
        } catch {
            let mapped = mapError(error)
            logger.error("paywall.purchase.failed packageID=\(id, privacy: .public) error=\(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    func restore() async {
        guard !isInFlight else { return }
        state = .restoring
        logger.info("paywall.restore.start")

        do {
            let outcome = try await purchasing.restorePurchases()
            await handleRestoreOutcome(outcome)
        } catch {
            let mapped = mapError(error)
            logger.error("paywall.restore.failed error=\(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    /// inline "重试" / "关闭" 按钮调用。错误清空后回到 ready（如 cachedOffering 可用）或 idle。
    func dismissError() {
        guard case .failed = state else { return }
        if let offering = cachedOffering {
            state = .ready(offering)
        } else {
            state = .idle
        }
    }

    /// close button 调用。gate 拦住成功 hold 期间的误触发（§ 2.3 R59）。
    func requestClose() {
        finishOnce(.userClosed)
    }

    // MARK: - Private

    private func handlePurchaseOutcome(
        _ outcome: PaywallPurchaseOutcome,
        packageID: String,
        fallbackOffering: PaywallOffering
    ) async {
        switch outcome {
        case .success:
            logger.info("paywall.purchase.succeeded packageID=\(packageID, privacy: .public)")
            await premiumGate.refresh()
            logger.info("paywall.refresh.postPurchase isPremium=\(self.premiumGate.isPremium, privacy: .public)")
            #if DEBUG
            if premiumGate.overrideStatus != nil {
                state = .failed(.debugOverrideMasksPro)
                return
            }
            #endif
            if premiumGate.isPremium {
                state = .succeeded
                await holdThenFinish()
            } else {
                state = .failed(.entitlementNotReady)
            }

        case .cancelled:
            logger.info("paywall.purchase.cancelled packageID=\(packageID, privacy: .public)")
            state = .ready(fallbackOffering)

        case .pending:
            logger.info("paywall.purchase.pending packageID=\(packageID, privacy: .public)")
            state = .pendingApproval
            finishOnce(.pendingApproval)

        case .nothingToRestore:
            // 购买路径不应出现；防御性处理
            logger.error("paywall.purchase unexpected nothingToRestore packageID=\(packageID, privacy: .public)")
            state = .failed(.unknown)
        }
    }

    private func handleRestoreOutcome(_ outcome: PaywallPurchaseOutcome) async {
        switch outcome {
        case .success:
            // Restore 的 .success 语义：RC 已确认 entitlement 激活（生产实现在
            // RevenueCatPaywallPurchasing.restorePurchases 里校验 isActive）。
            // 不再做 PremiumGate.isPremium 校验——若 PremiumGate 延迟传播，
            // 用户关 sheet 后 Profile 会在下次 refresh 反映，UX 与 purchase 不同。
            await premiumGate.refresh()
            logger.info("paywall.refresh.postRestore isPremium=\(self.premiumGate.isPremium, privacy: .public)")
            #if DEBUG
            if premiumGate.overrideStatus != nil {
                state = .failed(.debugOverrideMasksPro)
                return
            }
            #endif
            logger.info("paywall.restore.succeeded")
            state = .succeeded
            await holdThenFinish()

        case .nothingToRestore:
            logger.info("paywall.restore.nothingToRestore")
            state = .failed(.nothingToRestore)

        case .cancelled, .pending:
            // restore 路径不应出现；防御性处理
            logger.error("paywall.restore unexpected outcome=\(String(describing: outcome), privacy: .public)")
            state = .failed(.unknown)
        }
    }

    private func finishOnce(_ reason: PaywallFinishReason) {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished(reason)
    }

    private func holdThenFinish() async {
        try? await Task.sleep(for: successHoldDuration)
        finishOnce(.purchasedOrRestored)
    }

    private func autoSelectPackageID(in offering: PaywallOffering) -> String? {
        // 优先选带免费试用的（通常年包），次选第一个
        if let pkg = offering.packages.first(where: { $0.introductoryOffer?.isFreeTrial == true }) {
            return pkg.id
        }
        return offering.packages.first?.id
    }

    private func mapError(_ error: Error) -> PaywallError {
        if let pe = error as? PaywallError { return pe }
        return PaywallError(from: error)
    }
}

// MARK: - PaywallFinishReason

enum PaywallFinishReason: Equatable, Sendable {
    case purchasedOrRestored
    case pendingApproval
    case userClosed
}
