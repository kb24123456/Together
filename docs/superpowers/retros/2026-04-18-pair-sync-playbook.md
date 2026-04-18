# Pair Sync Playbook — 经验复盘 + 可复用接入清单

**时段**：2026-04-15 至 2026-04-18，从架构审计到双设备打通空间名秒级同步
**范围**：Together iOS app 的 Supabase 双人同步（push / pull / Realtime / 配对）
**最终状态**：空间名、昵称、任务推拉、并发、tombstone、冲突保护全通；头像文件上传 Plan B 待补

---

## §1 全景时间线

| 阶段 | Commits | 干了什么 |
|---|---|---|
| 审计 | （口头报告） | 列出 20+ 处 push/pull/状态/竞态/RLS/字段缺失问题 |
| Plan A 写作 | 计划文档 `2026-04-17-pair-sync-comprehensive-fix.md`（13 个任务，分 3 阶段） | 锁定 P0 数据正确性 + P1 并发稳定性 |
| Plan A 执行 | `e3440fa..73a2180` 共 15 个 commit | Supabase migration 003、PersistentItem tombstone、TaskDTO 5 字段补全、saveItem/deleteItem 记录变更、unbind 归档、push 串行化、sending 恢复、lastSyncedAt 持久化、updatedAt 冲突 guard、Realtime echo filter |
| 双设备实测暴露的连环 bug | `547ebe6, f396782, a0cb29e, 4013566, 38a94a1, 3054991, 73a2180` | (1) cloudkit.share 噪音；(2) startSupabaseSyncIfNeeded 竞态导致重复订阅；(3) Realtime channel 缓存导致 "Cannot add postgres_changes"；(4) **Bug A**：createInvite 把昵称当空间名；(5) **Bug C**：CKSyncEngine 把 pair 变更当 solo；(6) **Bug D**：push() early-return 漏释放 isPushing → 永久卡死；(7) **Bug E**：spaces 表没订阅 Realtime |
| 验证通过 | （日志确认）| iPhone 改名 → 1-3s iPad 自动刷新 |

> **关键认知**：审计阶段抓出 20+ 问题，但真上双设备又冒出 7 个新 bug，且其中 4 个（B/D/E）是 Plan A 修复**引入的连锁问题**。说明：架构审计 ≠ 集成验证；只有跨设备真实运行才暴露竞态、缓存、订阅遗漏类问题。

---

## §2 反模式（Anti-patterns）—— 每条都付出过代价，要主动规避

### A1 · "TODO 将在集成测试中补充"

**症状**：注释里写 TODO 或 "后续完善"，实际从未补充。

**这轮的实例**：
- `applyToLocal` 注释 "新记录创建需要完整的 PersistentItem 初始化，将在集成测试阶段补充完善" —— 从未补充，导致对方新建的所有数据**静默丢弃**
- `pushUpsert .avatarAsset: break // 头像文件上传由 Storage 单独管理` —— Storage 上传根本没实现
- `CloudPairingService.unbind` 的 `// TODO: Supabase 端解绑操作` —— 对方永远不知道被解绑

**对策**：
- 任何 `// TODO` / "后续" / "暂时" 注释必须配一个**失败的测试用例**作为 ledger，提交时一并入库
- code review 时把"无测试覆盖的 TODO"视为 bug，不允许合入
- 如果当下不实现，删掉那段代码不要留语义残骸

---

### A2 · 多层都"让别人做"，结果谁都没做

**症状**：同一职责（如"任务变更要 push"）分散在多层，每层都觉得别人会处理。

**这轮的实例**：
- `LocalItemRepository.saveItem` 不调 `recordLocalChange` ← 它假设 ViewModel 会做
- `HomeViewModel.emitSharedTaskMutation` 触发回调 ← 它假设 AppContext 会 record
- `AppContext.flushRecordedSharedMutation` 只 push 不 record ← 它假设 record 已经发生
- 结果：**三层都不 record，push 时 PersistentSyncChange 表是空的，什么都没推送**

**对策**：
- **Repository 是单一可信来源（Single Source of Truth）**：所有数据修改入口必须在 Repository 层调用 `recordLocalChange` 同步
- 上层（ViewModel / AppContext）**禁止**重复 record，只触发 push
- 在 Repository 协议头注释里写明这条契约

---

### A3 · 双向同步只想了一边

