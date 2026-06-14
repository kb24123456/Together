#if DEBUG
import Foundation
import os

/// Dev-only: 调度并执行本地 SwiftData store 清盘操作。
///
/// 设计：
/// 1. UI 点按钮 → `schedule*` 写 UserDefaults flag → `exit(0)` 立即退出
/// 2. 下次冷启动，`TogetherApp.init` 最早期调 `applyPendingNukeIfNeeded`
/// 3. `applyPendingNukeIfNeeded` 在 SwiftData container 被打开 **之前** 删文件
///
/// 测试通过注入 `defaults` + 3 个闭包让纯逻辑可独立验证。
enum DebugResetCoordinator {

    // MARK: - Flag keys (test-visible)

    static let pendingLocalNukeKey = "DebugReset.pendingLocalNuke"
    static let pendingCloudWipeKey = "DebugReset.pendingCloudWipe"

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.together.debug",
        category: "reset"
    )

    // MARK: - Schedule (UI 调用)

    /// 安排下次启动时清本地 store。写 flag 后调用方应 `exit(0)`。
    static func scheduleLocalNuke(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingLocalNukeKey)
        defaults.set(false, forKey: pendingCloudWipeKey)
        logger.info("Scheduled local nuke. exit(0) expected next.")
    }

    /// 兼容旧 debug 入口；当前架构不再直接删除 CloudKit zone。
    static func scheduleLocalPlusCloudWipe(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingLocalNukeKey)
        defaults.set(false, forKey: pendingCloudWipeKey)
        logger.info("Scheduled local nuke via legacy local+cloud entry. exit(0) expected next.")
    }

    // MARK: - Apply (冷启动最早期调用)

    enum ApplyResult: Equatable {
        case noop
        case localOnly
        case localAndCloud
    }

    /// 冷启动时在 SwiftData container 打开前调用。
    /// 所有文件/网络操作通过闭包注入，方便单元测试。
    @discardableResult
    static func applyPendingNukeIfNeeded(
        defaults: UserDefaults = .standard,
        deleteStoreFiles: () -> Void = { PersistenceController.deleteStoreFiles() },
        clearMigrationFlags: () -> Void = {}
    ) -> ApplyResult {
        let localPending = defaults.bool(forKey: pendingLocalNukeKey)
        let cloudPending = defaults.bool(forKey: pendingCloudWipeKey)

        guard localPending || cloudPending else {
            return .noop
        }

        logger.info("Applying pending nuke: local=\(localPending) legacyCloudFlag=\(cloudPending)")

        if localPending {
            deleteStoreFiles()
            clearMigrationFlags()
        }

        // 清 flag 本身，保证幂等
        defaults.removeObject(forKey: pendingLocalNukeKey)
        defaults.removeObject(forKey: pendingCloudWipeKey)

        let result: ApplyResult = .localOnly
        logger.info("Applied nuke result=\(String(describing: result))")
        return result
    }
}
#endif
