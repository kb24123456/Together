# Dev-only 本地清盘 + "已完成 → 逾期" 诊断埋点

- 状态：Draft · 待用户 review
- 日期：2026-04-20
- Branch：`feat/ui-polish`（或新开一个 `feat/devtools-reset-and-diagnosis`）

## 背景

在日常开发循环（Xcode 反复 rerun）里，单人模式 Today 页出现 21 条「已逾期任务」，伴随两个观察：

1. 这些任务详情页的「编辑 / 移除」按钮灰掉 —— 定位到 `PairPermissionService.canEditTask / canDeleteTask` 的 `creatorID == actorID` 硬判定失败。说明任务被创建时的 `creatorID` 和当前 session 恢复出来的 `sessionStore.currentUser?.id` 不一致。
2. 用户反馈「之前已完成的任务又变成逾期」——单人模式下 `LocalItemRepository.markCompleted` 不走 creator-check（guard 只管 `.partner` assigneeMode），所以完成流程理论上能成功；但 cold-start 后 status 又回到非 `.completed`，说明要么完成操作**根本没落盘**，要么**落盘后被冷启动 sync pull 覆盖**。

用户自述这些任务是长期迭代（多次登入登出、多次 Apple ID 换账号）中留下来的 dev 测试数据，app 尚未 TestFlight / App Store，没有真用户数据保全压力。

## 范围

本 spec **不解决** userID 漂移的 root cause（B 方向 `loadOrCreateUser` 的 fetch 顺序 / `signOut` 清表等），也**不做** `PairPermissionService` 的单人模式 bypass。这两项留给后续 spec（发 TestFlight 前必做）。

本 spec 只做两件事：

- **A. Dev-only 一键清盘按钮**：在 Profile 页加 `#if DEBUG` 的「开发者」section，两档清理（仅本地 / 本地 + 云端 solo zone），flag + `exit(0)` + 下次冷启动在 SwiftData init 之前删文件。解决"每次测试被 21 条脏数据挡路"的即时痛点。
- **C. `Item.status` 诊断埋点**：在 3 条可能修改 status 的路径上用 `os.Logger` 打结构化日志，用户复现一次后贴 log 回来，定位到底是完成没落盘 / 被 sync 覆盖 / 本地有二次 reset。

这两件事互相正交：A 让你能跑干净的测试，C 让你能看清"完成 → 逾期"到底发生在哪一步。

## 非目标

- 不改 `PairPermissionService` 行为
- 不改 `AppleAuthService.loadOrCreateUser` / `signOut`
- 不做一次性 migration 回填 `creatorID`
- 不动 Supabase 后端数据 / pair zone（单人模式看不到它们）
- 不改任何 release 行为（A 用 `#if DEBUG`，C 只加 `os.Logger` 调用，release 被 unified logging 自动丢弃）

---

## 设计 A — Dev-only 一键清盘

### 入口 UI

Profile（"我"）页底部新增独立「开发者」section，整段 `#if DEBUG` 条件编译。视觉上参考 TestFlight / Feedback Assistant 约定：灰色分组背景 + 顶部 "开发者（DEBUG）" 小字标题 + 两行按钮。

**两个按钮**：

1. **"清空本地数据"**（safer 默认项，destructive role）
   - 单次 `confirmationDialog`：列出将清掉的内容（SwiftData 全表、migration flag、用户偏好）
   - CloudKit solo zone 保留 —— 下次启动 CKSyncEngine 会把云端数据重新拉回
   - 适用于测试 "从云端重新下发" 的 pull 路径

2. **"清空本地 + 云端（危险）"**（更 destructive，双次确认）
   - 第一次 `confirmationDialog`：明确提示"此操作无法撤销，包括云端 solo zone 的所有备份"
   - 第二次 `confirmationDialog`：再次确认
   - 清本地 + 调用 `CKDatabase.deleteRecordZone` 删 solo zone
   - Supabase pair 侧不动（单人模式无关）

### 执行流程（两档共用）

