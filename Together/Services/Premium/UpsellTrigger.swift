import Foundation

/// ViewModel → View 的"触发付费墙"信号。每个值对应产品 spec § 3 的一个触发场景。
///
/// 观察式消费模式：ViewModel 暴露 `pendingUpsellTrigger: UpsellTrigger?`，
/// View 通过 `.sheet(item:)` 展示对应 Phase 3 付费墙视图。
enum UpsellTrigger: Identifiable, Equatable, Sendable {
    case anniversaryQuota     // 新建第 6 个纪念日
    case projectQuota         // 新建第 4 个项目
    case logbookHistory       // Logbook 滚到 31 天前
    case crossDeviceSync      // 新设备首次打开且本机无数据

    var id: String {
        switch self {
        case .anniversaryQuota: return "anniversary_quota"
        case .projectQuota: return "project_quota"
        case .logbookHistory: return "logbook_history"
        case .crossDeviceSync: return "cross_device_sync"
        }
    }
}
