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
        wipeCloudZone: () -> Void = { Self.wipeAllCloudKitZonesBestEffort() }
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

    /// 清理 CloudKit private DB 下所有自定义 zone（solo + 所有 pair-*）。
    /// 默认 zone 过滤掉（系统 zone 不能删）。每次尝试 30s 超时，失败重试至多 3 次。
    /// 全部失败只 log 不抛，不 block 本地清。
    private static func wipeAllCloudKitZonesBestEffort() {
        let container = CKContainer(identifier: CloudKitSyncConfiguration.defaultContainerIdentifier)
        let maxAttempts = 3
        let perAttemptTimeoutSeconds = 30

        for attempt in 1...maxAttempts {
            // Step 1: fetch all custom zones
            let fetchResult = fetchAllCustomZoneIDsSync(
                container: container,
                timeoutSeconds: perAttemptTimeoutSeconds
            )

            let zoneIDs: [CKRecordZone.ID]
            switch fetchResult {
            case .success(let ids):
                zoneIDs = ids
            case .failure(let err):
                let code = (err as? CKError).map { "CKError.\($0.code.rawValue)" } ?? "non-CKError"
                logger.error("""
                    Cloud zones fetch attempt \(attempt)/\(maxAttempts) failed: \
                    code=\(code, privacy: .public) \
                    err=\(String(describing: err), privacy: .public)
                    """)
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: 3)
                    continue
                }
                logger.error("Cloud zones fetch exhausted \(maxAttempts) attempts; giving up. Local wipe still proceeding.")
                return
            }

            if zoneIDs.isEmpty {
                logger.info("No CloudKit custom zones to wipe (attempt \(attempt)).")
                return
            }

            // Step 2: delete all fetched zones in one batch operation
            let names = zoneIDs.map(\.zoneName).joined(separator: ", ")
            logger.info("Wiping \(zoneIDs.count) CloudKit zones on attempt \(attempt): \(names, privacy: .public)")

            let deleteErr = deleteZonesSync(
                container: container,
                zoneIDs: zoneIDs,
                timeoutSeconds: perAttemptTimeoutSeconds
            )

            guard let deleteErr else {
                logger.info("Wiped \(zoneIDs.count) CloudKit zones on attempt \(attempt).")
                return
            }

            let code = (deleteErr as? CKError).map { "CKError.\($0.code.rawValue)" } ?? "non-CKError"
            logger.error("""
                Cloud zones delete attempt \(attempt)/\(maxAttempts) failed: \
                code=\(code, privacy: .public) \
                err=\(String(describing: deleteErr), privacy: .public)
                """)

            if attempt < maxAttempts {
                Thread.sleep(forTimeInterval: 3)
            }
        }

        logger.error("""
            Cloud zones wipe exhausted \(maxAttempts) attempts; giving up. \
            Local wipe still proceeding; zones may repopulate local on next sync.
            """)
    }

    /// 同步 fetch private DB 所有自定义 zone（过滤掉系统默认 zone `_defaultZone`）。
    private static func fetchAllCustomZoneIDsSync(
        container: CKContainer,
        timeoutSeconds: Int
    ) -> Result<[CKRecordZone.ID], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var finalResult: Result<[CKRecordZone.ID], Error> = .success([])
        let defaultZoneName = CKRecordZone.default().zoneID.zoneName

        container.privateCloudDatabase.fetchAllRecordZones { zones, error in
            if let error {
                finalResult = .failure(error)
            } else {
                let customIDs = (zones ?? [])
                    .map(\.zoneID)
                    .filter { $0.zoneName != defaultZoneName }
                finalResult = .success(customIDs)
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
        if waitResult == .timedOut {
            return .failure(NSError(
                domain: "DebugResetCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Zones fetch timed out after \(timeoutSeconds)s"]
            ))
        }
        return finalResult
    }

    /// 同步等待 batch zone 删除完成。
    private static func deleteZonesSync(
        container: CKContainer,
        zoneIDs: [CKRecordZone.ID],
        timeoutSeconds: Int
    ) -> Error? {
        guard !zoneIDs.isEmpty else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var finalError: Error?

        let op = CKModifyRecordZonesOperation(
            recordZonesToSave: nil,
            recordZoneIDsToDelete: zoneIDs
        )
        op.modifyRecordZonesResultBlock = { result in
            switch result {
            case .success:
                finalError = nil
            case .failure(let err):
                finalError = err
            }
            semaphore.signal()
        }
        container.privateCloudDatabase.add(op)

        let waitResult = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
        if waitResult == .timedOut {
            return NSError(
                domain: "DebugResetCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Zones delete timed out after \(timeoutSeconds)s"]
            )
        }
        return finalError
    }
}
#endif
