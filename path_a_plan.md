# Path A 实施计划：CloudKit 公共库简化双人同步

> 本文件是 Path A（CloudKit Public DB 轮询同步）的完整执行计划。
> 所有细节均来自多轮需求访谈和风险审计的共识结论。
> **本计划替代 `plans.md` 中 Milestone 01–08 的 CKSyncEngine 架构。**

---

## 一、架构总览

### 1.1 核心思路

**抛弃 CKSyncEngine + Private/Shared DB 方案，改用 CloudKit Public DB + CKQuery 轮询。**

理由：
- CKSyncEngine + sharedCloudDatabase 在 Apple 文档中几乎无案例，行为不可预测
- 8 个迭代 Milestone 未能稳定双人同步，根因是平台 API 组合本身不可靠
- Public DB + 轮询是经过行业验证的方案（OurGroceries 20s 轮询、百万用户）
- 当前零冲突权限设计（仅创建者编辑/删除、仅邀请者改名）使 Public DB 的"全可写"风险降到最低

### 1.2 数据库职责划分

| 数据库 | 用途 | 记录类型 |
|--------|------|----------|
| **Public DB** | 邀请发现 + 双人同步数据 | PairInvite, PairTask, PairTaskList, PairProject, PairProjectSubtask, PairPeriodicTask, PairSpace, PairMemberProfile, PairAvatarAsset |
| **Private DB** | 单人模式数据（现有 CKSyncEngine 保持不动） | solo zone 所有记录 |
| **Shared DB** | **不再使用** | — |

### 1.3 架构对比

```
当前架构（失败）：
  CKSyncEngine → Private DB (owner) / Shared DB (participant)
  → 推送驱动 + 5s 轮询兜底
  → 886 行 SyncEngineDelegate + 416 行 SyncEngineCoordinator
  → 实际同步在几分钟后停止

目标架构（Path A）：
  CKQuery → Public DB (双方写入同一空间)
  → 推送主驱动 + 自适应轮询兜底
  → 预估 ~400 行核心同步代码（PairSyncService）
  → 不依赖任何 CKSyncEngine API
```

### 1.4 同步数据流

```
本地修改 → 记录 PersistentSyncChange (pending)
         → PairSyncService.push()
         → CKModifyRecords(.changedKeys) → Public DB
         → 成功: confirmed / 失败: retry with serverRecord

远程变更 → CKQuerySubscription 静默推送 (主路径)
         → 或自适应轮询 (兜底路径)
         → PairSyncService.pull()
         → CKQuery(updatedAt > lastSync, spaceID == X)
         → 解码 → 检查本地 pending → 合并 → SwiftData
         → UI 刷新
```

---

## 二、CloudKit Dashboard 配置

### 2.1 新增记录类型

以下记录类型需在 CloudKit Dashboard **Development 环境**中创建，字段标记 `Q` = Queryable，`S` = Sortable，`Se` = Searchable：

#### PairTask（公共库任务记录）

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| spaceID | String | Q | 空间隔离键 |
| listID | String | — | 所属列表 |
| projectID | String | — | 所属项目 |
| creatorID | String | Q | 创建者 ID（权限校验） |
| title | String | Se | 任务标题 |
| notes | String | — | 备注 |
| locationText | String | — | 位置 |
| executionRole | String | — | 执行角色 |
| assigneeMode | String | — | 分配模式 |
| status | String | Q | 任务状态 |
| assignmentState | String | — | 分配生命周期 |
| dueAt | Date/Time | S | 截止时间 |
| hasExplicitTime | Int64 | — | 是否有明确时间 |
| remindAt | Date/Time | — | 提醒时间 |
| createdAt | Date/Time | S | 创建时间 |
| updatedAt | Date/Time | Q, S | 更新时间（增量同步关键） |
| completedAt | Date/Time | — | 完成时间 |
| isPinned | Int64 | — | 是否置顶 |
| isDraft | Int64 | — | 是否草稿 |
| isDeleted | Int64 | Q | **软删除标记** |
| deletedAt | Date/Time | — | 删除时间 |
| isArchived | Int64 | — | 是否归档 |
| archivedAt | Date/Time | — | 归档时间 |
| repeatRuleJSON | String | — | 重复规则 JSON |
| latestResponseJSON | String | — | 最新回复 JSON |
| responseHistoryJSON | String | — | 回复历史 JSON |
| assignmentMessagesJSON | String | — | 分配消息 JSON |
| lastActionByUserID | String | — | 最后操作者 |
| lastActionAt | Date/Time | — | 最后操作时间 |
| reminderRequestedAt | Date/Time | — | 提醒请求时间 |
| occurrenceCompletionsJSON | String | — | 周期完成记录 JSON |

#### PairTaskList

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| spaceID | String | Q | 空间隔离键 |
| name | String | — | 列表名称 |
| kind | String | — | 列表类型 |
| colorToken | String | — | 颜色标记 |
| sortOrder | Double | — | 排序 |
| creatorID | String | Q | 创建者 |
| isDeleted | Int64 | Q | 软删除 |
| deletedAt | Date/Time | — | 删除时间 |
| isArchived | Int64 | — | 是否归档 |
| createdAt | Date/Time | S | 创建时间 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

#### PairProject

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| spaceID | String | Q | 空间隔离键 |
| name | String | — | 项目名 |
| notes | String | — | 说明 |
| colorToken | String | — | 颜色 |
| status | String | — | 状态 |
| targetDate | Date/Time | — | 目标日期 |
| remindAt | Date/Time | — | 提醒 |
| creatorID | String | Q | 创建者 |
| isDeleted | Int64 | Q | 软删除 |
| deletedAt | Date/Time | — | 删除时间 |
| createdAt | Date/Time | S | 创建时间 |
| updatedAt | Date/Time | Q, S | 增量同步键 |
| completedAt | Date/Time | — | 完成时间 |