**症状**：写 push 链时忘了 pull 链，或反过来。订阅时漏了某张表。

**这轮的实例**：
- `pushUpsert .space` 实现了，`pullSpaces` 一开始没有 —— 对方 push 的空间名拉不到
- `pushUpsert .memberProfile` 实现了，`pullSpaceMembers` 一开始没有
- 5 张业务表都订阅了 Realtime，spaces 表漏掉 —— 对方改名收不到推送（只能等下次 catchUp）
- TaskDTO push 5 字段补齐了，但 INSERT 时 PersistentItem 默认值用 placeholder

**对策**：每个 entity 维护一张**同步矩阵**，六列必填：

| Entity | push (upsert/delete) | pull (catchUp) | Realtime 订阅 | applyToLocal INSERT | applyToLocal UPDATE | tombstone / soft-delete |
|---|---|---|---|---|---|---|

每行必须 ✅ 或显式标 N/A 并写明原因。

---

### A4 · 字段同名异义

**症状**：不同概念用同一个参数名，调用层误传。

**这轮的实例**：`createInvite(displayName: String)` 接收的是邀请人的 USER 昵称，但被传给了 `createSpace(displayName: String)` —— 这里的 displayName 是 SPACE 名称。结果 `spaces.display_name = "猪皮小狗"`（用户昵称），iPad 拉到当成空间名显示。

**对策**：
- 跨语义边界的参数必须重命名：`createSpace(name: String)` 而非 `displayName`
- 同名参数若指代不同概念，加 `for` / `as` / 类型 wrapper 区分（如 `SpaceName(rawValue:)`）

---

### A5 · 获取-持有-释放锁的每条 return path 都要释放

**症状**：加了 `isXxx` 锁，但 early-return 路径漏掉释放，永久卡死。

**这轮的实例**：`push()` 加了 `isPushing` 序列化锁。但当 fetch 返回空时 `guard ... else { return }` 直接 return，没有 `isPushing = false`。**第一次启动 push 找不到 pending 就卡住，后续所有 push 永远被守卫挡掉**。

**对策**：
- Swift：用 `defer { finishXxx() }` 在函数顶部声明，编译器保证所有 return 都执行
- 或把清理代码封装成 helper（`finishPush()`），手工在每个 return 前调用一次
- 写个测试：调用 `func()` N 次，断言锁状态最终为 false

---

### A6 · Realtime 只订了"业务热表"，元数据表被遗忘

**症状**：下意识觉得 spaces / settings 这种"配置类"表不会动态变。

**这轮的实例**：tasks/task_lists/projects/periodic_tasks/space_members 五张表都订阅了 Realtime，**spaces 表没订阅** —— 对方改空间名只能等下次 app 启动 catchUp 才看到。

**对策**：
- 所有 push 写入的目标表必须有对应 Realtime 订阅，或在订阅代码处显式注释 N/A 并写理由
- 加表的 PR 模板里必须勾选"是否需要 Realtime 订阅"

---

### A7 · 跨设备调试反馈环路太长

**症状**：改一行代码 → 双端 rebuild → 双端 launch → 配对 → 复现 → 看 log → 改 → 重来，每轮 5-10 分钟。

**对策**：
- **先做客户端/服务端二分法再动客户端代码**：
  1. Supabase SQL 看表数据有没有变 → 排除 push 没发
  2. Supabase API logs 看请求 → 排除客户端没发
  3. Supabase Realtime logs 看 broadcast → 排除服务端没推
- 关键路径加诊断 logger（不是 print），用 `os.Logger` 保证物理设备上 Xcode 控制台一定能看到
- log 必须带 4 个上下文：kind / op / recordID / spaceID

---

### A8 · 硬编码"对方会有更好的值"

**症状**：DTO init 把某字段设为 nil / false，每次 push 都把远端的有效值抹掉。

**这轮的实例**：
- `TaskDTO.occurrenceCompletions = nil` —— 每次 push 抹掉对方设备上做的周期任务完成记录
- `TaskDTO.isDeleted = false` 硬编码 —— 已软删除的任务复活

**对策**：
- 对"本地无权威"字段：自定义 `encode(to:)` 用 `encodeIfPresent` 或直接跳过该 key
- 对软删除字段：从本地 tombstone state 派生（`isDeleted = persistent.isLocallyDeleted`）

