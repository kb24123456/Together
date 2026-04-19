# Dev-only 本地清盘 + `Item.status` 诊断埋点 实施 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Together app 加两个正交的 dev 期工具：(A) `#if DEBUG` 一键清盘按钮，解锁日常测试节奏；(C) `Item.status` 变更路径的 `os.Logger` 埋点，支撑 "已完成 → 逾期" root cause 定位。

**Architecture:** A 通过 `UserDefaults` flag + `exit(0)` + `TogetherApp.init` 最早期 pre-init 删文件，绕开 SwiftData container 热启动的 UB 风险；C 新增一个 namespace `ItemStatusDiagnosisLog` 统一打 log，接入 3 个修改 `Item.status` 的路径（`markCompleted` / 两条 sync apply 路径），不改行为，release build 被 unified logging 自动过滤。

**Tech Stack:** Swift 6 · SwiftUI · SwiftData · Swift Testing (`import Testing`) · `os.Logger` · CloudKit（仅清 zone 用）

**Spec**: `docs/superpowers/specs/2026-04-20-devtools-and-overdue-diagnosis-design.md`

**硬性约束（project_together_progress.md）**:
- Swift Testing 唯一（`import Testing` / `@Test` / `#expect`），不用 XCTest
- In-memory `ModelContainer` 必须列全 17 个 Persistent 模型
- Commit message 英文 conventional commit + trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- 每 task 一个 commit，build + 全量 regression 绿才算完成
- 禁 `print`（用 `os.Logger`）；禁 `// TODO` / `// FIXME`
- 不改 `.pbxproj`（Xcode 16 synchronized file groups 自动纳入）
- A 部分所有新代码 `#if DEBUG` 包裹

**测试命令模板**:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/<SuiteName>
```
全量 regression（每 task 完成后）：
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## File Structure

### Part A（Dev-only 清盘按钮）

| 文件 | 动作 | 责任 |
|------|------|------|
| `Together/App/Debug/DebugResetCoordinator.swift` | **Create** | Flag read/write + pre-init nuke + 可选 CloudKit zone 删除；全文 `#if DEBUG` |
| `Together/Features/Profile/ProfileDebugSection.swift` | **Create** | UI：两个按钮 + 两层 confirmation；全文 `#if DEBUG` |
| `TogetherTests/DebugResetCoordinatorTests.swift` | **Create** | Flag 读写 + apply 幂等性测试（纯逻辑，不碰文件系统） |
| `Together/Persistence/PersistenceController.swift` | **Modify** | 把 `deleteStoreFiles` 从 `private static` 改成 `static`，让 coordinator 复用；新增 `storeArtifactURLs()` 同步 |
| `Together/TogetherApp.swift` | **Modify** | `init()` 最顶部加 `#if DEBUG / applyPendingNukeIfNeeded / #endif` |
| `Together/Features/Profile/ProfileView.swift` | **Modify** | `body` 主 VStack 末尾（`signOutFooter` 之后）挂 `#if DEBUG ProfileDebugSection() #endif` |

### Part C（诊断埋点）

| 文件 | 动作 | 责任 |
|------|------|------|
| `Together/Debug/ItemStatusDiagnosisLog.swift` | **Create** | `enum ItemStatusDiagnosisLog`，统一 `os.Logger` 实例 + 格式化方法 |
| `Together/Services/Items/LocalItemRepository.swift` | **Modify** | `markCompleted`：落盘前 / 落盘后 / readback 3 处 log |
| `Together/Sync/Engine/SyncEngineDelegate.swift` | **Modify** | `applyItem` 方法：apply 前 / apply 后 2 处 log |
| `Together/Sync/SupabaseSyncService.swift` | **Modify** | `TaskDTO.applyToLocal`：apply 前 / apply 后 2 处 log |

---

## Task 执行顺序

1. A1 → A2 → A3 → A4 → A5（Part A 先完）
2. 用户用 A1-A5 清一次脏数据 + 重建少量测试任务
3. C1 → C2 → C3 → C4（Part C）
4. 用户复现 + 贴 log

