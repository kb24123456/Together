# Anniversaries: Pinned Today + Live Counter + Holiday Schedule (1.0 + 1.0.1)

**日期**：2026-04-27
**作者**：pigdog + Claude (brainstorming)
**目标版本**：1.0（核心）+ 1.0.1（holiday OTA fetch）
**前置工作**：build 7 birthday viewer-relative + build 8 capsule rose accent 已落地。

---

## 1. 目标与非目标

### Goals

1. **活计数器（live days counter）**：自定义纪念日如「我们在一起」「结婚纪念日」「宠物到家」自动显示「{title} N 天」（正计时）或「距下次 X 还有 N 天」（倒计时），UI 不强制 title 语法。
2. **Today 常驻多胶囊 + 用户控制**：用户在纪念日管理 sheet 里 pin/unpin 任意条目；Today 视图显示所有 pinned，多个用 iOS Lock-Screen 通知 stack 视觉叠放，点击展开。
3. **法定节假日预设扩充**：preset holiday 列表从 3 项扩到 10 项（元旦、春节、清明、劳动节、端午、中秋、国庆、圣诞、情人节、七夕），加进来的节日 default-pinned 显示放假倒计时。
4. **节假日**真正展示「距离放假还有 N 天」，基于国务院公告的放假区间（含调休），1.0 hardcoded、1.0.1 OTA fetch。
5. **沉浸感不破坏**：所有交互无刷屏、无自动循环切换、无突兀模态，与现有 rose-tint capsule 风格一致。

### Non-Goals (1.0)

- 用户在 preset 之外自定义任意 holiday（用 `.custom` kind 即可）
- 多语言 i18n
- 系统 Calendar 同步 / iCal export
- holiday-cn 网络 fetch（推迟 1.0.1）
- 用户分组管理 / 标签

---

## 2. 数据模型

### 2.1 ImportantDate 字段新增

```swift
struct ImportantDate {
    // ...existing fields...
    var isPinnedToToday: Bool = false  // NEW
}

@Model final class PersistentImportantDate {
    // ...existing fields...
    var isPinnedToToday: Bool = false  // NEW
}
```

**Supabase migration**：
```sql
ALTER TABLE important_dates
  ADD COLUMN is_pinned_to_today bool DEFAULT false NOT NULL;
```

旧行自动 false，无破坏。

### 2.2 ImportantDateKind 不变

`.birthday(memberUserID:)` / `.anniversary` / `.holiday` / `.custom` 沿用 build 7 已修的语义（memberUserID 用 supabase auth.uid 跨设备唯一）。**不引入** `.relationshipStart` 之类新 kind ——「我们在一起」就是普通 `.anniversary`，user 自创建（B 方案，YAGNI）。

### 2.3 PresetHolidayID 扩充

```swift
enum PresetHolidayID: String, CaseIterable, Sendable, Codable {
    // 已有
    case valentines       // 公历 2/14
    case qixi             // 农历 7/7
    case springFestival   // 农历 1/1（除夕）

    // 新增 (1.0)
    case newYear          // 公历 1/1
    case qingming         // 节气，公历约 4/5
    case laborDay         // 公历 5/1
    case dragonBoat       // 农历 5/5
    case midAutumn        // 农历 8/15
    case nationalDay      // 公历 10/1
    case christmas        // 公历 12/25
}
```

**老 client 兼容**：String rawValue Codable，老 client 解 unknown rawValue 时 fall back 到 `presetHolidayID = nil`，仅丢失 preset icon 默认值，不破。

### 2.4 HolidaySchedule（新值类型，纯客户端）

```swift
struct HolidaySchedule: Hashable, Sendable {
    let name: String          // "2026 年春节"
    let startDate: Date       // 放假首日
    let endDate: Date         // 放假末日
    let offDays: Int          // 放假天数（含调休总天数）
    /// PresetHolidayID 关联（用于跟用户创建的 ImportantDate 对接）
    let preset: PresetHolidayID?
}
```

**注意**：`HolidaySchedule` 不入 SwiftData / Supabase，纯 in-memory 数据。来源是 hardcoded array（1.0）/ holiday-cn fetch + cache（1.0.1）。

### 2.5 ImportantDate × HolidaySchedule 的对接

