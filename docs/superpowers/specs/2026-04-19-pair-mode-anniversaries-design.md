# Pair 模式纪念日 + IA 瘦身 — 设计

## 背景

Together 之前 pair 模式和 solo 模式沿用完全相同的任务体系（普通任务、项目 + 子任务、例行事务），缺乏差异化。pair 模式下用户真正的价值不是"个人效率"，而是"两个人的生活连接"。本次迭代把 pair 模式从"solo 的复制"转型为"情侣场景专用"：

- **砍掉**例行事务（v1 开发阶段硬删 pair-space 数据）
- **保留**普通任务和项目（情侣共同计划如婚礼、装修、蜜月等本质就是 project）
- **新增"纪念日"**：双方生日、在一起纪念日、常见节日的倒计时 + 自动推送

核心差异化来自"**让粗心的那个人也不会忘掉重要日子**"—— APNs 推送（本机 `UNUserNotification` 实现）是关键 feature。

---

## 1. 信息架构（IA）变更

| 维度 | Solo | Pair |
|---|---|---|
| 普通任务 | ✅ | ✅ |
| 项目 + 子任务 | ✅ | ✅（情侣共同计划） |
| 例行事务 | ✅ | ❌ v1 移除 |
| **纪念日** 🆕 | ❌ | ✅ |

**Pair 模式下例行事务的处理**（dev 阶段，无线上用户）：
- 服务端 migration 015 直接 `DELETE FROM periodic_tasks WHERE space_id IN pair_spaces`
- 客户端一次性迁移 `PairPeriodicPurgeMigration.runIfNeeded` 删除本地 `PersistentPeriodicTask` 中 pair space 的行
- UI tab bar + Home 卡片在 pair 模式条件不渲染
- Service 层 `LocalPeriodicTaskRepository.save` 拒绝 pair space 作为兜底

---

## 2. 纪念日功能范围

### 2.1 事件类型

四大 `kind`：
1. **`birthday`** — 双方生日（每年公历循环），分 A 和 B 两条独立数据，共享可见
2. **`anniversary`** — 在一起纪念日（每年循环）。单条数据展示"已过 XXX 天" + "下次周年还有 XX 天"两种视图
3. **`holiday`** — 常见节日（用户从预置列表勾选添加）
4. **`custom`** — 用户完全自定义（搬家日、第一次约会、买房日等）

### 2.2 预置节日（MVP 3 项）

| `PresetHolidayID` | 名称 | 日期 | `recurrence` | 默认图标 |
|---|---|---|---|---|
| `valentines` | 情人节 | 公历 2/14 | `solarAnnual` | `heart.fill` |
| `qixi` | 七夕 | 农历 7/7 | `lunarAnnual` | `sparkles` |
| `springFestival` | 春节 | 农历 1/1 | `lunarAnnual` | `party.popper.fill` |

国庆、中秋、圣诞等不纳入 MVP。用户若要追踪可用 custom kind 手动添加。

### 2.3 数据共享

pair 空间内**完全共享**：任何一方添加、编辑、删除的纪念日双方都看得到、都能改。不做"私密备忘"模式。论据：app 定位是**协作型情侣**不是**惊喜型**，共享透明是 feature 而非 bug。

### 2.4 通知策略

- **本机 `UNUserNotification` 调度**（非 APNs 服务端推送），详见 §4
- **默认提前 7 天 + 当天** 2 次推送
- 每条纪念日可改"提前多少天"，固定 5 档单选：`1 / 3 / 7 / 15 / 30`
- "当天提醒"可开关
- **双方设备各自调度**，不区分接收方（v1 不做"只推对方"的 smart rule）

---

## 3. 数据模型

### 3.1 Supabase 新表 `important_dates`

```sql
CREATE TABLE important_dates (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id           uuid NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    creator_id         uuid NOT NULL,                -- 本地 UUID
    kind               text NOT NULL,                -- 'birthday' | 'anniversary' | 'holiday' | 'custom'
    title              text NOT NULL,
    date_value         date NOT NULL,                -- 首次发生日期（公历存储）
    is_recurring       boolean NOT NULL DEFAULT true,
    recurrence_rule    text,                         -- 'solar_annual' | 'lunar_annual' | null
    notify_days_before int  NOT NULL DEFAULT 7,      -- 1/3/7/15/30
    notify_on_day      boolean NOT NULL DEFAULT true,
    icon               text,                         -- SF Symbol 名称（可选）
    member_user_id     uuid,                         -- 仅 birthday 填，标识是谁的生日
    is_preset_holiday  boolean NOT NULL DEFAULT false,
    preset_holiday_id  text,                         -- 'valentines' | 'qixi' | 'springFestival'
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    is_deleted         boolean NOT NULL DEFAULT false,
    deleted_at         timestamptz
);

CREATE INDEX ON important_dates (space_id, is_deleted);

-- 防止同一 space 重复勾选同一 preset
CREATE UNIQUE INDEX important_dates_unique_preset
ON important_dates (space_id, preset_holiday_id)
WHERE is_preset_holiday AND NOT is_deleted;
```