#### PairProjectSubtask

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| projectID | String | Q | 父项目 |
| spaceID | String | Q | 空间隔离键 |
| title | String | — | 子任务标题 |
| isCompleted | Int64 | — | 是否完成 |
| sortOrder | Int64 | — | 排序 |
| creatorID | String | — | 创建者 |
| isDeleted | Int64 | Q | 软删除 |
| deletedAt | Date/Time | — | 删除时间 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

#### PairPeriodicTask

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| spaceID | String | Q | 空间隔离键 |
| creatorID | String | Q | 创建者 |
| title | String | — | 名称 |
| notes | String | — | 说明 |
| cycle | String | — | 周期类型 |
| reminderRulesJSON | String | — | 提醒规则 JSON |
| completionsJSON | String | — | 完成记录 JSON |
| sortOrder | Double | — | 排序 |
| isActive | Int64 | — | 是否启用 |
| isDeleted | Int64 | Q | 软删除 |
| deletedAt | Date/Time | — | 删除时间 |
| createdAt | Date/Time | S | 创建时间 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

#### PairSpace（共享空间元数据）

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| spaceID | String | Q | 空间 ID（也是 recordName） |
| displayName | String | — | 空间显示名 |
| ownerUserID | String | Q | 邀请方 ID（仅此人可改名） |
| status | String | — | 空间状态 |
| createdAt | Date/Time | — | 创建时间 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

#### PairMemberProfile

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| userID | String | Q | 用户 ID |
| spaceID | String | Q | 空间隔离键 |
| displayName | String | — | 昵称 |
| avatarSystemName | String | — | SF Symbol 名 |
| avatarAssetID | String | — | 头像资产 ID |
| avatarVersion | Int64 | — | 头像版本号 |
| avatarDeleted | Int64 | — | 头像是否被删 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

#### PairAvatarAsset

| 字段名 | 类型 | 索引 | 说明 |
|--------|------|------|------|
| assetID | String | Q | 资产 ID（recordName） |
| spaceID | String | Q | 空间隔离键 |
| version | Int64 | — | 版本号 |
| fileName | String | — | 文件名 |
| avatarData | Asset | — | CKAsset 头像二进制 |
| updatedAt | Date/Time | Q, S | 增量同步键 |

### 2.2 索引配置

每个记录类型必须配置以下复合查询能力（CloudKit Dashboard → Indexes）：

**必须的查询模式（所有 Pair* 记录类型通用）：**
- `spaceID == X AND updatedAt > Y` — 增量拉取
- `spaceID == X AND isDeleted == 0` — 活跃记录
- `spaceID == X` — 全量拉取

**PairTask 额外查询：**
- `spaceID == X AND creatorID == Y` — 创建者筛选
- `spaceID == X AND status == Z` — 状态筛选

**PairInvite 查询（已有）：**
- `inviteCode == X AND status == "pending"` — 邀请码查找

### 2.3 Security Roles 配置

CloudKit Dashboard → Security Roles → Public Database:

| 记录类型 | World (未登录) | Authenticated (已登录) |
|----------|---------------|----------------------|
| PairInvite | Read | Read, Write, Create |
| PairTask | — | Read, Write, Create |
| PairTaskList | — | Read, Write, Create |
| PairProject | — | Read, Write, Create |
| PairProjectSubtask | — | Read, Write, Create |
| PairPeriodicTask | — | Read, Write, Create |
| PairSpace | — | Read, Write, Create |
| PairMemberProfile | — | Read, Write, Create |
| PairAvatarAsset | — | Read, Write, Create |

> ⚠️ **Public DB 所有已登录 iCloud 用户都能读写任何记录。** 安全性依赖于 spaceID 隔离 + 8 位邀请码的不可猜测性 + 客户端权限校验。详见第八节权限规则。

### 2.4 环境配置

1. 在 **Development** 环境配置所有记录类型和索引
2. 使用 TestFlight 验证通过后，在 Dashboard 点击 **Deploy to Production**
3. Production 部署后记录类型不可删除字段、不可重命名，只能新增

---

## 三、核心组件设计

### 3.1 PairSyncService — 新的双人同步核心（~300-400 行）

```
文件: Together/Sync/PairSyncService.swift
类型: actor PairSyncService
职责: 双人模式的全部 push/pull 逻辑
```

**核心方法：**

```swift
actor PairSyncService {
    // 配置
    func configure(spaceID: UUID, myUserID: UUID)
    func teardown()
    
    // 推送本地变更到 Public DB
    func push(changes: [SyncChange]) async throws -> PushResult
    
    // 从 Public DB 拉取远程变更
    func pull() async throws -> PullResult
    
    // 单次完整同步周期（push + pull）
    func syncOnce() async throws
}
```

**推送 (push) 流程：**

1. 从 `PersistentSyncChange` 读取所有 `pending` 状态的变更
2. 按 `entityKind` 分组，用对应 Codec 编码为 `CKRecord`
3. 调用 `CKDatabase.modifyRecords(saving:deleting:savePolicy:.changedKeys)`
4. 成功 → 标记 `confirmed`
5. 失败 → 检查错误类型：
   - `serverRecordChanged` → 提取 serverRecord，重新应用本地字段，重试一次
   - `rateLimited` → 读取 `CKErrorRetryAfterKey`，延迟重试
   - 其他 → 标记 `failed`，记录错误信息

**拉取 (pull) 流程：**