- **创建路径**：用户在 PresetHolidayPickerSheet 选「春节」→ 系统创建一个 `ImportantDate(kind: .holiday, presetHolidayID: .springFestival, recurrence: .lunarAnnual, dateValue: <节日核心日>)`，**dateValue 仍是节日核心日（农历正月初一）**
- **显示路径**：Today/管理 sheet 渲染时，对 `kind == .holiday && presetHolidayID != nil` 的 row：
  1. 优先查 `HolidayScheduleService.lookup(preset:, year:)` 得当年放假区间
  2. 用 `schedule.startDate` 作为 anchor 显示「距春节假期还有 N 天」
  3. 找不到当年 schedule（如用户用了未来年份超出 hardcoded 范围）→ 回退到 `dateValue` 的 `nextOccurrence`，显示「距春节还有 N 天」（节日核心日）
- 这个 fallback 保证：用户不升级 app 也仍能显示节日倒计时（数据降级，不空白）

---

## 3. 显示规则

### 3.1 Mode 选择优先级

```
显示模式 = pickMode(date: ImportantDate)：
  1. 若 anchor (date.dateValue) > now：
       → 倒计时「距 {title} 还有 N 天」（不论 kind）
       → 这覆盖用户创建未来 anchor 的所有 kind

  2. 否则（anchor 在过去）：
       a. .birthday        → 倒计时（距下次生日）
       b. .holiday         → 倒计时（距当年放假首日，fallback 节日核心日）
       c. .anniversary     → 默认正计时「{title} N 天」
                              当 nextOccurrence - now < 30 天 → 切倒计时「距下次 {title} 还有 N 天」
       d. .custom + .none recurrence → 正计时「{title} N 天」
       e. .custom + 周期 recurrence  → 同 .anniversary
```

### 3.2 Long-press peek（另一面）

- **仅当 mode 是 .anniversary 或 .custom recurring 时**有"另一面"（既有 daysSinceStart 又有 daysUntilNext 的场合）
- 长按胶囊 1.0s → 临时切到另一面 1.5s → 自动回原态
- `HomeInteractionFeedback.selection()` 触觉反馈在长按触发的瞬间触发
- birthday / holiday / 一次性 custom 长按**无操作**（只有一种 metric，不引入误导）

### 3.3 文案样式

```
{title} · {N} 天        // 正计时，例「我们在一起 · 730 天」
{title} · 还有 {N} 天    // 倒计时，例「春节 · 还有 25 天」
{title} · 今天          // 倒计时 N == 0
```

中点 `·` 作为视觉 separator，不依赖中文语法。所有 capsule 统一这个格式。

---

## 4. 节假日数据源

### 4.1 1.0 — hardcoded

**位置**：`Together/Resources/HolidayScheduleData.swift`（新文件）

```swift
enum HolidayScheduleData {
    /// Hardcoded 2026-2027 放假安排，基于国务院公告。
    /// 每年 11 月公告发布后随版本更新追加新一年。
    static let all: [HolidaySchedule] = [
        // 2026
        .init(name: "2026 元旦", startDate: makeDate(2026, 1, 1), endDate: makeDate(2026, 1, 1), offDays: 1, preset: .newYear),
        .init(name: "2026 春节", startDate: makeDate(2026, 2, 16), endDate: makeDate(2026, 2, 22), offDays: 7, preset: .springFestival),
        // ...约 14 条 entries 共 2026 + 2027
    ]

    static func lookup(preset: PresetHolidayID, year: Int) -> HolidaySchedule? {
        all.first { schedule in
            schedule.preset == preset &&
            Calendar.current.component(.year, from: schedule.startDate) == year
        }
    }

    static func nextUpcoming(now: Date = .now) -> [HolidaySchedule] {
        all.filter { $0.endDate >= now }.sorted { $0.startDate < $1.startDate }
    }
}
```

**精度**：每条来自国务院当年公告。维护成本：每年一次手敲（10 分钟），随版本号一起出。

### 4.2 1.0.1 — OTA fetch（spawn task scope）

新建 `HolidayScheduleService` actor：
- 冷启动 + 每周首次启动检查 cache 时效
- 过期 → fetch `https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json`
- holiday-cn JSON 格式：每天一行 `{name, date, isOffDay}`，需后处理 group consecutive `isOffDay==true` days into `HolidaySchedule`
- 解析成功 → 写本地 file cache（`Application Support/holiday-schedules-{year}.json`）
- fetch 失败 / 网络无 → fall back to hardcoded
- 提供同 hardcoded 一样的 `lookup(preset:year:)` API

**1.0.1 不在 1.0 spec 范围**，单独 backlog spawn task。

---

## 5. Today UI 布局

### 5.1 Today 中纪念日区块的渲染