---

### A9 · 身份体系互不认识

**症状**：用户本地 UUID / Supabase auth UID / membership.local_user_id / iCloud recordName，多套 ID 各自独立，跨边界时用 `UUID()` 占位。

**这轮的实例**：`CloudPairingService.checkAndFinalizeIfAccepted` 里 `let responderLocalID = UUID()` —— Device A 永远不知道 Device B 的真实本地 UUID，只能造个占位值。后续 partner profile 同步、历史配对查找都依赖这个占位值，潜在错乱。

**对策**：
- 在 `space_members` 表加 `local_user_id uuid` 列，配对双方各自把自己的本地 UUID 写进去
- 客户端拉到 partner 的 `local_user_id` 后用作可信标识，而非占位
- 每条跨设备记录必须明确 ID 来自哪个体系

---

## §3 正模式（Patterns）—— 直接复用

### P1 · Supabase MCP 三段式诊断

```
怀疑同步问题 →
  1. execute_sql 直接查目标表 —— 数据进没进去？updated_at 是不是新鲜？
  2. get_logs api —— 客户端有没有真的发出请求？status_code 多少？
  3. get_logs realtime + pg_replication_slots —— Realtime 有没有 broadcast？replication 健不健康？
```

**这轮的胜利**：靠这三段 SQL/log 查询，几分钟内就定位了 Bug A（spaces.display_name 是昵称）、Bug E（Realtime 服务一时连不上 + spaces 表未订阅），不用碰客户端代码。

---

### P2 · 诊断 logger 标配 4 个点

每条同步路径必须有：
- **submit 入口**：`[SharedMutation] submit kind= op= recordID= spaceID= supabaseService=`
- **push 前**：`[Push] queue size = N for space …` + `[Push] → tableName UPDATE/INSERT … WHERE …`
- **push 后**：`[Push] ✅ kind op recordID` 或 `[Push] ❌ error`
- **catchUp / pull**：`[Pull] ✅ 拉取 N 条 tableName` 或 `[Pull] ❌ error`

用 `os.Logger`（`Logger(subsystem: "com.pigdog.Together", category: "...")`）—— 物理设备上 `print()` 可能被 stdout 重定向丢掉，Logger 不会。

---

### P3 · 单一入口 `submitSharedMutation` 模式

```swift
private func submitSharedMutation(_ change: SyncChange) async {
    appContextLogger.info("[SharedMutation] submit ...")
    // recordLocalChange 已由 Repository 层做（Pattern P4），这里只触发 push
    await supabaseSyncService?.push()
    await refreshSharedSyncStatusAsync()
}
```

所有 partner-only 资源（avatar / nickname / space name / task message）变更**统一走这一个入口**。

---

### P4 · Repository save/delete + record + tombstone

```swift
func saveItem(_ item: Item) async throws -> Item {
    // ... 持久化 ...
    try context.save()
    if let sid = item.spaceID {
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .task, operation: .upsert, recordID: item.id, spaceID: sid)
        )
    }
    // ...
}

func deleteItem(itemID: UUID) async throws {
    // ... 找记录 ...
    record.isLocallyDeleted = true        // tombstone，不 hard delete
    record.updatedAt = .now
    try context.save()
    if let sid = spaceID {
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .task, operation: .delete, recordID: itemID, spaceID: sid)
        )
    }
}
```

`TaskListRepository / ProjectRepository / PeriodicTaskRepository` 必须按此结构审一遍（目前只 LocalItemRepository 改完了）。

---

### P5 · `isPushing + finishPush()` 锁结构

```swift
private var isPushing = false
private var pushRequestedDuringFlight = false

func push() async {
    guard let spaceID else { return }
    if isPushing {
        pushRequestedDuringFlight = true
        return
    }
    isPushing = true

    // ... 工作 ...
    guard !changes.isEmpty else {
        finishPush()      // 关键：每条 return 路径都要 finishPush
        return
    }
    // ... 更多工作 ...
    finishPush()
}

private func finishPush() {
    isPushing = false
    if pushRequestedDuringFlight {
        pushRequestedDuringFlight = false
        Task { [weak self] in await self?.push() }
    }
}
```

任何需要序列化的 actor 方法都套这个结构。

---

### P6 · DTO 三分支 applyToLocal