1. 读取上次同步时间 `lastPullDate`（存于 `PersistentSyncState`）
2. 构造查询：`spaceID == X AND updatedAt > (lastPullDate - 2s)`（2 秒重叠窗口防遗漏）
3. 执行 `CKQuery` + 分页 (`CKQueryOperation.Cursor`)
4. 解码每条记录 → 检查本地 `PersistentSyncChange` 是否有 pending/sending 状态
5. 若本地有 pending → 跳过该记录（保护本地未确认的修改）
6. 若本地无 pending → 合并到 SwiftData
7. 处理软删除：`isDeleted == true` → 归档本地对应记录
8. 更新 `lastPullDate` 为当前时间

### 3.2 PairSyncPoller — 自适应轮询调度器

```
文件: Together/Sync/PairSyncPoller.swift
类型: @MainActor @Observable class PairSyncPoller
职责: 管理轮询生命周期和自适应间隔
```

**自适应轮询策略：**

```
初始间隔: 5 秒
连续无变更 3 次后: 15 秒
连续无变更 6 次后: 30 秒
检测到变更时: 立即回到 5 秒
收到推送通知时: 立即触发 + 重置为 5 秒
App 进入前台: 立即触发 + 重置为 5 秒
App 进入后台: 停止轮询（iOS 不允许持续后台网络）
连续失败时: 指数退避，最大 120 秒
```

**关键设计：轮询不会自毁**

当前代码的致命 bug 是 `reloadAfterSync()` 可能使 `pairSpaceSummary` 暂时为 nil，导致 `updateSyncPolling()` 停止轮询。新设计中：

- `PairSyncPoller` 持有 `spaceID`，而非依赖 `pairSpaceSummary`
- 只有显式调用 `stop()` 才会停止轮询
- `syncOnce()` 中的任何错误不会触发停止，只会触发退避
- 瞬态的 SwiftData 查询结果不影响轮询决策

```swift
@MainActor @Observable
class PairSyncPoller {
    private(set) var isActive = false
    private(set) var currentInterval: TimeInterval = 5
    private(set) var consecutiveNoChange = 0
    private(set) var consecutiveFailures = 0
    
    func start(spaceID: UUID) { ... }  // 开始轮询
    func stop() { ... }                 // 显式停止
    func nudge() { ... }                // 推送/前台触发立即同步 + 重置间隔
    
    // 内部: 根据 syncOnce() 结果调整间隔
    private func adjustInterval(hasChanges: Bool, didFail: Bool) { ... }
}
```

### 3.3 PairSyncCodecRegistry — 公共库编解码注册表

```
文件: Together/Sync/Codecs/PairSyncCodecRegistry.swift
类型: struct PairSyncCodecRegistry: Sendable
职责: 为公共库记录类型提供编解码映射
```

**复用策略：**

现有 `RecordCodecRegistry` 和 8 个 `*RecordCodable` 文件是为 CKSyncEngine 的 Private/Shared zone 设计的。它们编码/解码的逻辑可以**大部分复用**，但需要调整：

1. **记录类型名称不同**：CKSyncEngine 用 `"Task"`, `"TaskList"` 等，公共库需要用 `"PairTask"`, `"PairTaskList"` 等前缀（避免和已有公共库 `"Task"` 记录冲突）
2. **Zone ID 不同**：公共库只有 default zone，编码时不传 zoneID
3. **新增 `isDeleted/deletedAt` 字段**：公共库不支持真删除，所有 codec 需要支持软删除
4. **新增 `creatorID` 字段**：部分记录类型需要新增创建者字段用于权限校验

**实现方式**：在现有 Codec 基础上新增一个 `PairSyncCodecRegistry`，内部创建新的 `PairTaskRecordCodec`、`PairTaskListRecordCodec` 等，复用字段映射逻辑但使用不同的 recordType 名称和 default zone。

### 3.4 推送通知设计

#### CKQuerySubscription（静默推送 — 主同步驱动）

```swift
// 为每个 Pair* 记录类型创建订阅
// 谓词: spaceID == <pairSpaceID>
// 通知: shouldSendContentAvailable = true（静默推送）
// 订阅 ID: "pair-<recordType>-<spaceID>"

let subscription = CKQuerySubscription(
    recordType: "PairTask",
    predicate: NSPredicate(format: "spaceID == %@", spaceID.uuidString),
    subscriptionID: "pair-PairTask-\(spaceID.uuidString)",
    options: [.firesOnRecordCreation, .firesOnRecordUpdate]
)
let info = CKSubscription.NotificationInfo()
info.shouldSendContentAvailable = true  // 静默推送
subscription.notificationInfo = info
```

**订阅的记录类型（优先级）：**

| 记录类型 | 订阅 | 原因 |
|----------|------|------|
| PairTask | ✅ 必须 | 最高频变更 |
| PairTaskList | ✅ 必须 | 列表增删 |
| PairProject | ✅ 必须 | 项目变更 |
| PairSpace | ✅ 必须 | 空间改名 |
| PairMemberProfile | ✅ 必须 | 昵称/头像变更 |
| PairProjectSubtask | ⚡ 可选 | 可由 Project 订阅间接驱动 |
| PairPeriodicTask | ✅ 必须 | 周期任务变更 |
| PairAvatarAsset | ⚡ 可选 | 可由 MemberProfile 订阅间接驱动 |

#### 可见 APNs 推送（重要事件 — 用户感知）

对于**伙伴向你分配了新任务**、**伙伴完成了你分配的任务**等重要事件，使用可见推送（CKQuerySubscription + alertBody）：

```swift
let info = CKSubscription.NotificationInfo()
info.shouldSendContentAvailable = true
info.alertBody = "你的伙伴分配了新任务"  // 可见通知
info.soundName = "default"
info.shouldBadge = true
```

> ⚠️ 可见推送更可靠（即使 App 被强制退出也能送达），但频率需要控制，避免通知轰炸。仅对「分配新任务」和「完成你的任务」使用可见推送。

#### handleCloudKitNotification 修复

