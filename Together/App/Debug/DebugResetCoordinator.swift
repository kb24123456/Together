#if DEBUG
import CloudKit
import Foundation
import os

/// Dev-only: 调度并执行本地 SwiftData store / CloudKit solo zone 的清盘操作。
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

    // MARK: - Known migration flags (显式枚举，不用前缀扫)

    private static let knownMigrationFlagKeys: [String] = [
        "didCleanupLegacyPeriodicData.v1",        // PersistenceController
        "migration_pair_periodic_purged_v1",      // PairPeriodicPurgeMigration
        "migration_pair_space_orphan_purged_v1"   // PairSpaceOrphanPurgeMigration
    ]

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

    /// 安排下次启动时清本地 store + CloudKit solo zone。写 flag 后调用方应 `exit(0)`。
    static func scheduleLocalPlusCloudWipe(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingLocalNukeKey)
        defaults.set(true, forKey: pendingCloudWipeKey)
        logger.info("Scheduled local+cloud wipe. exit(0) expected next.")
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
        clearMigrationFlags: () -> Void = { Self.clearKnownMigrationFlags() },
        wipeCloudZone: () -> Void = { Self.wipeSoloZoneBestEffort() }
    ) -> ApplyResult {
        let localPending = defaults.bool(forKey: pendingLocalNukeKey)
        let cloudPending = defaults.bool(forKey: pendingCloudWipeKey)

        guard localPending || cloudPending else {
            return .noop
        }

        logger.info("Applying pending nuke: local=\(localPending) cloud=\(cloudPending)")

        if cloudPending {
            wipeCloudZone()
        }

        if localPending {
            deleteStoreFiles()
            clearMigrationFlags()
        }

        // 清 flag 本身，保证幂等
        defaults.removeObject(forKey: pendingLocalNukeKey)
        defaults.removeObject(forKey: pendingCloudWipeKey)

        let result: ApplyResult = cloudPending ? .localAndCloud : .localOnly
        logger.info("Applied nuke result=\(String(describing: result))")
        return result
    }

    // MARK: - Private helpers (default closure impls)

    private static func clearKnownMigrationFlags() {
        for key in knownMigrationFlagKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Best-effort：失败只 log 不抛，不 block 本地清。
    private static func wipeSoloZoneBestEffort() {
        let container = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
        let zoneID = CKRecordZone.ID(zoneName: "solo")
        let semaphore = DispatchSemaphore(value: 0)
        var finalError: Error?

        container.privateCloudDatabase.delete(withRecordZoneID: zoneID) { _, error in
            finalError = error
            semaphore.signal()
        }

        // 最多等 5 秒。超时也继续往下走。
        _ = semaphore.wait(timeout: .now() + .seconds(5))

        if let finalError {
            logger.warning("Cloud solo zone wipe failed: \(String(describing: finalError))")
        } else {
            logger.info("Cloud solo zone wiped.")
        }
    }
}
#endif