```swift
nonisolated func applyToLocal(context: ModelContext) {
    let descriptor = FetchDescriptor<PersistentXxx>(predicate: #Predicate { $0.id == id })
    if let existing = try? context.fetch(descriptor).first {
        // 分支 1：UPDATE
        if updatedAt < existing.updatedAt { return }   // P7 冲突保护
        // ... 字段映射 ...
        if isDeleted {
            existing.isLocallyDeleted = true            // 分支 3：tombstone
        }
    } else if !isDeleted {
        // 分支 2：INSERT
        let new = PersistentXxx(...)
        context.insert(new)
    }
    // 软删除 + 记录不存在的情况：不做任何事
}
```

每个 DTO 都必须三分支齐全 + 对应单测。

---

### P7 · `updatedAt` 冲突 guard

每个 DTO 的 UPDATE 分支首行：

```swift
if updatedAt < existing.updatedAt { return }
```

防止时钟漂移 / 网络乱序时旧版数据覆盖新版。SpaceDTO 因为 updatedAt 是可选要写 `if let incoming = updatedAt, incoming < existing.updatedAt { return }`。

---

### P8 · 测试三件套

每个新 entity 必须有：

1. **`<Entity>InsertTests`**（仿 `SyncInsertTests`）：DTO.applyToLocal 的 insert / update / tombstone 三个断言
2. **`<Entity>ConflictTests`**（仿 `SyncConflictTests`）：旧 DTO 不覆盖新本地的断言
3. **`<Entity>RepositorySyncTests`**（仿 `ItemRepositorySyncTests`）：save/delete 触发 recordLocalChange 的断言

测试用 `ModelContainer(... isStoredInMemoryOnly: true)` + 完整 schema graph（**注意**：缺一个 PersistentXxx 都会 `loadIssueModelContainer`），用 `SpyCoordinator` 验证 `recordLocalChange` 被正确调用。

---

## §4 新同步 Entity 接入清单（直接抄）

```
□ Supabase schema
  □ 表存在且字段全（对照 Persistent Model 比对一遍）
  □ RLS 至少 SELECT via is_space_member + ALL via is_space_member
  □ 如需 Realtime：ALTER PUBLICATION supabase_realtime ADD TABLE …
  □ 如有 space_id 列要 NOT NULL（除非 project_subtasks 那种特殊场景）
  □ updated_at 列有 trigger 自动维护

□ 客户端 DTO（A8）
  □ Encodable + Decodable + Sendable
  □ CodingKeys 全部 snake_case 映射
  □ "本地无权威"的字段用 encodeIfPresent 或自定义 encode 跳过
  □ init(from: Persistent, spaceID:) 签名一致

□ push 路径（A1, A2）
  □ pushUpsert 有对应 case，不能 break / 留空
  □ pushDelete 走 soft-delete（tombstone），不 hard delete
  □ Repository 层做 recordLocalChange（P4）
  □ 上层 ViewModel 不做 record，只 emit / 触发 push

□ pull 路径（A3）
  □ catchUp 里调用了 pull<Entity>
  □ pull<Entity> 用 space_id=eq 过滤（注意 spaces 表本身是 id=eq）
  □ 回写本地一次性 save
  □ Realtime 订阅这张表 + 路由到 handleRealtimeChange

□ applyToLocal（P6, P7）
  □ UPDATE 分支首行 updatedAt 冲突 guard
  □ UPDATE 分支尾部 isDeleted → tombstone 而非硬删
  □ INSERT 分支 !isDeleted 时创建，字段用 DTO 值非 placeholder
  □ @Model 必填字段全部从 DTO 派生（不要 latestResponseData = nil 之类的暴力默认）

□ 并发 / 回声（A5, P5）
  □ pushUpsert 成功后 recentlyPushedIDs[recordID] = now
  □ Realtime echo filter 自动跳过自己刚 push 的事件

□ 测试（P8）
  □ <Entity>InsertTests：insert / update / tombstone 三断言
  □ <Entity>ConflictTests：older_dto 不覆盖
  □ <Entity>RepositorySyncTests：save/delete 触发 record

□ 端到端验证（A7, P1, P2）
  □ iPhone 触发 → 看到 [SharedMutation submit] + [Push → X] + [Push ✅]
  □ Supabase SQL 查表，行确实更新 + updated_at 新鲜
  □ iPad 看到 [CatchUp ✅] / [Pull ✅] + UI 自动刷新
```