```swift
// 当前是 NO-OP，必须修复为：
func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async {
    // 1. 验证是 CloudKit 通知
    guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
          notification.subscriptionID?.hasPrefix("pair-") == true
    else { return }
    
    // 2. 立即触发同步
    pairSyncPoller.nudge()
}
```

---

## 四、Codec 设计

### 4.1 已有 Codec（可复用的编码逻辑）

以下现有 Codec 的**字段映射逻辑**可直接复用：

| 现有文件 | 复用方式 |
|----------|----------|
| `ItemRecordCodable.swift` | 字段映射逻辑 → `PairTaskRecordCodec` |
| `TaskListRecordCodable.swift` | 字段映射逻辑 → `PairTaskListRecordCodec` |
| `ProjectRecordCodable.swift` | 字段映射逻辑 → `PairProjectRecordCodec` |
| `ProjectSubtaskRecordCodable.swift` | 字段映射逻辑 → `PairProjectSubtaskRecordCodec` |
| `PeriodicTaskRecordCodable.swift` | 字段映射逻辑 → `PairPeriodicTaskRecordCodec` |
| `SpaceRecordCodable.swift` | 字段映射逻辑 → `PairSpaceRecordCodec` |
| `MemberProfileRecordCodable.swift` | 字段映射逻辑 → `PairMemberProfileRecordCodec` |
| `AvatarAssetRecordCodable.swift` | 字段映射逻辑 → `PairAvatarAssetRecordCodec` |

### 4.2 新增 Codec 的共同差异

所有 `Pair*RecordCodec` 相对于原 Codec 的统一差异：

1. **recordType 前缀 `"Pair"`**：`"PairTask"` 而非 `"Task"`
2. **无 zoneID 参数**：公共库只有 default zone
3. **recordName 使用 UUID**：`CKRecord.ID(recordName: entity.id.uuidString)`
4. **新增 `isDeleted` / `deletedAt` 编解码**
5. **新增 `creatorID` 字段**（Task/TaskList/Project/PeriodicTask）

### 4.3 Codec 编码示例（PairTaskRecordCodec）

```swift
struct PairTaskRecordCodec {
    static let recordType = "PairTask"
    
    static func encode(_ item: Item) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["spaceID"] = item.spaceID?.uuidString
        record["creatorID"] = item.creatorID.uuidString
        record["title"] = item.title
        // ... 其余字段与 CloudKitTaskRecordCodec.populateRecord 相同 ...
        record["isDeleted"] = (item.isArchived && item.archivedAt != nil) ? 1 : 0
        record["deletedAt"] = item.archivedAt
        record["updatedAt"] = item.updatedAt
        return record
    }
    
    static func decode(_ record: CKRecord) -> Item { ... }
}
```

### 4.4 CKAsset 处理（PairAvatarAsset）

头像二进制通过 `CKAsset` 传输：

```swift
// 编码
let tempURL = FileManager.default.temporaryDirectory.appending(path: "\(assetID).jpg")
try data.write(to: tempURL)
record["avatarData"] = CKAsset(fileURL: tempURL)

// 解码
if let asset = record["avatarData"] as? CKAsset,
   let fileURL = asset.fileURL,
   let data = try? Data(contentsOf: fileURL) {
    // 写入本地缓存: Documents/Together/Avatars/asset-{assetID}.jpg
}
```

---

## 五、serverRecordChanged 冲突处理

### 5.1 冲突场景

零冲突设计下，理论上不会有两个用户同时写同一条记录的同一字段。但以下场景仍可能触发 `serverRecordChanged`：

1. **同一用户多设备**：iPhone 和 iPad 同时修改同一条记录
2. **快速连续操作**：修改后立即又修改，第一次 push 还未确认时第二次 push 已发出
3. **极罕见竞态**：两人在极短时间窗口内操作同一记录的不同字段

### 5.2 处理策略

```swift
func handleServerRecordChanged(
    clientRecord: CKRecord,
    serverRecord: CKRecord
) -> CKRecord {
    // 策略: 在 serverRecord 基础上重新应用本地变更字段
    // 因为使用 .changedKeys，CloudKit 只发送了本地变更的字段
    // serverRecord 包含了服务器最新的完整状态
    
    // 重新应用本地变更到 serverRecord 上
    for key in clientRecord.changedKeys() {
        serverRecord[key] = clientRecord[key]
    }
    return serverRecord
    // 调用方用 serverRecord 重试一次 modifyRecords
}
```

### 5.3 重试逻辑

```
第一次 push 失败 (serverRecordChanged)
→ 提取 serverRecord
→ 合并本地变更
→ 重试 push（第二次）
→ 若再次失败 → 标记 failed，下次 sync 周期重试
→ 连续 3 次失败 → 记录错误，等待人工干预或下次拉取覆盖
```

---

## 六、软删除机制

### 6.1 为什么需要软删除

CloudKit Public DB **不能通过 CKQuery 检测到已删除的记录**。如果直接删除记录，另一台设备永远不知道这条记录已被删除。

### 6.2 软删除流程

**删除操作（本地）：**

```
用户删除任务 →
  1. 本地 SwiftData: 设置 isArchived = true, archivedAt = now
  2. 本地 PersistentSyncChange: 记录 .archive 操作
  3. push: 更新 CKRecord 的 isDeleted = 1, deletedAt = now, updatedAt = now
```

**远程应用（拉取）：**

```
拉取到 isDeleted == 1 的记录 →
  1. 查找本地对应记录
  2. 设置 isArchived = true
  3. 从 UI 列表中移除
```

### 6.3 软删除记录清理

软删除记录会在公共库中累积。清理策略：

- **短期（0-3K 用户）**：不主动清理，每次拉取都带 `isDeleted == 0` 条件过滤
- **中期**：App 端定期发起清理请求，删除 30 天前的 `isDeleted == 1` 记录
- **长期**：迁移到自建后端后由服务器端 cron 处理