| Pinned 数 | 渲染 |
|---|---|
| 0 | **不显示该区块**（不占位、不强 CTA） |
| 1 | 沿用 `AnniversaryCapsuleView`（rose-tint capsule，build 8 已落地） |
| ≥2 | 自定义 `PinnedAnniversaryStack` 视图（下方 5.2 详述） |

排序键 `displayAnchorDate`：
- `.recurrence != .none` → 用 `nextOccurrence(after: now)`
- `.custom + .none recurrence + anchor 在未来` → 用 `dateValue` 本身
- `.custom + .none recurrence + anchor 已过` → 排序键 = `.distantFuture`（这类已过一次性事件正计时态，不抢前面位置）

升序排列，最近的事件在最上层。

### 5.2 PinnedAnniversaryStack（多胶囊叠放）

**视觉**：mimic iOS Lock Screen notification stack
- 第 1 张：完整显示，rose-tint capsule
- 第 2/3+ 张：依次向下偏移 4-6pt + scale 0.96 / 0.92，仅露出顶部 24pt 边缘
- 最多渲染 3 张 z-stack（第 4+ 张不渲染避免视觉混乱）
- **仅当 pinned 总数 > 3 时**右上角 badge 显示「+{N-3}」（如总 6 个时显示「+3」，提示展开后还有未渲染的）；3 个及以下不显示 badge

**点击行为**：
- 折叠态点击叠堆任一区域 → `withAnimation(.spring)` 展开为 vertical list（间隔 8pt，每张完整 capsule）
- 展开态点击最上面胶囊 → 折叠回 stack
- 展开态点击其他胶囊 → 跳到该 ImportantDate 的 detail/edit
- 整个区块在 home scroll 容器内 inline expansion，不弹 sheet、不遮挡下方 task list

**Pin 数量上限**：硬上限 6 个。pin 第 7 个时纪念日管理 sheet 内弹 alert：「最多固定 6 个纪念日到 Today，请先取消其他」。

### 5.3 替换现有 AnniversaryCapsuleView 的 3 处调用

HomeView.swift 当前 3 处 `AnniversaryCapsuleView(nextEvent:...)` 调用（empty-state、list-mode、calendar-mode）改为：

```swift
PinnedAnniversaryArea(
    pinnedEvents: viewModel.pinnedAnniversaries,  // sorted by nextOccurrence
    viewerSupabaseUserID: appContext.currentSupabaseUserID,
    partnerDisplayName: appContext.sessionStore.pairSpaceSummary?.partner?.displayName,
    onTapEvent: { event in showEdit = event },
    onTapEmptyCTA: { isImportantDatesManagementPresented = true }
)
```

`PinnedAnniversaryArea` 内部根据 count 选 `EmptyState` / `AnniversaryCapsuleView` / `PinnedAnniversaryStack`。

---

## 6. 纪念日管理 Sheet (`ImportantDatesManagementView`)

### 6.1 List item 加 pin toggle

每行新增一个 leading swipe-action 或 trailing icon button：
- Icon：`bookmark` (未 pinned) / `bookmark.fill` (pinned)，rose tint
- Tap → toggle `event.isPinnedToToday`
- pin 第 7 个时弹 alert（见 5.2）

排序：pinned 项置顶，其内按 nextOccurrence 升序；其余项按 nextOccurrence 升序。**不分 section**（用 pin icon 视觉区分即可，避免空 section 状态）。

### 6.2 Sheet 高度自适应

- `ImportantDatesManagementView` + `PresetHolidayPickerSheet` + `ImportantDateEditSheet` 都套 `.presentationDetents([.medium, .large])` 默认 + `.presentationDragIndicator(.visible)`
- 进阶（可选）：用 PreferenceKey 测内容 height，`.presentationDetents([.height(measured), .large])`，让短内容 sheet 自动收窄
- 1.0 优先做 `.medium / .large` 默认；自适应作为 polish 二次迭代

### 6.3 Preset Holiday Picker

- 显示 10 个 preset，每行 icon + name + 「下次：{date}」
- 用户多选 → 一键添加，**默认 isPinnedToToday = true**（节假日核心 utility 是放假倒计时，加 = 想看 today）
- 普通自定义 anniversary（non-preset 入口）默认 isPinnedToToday = false

---

## 7. 数据迁移

### 7.1 SwiftData

`PersistentImportantDate` 加 `isPinnedToToday: Bool = false`。SwiftData lightweight migration 自动处理（加默认值字段，无需手写 migration plan）。

### 7.2 Supabase