**设计决策释义**：
- `date_value` 全系统统一公历存储（包括农历事件也存"下次公历发生日期"），避免跨日历排序 / 闰月 string 陷阱。农历展示在 UI 层动态转换。
- `member_user_id` 仅 birthday 填；pair 成员离开后不自动删，UI 端让用户决定是否清理
- `preset_holiday_id` 是候选列表的预置标识，防重复勾选；其他字段（title / icon / recurrence）创建时 copy 进行，之后表现和自定义事件完全一致

### 3.2 客户端 Domain

```swift
struct ImportantDate: Identifiable, Hashable, Sendable {
    let id: UUID
    let spaceID: UUID
    let creatorID: UUID
    var kind: ImportantDateKind
    var title: String
    var dateValue: Date
    var recurrence: Recurrence
    var notifyDaysBefore: Int           // 1/3/7/15/30
    var notifyOnDay: Bool
    var icon: String?
    var presetHolidayID: PresetHolidayID?
    var updatedAt: Date

    func nextOccurrence(after reference: Date) -> Date?
    func daysUntilNext(from reference: Date) -> Int?
    var daysSinceStart: Int
}

enum ImportantDateKind: Hashable, Sendable {
    case birthday(memberUserID: UUID)
    case anniversary
    case holiday
    case custom
}

enum Recurrence: String, Hashable, Sendable {
    case none, solarAnnual, lunarAnnual
}

enum PresetHolidayID: String, CaseIterable, Sendable {
    case valentines, qixi, springFestival
}
```

`PersistentImportantDate` 镜像全部字段，Schema 注册进 `PersistenceController.schema`（Persistent 模型清单从 16 变 17）。

### 3.3 同步接入

沿用现有 Supabase pair sync 架构：
- `SyncEntityKind.importantDate` + `supabaseTableName = "important_dates"`
- `ImportantDateDTO` snake_case CodingKeys
- `SupabaseSyncService.pushUpsert(.importantDate)` + `pullImportantDates`
- `ImportantDateReader` / `ImportantDateWriter` 测试 seam（沿用 `SpaceMemberReader`/`Writer` 同款 pattern）
- Realtime 订阅 `important_dates` channel，UPDATE → catchUp → 触发通知 refresh

---

## 4. 通知推送

### 4.1 方案对比与选型

| | A. 服务端 APNs | B. 本机 `UNUserNotification`（**选用**） |
|---|---|---|
| 实现 | Supabase cron + Edge Function 扫描推送 | 每台设备本地调度 `UNNotificationRequest` |
| 服务端成本 | APNs 额度 + cron | 零 |
| 离线支持 | 需网络 | ✅ 离线也触发 |
| 新设备 | 开箱即用 | 启动时自动扫描 schedule |
| 农历每年重算 | 服务端 | 客户端（启动时自然覆盖） |

选 B。**关键洞察**：纪念日是**时间触发**不是**事件触发**（partner-nudge 那种"对方点按钮才推"必须走服务端，纪念日不必）。双方都收到 = 两台设备各自 schedule 本地通知，不需要服务端参与。

### 4.2 `AnniversaryNotificationScheduler.refresh()` 流程

每次满足以下任一条件触发：
1. App 启动完成（`AppContext.postLaunch`）
2. `SupabaseSyncService` pull `important_dates` 完成
3. Realtime 收到 `important_dates` 变化
4. 用户手动 CRUD 纪念日

流程：