**拉取查询优化：**

```swift
// 增量拉取: 获取所有变更（包含删除的）
let predicate = NSPredicate(
    format: "spaceID == %@ AND updatedAt > %@",
    spaceID.uuidString, safeDate
)

// 全量拉取: 只获取活跃记录
let predicate = NSPredicate(
    format: "spaceID == %@ AND isDeleted == 0",
    spaceID.uuidString
)
```

---

## 七、邀请码流程

### 7.1 保留现有机制

`CloudKitInviteGateway` 已经在公共库上运行良好，**完全保留**。

### 7.2 邀请码规格（确认）

- **格式**: 8 位字母数字（大写 + 数字，排除易混淆字符 0/O/1/I/L）
- **有效期**: 3 分钟
- **一次性**: 接受后 status 变为 "accepted"
- **严格 1:1**: 一个空间最多两个成员

### 7.3 邀请流程（调整后）

```
设备 A（邀请方）:
  1. 创建 PairSpace (本地, status = pendingAcceptance)
  2. 创建 PairSpace 对应的 Space (本地)
  3. 生成 8 位邀请码
  4. 写入 PairInvite 记录到公共库 (status = "pending")
  5. 展示邀请码给用户
  6. 开始轮询 PairInvite 状态

设备 B（接受方）:
  1. 输入邀请码
  2. 查询公共库: inviteCode == X AND status == "pending"
  3. 校验未过期
  4. 更新 PairInvite: status = "accepted", responderUserUUID = Y
  5. 本地创建 PairSpace + Space（使用邀请中的 pairSpaceID + sharedSpaceID）
  6. 写入 PairMemberProfile 到公共库（自己的资料）
  7. 开始双人同步

设备 A（检测到接受）:
  1. 轮询发现 status == "accepted"
  2. 本地更新 PairSpace: status = active, memberB = 接受方信息
  3. 写入 PairMemberProfile 到公共库（自己的资料）
  4. 写入 PairSpace 到公共库
  5. 推送现有本地任务到公共库
  6. 开始双人同步
```

### 7.4 关键变更：不再创建 CKShare

旧流程中设备 A 创建 CKShare URL 并写入 PairInvite。新流程中：
- 不再创建 CKShare（不再使用 Shared DB）
- `CloudKitInviteGateway.publishInvite()` 中的 `shareURL` 参数传 nil
- `CloudKitShareManager` 不再需要

---

## 八、权限规则（零冲突设计）

### 8.1 权限矩阵

| 操作 | 创建者 | 另一方 |
|------|--------|--------|
| 编辑任务（标题/备注/时间等） | ✅ | ❌ |
| 删除任务 | ✅ | ❌ |
| 接受/拒绝/完成任务 | ❌ | ✅（被分配者） |
| 创建任务 | ✅ | ✅ |
| 编辑任务列表名称 | ✅（列表创建者） | ❌ |
| 删除任务列表 | ✅（列表创建者） | ❌ |
| 创建任务列表 | ✅ | ✅ |
| 修改空间名称 | ✅（邀请方/空间创建者） | ❌ |
| 编辑项目 | ✅（项目创建者） | ❌ |
| 删除项目 | ✅（项目创建者） | ❌ |
| 修改自己昵称/头像 | ✅（本人） | ❌ |
| 解除配对 | ✅ | ✅ |

### 8.2 客户端校验实现

```swift
// 通用权限校验
func canEdit(record: any PairSyncRecord, currentUserID: UUID) -> Bool {
    record.creatorID == currentUserID
}

func canDelete(record: any PairSyncRecord, currentUserID: UUID) -> Bool {
    record.creatorID == currentUserID
}

func canRenameSpace(space: PairSpace, currentUserID: UUID) -> Bool {
    space.ownerUserID == currentUserID  // 邀请方
}
```

### 8.3 服务端不校验的风险与缓解

Public DB 无法设置字段级权限。任何已登录 iCloud 用户理论上都能写入任何记录。

**风险评级: 🔴 红色（已知限制）**

**缓解措施：**
1. spaceID 是 UUID（128 位），不可猜测
2. 邀请码 8 位字母数字 + 3 分钟过期 + 一次性使用
3. 只有知道 spaceID 的人才能写入该空间的记录
4. 客户端拉取时可以校验 `creatorID`，忽略不合法的修改
5. **接受方案**：对于 1:1 双人场景（0-3K 用户），此风险可接受
6. **扩展方案**：达到 3K+ 用户后迁移到 Supabase 时实现服务端权限校验

---

## 九、数据迁移策略

### 9.1 方案选择：强制重新配对

**不做数据迁移。** 升级后：
1. 自动解绑旧配对关系
2. 清理所有旧的 CKSyncEngine 状态（PersistentSyncState、PersistentSyncChange 中 pair zone 数据）
3. 保留单人模式数据不变
4. 用户需要重新发送邀请码配对
5. 配对后，双方的本地双人任务数据推送到公共库

**理由：**
- 旧架构数据在 Private/Shared DB，新架构在 Public DB，无法跨库迁移
- 强制重新配对是最简单、最可靠的方式
- 用户只有 2 人，重新配对成本极低（1 分钟）
- 旧的本地双人任务可以保留并在重新配对后推送到新的公共库空间

### 9.2 升级流程

```swift
func migrateFromCKSyncEngineToPublicDB() async {
    // 1. 停止所有 pair CKSyncEngine 实例
    await syncEngineCoordinator.stopAllPairSync()
    
    // 2. 清理旧的 pair zone 同步状态
    // 保留 PersistentSyncState 中 solo zone 的状态
    // 删除所有 pair-* zone 的状态
    
    // 3. 保留本地双人任务数据（PersistentItem 等）
    // 这些数据在重新配对后会被推送到公共库
    
    // 4. 标记旧配对为已结束
    // PairSpace.status = .ended
    
    // 5. 设置迁移标记
    UserDefaults.standard.set(true, forKey: "migration.v3.publicDB.completed")
}
```