```
用户点按钮
  ↓
写 UserDefaults：pendingLocalStoreNuke = true
                 [可选] pendingCloudKitSoloZoneWipe = true
  ↓
exit(0) 立即退出
  ↓
[用户重新 launch / Xcode rerun]
  ↓
TogetherApp @main init 最顶部：
  DebugResetCoordinator.applyPendingNukeIfNeeded()
    ├── 若 cloud flag true：临时起最小 CKContainer，删 solo zone
    │   （失败只 log 不 block，不影响本地清）
    ├── 若 local flag true：
    │   ├── deleteStoreFiles()（3 个 .store* 文件 + _SUPPORT）
    │   ├── 清所有已知 migration flag（显式枚举，不用前缀扫）：
    │   │     - `didCleanupLegacyPeriodicData.v1`（PersistenceController）
    │   │     - PairPeriodicPurgeMigration 的 flag key（实施前 grep 定位精确名）
    │   │     - PairSpaceOrphanPurgeMigration 的 flag key（同上）
    │   │     - 日后新增 migration 时需显式加入清单（代码注释标记）
    │   └── 清 pending flag 本身
  ↓
PersistenceController.init 正常走 →
  attemptFullInit → seedIfNeeded → 干净启动
```

**关键设计决策 — 为什么要 flag + exit + 下次启动才删**：

当前 session 里 SwiftData container 还在跑，直接 `FileManager.removeItem` store 文件会造成 container 访问未定义内存 / panic。工业界标准做法是先标记 "pending"、立即终止进程，下次启动 init 最早期删文件，此时 SwiftData 还没 open。类似 Linux `/etc/.reboot-required`、Xcode "Erase All Content and Settings" 的思路。

### 文件改动

**新增**：`Together/App/Debug/DebugResetCoordinator.swift`（~100 行）
- `static let pendingLocalNukeKey = "DebugReset.pendingLocalNuke"`
- `static let pendingCloudWipeKey = "DebugReset.pendingCloudWipe"`
- `static func scheduleLocalNuke()` —— UI 调用
- `static func scheduleLocalPlusCloudWipe()` —— UI 调用
- `static func applyPendingNukeIfNeeded()` —— TogetherApp 入口调用
- `static func deleteStoreFiles()` —— 从 `PersistenceController` 挪出来或 `@testable` 暴露
- 全部方法内部用 `os.Logger(subsystem: "com.together.debug", category: "reset")` 打执行顺序
- 整文件 `#if DEBUG` 包裹

**新增**：`Together/Features/Profile/ProfileDebugSection.swift`（~80 行）
- `struct ProfileDebugSection: View`
- 两个按钮 + 两层 confirmationDialog
- 整文件 `#if DEBUG` 包裹

**修改**：`Together/Features/Profile/ProfileView.swift`
- 在主 `List` 底部加一行：`#if DEBUG\nProfileDebugSection()\n#endif`（~3 行）

**修改**：`Together/TogetherApp.swift`
- `@main` struct 里最早的 init / `body` 进入前 —— 加：
  ```
  #if DEBUG
  DebugResetCoordinator.applyPendingNukeIfNeeded()
  #endif
  ```
- 位置要在任何 `PersistenceController.shared` 被访问之前（~3 行）

**修改**：`Together/Persistence/PersistenceController.swift`
- 不改 `init` 逻辑
- 把 `deleteStoreFiles()` 提到 `internal` 或让 `DebugResetCoordinator` 复用（2-5 行调整可见性）

**总计**：新增 ~180 行，修改 ~10 行。

### 边界 / 失败处理

- **删文件失败**：log warn，继续往下走。下一次启动 SwiftData init 如果仍失败，走现有的 `deleteStoreFiles + reset` fallback 路径，最终也能启动。
- **CloudKit 删 zone 失败**：网络不通 / zone 不存在，log warn，不 block 本地清。下次上线时 CKSyncEngine 会自愈。
- **Release build**：所有入口 `#if DEBUG`，release 里这些代码完全不存在；UserDefaults key 即使意外残留也没人读。
- **误操作**：双层 confirmation + destructive role 红色文字提示。
- **测试**：`DebugResetCoordinator` 的 flag read/write + `deleteStoreFiles` 单元测试不必强求（纯 file IO），只做 smoke test 验证"写 flag 后下次 `applyPendingNukeIfNeeded` 返回 true"。