---

## Part A — Dev-only 清盘按钮

### Task A1: 暴露 `PersistenceController.deleteStoreFiles` 供 coordinator 复用

**Files:**
- Modify: `Together/Persistence/PersistenceController.swift`

- [ ] **Step 1: 打开文件找目标方法**

查 `PersistenceController.swift:102` 附近的 `private static func deleteStoreFiles()` 和 `private static func storeArtifactURLs() -> [URL]`（搜索 "storeArtifactURLs"）。

- [ ] **Step 2: 改 access level**

把：
```swift
private static func deleteStoreFiles() {
```
改成：
```swift
static func deleteStoreFiles() {
```

把：
```swift
private static func storeArtifactURLs() -> [URL] {
```
改成：
```swift
static func storeArtifactURLs() -> [URL] {
```

把：
```swift
private static var persistentStoreURL: URL {
```
改成：
```swift
static var persistentStoreURL: URL {
```

`persistentStoreSupportURL` 也改成 `static`（去掉 `private`）。

- [ ] **Step 3: 编译确认没有破坏调用方**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`（这几个方法之前只内部调用，改 public 不影响任何外部调用者）

- [ ] **Step 4: 跑全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```
git add Together/Persistence/PersistenceController.swift
git commit -m "$(cat <<'EOF'
chore(persistence): expose deleteStoreFiles / storeArtifactURLs to internal

Prep for DebugResetCoordinator reuse. No behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A2: 新建 `DebugResetCoordinator` + 单元测试

**Files:**
- Create: `Together/App/Debug/DebugResetCoordinator.swift`
- Create: `TogetherTests/DebugResetCoordinatorTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `TogetherTests/DebugResetCoordinatorTests.swift`：

```swift
#if DEBUG
import Foundation
import Testing
@testable import Together

@Suite("DebugResetCoordinator")
struct DebugResetCoordinatorTests {
    private let suiteName = "DebugResetCoordinatorTests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("scheduleLocalNuke sets pending flag")
    func scheduleLocalNukeSetsFlag() {
        defer { cleanup() }
        DebugResetCoordinator.scheduleLocalNuke(defaults: defaults)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == true)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }

    @Test("scheduleLocalPlusCloudWipe sets both flags")
    func scheduleBothSetsBothFlags() {
        defer { cleanup() }
        DebugResetCoordinator.scheduleLocalPlusCloudWipe(defaults: defaults)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == true)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == true)
    }

    @Test("applyPendingNukeIfNeeded no-op when no flag set")
    func applyNoFlags() {
        defer { cleanup() }
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { Issue.record("should not delete"); },
            clearMigrationFlags: { Issue.record("should not clear"); },
            wipeCloudZone: { Issue.record("should not wipe") }
        )
        #expect(result == .noop)
    }

    @Test("applyPendingNukeIfNeeded clears flags after local-only nuke")
    func applyLocalOnly() async {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        var deleteCalled = 0
        var clearFlagsCalled = 0
        var wipeCalled = 0
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { deleteCalled += 1 },
            clearMigrationFlags: { clearFlagsCalled += 1 },
            wipeCloudZone: { wipeCalled += 1 }
        )
        #expect(result == .localOnly)
        #expect(deleteCalled == 1)
        #expect(clearFlagsCalled == 1)
        #expect(wipeCalled == 0)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == false)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }

    @Test("applyPendingNukeIfNeeded runs both wipes when both flags set")
    func applyBoth() async {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        defaults.set(true, forKey: DebugResetCoordinator.pendingCloudWipeKey)
        var deleteCalled = 0
        var wipeCalled = 0
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: { deleteCalled += 1 },
            clearMigrationFlags: {},
            wipeCloudZone: { wipeCalled += 1 }
        )
        #expect(result == .localAndCloud)
        #expect(deleteCalled == 1)
        #expect(wipeCalled == 1)
    }

    @Test("applyPendingNukeIfNeeded clears flags even when cloud wipe closure throws")
    func applyClearsFlagsOnCloudFailure() async {
        defer { cleanup() }
        defaults.set(true, forKey: DebugResetCoordinator.pendingLocalNukeKey)
        defaults.set(true, forKey: DebugResetCoordinator.pendingCloudWipeKey)
        let result = DebugResetCoordinator.applyPendingNukeIfNeeded(
            defaults: defaults,
            deleteStoreFiles: {},
            clearMigrationFlags: {},
            wipeCloudZone: {
                // Simulate thrown error swallowed inside closure — coordinator treats closure as best-effort.
            }
        )
        #expect(result == .localAndCloud)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingLocalNukeKey) == false)
        #expect(defaults.bool(forKey: DebugResetCoordinator.pendingCloudWipeKey) == false)
    }
}
#endif
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/DebugResetCoordinatorTests 2>&1 | tail -20
```
Expected: `FAILED`（`Cannot find 'DebugResetCoordinator' in scope`）

- [ ] **Step 3: 写实现**

创建 `Together/App/Debug/DebugResetCoordinator.swift`：

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/DebugResetCoordinatorTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 跑全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```
git add Together/App/Debug/DebugResetCoordinator.swift TogetherTests/DebugResetCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
feat(devtools): add DebugResetCoordinator for scheduled local/cloud wipe

