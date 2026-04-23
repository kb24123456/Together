import Foundation
import Observation

/// App 根层的付费墙 sheet 合并器。spec § 2.8。
///
/// 存在理由：配额 trigger + Pro→Free lapse 两路都要弹付费墙 sheet，
/// 但 SwiftUI 同一 View 上挂多个 `.sheet(item:)` 行为未定义——所以由本合并器
/// 维护唯一 `presenting` + FIFO queue，`AppRootView` 唯一一个 `.sheet(item:)` 驱动。
///
/// 优先级：lapse 插 queue 头部优先弹；**永远不 preempt** 当前 presenting。
/// 去重：当前 presenting 或 queue 中已有相同 kind 时新请求被丢弃。
@MainActor
@Observable
final class RootPaywallPresentation {

    enum Kind: Identifiable, Equatable, Sendable {
        case quota(UpsellTrigger)
        case lapse(PremiumLapseNotice)

        var id: String {
            switch self {
            case .quota(let t): "quota:\(t.id)"
            case .lapse(let n): "lapse:\(n.dedupKey)"
            }
        }

        /// 映射到 UpsellContent 显示层契约。
        func toDisplayKind() -> UpsellDisplayKind {
            switch self {
            case .quota(let t): .trigger(t)
            case .lapse(let n): .lapse(n)
            }
        }
    }

    private(set) var presenting: Kind?
    private(set) var queue: [Kind] = []

    init() {}

    /// 追加到 queue 尾部（配额 trigger 优先级最低）。去重。
    func requestTrigger(_ trigger: UpsellTrigger) {
        enqueue(.quota(trigger), insertAtHead: false)
    }

    /// 插入到 queue **头部**（lapse 优先级高），但不 preempt 当前 presenting。去重。
    func requestLapse(_ notice: PremiumLapseNotice) {
        enqueue(.lapse(notice), insertAtHead: true)
    }

    /// sheet 关闭后由 View 层调用；pop 队首到 presenting，若 queue 空则清 presenting。
    func dismissCurrent() {
        guard presenting != nil else { return }
        if queue.isEmpty {
            presenting = nil
        } else {
            presenting = queue.removeFirst()
        }
    }

    // MARK: - Private

    private func enqueue(_ kind: Kind, insertAtHead: Bool) {
        if presenting == nil {
            presenting = kind
            return
        }
        if presenting == kind { return }
        if queue.contains(kind) { return }
        if insertAtHead {
            queue.insert(kind, at: 0)
        } else {
            queue.append(kind)
        }
    }
}