### 9.3 重新配对后的数据推送

```
重新配对完成后 →
  1. 遍历本地所有 spaceID == 旧双人空间ID 的数据
  2. 更新 spaceID 为新的双人空间 ID
  3. 标记所有记录为 PersistentSyncChange(pending)
  4. PairSyncService.push() 批量推送到公共库
```

---

## 十、文件变更清单

### 10.1 新增文件

| 文件路径 | 职责 | 预估行数 |
|----------|------|----------|
| `Sync/PairSyncService.swift` | 公共库双人同步核心 (push + pull) | ~300 |
| `Sync/PairSyncPoller.swift` | 自适应轮询调度器 | ~100 |
| `Sync/Codecs/PairTaskRecordCodec.swift` | 公共库任务编解码 | ~120 |
| `Sync/Codecs/PairTaskListRecordCodec.swift` | 公共库任务列表编解码 | ~60 |
| `Sync/Codecs/PairProjectRecordCodec.swift` | 公共库项目编解码 | ~70 |
| `Sync/Codecs/PairProjectSubtaskRecordCodec.swift` | 公共库子任务编解码 | ~50 |
| `Sync/Codecs/PairPeriodicTaskRecordCodec.swift` | 公共库周期任务编解码 | ~70 |
| `Sync/Codecs/PairSpaceRecordCodec.swift` | 公共库空间元数据编解码 | ~50 |
| `Sync/Codecs/PairMemberProfileRecordCodec.swift` | 公共库成员资料编解码 | ~50 |
| `Sync/Codecs/PairAvatarAssetRecordCodec.swift` | 公共库头像资产编解码 | ~60 |
| `Sync/Codecs/PairSyncCodecRegistry.swift` | 公共库编解码注册表 | ~40 |

**合计新增: ~970 行**

### 10.2 重大修改文件

| 文件路径 | 改动内容 |
|----------|----------|
| `App/AppContext.swift` | 替换 `startPairSyncEngineIfNeeded()` → 启动 `PairSyncService` + `PairSyncPoller`；修复 `handleCloudKitNotification`；删除 `updateSyncPolling()` 中的自毁逻辑；删除 pair CKSyncEngine 相关回调 |
| `App/AppDelegate.swift` | `didReceiveRemoteNotification` 调用修复后的 `handleCloudKitNotification` |
| `Sync/CloudKitSubscriptionManager.swift` | 改为订阅公共库 Pair* 记录类型（不再订阅错误的数据库） |
| `Sync/SyncCoordinatorProtocol.swift` | 可能微调，保留 `SyncChange`/`SyncMutationLifecycleState` 等类型 |
| `Services/Pairing/LocalPairingService.swift` | `setupPairingFromRemote` / `finalizeAcceptedInvite` 不再调用 CKShare 相关逻辑 |

### 10.3 可删除文件/代码块

| 文件/代码 | 原因 |
|-----------|------|
| `Sync/CloudKitShareManager.swift` | 不再使用 CKShare |
| `Sync/CloudKitZoneManager.swift` | 不再管理自定义 zone（公共库只有 default zone） |
| `Sync/Engine/PairSyncBridge.swift` | CKSyncEngine pair bridge 不再需要 |
| `Sync/Engine/SyncMigrationService.swift` | Public→Private 迁移不再需要 |
| `Sync/Engine/SyncEngineCoordinator.swift` 中 pair 相关方法 | `startPairSync`/`stopPairSync`/`teardownPairSync`/`fetchPairChanges`/`sendPairChanges` 等 |
| `Sync/Engine/SyncEngineDelegate.swift` 中 pair 相关 apply 逻辑 | pair zone 的 entity apply 由 `PairSyncService` 接管 |
| `App/AppContext.swift` 中 ~150 行 pair CKSyncEngine 代码 | `startPairSyncEngineIfNeeded`/`ensurePairSyncPolling`/`stopPairSyncPolling`/pair 回调 |
| `Sync/CloudKitProfileRecordCodec.swift` | 已删除（v2.1 已完成） |

### 10.4 保留不动的文件

| 文件/模块 | 原因 |
|-----------|------|
| `Sync/Engine/SyncEngineCoordinator.swift` (solo 部分) | 单人模式 CKSyncEngine 继续使用 |
| `Sync/Engine/SyncEngineDelegate.swift` (solo 部分) | 单人模式 delegate 继续使用 |
| `Sync/Engine/RecordCodecRegistry.swift` | solo zone 的 codec 注册表继续使用 |
| 所有现有 `*RecordCodable.swift` | solo zone 编解码继续使用 |
| `Sync/CloudKitInviteGateway.swift` | 邀请码机制完全保留 |
| `Sync/CloudKitSyncGateway.swift` | 作为参考，新 PairSyncService 可参考其 push/pull 模式 |
| `Sync/SyncScheduler.swift` | 重新评估后可参考其退避逻辑 |
| 所有 `Services/` 下的文件 | 服务层不变，sync 层变更对其透明 |
| 所有 `Domain/` 下的文件 | 领域模型不变 |
| 所有 `Features/` 下的文件 | UI 层通过 `SessionStore` / `SharedSyncStatus` 间接感知变化 |

---

## 十一、风险缓解措施

### 11.1 红色风险（必须解决）

#### R1: 公共库写权限（安全性）