- schedule*() writes UserDefaults flags; caller should exit(0) after
- applyPendingNukeIfNeeded() runs at cold-boot before SwiftData opens
- Inject closures for deleteStoreFiles / clearMigrationFlags / wipeCloudZone to keep tests fast and hermetic
- 6 Swift Testing cases cover flag read/write + apply branches
- Entire file #if DEBUG; zero footprint in release builds

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A3: `TogetherApp.init` 接入 pre-init nuke

**Files:**
- Modify: `Together/TogetherApp.swift`

- [ ] **Step 1: 改 init**

打开 `Together/TogetherApp.swift`，找到：
```swift
init() {
    StartupTrace.mark("TogetherApp.init")
}
```

改成：
```swift
init() {
    #if DEBUG
    DebugResetCoordinator.applyPendingNukeIfNeeded()
    #endif
    StartupTrace.mark("TogetherApp.init")
}
```

**关键**：`applyPendingNukeIfNeeded` 必须在 `StartupTrace.mark` 之前、更重要的是在**任何** `PersistenceController.shared` 访问之前。TogetherApp `init` 本身没访问 PersistenceController（访问发生在 `appBootstrapper.bootstrapIfNeeded()` 里，那是 `.task` 里异步触发的），所以这里是最早的安全点。

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add Together/TogetherApp.swift
git commit -m "$(cat <<'EOF'
feat(devtools): wire DebugResetCoordinator pre-init check into TogetherApp

Runs in init() before any PersistenceController.shared access, #if DEBUG guarded.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A4: 新建 `ProfileDebugSection` UI

**Files:**
- Create: `Together/Features/Profile/ProfileDebugSection.swift`

- [ ] **Step 1: 写 view**

创建 `Together/Features/Profile/ProfileDebugSection.swift`：

