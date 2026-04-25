import Foundation
import Observation
import OSLog

/// 监听 `PremiumGate.status` 由 non-premium → .pro 的转活边沿，记 OSLog。
///
/// 名称沿用 spec § 2.6 描述（"pending approval → active 翻转通知"），实际监听
/// PremiumGate.status 的 non-pro→pro 边沿，间接覆盖 Ask to Buy 批准 / restore /
/// 首次购买完成等所有"激活时刻"。pendingApproval 不在 PremiumStatus enum 内，
/// 无法直接区分来源；OSLog 留给 Session C 评估是否升级到 toast / 通知。
///
/// 后台翻转场景：app 在后台时 status 变更 → 重启后 lastSeenStatus 为 nil，新
/// status 是 .pro，本 observer 不触发（spec § 2.6 风险栏明确不解决）。
@MainActor
final class PendingApprovalObserver {
    private let premiumGate: PremiumGate
    private let logger: Logger
    private var lastSeenStatus: PremiumStatus?
    private var isStopped = false

    /// Test hook：每次 non-pro→pro 翻转触发；生产代码不读，仅测试断言。
    var onActivation: ((_ from: PremiumStatus, _ to: PremiumStatus) -> Void)?

    init(premiumGate: PremiumGate,
         logger: Logger = Logger(subsystem: "Together", category: "PendingApprovalObserver")) {
        self.premiumGate = premiumGate
        self.logger = logger
    }

    /// 启动 observation。AppContainer 在 init 末尾调用一次。Re-register 在 onChange 内自循环。
    func start() {
        isStopped = false
        lastSeenStatus = premiumGate.effectiveStatus
        observeNext()
    }

    /// 停止 observation。下一次 onChange 触发时 observeNext 自然退出。
    func stop() {
        isStopped = true
        lastSeenStatus = nil
    }

    /// 边沿检测纯逻辑。从 non-premium → .pro 触发 OSLog + onActivation hook；其他过渡忽略。
    /// `internal` 暴露便于单测（不通过 observation 触发，纯函数测试）。
    func recordStatus(_ new: PremiumStatus) {
        defer { lastSeenStatus = new }
        guard let last = lastSeenStatus else { return }
        let wasPremium = last.isPremium
        let isNowPro: Bool
        if case .pro = new { isNowPro = true } else { isNowPro = false }
        if !wasPremium && isNowPro {
            logger.info("status_transition.activated from=\(String(describing: last), privacy: .public) to=\(String(describing: new), privacy: .public)")
            onActivation?(last, new)
        }
    }

    // MARK: - Private

    /// withObservationTracking onChange 是 fire-once；每次触发后必须重新注册才能继续接收。
    /// 监听 effectiveStatus 让 DEBUG override 切换也能触发（用于 S5 真机 smoke）；
    /// release 下 override 永远 nil，effective == raw status 行为不变。
    private func observeNext() {
        guard !isStopped else { return }
        withObservationTracking {
            _ = premiumGate.effectiveStatus
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.recordStatus(self.premiumGate.effectiveStatus)
                self.observeNext()
            }
        }
    }
}