- **风险**：任何登录 iCloud 的用户都能写入任何公共库记录
- **缓解**：
  - spaceID 为 UUID (128 位)，不可猜测
  - 客户端拉取时校验 `creatorID`，丢弃非法修改
  - 邀请码 8 位 + 3 分钟过期 + 一次性
  - 0-3K 用户规模下可接受

#### R2: 缺失的实体 Codec

- **风险**：当前公共库只有 `CloudKitTaskRecordCodec`，其余 7 种实体类型没有公共库 Codec
- **缓解**：
  - 本计划第四节详细设计了所有 8 种 Codec
  - 每种 Codec 基于已有的 Private zone Codec 调整，逻辑经过验证
  - 分批实现，先 Task → TaskList → Project → 其余

#### R3: serverRecordChanged 处理

- **风险**：当前代码中 `CloudKitSyncGateway.push()` 对 save 失败直接 throw，没有冲突重试
- **缓解**：
  - 本计划第五节设计了完整的冲突处理策略
  - 利用 `.changedKeys` + serverRecord 合并 + 单次重试
  - 零冲突设计确保真正的字段冲突极为罕见

### 11.2 黄色风险（需要关注）

#### Y1: 数据迁移（用户体验）

- **风险**：强制重新配对可能引发用户不满
- **缓解**：
  - 明确告知用户升级内容和原因
  - 保留本地双人任务，重新配对后自动推送
  - 整个过程 < 1 分钟

#### Y2: 头像配额（CKAsset 大小）

- **风险**：公共库 CKAsset 有大小限制（250 MB 每用户）
- **缓解**：
  - 头像压缩到 500KB 以内（JPEG quality 0.7）
  - 一个空间最多 2 个用户，头像总量 < 1MB
  - 旧头像不累积（每次更新覆盖同一 recordName）

#### Y3: 多设备同步

- **风险**：同一用户在 iPhone + iPad 上同时操作
- **缓解**：
  - `serverRecordChanged` 处理（第五节）
  - `.changedKeys` 字段级合并天然支持
  - 最终一致性在 5-30 秒内收敛

#### Y4: 邀请码原子性

- **风险**：两人同时输入同一邀请码可能导致竞态
- **缓解**：
  - 已有 fetch-then-save 模式（`CloudKitInviteGateway` 第 147-152 行）
  - `serverRecordChanged` 时只接受第一个 responder
  - 客户端校验 responderUserUUID 是否为自己

#### Y5: 软删除记录累积

- **风险**：公共库中 `isDeleted == 1` 记录持续增长
- **缓解**：
  - 增量拉取包含删除记录（用于同步删除状态）
  - 全量拉取过滤删除记录（`isDeleted == 0`）
  - 月度 App 端清理 30 天前的软删除记录
  - 0-3K 用户规模下增长极慢（每对用户/天 < 100 条删除）

#### Y6: 时钟偏移

- **风险**：两台设备系统时钟不一致导致 `updatedAt` 比较不准
- **缓解**：
  - 2 秒重叠窗口（第三节 pull 流程）
  - 零冲突设计下不依赖时间戳做冲突仲裁
  - `updatedAt` 仅用于增量拉取的范围过滤

### 11.3 绿色风险（已缓解）

| 风险 | 缓解 |
|------|------|
| GCBD（中国贵州云）延迟 | 自适应轮询自动适应网络条件 |
| iOS 后台限制 | 进入后台停止轮询，前台恢复；重要事件用可见推送 |
| CKQuerySubscription 丢失 | 轮询兜底确保最终收到变更 |
| 单人模式受影响 | solo CKSyncEngine 完全不动 |
| 公共库限流 | 自适应轮询 + `rateLimited` 错误处理 + 退避 |
| App 被强制退出 | 可见推送仍可送达；下次打开时全量同步 |
| 网络断开 | 本地操作正常，pending 队列持久化，恢复后自动推送 |

---

## 十二、实施里程碑

### Milestone A1: 基础设施（预估 1-2 天）

**范围：**
- 创建 `PairSyncService`（push + pull 骨架）
- 创建 `PairSyncPoller`（自适应轮询）
- 创建 `PairSyncCodecRegistry` + `PairTaskRecordCodec`（先支持 Task）
- 在 CloudKit Dashboard 创建 `PairTask` 记录类型 + 索引

**验收标准：**
- 能够将一条本地双人任务推送到公共库并在另一台设备拉取到
- 自适应轮询能正常启停和调速
- 构建通过：`xcodebuild build`

**关键文件：**
- 新建: `Sync/PairSyncService.swift`, `Sync/PairSyncPoller.swift`, `Sync/Codecs/PairTaskRecordCodec.swift`, `Sync/Codecs/PairSyncCodecRegistry.swift`
- 修改: `App/AppContext.swift`（接入新 service）

### Milestone A2: 完整实体同步（预估 2-3 天）

**范围：**
- 创建剩余 7 种 Pair* Codec
- 在 CloudKit Dashboard 创建对应记录类型
- PairSyncService 支持所有实体类型的 push/pull
- 软删除机制

**验收标准：**
- 任务、任务列表、项目、子任务、周期任务、空间、成员资料、头像均能双向同步
- 软删除在对方设备正确归档
- 构建 + 测试通过

**关键文件：**
- 新建: 7 个 `PairXxxRecordCodec.swift`
- 修改: `PairSyncService.swift`（支持全实体 push/pull）

### Milestone A3: 通知与恢复（预估 1-2 天）

**范围：**
- 修复 `handleCloudKitNotification`（从 NO-OP 变为触发 nudge）
- 改造 `CloudKitSubscriptionManager`（订阅公共库 Pair* 记录）
- serverRecordChanged 冲突处理
- push 失败重试逻辑
- 可见推送（分配新任务 / 完成任务）

**验收标准：**
- 对方修改后 1-2 秒内本地收到变更（推送路径）
- 推送不可用时，轮询兜底在 5-30 秒内收到变更
- 冲突场景不丢数据
- 构建 + 测试通过

