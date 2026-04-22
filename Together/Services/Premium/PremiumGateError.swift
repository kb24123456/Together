import Foundation

/// 会员门禁相关错误。MVP 仅覆盖配额超限场景；跨设备同步不启动走静默 early-return
/// 而非错误通道（对应 spec § 6.1）。
enum PremiumGateError: Error, Equatable, Sendable {
    case quotaExceeded(limit: Int, feature: GatedFeature)
}

/// 受配额限制的功能分类。
enum GatedFeature: String, Equatable, Sendable {
    case anniversary
    case project
    case logbookHistory
}