```swift
#if DEBUG
import SwiftUI

/// Dev-only "开发者" section 显示在 Profile 页底部。
/// 提供两档清盘：仅本地 / 本地 + 云端 solo zone。
struct ProfileDebugSection: View {
    @State private var confirmLocalNuke = false
    @State private var confirmCloudWipeStep1 = false
    @State private var confirmCloudWipeStep2 = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("开发者 (DEBUG)")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.muted)
                .padding(.horizontal, AppTheme.spacing.sm)

            VStack(spacing: AppTheme.spacing.sm) {
                Button(role: .destructive) {
                    confirmLocalNuke = true
                } label: {
                    Text("清空本地数据")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(role: .destructive) {
                    confirmCloudWipeStep1 = true
                } label: {
                    Text("清空本地 + 云端（危险）")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .confirmationDialog(
            "清空本地数据？",
            isPresented: $confirmLocalNuke,
            titleVisibility: .visible
        ) {
            Button("确认清空", role: .destructive) {
                DebugResetCoordinator.scheduleLocalNuke()
                exit(0)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清掉 SwiftData 全表 + 所有 migration flag。CloudKit solo zone 保留（下次启动会重新拉回）。app 会立即退出。")
        }
        .confirmationDialog(
            "清空本地 + 云端？",
            isPresented: $confirmCloudWipeStep1,
            titleVisibility: .visible
        ) {
            Button("继续（还会再次确认）", role: .destructive) {
                confirmCloudWipeStep2 = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将同时清掉本地数据和 CloudKit solo zone 的所有备份，无法撤销。需要二次确认。")
        }
        .confirmationDialog(
            "再次确认",
            isPresented: $confirmCloudWipeStep2,
            titleVisibility: .visible
        ) {
            Button("我确定，全部清掉", role: .destructive) {
                DebugResetCoordinator.scheduleLocalPlusCloudWipe()
                exit(0)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这是最后一次确认。点击后 app 会立即退出，下次启动时本地 + 云端都会被清空。")
        }
    }
}
#endif
```

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add Together/Features/Profile/ProfileDebugSection.swift
git commit -m "$(cat <<'EOF'
feat(devtools): add ProfileDebugSection with two-tier reset UI

- Local-only reset (single confirm)
- Local + CloudKit solo zone wipe (two-stage confirm)
- Both paths: schedule flag → exit(0) → pre-init nuke on next launch
- Entire file #if DEBUG

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A5: 把 `ProfileDebugSection` 挂到 `ProfileView`

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: 插入 section**

打开 `Together/Features/Profile/ProfileView.swift`，找到 `body` 主 `VStack` 末尾 `signOutFooter` 这一行（当前在第 54 行附近）：

```swift
// MARK: - 退出登录
signOutFooter
```

在 `signOutFooter` 之后插入：

```swift
// MARK: - 退出登录
signOutFooter

#if DEBUG
ProfileDebugSection()
#endif
```

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: 手动冒烟（用户操作，不自动化）**

用户用 Xcode run 到 Simulator：
1. 进 Profile 页，滚到底部应看到「开发者 (DEBUG)」section 两个红色按钮
2. 点"清空本地数据" → confirmationDialog 弹出，文案正确 → 点确认 → app 退出
3. Xcode 再按 ⌘R → app 启动，Today 页业务数据清空，回到 seed 状态
4. 点击任意一条新建任务，编辑 / 移除按钮可用（creatorID == currentUserID）
5. 重复点"清空本地 + 云端"验证双层 confirmation 流程

（这一步不是 CI 验收项，只是用户验证清单，不 block commit。）

- [ ] **Step 5: Commit**

```
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
feat(devtools): mount ProfileDebugSection at the bottom of ProfileView

Placed below signOutFooter, wrapped in #if DEBUG.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part C — `Item.status` 诊断埋点

### Task C1: 新建 `ItemStatusDiagnosisLog` namespace

**Files:**
- Create: `Together/Debug/ItemStatusDiagnosisLog.swift`

- [ ] **Step 1: 写 namespace**

创建 `Together/Debug/ItemStatusDiagnosisLog.swift`：

```swift
import Foundation
import os

/// 诊断 `Item.status` / `completedAt` 在哪一条路径上被修改。
///
/// 用法：Console.app filter `subsystem:com.together.diagnosis category:item-status`
///
/// 所有方法打 `.info` 级别。Release build 由 unified logging 自动过滤；
/// 纯观测，不改任何行为，因此不需要 `#if DEBUG` 包裹。
enum ItemStatusDiagnosisLog {
    private static let logger = Logger(
        subsystem: "com.together.diagnosis",
        category: "item-status"
    )

    // MARK: - markCompleted path

    static func markCompletedBegin(
        itemID: UUID,
        oldStatus: String,
        oldCompletedAt: Date?,
        actorID: UUID,
        creatorID: UUID,
        hasRepeatRule: Bool
    ) {
        logger.info("""
            markCompleted.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            oldStatus=\(oldStatus, privacy: .public) \
            oldCompletedAt=\(oldCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            actorID=\(actorID.uuidString, privacy: .public) \
            creatorID=\(creatorID.uuidString, privacy: .public) \
            hasRepeatRule=\(hasRepeatRule, privacy: .public)
            """)
    }