```swift
func refresh() async {
    // 清空所有已调度的纪念日通知
    let pending = await center.pendingNotificationRequests()
    let ourIDs = pending.filter { $0.identifier.hasPrefix("anniversary-") }.map(\.identifier)
    await center.removePendingNotificationRequests(withIdentifiers: ourIDs)

    // 重新调度所有未来事件
    let events = try await importantDateRepository.fetchAll(spaceID: pairSpace.id)
    let now = Date.now
    for event in events.sortedByNextOccurrence(from: now).prefix(32) {
        guard let next = event.nextOccurrence(after: now) else { continue }

        if event.notifyDaysBefore > 0 {
            schedule(
                identifier: "anniversary-\(event.id)-before",
                date: next.addingDays(-event.notifyDaysBefore).atTime(9, 0),
                content: advanceContent(for: event)
            )
        }
        if event.notifyOnDay {
            schedule(
                identifier: "anniversary-\(event.id)-day",
                date: next.atTime(9, 0),
                content: dayOfContent(for: event)
            )
        }
    }
}
```

**幂等全量重建**：简单可靠。iOS 64 通知上限靠 `prefix(32)` 兜底（32 事件 × 2 通知 = 64）。

### 4.3 文案模板（按当前设备用户本地化）

| 事件类型 | 提前提醒 | 当天提醒 |
|---|---|---|
| 伴侣生日 | `💝 {伴侣昵称} 生日还有 {N} 天` | `🎂 今天是 {伴侣昵称} 生日` |
| 我的生日 | `🎁 你的生日还有 {N} 天` | `🎉 生日快乐！` |
| 在一起纪念日 | `💕 纪念日还有 {N} 天` | `💕 今天是你们在一起的第 X 周年` |
| 节日 | `✨ {节日名} 还有 {N} 天` | `✨ {节日名} 快乐！` |
| 自定义 | `📌 {标题} 还有 {N} 天` | `📌 今天是 {标题}` |

"伴侣昵称" 从 `sessionStore.pairSpaceSummary.partner.displayName` 取。

### 4.4 时间

固定每天 **9:00（当地时区）**。不可配置（v1 简化）。

### 4.5 权限

沿用 partner-nudge 的 `PairJoinObserver.onSuccessfulPairJoin` 权限请求逻辑，pair 加入时已引导过一次。`refresh()` 调度前检查 `authorizationStatus`，未授予则 `logger.warning` 并跳过（不阻塞功能流）。

---

## 5. 农历处理

### 5.1 `nextOccurrence(after:)` 按 `Recurrence` 分派

**`.solarAnnual`**：按 `Calendar(.gregorian)` 取年月日，滚到下一年。

**`.lunarAnnual`**：
```swift
let chineseCal = Calendar(identifier: .chinese)
let lunarMonth = chineseCal.component(.month, from: dateValue)
let lunarDay = chineseCal.component(.day, from: dateValue)

var comps = DateComponents()
comps.year = chineseCal.component(.year, from: reference)
comps.month = lunarMonth
comps.day = lunarDay
var candidate = chineseCal.date(from: comps)

if let c = candidate, c <= reference {
    comps.year = comps.year! + 1
    candidate = chineseCal.date(from: comps)
}
return candidate   // Swift 自动返回公历 Date
```

### 5.2 闰月降级

某些农历年的某月无闰，闰月事件在那年需要降级到非闰月同月日：

```swift
if candidate == nil {
    var fallback = comps
    fallback.isLeapMonth = false
    candidate = chineseCal.date(from: fallback)
}
```

UI 不暴露"闰月" UX，系统透明处理。

### 5.3 展示

节日勾选表和管理页列表行，对农历事件显示"下次发生的公历日期"，避免用户手算。

### 5.4 测试（5 个关键场景）

1. `.solarAnnual` 今年未过 → 返回今年
2. `.solarAnnual` 今年已过 → 返回明年
3. `.lunarAnnual` 基本（七夕） → 转换正确
4. `.lunarAnnual` 闰月 fallback（2025 闰六月、2028 闰五月等）
5. `.none` 已过 → nil

---

## 6. UI / UX

### 6.1 主页胶囊

位置：任务列表顶部，与现有"逾期胶囊" / "例行胶囊"同层。pair 模式下例行胶囊消失，纪念日胶囊占位。

显示规则：
- 有数据：显示**下次发生最近的 1 条**倒计时。如 `❤️ 还有 7 天 · 伴侣生日`。当天显示紧急样式 `🎂 今天是伴侣生日`
- 0 条数据：显示引导 `✨ 添加第一个纪念日`
- 点击 → 纪念日全屏管理页

### 6.2 "我" 页入口

在"双人协作"卡片区新增：
```
📅 纪念日管理       >
```
点击 → 同一个纪念日管理页。

### 6.3 管理页

**空状态**：顶部引导卡片 × 3
- `添加伴侣生日 🎂` （primary）
- `添加我的生日 🎁`
- `添加在一起纪念日 💕`