---

## 设计 C — `Item.status` 诊断埋点

### 目标

让用户复现一次完整的 "完成任务 → Xcode rerun → 任务变逾期" 流程后，通过 Console.app 查 log 即可分辨三种 root cause：

| 现象 | log 表现 |
|------|----------|
| 完成操作没落盘 | 只看到 markCompleted.begin，看不到 markCompleted.saved 或 readback 显示 status 还是旧值 |
| 落盘后被 sync 覆盖 | markCompleted.saved 正常；冷启动后 sync.apply 日志显示 incoming status != .completed 且 local 被覆盖 |
| 本地有二次 reset | 落盘正常，sync 也没覆盖，但 cold start 后某处 log 显示 status 被重置 |

### 埋点 3 处

**1. `LocalItemRepository.markCompleted`**（[LocalItemRepository.swift:207](Together/Services/Items/LocalItemRepository.swift:207)）

在 3 个关键时刻打 log：

```
ItemStatusDiagnosisLog.markCompletedBegin(
    itemID: record.id,
    oldStatus: record.statusRawValue,
    oldCompletedAt: record.completedAt,
    actorID: actorID,
    creatorID: record.creatorID,
    hasRepeatRule: item.repeatRule != nil
)
// ... 原有逻辑 ...
try context.save()
ItemStatusDiagnosisLog.markCompletedSaved(
    itemID: record.id,
    newStatus: record.statusRawValue,
    newCompletedAt: record.completedAt
)
// 紧接着再 fetch 一次验证 SwiftData 真的写下去了
let readback = try fetchRecord(itemID: itemID, context: context)
ItemStatusDiagnosisLog.markCompletedReadback(
    itemID: itemID,
    readbackStatus: readback?.statusRawValue,
    readbackCompletedAt: readback?.completedAt
)
```

**2. CKSyncEngine solo zone 的 apply 路径**

先定位（`SyncEngineDelegate` 或 `SoloSyncService` 处理 item 记录的入口），在每次 apply item 的 status / completedAt 字段**之前**和**之后**各打一次：

```
ItemStatusDiagnosisLog.soloSyncApplyBegin(
    itemID: incoming.id,
    incomingStatus: incoming.status,
    incomingCompletedAt: incoming.completedAt,
    localStatus: existing?.statusRawValue,
    localCompletedAt: existing?.completedAt,
    incomingUpdatedAt: incoming.updatedAt,
    localUpdatedAt: existing?.updatedAt
)
// ... apply ...
ItemStatusDiagnosisLog.soloSyncApplyDone(
    itemID: incoming.id,
    decision: .applied / .skippedStale / .skippedTombstoned
)
```

**3. `SupabaseSyncService.applyToLocal` 的 task 分支**

同格式埋一次。单人模式理论不走这条，保险起见埋上排除。

### Logger 定义（新文件）

**新增**：`Together/Debug/ItemStatusDiagnosisLog.swift`（~60 行）

```swift
import Foundation
import os

enum ItemStatusDiagnosisLog {
    private static let logger = Logger(
        subsystem: "com.together.diagnosis",
        category: "item-status"
    )

    static func markCompletedBegin(...) {
        logger.info("markCompleted.begin itemID=\(...) oldStatus=\(...) ...")
    }

    static func markCompletedSaved(...) { ... }
    static func markCompletedReadback(...) { ... }
    static func soloSyncApplyBegin(...) { ... }
    static func soloSyncApplyDone(...) { ... }
    static func supabaseApplyBegin(...) { ... }
    static func supabaseApplyDone(...) { ... }
}
```

所有方法用 `logger.info` 或 `logger.debug`。不 `#if DEBUG` 包裹 —— `os.Logger` 在 release 走 unified logging，不会进 Xcode console 也不会影响性能；测试时 Console.app 过滤 `subsystem:com.together.diagnosis` 即可。

### 用户侧操作指引（spec 落地时写进 PR 描述）