    static func markCompletedSaved(
        itemID: UUID,
        newStatus: String,
        newCompletedAt: Date?
    ) {
        logger.info("""
            markCompleted.saved \
            itemID=\(itemID.uuidString, privacy: .public) \
            newStatus=\(newStatus, privacy: .public) \
            newCompletedAt=\(newCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    static func markCompletedReadback(
        itemID: UUID,
        readbackStatus: String?,
        readbackCompletedAt: Date?
    ) {
        logger.info("""
            markCompleted.readback \
            itemID=\(itemID.uuidString, privacy: .public) \
            readbackStatus=\(readbackStatus ?? "nil", privacy: .public) \
            readbackCompletedAt=\(readbackCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    // MARK: - Solo CKSyncEngine apply path

    enum ApplyDecision: String {
        case applied
        case skippedStale
        case skippedNotFound
    }

    static func soloSyncApplyBegin(
        itemID: UUID,
        incomingStatus: String,
        incomingCompletedAt: Date?,
        localStatus: String?,
        localCompletedAt: Date?,
        incomingUpdatedAt: Date,
        localUpdatedAt: Date?,
        hasPendingLocalSave: Bool
    ) {
        logger.info("""
            soloSync.apply.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            incomingStatus=\(incomingStatus, privacy: .public) \
            incomingCompletedAt=\(incomingCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            localStatus=\(localStatus ?? "nil", privacy: .public) \
            localCompletedAt=\(localCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            incomingUpdatedAt=\(incomingUpdatedAt.iso8601, privacy: .public) \
            localUpdatedAt=\(localUpdatedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            hasPendingLocalSave=\(hasPendingLocalSave, privacy: .public)
            """)
    }

    static func soloSyncApplyDone(itemID: UUID, decision: ApplyDecision) {
        logger.info("""
            soloSync.apply.done \
            itemID=\(itemID.uuidString, privacy: .public) \
            decision=\(decision.rawValue, privacy: .public)
            """)
    }

    // MARK: - Supabase apply path

    static func supabaseApplyBegin(
        itemID: UUID,
        incomingStatus: String,
        incomingCompletedAt: Date?,
        localStatus: String?,
        localCompletedAt: Date?,
        incomingUpdatedAt: Date,
        localUpdatedAt: Date?
    ) {
        logger.info("""
            supabaseSync.apply.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            incomingStatus=\(incomingStatus, privacy: .public) \
            incomingCompletedAt=\(incomingCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            localStatus=\(localStatus ?? "nil", privacy: .public) \
            localCompletedAt=\(localCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            incomingUpdatedAt=\(incomingUpdatedAt.iso8601, privacy: .public) \
            localUpdatedAt=\(localUpdatedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    static func supabaseApplyDone(itemID: UUID, decision: ApplyDecision) {
        logger.info("""
            supabaseSync.apply.done \
            itemID=\(itemID.uuidString, privacy: .public) \
            decision=\(decision.rawValue, privacy: .public)
            """)
    }
}

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
```

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add Together/Debug/ItemStatusDiagnosisLog.swift
git commit -m "$(cat <<'EOF'
feat(debug): add ItemStatusDiagnosisLog namespace for status mutation tracing

os.Logger subsystem=com.together.diagnosis category=item-status.
All fields .public privacy so they show in Console.app during dev.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C2: `LocalItemRepository.markCompleted` 埋点

**Files:**
- Modify: `Together/Services/Items/LocalItemRepository.swift`

- [ ] **Step 1: 加埋点**

打开 `Together/Services/Items/LocalItemRepository.swift`，找到 `markCompleted` 方法（第 207 行附近）。

**落盘前** —— 在 `guard let record = try fetchRecord(itemID: itemID, context: context) else { ... }` 之后、`var item = record.domainModel()` 之前插入：

```swift
ItemStatusDiagnosisLog.markCompletedBegin(
    itemID: record.id,
    oldStatus: record.statusRawValue,
    oldCompletedAt: record.completedAt,
    actorID: actorID,
    creatorID: record.creatorID ?? UUID(),
    hasRepeatRule: record.repeatRuleData != nil
)
```

（注：如果 `record.creatorID` 是 non-optional `UUID`，把 `?? UUID()` 去掉。看类型。）

**落盘后** —— 在 `try context.save()` 之后、`if let sid = record.spaceID` 之前插入：

```swift
ItemStatusDiagnosisLog.markCompletedSaved(
    itemID: record.id,
    newStatus: record.statusRawValue,
    newCompletedAt: record.completedAt
)

// Read-back verification — re-fetch to confirm save actually persisted.
let readback = try? fetchRecord(itemID: itemID, context: context)
ItemStatusDiagnosisLog.markCompletedReadback(
    itemID: itemID,
    readbackStatus: readback?.statusRawValue,
    readbackCompletedAt: readback?.completedAt
)
```

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 跑 item repo 相关测试**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/LocalItemRepositoryTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（log 调用是观测，不影响测试结果）

- [ ] **Step 4: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```
git add Together/Services/Items/LocalItemRepository.swift
git commit -m "$(cat <<'EOF'
feat(debug): instrument markCompleted with ItemStatusDiagnosisLog

Logs begin / saved / readback — the last one re-fetches to verify
the save actually persisted to SwiftData. Observability only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C3: `SyncEngineDelegate.applyItem` 埋点

**Files:**
- Modify: `Together/Sync/Engine/SyncEngineDelegate.swift`

- [ ] **Step 1: 加埋点**

打开 `Together/Sync/Engine/SyncEngineDelegate.swift`，找到 `applyItem` 方法（第 391 行附近）：

```swift
private func applyItem(_ item: Item, hasPendingLocalSave: Bool, context: ModelContext) {
    let itemID = item.id
    let descriptor = FetchDescriptor<PersistentItem>(
        predicate: #Predicate<PersistentItem> { $0.id == itemID }
    )
    if let existing = try? context.fetch(descriptor).first {
        if Self.shouldApplyFetchedRecord(
            remoteUpdatedAt: item.updatedAt,
            localUpdatedAt: existing.updatedAt,
            hasPendingLocalSave: hasPendingLocalSave
        ) {
            existing.update(from: item)
        }
    } else {
        context.insert(PersistentItem(item: item))
    }
}
```

改成：

```swift
private func applyItem(_ item: Item, hasPendingLocalSave: Bool, context: ModelContext) {
    let itemID = item.id
    let descriptor = FetchDescriptor<PersistentItem>(
        predicate: #Predicate<PersistentItem> { $0.id == itemID }
    )
    let existing = try? context.fetch(descriptor).first

    ItemStatusDiagnosisLog.soloSyncApplyBegin(
        itemID: itemID,
        incomingStatus: item.status.rawValue,
        incomingCompletedAt: item.completedAt,
        localStatus: existing?.statusRawValue,
        localCompletedAt: existing?.completedAt,
        incomingUpdatedAt: item.updatedAt,
        localUpdatedAt: existing?.updatedAt,
        hasPendingLocalSave: hasPendingLocalSave
    )

    let decision: ItemStatusDiagnosisLog.ApplyDecision
    if let existing {
        if Self.shouldApplyFetchedRecord(
            remoteUpdatedAt: item.updatedAt,
            localUpdatedAt: existing.updatedAt,
            hasPendingLocalSave: hasPendingLocalSave
        ) {
            existing.update(from: item)
            decision = .applied
        } else {
            decision = .skippedStale
        }
    } else {
        context.insert(PersistentItem(item: item))
        decision = .applied
    }

    ItemStatusDiagnosisLog.soloSyncApplyDone(itemID: itemID, decision: decision)
}
```

注：如果 `item.status` 是 `ItemStatus` 枚举（看 `Domain/Enums/ItemStatus.swift`），`item.status.rawValue` 是对的。如果已经是 String 则直接 `item.status`。请根据实际类型取值。

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 跑 sync 相关测试**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests 2>&1 | grep -E "(Failing|Passed|Failed|TEST SUCCEEDED|TEST FAILED)" | tail -20
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add Together/Sync/Engine/SyncEngineDelegate.swift
git commit -m "$(cat <<'EOF'
feat(debug): instrument SyncEngineDelegate.applyItem with diagnosis log

Records incoming vs local status/completedAt/updatedAt and the final
apply decision (applied / skippedStale). Restructures apply body to
return decision cleanly without changing behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C4: `TaskDTO.applyToLocal` 埋点

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

- [ ] **Step 1: 加埋点**

打开 `Together/Sync/SupabaseSyncService.swift`，找到第 1056 行的 `TaskDTO.applyToLocal` 方法：

```swift
nonisolated func applyToLocal(context: ModelContext) {
    let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == id })
    if let existing = try? context.fetch(descriptor).first {
        // 冲突保护：incoming 比本地旧则跳过（网络乱序 / 时钟漂移场景）
        if updatedAt < existing.updatedAt { return }
        // UPDATE: 同步远端字段
        existing.title = title
        ...
```

改成（在开头 fetch 之后加 begin log、在每一条可能 return 的分支前加 done log、末尾加 done log）：

```swift
nonisolated func applyToLocal(context: ModelContext) {
    let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == id })
    let existing = try? context.fetch(descriptor).first

    ItemStatusDiagnosisLog.supabaseApplyBegin(
        itemID: id,
        incomingStatus: status,
        incomingCompletedAt: completedAt,
        localStatus: existing?.statusRawValue,
        localCompletedAt: existing?.completedAt,
        incomingUpdatedAt: updatedAt,
        localUpdatedAt: existing?.updatedAt
    )

    if let existing {
        // 冲突保护：incoming 比本地旧则跳过（网络乱序 / 时钟漂移场景）
        if updatedAt < existing.updatedAt {
            ItemStatusDiagnosisLog.supabaseApplyDone(itemID: id, decision: .skippedStale)
            return
        }
        // UPDATE: 同步远端字段
        existing.title = title
        existing.notes = notes
        existing.listID = listId
        existing.projectID = projectId
        existing.assigneeModeRawValue = assigneeMode
        existing.statusRawValue = status
        existing.dueAt = dueAt
        existing.hasExplicitTime = hasExplicitTime
        existing.remindAt = remindAt
        existing.isPinned = isPinned
        existing.isDraft = isDraft
        existing.completedAt = completedAt
        existing.isArchived = isArchived
        existing.archivedAt = archivedAt
        existing.updatedAt = updatedAt
        existing.executionRoleRawValue = executionRole
        existing.assignmentStateRawValue = assignmentState
        if let h = responseHistory, let d = h.data(using: .utf8) { existing.responseHistoryData = d }
        if let m = assignmentMessages, let d = m.data(using: .utf8) { existing.assignmentMessagesData = d }
        existing.reminderRequestedAt = reminderRequestedAt
        existing.locationText = locationText
        // 软删除：用 tombstone 标记，不硬删，避免下次 pull 被 INSERT 复活
        if isDeleted {
            existing.isLocallyDeleted = true
        }
        ItemStatusDiagnosisLog.supabaseApplyDone(itemID: id, decision: .applied)
    } else if !isDeleted {
        // INSERT: 本地不存在 & 未被软删除 → 创建新记录
        // 保留原有 PersistentItem 构造调用（不复制，原代码后续 50 行不变）
        // ⬇ 原有 context.insert(...) 代码保持不变
        // ⬆ 在 context.insert 之后加下面这行：
        // ItemStatusDiagnosisLog.supabaseApplyDone(itemID: id, decision: .applied)

        // ↑ 在原有 insert 代码之后（闭合本分支之前）调 done(.applied)
    } else {
        // 不存在且是 tombstone → skip
        ItemStatusDiagnosisLog.supabaseApplyDone(itemID: id, decision: .skippedNotFound)
    }
}
```

**重要**：原 `applyToLocal` INSERT 分支代码有 ~50 行（`let item = PersistentItem(...)` + `context.insert(item)`）。请**保留原样不改**，只在原 `context.insert(item)` 之后插入：

```swift
ItemStatusDiagnosisLog.supabaseApplyDone(itemID: id, decision: .applied)
```

实施时请以实际文件 1056-1170 行为准确定边界，不要大段重写。

- [ ] **Step 2: 编译**

Run:
```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 跑 Supabase sync 相关测试**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests 2>&1 | grep -E "(Failing|TEST SUCCEEDED|TEST FAILED)" | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: 全量 regression**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```
git add Together/Sync/SupabaseSyncService.swift
git commit -m "$(cat <<'EOF'
feat(debug): instrument TaskDTO.applyToLocal with diagnosis log

Logs begin with incoming/local status, completedAt, updatedAt;
done with decision (applied / skippedStale / skippedNotFound).
No behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 用户侧诊断操作指引（Part C 落地后，用户做）

1. Xcode run 到 iPhone 17 Pro Simulator
2. 打开 Console.app → 左侧选 iPhone Simulator 设备 → 搜索框输入 `subsystem:com.together.diagnosis`
3. 清一次数据（Part A 的"清空本地数据"按钮）重启
4. 新建一条普通任务，设置 dueAt 为 "今天 14:00"
5. 手动把系统时间拨到 14:30 之后（Simulator → Features → Control Center → 或用 Debug 菜单）；或直接等一会儿
6. 回 Today 页，确认该任务显示为"逾期"
7. 勾选完成。Console 应出现 3 条 log：`markCompleted.begin / saved / readback`。**确认 readback status = completed**
8. 退出 app（Xcode ⌘.），按 ⌘R 重跑
9. 观察冷启动 log：
   - 若 `soloSync.apply.begin` 出现 + `localStatus=completed` + `incomingStatus=inProgress` + `decision=applied` → **root cause = solo CloudKit 覆盖本地完成态**
   - 若没有 `soloSync.apply` 但冷启动后任务又逾期 → **root cause = 完成写盘根本没成功**（readback 里就能看到），或 SwiftData 读时走了别的路径
   - 若 `supabaseSync.apply` 对单人模式的任务也触发 → 意料外，查 pair/solo 隔离
10. 把 Console 完整 log 导出（⌘A + ⌘C 复制，或 File → Export Messages）贴回对话

---

## Self-Review

- ✅ Spec 两块都有 task 覆盖：A1-A5 覆盖 "清盘按钮"，C1-C4 覆盖 "诊断埋点"
- ✅ 没有 `TBD / TODO / FIXME / "implement later"`；C4 有一处说明 "保留原样不改"，但带了精确行号范围和单行插入位置
- ✅ 类型一致性：`DebugResetCoordinator` 的 `pendingLocalNukeKey / pendingCloudWipeKey / applyPendingNukeIfNeeded / scheduleLocalNuke / scheduleLocalPlusCloudWipe` 在 A2 / A3 / A4 使用一致；`ItemStatusDiagnosisLog` 的方法名 `markCompletedBegin/Saved/Readback`、`soloSyncApplyBegin/Done`、`supabaseApplyBegin/Done` 在 C1 定义后 C2/C3/C4 调用完全对应
- ✅ `ApplyDecision` 枚举在 C1 声明，C3/C4 只用 `.applied / .skippedStale / .skippedNotFound`，与定义一致
- ✅ Swift Testing（`import Testing` / `@Test` / `#expect`）唯一用在 A2 的测试里；其他任务是观测 / UI，不引入新 test suite
- ✅ 每 task 一个 commit，commit message 英文 conventional + co-author trailer 模板
- ✅ 硬性约束（禁 print / TODO / FIXME / 不改 pbxproj）全遵守
- ✅ `#if DEBUG` 包裹所有 Part A 新代码；Part C 不包裹（os.Logger release 自动过滤，纯观测）