---

## §5 对下一步工作的具体映射

### 头像文件 → Supabase Storage（Plan B）

| 关注点 | 已预见的坑 | 复用 |
|---|---|---|
| `pushUpsert .avatarAsset: break` 是典型 A1（TODO 留白） | 直接实现 Storage 上传，不留 TODO | P3 / P4 / P8 |
| 上传后写 URL 回 `space_members.avatar_url` | A3：上传 + URL 写回 + 对方下载 + 缓存四步全做 | 接入清单 §4 |
| 删除头像时 Storage object 也要清理 | A8：避免硬编码 nil 抹掉远端 | P6 三分支 |

### 任务接受 / 拒绝 / 响应历史

| 关注点 | 已预见的坑 | 复用 |
|---|---|---|
| `respondToTask` 调用链里有没有 record？ | A2 | P4 审一遍 TaskApplicationService |
| `responseHistory` 字段已加，但 applyToLocal 是否完整 | A3 | P6 三分支 + 测试 |

### 任务消息 / 催促

| 关注点 | 已预见的坑 | 复用 |
|---|---|---|
| `task_messages` 表客户端从未写入 | A1 + A3 | 整套清单 §4 |
| `send-push-notification` Edge Function 期望事件源不存在 | A1 | P1 先用 SQL 验证表为空 |

### 纪念日（important_dates）

| 关注点 | 已预见的坑 | 复用 |
|---|---|---|
| `LocalServiceFactory` 用 `MockAnniversaryRepository` | A1 | 整套清单 §4 从 Schema 到测试走一遍 |

---

## §6 给下一轮 Plan B/C 的硬性要求

1. **开工前**先把 §4 清单作为 plan 的 verification checklist 贴进去
2. **每个新 entity** 的 commit 必须带对应 `<Entity>InsertTests` / `ConflictTests` / `RepositorySyncTests` 三组测试的绿灯
3. **双端端到端前**先 Supabase SQL 单端验证 —— 别再浪费双设备 rebuild 反馈环
4. **所有 "TODO" / "后续完善"** 一律改为失败测试或直接实现，禁止留言

---

## §7 元教训：Plan A 之外的 5 个 bug 是怎么冒出来的

| Bug | 类型 | 修复 commit | 元教训 |
|---|---|---|---|
| Realtime channel 缓存 → "Cannot add postgres_changes after subscribe()" | SDK 缓存机制误用 | `a0cb29e` | SDK 行为不能用直觉，必须读源码或测试 |
| `startSupabaseSyncIfNeeded` 竞态 → 重复订阅 | actor 之外的状态访问竞态 | `f396782` | `@MainActor` 类的状态字段也会因 await suspension 出现竞态，需要 `isStarting` 类二级守卫 |
| Bug A：昵称当空间名 | 字段同名异义（A4） | `4013566` | 跨语义参数必须重命名 |
| Bug C：CKSync 收到 pair 变更 | 路由层无差别转发 | `38a94a1` | 任何"扇出"都必须问"接收方该不该收" |
| Bug D：isPushing 永久泄漏 | 锁释放路径不全（A5） | `3054991` | `defer` 是好朋友 |
| Bug E：spaces 表订阅遗漏 | 元数据表被忽视（A6） | `73a2180` | 订阅清单要对照 push 目标表清点 |

5 个 bug 中，**4 个对应 §2 反模式表里能找到的条目**（A4/A5/A6 + actor 竞态扩展）。说明只要这套反模式清单内化，下次 Plan B 不会再冒类似的"5 个连环 bug"。

---

## 附录：关键文件路径

- 计划文档：`docs/superpowers/plans/2026-04-17-pair-sync-comprehensive-fix.md`
- 同步主体：`Together/Sync/SupabaseSyncService.swift`
- Repository 模板：`Together/Services/Items/LocalItemRepository.swift`（saveItem/deleteItem 是 P4 的标杆实现）
- AppContext：`Together/App/AppContext.swift`（submitSharedMutation 是 P3 的入口）
- 测试模板：`TogetherTests/SyncInsertTests.swift` / `SyncConflictTests.swift` / `ItemRepositorySyncTests.swift`
- Supabase migrations：`supabase/migrations/003_sync_completeness.sql`