1. Xcode run 到 iPhone Simulator
2. 打开 Console.app，filter: `subsystem:com.together.diagnosis`
3. 在 app 里完成一条任务（任意一条现在显示逾期的）
4. 观察 `markCompleted.begin / saved / readback` 三条 log 是否齐全，status 变化是否符合预期
5. Xcode 按 ⌘. 停止，再按 ⌘R 重跑
6. 冷启动后观察是否有 `soloSync.apply` 相关 log 把该 itemID 的 status 覆盖回去
7. 把完整 log 截图 / 导出贴回对话

### 文件改动

**新增**：`Together/Debug/ItemStatusDiagnosisLog.swift`（~60 行）

**修改**：`Together/Services/Items/LocalItemRepository.swift`
- `markCompleted` 方法内加 3 处 log 调用（~8 行）

**修改**：CKSyncEngine solo apply 对应文件
- 实施第一步：grep `SyncEngineDelegate`、`applyRemoteItem`、`handleRemoteChange` 等关键词定位入口
- 候选：`Together/Sync/Engine/SyncEngineDelegate.swift` / `SyncEngineCoordinator` 相关文件
- apply item status/completedAt 前后各一处 log（~6 行）

**修改**：`Together/Sync/SupabaseSyncService.swift`
- `applyToLocal` task 分支前后各一处 log（~6 行）

**总计**：新增 ~60 行，修改 ~20 行。

### 边界 / 失败处理

- Log 参数格式化失败（UUID / Date 转字符串）—— 不可能，用标准 `.uuidString` / ISO8601。
- Logger 本身是 thread-safe + lock-free，不会引入并发问题。
- 纯观测，不改任何行为，所以不破坏测试。

---

## 测试计划

### A 的验收

1. Xcode run app → Profile 页底部看到「开发者 (DEBUG)」section + 两个红色按钮
2. 点"清空本地数据" → confirmationDialog 弹出 → 点确认 → app 退出
3. Xcode 再按 ⌘R → app 启动，Today 页所有业务数据清空，回到 seed 状态
4. 重新创建一个任务，确认 creatorID == 当前 userID，编辑/移除按钮正常可点
5. 点"清空本地 + 云端" → 双层 confirmation → 确认 → 退出 → 重跑 → 本地清 + CloudKit solo zone 也不再下发历史数据

### C 的验收

1. 复现一次完成 → rerun → 逾期的完整流程
2. Console.app 里看到 `markCompleted.begin / saved / readback` 三条齐全，status 字段从 `inProgress` → `completed`
3. 冷启动后能看到 `soloSync.apply` 对同一 itemID 的 log（或能看不到 = apply 没发生）
4. 用户把 log 贴回，根据表现分类到 "没落盘 / 被 sync 覆盖 / 二次 reset" 之一

### Regression

- 跑一次全量 `xcodebuild test -scheme Together` 确认没破坏现有测试
- A 的 `#if DEBUG` 包裹 —— release 配置下 build 确认无引用

---

## 实施顺序建议

1. **先做 A**（~2 小时）—— 立即解锁你的日常测试节奏
2. 用 A 清一次 + 重新建几条任务作为干净 test corpus
3. **再做 C**（~1 小时）—— 在干净 corpus 上跑一次诊断流程
4. 根据 C 的 log 输出决定下一个 spec 的方向（root cause 修法）

---

## 后续（不在本 spec 范围）

基于 C 的诊断结果，大概率会写以下后续 spec 之一：

- **spec-B1**：`PairPermissionService` 单人模式 bypass（解决 "编辑/移除 灰掉"）
- **spec-B2**：`AppleAuthService.loadOrCreateUser` fetch sort 稳定化 + `signOut` 清 profile 表（解决 userID 漂移）
- **spec-B4**：一次性 migration 回填历史 Item.creatorID（如果 A 清盘后你决定保留部分历史数据）
- **spec-D**：solo CKSyncEngine echo filter / 冲突处理修正（如果 C 的 log 证明是 sync 覆盖）

这些留到有 C 的数据后再拟。