**关键文件：**
- 修改: `App/AppContext.swift`, `App/AppDelegate.swift`, `Sync/CloudKitSubscriptionManager.swift`
- 修改: `PairSyncService.swift`（冲突处理）

### Milestone A4: 接入与清理（预估 1-2 天）

**范围：**
- AppContext 中的 pair sync 入口完全切换到 PairSyncService + PairSyncPoller
- 删除/禁用 pair CKSyncEngine 代码路径
- 邀请流程不再创建 CKShare
- 数据迁移逻辑（旧配对 → 解绑 → 引导重新配对）
- 清理不再使用的文件

**验收标准：**
- 旧架构 pair 代码完全不在 runtime 路径中
- 邀请 → 配对 → 任务创建 → 同步 → 接受/完成 → 同步 全流程通过
- 解绑后数据清理干净
- 构建 + 测试通过

**关键文件：**
- 修改: `App/AppContext.swift`（大幅简化）, `Services/Pairing/LocalPairingService.swift`
- 删除/禁用: `CloudKitShareManager.swift`, `CloudKitZoneManager.swift`, `PairSyncBridge.swift`, `SyncMigrationService.swift`

### Milestone A5: 验证与上线（预估 1-2 天）

**范围：**
- TestFlight 真机双设备测试
- CloudKit Dashboard Deploy to Production
- UI 同步状态标识验证（同步中/已同步/同步失败）
- 边缘场景测试（离线→恢复、后台→前台、强制退出→重开）
- 性能验证（电量消耗、网络请求频率）

**验收标准：**
- 两台真机完整配对流程通过
- 任务创建/编辑/删除/接受/完成全部双向同步
- 空间改名、昵称修改、头像更新双向同步
- 离线操作恢复后自动同步
- 同步状态 UI 正确显示
- 无明显电量/性能问题

---

## 十三、关键技术细节备忘

### 13.1 CKModifyRecords 批量限制

- 每次 `modifyRecords` 最多 400 条记录
- 超过时需要分批处理

### 13.2 CKQuery 结果限制

- `resultsLimit: CKQueryOperation.maximumResults` 让系统决定每页大小
- 使用 `cursor` 分页拉取直到 cursor 为 nil

### 13.3 updatedAt 重叠窗口

- 增量拉取时 `updatedAt > (lastSync - 2秒)`
- 2 秒窗口防止时钟漂移和传播延迟导致的遗漏
- 去重由 recordName (UUID) 保证幂等

### 13.4 recordName 策略

- 所有 Pair* 记录的 `recordName` = 实体 `id.uuidString`
- 确保同一实体只有一条 CKRecord
- upsert 语义：存在则更新，不存在则创建

### 13.5 公共库 .changedKeys 行为

- `CKModifyRecordsOperation.savePolicy = .changedKeys`
- 只发送本地修改的字段到服务器
- 服务器端做字段级合并
- **关键**：第一次创建记录时必须发送所有字段

### 13.6 GCBD（贵州云大数据）注意事项

- 中国用户的 iCloud 数据存储在贵州
- CloudKit API 延迟可能比全球节点高 100-300ms
- 自适应轮询自动适应：延迟高 → fetch 慢 → 轮询周期自然拉长
- 静默推送在中国可能延迟更大 → 轮询兜底更为关键

### 13.7 iOS 后台行为

- App 进入后台后不能持续轮询
- 静默推送（`shouldSendContentAvailable`）可以在后台唤醒 App 约 30 秒
- 可见推送可以在 App 完全退出时送达
- `scenePhase == .active` 时恢复轮询 + 立即触发一次全量同步

### 13.8 并发安全

- `PairSyncService` 为 `actor`，天然线程安全
- `PairSyncPoller` 为 `@MainActor`，在主线程调度
- SwiftData `ModelContext` 在 push/pull 内部创建，不跨方法持有
- Codec 全部为值类型 (`struct`)，无共享状态

---

## 十四、扩展路线图

```
Phase 1 (当前): CloudKit Public DB (0-3K 用户)
  → 最简实现，快速验证
  → 自适应轮询 + 推送
  → 零冲突客户端权限

Phase 2 (未来): Supabase (3K-50K 用户)
  → Postgres 实时订阅替代轮询
  → Row Level Security 服务端权限
  → 保留本地 SwiftData 缓存
  → 需要实现离线队列

Phase 3 (远期): 自建后端 (50K+ 用户)
  → WebSocket 实时双向同步
  → 完整服务端业务逻辑
  → 多人空间支持
```

---

## 十五、与旧架构的对比总结

| 维度 | 旧架构 (CKSyncEngine) | 新架构 (Public DB) |
|------|----------------------|-------------------|
| 同步引擎 | CKSyncEngine (poorly documented for shared DB) | CKQuery + CKModifyRecords (well documented) |
| 数据库 | Private + Shared | Public (pair) + Private (solo) |
| 推送 | CKSyncEngine 内置 (对 shared DB 不稳定) | CKQuerySubscription (公共库原生支持) |
| 轮询 | 5s 固定 + 自毁 bug | 自适应 5s→15s→30s + 不会自毁 |
| 冲突处理 | Zone-based shared authority | .changedKeys + serverRecord 合并 |
| 代码量 | ~6000 行 (SyncEngineCoordinator + Delegate + Bridge + ...) | ~1000 行预估 |
| 可调试性 | CKSyncEngine 黑盒，事件难追踪 | CKQuery/CKModify 请求-响应，完全透明 |
| 删除检测 | CKSyncEngine zone feed 提供 | 软删除标记 (isDeleted) |
| 稳定性 | 几分钟后停止同步 | 轮询保底，不依赖引擎内部状态 |