新 migration `024_add_is_pinned_to_today.sql`：
```sql
ALTER TABLE important_dates
  ADD COLUMN is_pinned_to_today bool DEFAULT false NOT NULL;
```
现有 row 自动 false。无 RLS 改动（沿用既有 space_member 读写策略）。

### 7.3 ImportantDateDTO 同步

加 `isPinnedToToday: Bool` 到 push/pull DTO 的 Codable + applyToLocal 路径。

### 7.4 老 build 兼容

- 老 client（build 7 及以前）不知道 `is_pinned_to_today` 字段，pull 时该字段被 SDK 忽略（Codable 默认行为）→ 老 client 仍正常显示纪念日列表，仅没有 pin 功能 → today 不会出现新 pinned 区块。
- 老 client 看到 `presetHolidayID` 新值（如 `"newYear"`）→ Codable decode unknown rawValue 失败 → 该字段 fall back 到 nil，icon 走 default。不 crash。

---

## 8. 测试覆盖

新增单测：
- `HolidayScheduleDataTests`：`lookup(preset:year:)` 命中 / 不命中、`nextUpcoming` 时间过滤
- `ImportantDateDisplayModeTests`：5 种 kind × anchor 在过去/未来 × recurrence 类型，覆盖 mode 选择决策表
- `PinnedAnniversaryStackOrderingTests`：pinned 排序按 nextOccurrence 升序
- `PinnedAnniversaryQuotaTests`：pin 第 7 个抛 quota error
- `ImportantDateDTOTests`：isPinnedToToday 双向 push/pull 兼容

UI 测试（quick smoke）：
- Today 0/1/N pinned 三态渲染
- Stack 折叠 → 展开 → 折叠
- 长按 peek 1.5s 后回原态

---

## 9. 风险 & 开放问题

### 9.1 已识别风险

1. **节假日 hardcoded 漂移**：超出 2026-2027 范围的年份用户看到的不是放假区间而是节日核心日（fallback）。1.0.1 holiday-cn fetch 解决。
2. **PresetHolidayID enum 增删的 forward-compat**：当前老 client 看到新 case 会 nil out，可接受。后续若必须删某 case（不太可能），需走 deprecate 流程。
3. **Stack 视觉 + 触摸热区**：iOS Lock Screen 通知 stack 是系统级实现，自实现的 ZStack 触摸热区可能有边缘情况（最底层胶囊 hit-test）。1.0 验收：折叠态整个区块作为单一 hit target；展开态各胶囊独立 hit target。
4. **Long-press peek 跟现有 swipe action 冲突**：list 行已有 swipe-to-delete + onTapGesture(edit)，再加 long-press 会不会触发冲突？需要在 implementation plan 阶段验证 SwiftUI gesture priority。

### 9.2 待 implementation 阶段决策（不阻塞 spec）

- Stack 折叠态触摸热区是「整个区块」还是仅最上层胶囊？倾向「整个区块」让用户更易触发展开。
- Pin 上限 alert 文案：「最多固定 6 个纪念日到 Today，请先取消其他」OK 吗？是否提供「直接进 sheet 编辑」的快捷入口？

---

## 10. Out of Scope（1.0.1+ Backlog）

- holiday-cn JSON OTA fetch + cache + fallback chain（**1.0.1 spawn task**）
- 用户自定义 non-preset 节假日（**user 用 `.custom` kind 已可达成，不开发新功能**）
- 多语言 i18n（**1.x**）
- 倒计时进入 Live Activity / Lock Screen widget（**1.x，依赖 ActivityKit 整合**）
- 纪念日分组 / 颜色标签（**1.x**）

---

## 11. 实施顺序（writing-plans 阶段会再细化）

1. Migration 024（schema）
2. PersistentImportantDate + ImportantDate.isPinnedToToday 字段
3. ImportantDateDTO + applyToLocal 双向同步
4. HolidaySchedule + HolidayScheduleData hardcoded
5. PresetHolidayID 7 个新 case + PresetHolidayPickerSheet 扩 list + 默认 isPinnedToToday=true
6. ImportantDate.displayMode 决策 + UI 文案 helper
7. AnniversaryCapsuleView：long-press peek + haptic
8. PinnedAnniversaryStack（叠放 + 展开）
9. PinnedAnniversaryArea wrapper + HomeView 替换 3 处
10. ImportantDatesManagementView：pin toggle button + sticky pinned ordering + quota alert
11. Sheet height adaption (basic detents 先做)
12. Tests 全套
13. 真机回归