底部 `+ 其他纪念日 / 添加常见节日`。

**非空列表**：按下次发生时间升序。每行 `图标 + 标题 + 还有 N 天 + 日期 (3/14 · 农历)`。右划删除，点击进入编辑。

**底部固定 + 按钮** → action sheet：
- 🎂 伴侣生日 / 我的生日（已存在则 disabled）
- 💕 在一起纪念日（已存在则 disabled）
- 🎉 添加常见节日 → 节日勾选表
- ✏️ 自定义

### 6.4 节日勾选表

全屏 sheet，列表形式：
```
☐ 情人节    2/14 · 公历
☑ 七夕      农历 7/7 · 2026/8/19
☐ 春节      农历 1/1 · 2027/2/17
```

已勾选显示下次发生公历日期，顶部"完成"批量创建 / 删除。

### 6.5 创建 / 编辑 sheet

字段顺序：
- **图标**（SF Symbol 选择器，可选）
- **标题** text field
- **日期** date picker
- **重复规则** segmented control：`一次性 / 每年（公历） / 每年（农历）`
- **提前提醒** radio：`1 / 3 / 7 / 15 / 30 天`
- **当天提醒** toggle
- （仅 birthday）**属于**：自动填 kind 决定，不可改

### 6.6 视觉

- Primary accent：`AppTheme.colors.coral`
- 默认图标：birthday `gift.fill` / anniversary `heart.fill` / holiday `sparkles` / custom `star.fill`

### 6.7 命名

- Schema / code 层统一 `important_date` / `ImportantDate`
- 用户可见文案 "纪念日"
- 避免 code-level 用 "anniversary" 引起和 `kind=.anniversary` 子类型混淆

---

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `Calendar(.chinese)` 闰月边界异常 | 单元测试覆盖 5+ 闰月年份 |
| iOS 64 pending notification 上限 | Scheduler 按 `daysUntilNext` 排序取前 32 事件调度，其余下次轮转 |
| 切 solo/pair tab bar 动画卡顿 | 条件渲染用稳定 `.id()` 避免 tab bar 重建闪烁 |
| 通知权限未授予 | Scheduler 检查 `authorizationStatus`，未授予则 log 后跳过 |
| pair member 离开后 birthday 孤儿 | `member_user_id` 保留，UI 让用户自行决定是否清理 |

---

## 8. 测试策略（按层）

| 层 | 类型 | 关键用例 |
|---|---|---|
| Domain | 单元 | `nextOccurrence` 4 分支 + 闰月 fallback；`daysSinceStart` |
| Repository | 单元 | `LocalImportantDateRepository` save/delete/fetch/tombstone 4 件套 |
| Sync DTO | 单元 | round-trip / CodingKeys / enum 序列化 |
| Sync push/pull | Integration | capturing `ImportantDateReader` / `Writer` spy |
| Scheduler | 单元 | `refresh()` 正确 schedule；清空旧 identifier；权限未授时跳过 |
| Periodic 清理 | 单元 | migration 幂等 + Service guard 拒绝 pair space |
| UI | View | 胶囊条件渲染 / tab bar 条件 / 节日勾选表交互 |
| E2E | 真机双设备 | A 加 B 生日 → B 10s 内看到胶囊 + 列表 + 收到提前 / 当天通知 |

---

## 9. 开发阶段遗留 / v2 待办

- 节日规则化（母亲节 5 月第二周日 / 父亲节 6 月第三周日）
- 通知 "智能接收方" rule（"对方生日只推我，避免自己吵自己"）
- 通知时间用户可配置（9am / 10am / 自定义）
- "私密惊喜"模式（某条 event 只对自己可见）
- 纪念日回顾统计（"我们一共有 X 个纪念日，第一个到现在已过 Y 天"）

## 10. 参考：现有实现清理

| 现有文件 | 处理 |
|---|---|
| `Together/Services/Anniversaries/MockAnniversaryRepository.swift` | 重命名为 `MockImportantDateRepository`，移至测试目标或保留生产（按项目既有 Mock 放置惯例） |
| `Together/Domain/Protocols/AnniversaryRepositoryProtocol.swift` | 重命名为 `ImportantDateRepositoryProtocol`，signature 按新 domain model 重写 |
| `Together/Features/Anniversaries/AnniversariesViewModel.swift` | 视旧实现内容决定：轻微改动保留；否则直接重写为 `ImportantDateViewModel` |
