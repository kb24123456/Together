# Logbook Entry 设计规范

- **日期**: 2026-04-20
- **范围**: Home 顶栏新增「日志」入口 + `CompletedHistoryView` 增强（Pair 模式 stats hero + 行内完成人小头像）
- **方向**: β 延续（Claude 克制骨架 + Together 双人温度）
- **Scope**: MVP + 完成人 avatar (option a)
- **前置**: Profile L3 redesign 已合入 main（HEAD `7c7414c`）

---

## 1. 背景

### 1.1 问题起源

Profile L3 redesign（`2026-04-20-profile-ux-audit-design.md`）把「历史任务」从 Profile 分组删除——理由是"数据视图不属于设置"。但此次 redesign 只做了"删除"没做"迁移"，导致**功能 regression**：用户目前没有常规入口访问已完成任务列表。

### 1.2 行业调研结论（5 种主流模式）

| 模式 | 代表 App | 心智 |
|---|---|---|
| 日志视图一级导航 | Things 3 Logbook | "完成任务存入历史册" |
| 列表就地 + 过滤 | Apple Reminders | "已完成是状态" |
| Perspective / Archive | OmniFocus | "历史是查询" |
| 隐藏 + Activity Log | Todoist | "什么发生过" |
| 日历回看 | Sunsama / Amie | "那天做了什么" |

选 **Things Logbook 风**——与 β 编辑气质最契合，且能承载 pair 模式下"我们一起完成了什么"的情感价值。

### 1.3 β 定位的延续

- Solo 模式：纯工具——复用现有列表，加入口即可
- Pair 模式：情感承载点——加 narrative stats hero + 每行完成人头像

---

## 2. 目标与非目标

### 2.1 Goals

1. 恢复历史任务可达性（补 Profile redesign 留下的 regression）
2. 为 pair 模式提供第二个情感承载点（名片区是第一个）
3. 保持 β 气质：克制、编辑感、hairline、narrative-first

### 2.2 Non-goals

1. 不改造 `CompletedHistoryView` 列表本身的结构（保留按日分组、搜索、swipe 恢复/删除、分页加载）
2. 不新增数据 schema（`lastActionByUserID` 作为完成人代理）
3. 不改底栏 dock bar（仍 5 按钮，Logbook 走顶栏）
4. 不做 StoreKit / 通知 / 深链改动
5. 不做 streak / 连续天数等 gamification

---

## 3. 入口点（Home 顶栏 icon）

### 3.1 位置

`HomeView.headerSection` HStack 内，**`headerAvatarButton` 的左侧 sibling**。

```
┌──── Home 顶栏 ──────────────────────────────────┐
│                                                  │
│ [Title + spaceModeLine]   [book.closed] [Avatar] │
│                                  ↑         ↑     │
│                               新入口     保留     │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 3.2 视觉规格

| 属性 | 值 |
|---|---|
| Icon | `Image(systemName: "book.closed")` |
| 大小 | 22pt（`typography.sized(22, weight: .semibold)`）|
| 颜色 | `headerPrimaryColor`（与 title 同色系）|
| 触控热区 | 44 × 44pt，`contentShape(Rectangle())` |
| 背景 | 透明（不做圆背景 / capsule）|
| Haptic on tap | `HomeInteractionFeedback.selection()` |
| Pair 模式视觉提示 | **无**（solo / pair 视觉一致，保持克制）|

### 3.3 Accessibility

```swift
.accessibilityLabel("日志")
.accessibilityHint("查看已完成任务")
```

### 3.4 路由

**新增 `HomeRoute`（本地 route，不跨 tab）**：

```swift
// Together/App/AppRoute.swift — 新增
enum HomeRoute: Hashable {
    case logbook
}
```

`HomeView` 顶层 `NavigationStack` 挂 `navigationDestination`：

```swift
.navigationDestination(for: HomeRoute.self) { route in
    switch route {
    case .logbook:
        CompletedHistoryView(viewModel: viewModel.makeCompletedHistoryViewModel())
    }
}
```

Icon 按钮用 `NavigationLink(value: HomeRoute.logbook)` 触发 push。

### 3.5 与 Profile 路由的关系

- Profile 内**不再**显示"历史任务"行（保持 Profile redesign 的 IA 决策）
- Profile 的 `ProfileRoute.completedHistory` navigationDestination **保留**（防止未来深链 / 其他入口断掉）
- Home 路由与 Profile 路由物理上都挂到 `CompletedHistoryView`，视作同一屏两入口

---

## 4. Pair 模式 Stats Hero

仅 pair 模式显示，在 `CompletedHistoryView` 的 List 最顶部。

### 4.1 视觉布局

```
┌────────────────────────────────────────┐
│                                        │
│  我们一起完成了 124 件事                  │
│  本月 23 件 · 最近一次：2 小时前         │
│                                        │
└────────────────────────────────────────┘
────────────────────────────────────────   ← hairline
┌────────────────────────────────────────┐
│ 5 月 20 日                              │
│ ○ 任务 A                               │
│ ○ 任务 B                               │
└────────────────────────────────────────┘
```

**无卡片背景 / 无阴影 / 无描边**——裸露在 `background` 米白上，底部 hairline 分隔。

### 4.2 Typography

| 元素 | Font | Color |
|---|---|---|
| 主标 | `displayLight(20)` + `.tracking(0.2)` | `title` |
| 副标 | `sized(13, .regular)` | `textTertiary` |
| 数字 | 继承主标 font + color | 不特殊加粗 / 不变色 |

### 4.3 Layout

```
padding.horizontal: spacing.md (16pt)
padding.vertical:   spacing.lg (20pt)
padding.top:        spacing.md 额外（顶部呼吸）
alignment:          .leading
底部 hairline:      1px AppTheme.colors.hairline
```

### 4.4 文案规则（三档，严格）

| 条件 | 主标 | 副标 |
|---|---|---|
| `totalCount == 0` | `一起开始记录` | `你们的第一件任务还在路上` |
| `1 <= totalCount < 10` | `我们一起完成了 \(N) 件事` | `第一件：\(firstItemTitle)` |
| `totalCount >= 10` | `我们一起完成了 \(N) 件事` | `本月 \(M) 件 · 最近一次：\(relativeTime)` |

### 4.5 `relativeTime` 格式

| 时间差 | 格式 |
|---|---|
| < 1 分钟 | `刚刚` |
| 1–59 分钟 | `\(N) 分钟前` |
| 1–23 小时 | `\(N) 小时前` |
| 1–6 天 | `\(N) 天前` |
| 7+ 天 | `M 月 D 日` |

### 4.6 动画

- 滚动时 hero **随列表一起滚出**（不 sticky）
- 数字变化：`.contentTransition(.numericText())` + `spring(response:0.38, dampingFraction:0.86)` 动画 value = `totalCount`
- 初次加载：随 List 默认淡入

### 4.7 组件结构

**新建**：`Together/Features/Profile/LogbookPairSummaryHero.swift`

```swift
struct LogbookPairSummary: Equatable {
    let totalCount: Int
    let thisMonthCount: Int
    let firstItemTitle: String?
    let lastCompletedAt: Date?
}

struct LogbookPairSummaryHero: View {
    let summary: LogbookPairSummary

    var body: some View { ... }

    private var primaryText: String { ... }  // 3 档文案
    private var secondaryText: String { ... } // 3 档副标
    private func formatRelativeTime(_ date: Date) -> String { ... }
}
```

### 4.8 VM 数据暴露

`CompletedHistoryViewModel` 新增：

```swift
var isPairMode: Bool { sessionStore.hasActivePairSpace }

var pairSummary: LogbookPairSummary? {
    guard isPairMode else { return nil }
    // 从 completedItems 聚合 totalCount / thisMonthCount /
    // firstItemTitle / lastCompletedAt
}
```

聚合时机：load 后一次性计算，cache 到属性。数据变动时（swipe 删除 / 恢复）重新计算。

### 4.9 Solo 模式

**完全不渲染 hero**——`pairSummary` 返回 `nil`，UI 条件分支跳过。

### 4.10 Dark mode

- 继承 `background` / `title` / `textTertiary` / `hairline` 的 dark 变体
- 数字不使用 pair coral tint（保持克制）

---

## 5. 行内完成人小头像（Pair Only）

### 5.1 布局改动

`historyRow(for:)` 函数改动：外包一个 `HStack`，pair 模式加 leading avatar 列。

```swift
private func historyRow(for item: Item) -> some View {
    HStack(alignment: .top, spacing: AppTheme.spacing.md) {
        if viewModel.isPairMode {
            completionAvatar(for: item)
        }
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            // 原有 title + subtitle + date stack 不变
        }
    }
    .padding(.vertical, AppTheme.spacing.xs)
}
```

Solo 模式布局保持现状（`if viewModel.isPairMode` 条件跳过 avatar）。

### 5.2 Avatar 规格

| 属性 | 值 |
|---|---|
| 大小 | 20pt diameter |
| Top offset | `.padding(.top, 2)`（基线对齐 headline 字形）|
| 组件 | `UserAvatarView` 复用 |
| Ring stroke | **无**（不加白边）|
| Fill color | 继承 `avatarAsset` 原色，fallback `avatarWarm` |

### 5.3 完成人解析（`lastActionByUserID` 作为代理）

```swift
@ViewBuilder
private func completionAvatar(for item: Item) -> some View {
    let completerID = item.lastActionByUserID
    let avatarAsset = viewModel.avatarAsset(forUserID: completerID)
    let displayName = viewModel.displayName(forUserID: completerID)

    UserAvatarView(
        avatarAsset: avatarAsset,
        displayName: displayName,
        size: 20,
        fillColor: AppTheme.colors.avatarWarm,
        symbolColor: AppTheme.colors.title.opacity(0.82),
        symbolFont: AppTheme.typography.sized(10, weight: .semibold),
        overrideImage: nil
    )
    .padding(.top, 2)
}
```

### 5.4 VM 新增 helpers

```swift
func avatarAsset(forUserID userID: UUID?) -> UserAvatarAsset
func displayName(forUserID userID: UUID?) -> String
```

数据源：
- `sessionStore.currentUser.id` + `.avatarAsset` → self
- `sessionStore.pairSpaceSummary?.partner.userID` + `.avatarAsset` → partner
- 其他 / nil → fallback `person.fill` icon + `avatarNeutral` 背景

### 5.5 Fallback 规则

| 条件 | Fallback |
|---|---|
| `lastActionByUserID == nil` | `.system("person.fill")` icon + `avatarNeutral` 背景 |
| userID 不在当前 pair space | 同上 |
| Avatar 图片未同步 | `UserAvatarView` 的 `reloadTick` 逻辑已处理 |

### 5.6 VoiceOver

整行 label 合并（避免嵌套 VO 元素）：

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel(
    "\(viewModel.displayName(forUserID: item.lastActionByUserID)) 完成 · \(item.title) · \(viewModel.completedDateText(for: item))"
)
```

读出示例：`"小狗 完成 · 洗衣服 · 今天 11:24"`

### 5.7 边缘情况

| 场景 | 处理 |
|---|---|
| 完成后 archive（`lastActionByUserID` 漂移到 archive 者）| MVP 接受精度损失；follow-up 可加专用 `completedByUserID` 字段 |
| 解除双人又重绑 pair（userID 漂移）| fallback 到通用 person icon |
| Solo 模式 | 整行无 avatar 列，布局与现状一致 |

---

## 6. 命名与空态

### 6.1 用户可见文案汇总

| 位置 | 文案 |
|---|---|
| Home icon accessibility label | `日志` |
| Home icon accessibility hint | `查看已完成任务` |
| `CompletedHistoryView.navigationTitle` | `历史任务` → **`日志`** |
| `searchable` prompt | `搜索已完成任务`（保持不变）|
| Solo / Pair 无数据但无 hero 场景的 empty state | 保持现有 `EmptyStateCard`：`还没有历史任务 / 已完成任务会在这里沉淀` |

### 6.2 空态条件分流

```swift
if viewModel.isPairMode, let summary = viewModel.pairSummary {
    LogbookPairSummaryHero(summary: summary)
}

if !viewModel.isPairMode, viewModel.sections.isEmpty {
    emptySection  // solo 专属 empty
}

if viewModel.isPairMode, viewModel.pairSummary?.totalCount == 0, viewModel.sections.isEmpty {
    // hero 已显示 "一起开始记录"，不再叠加 emptySection
}

ForEach(viewModel.sections) { ... }
```

最终渲染顺序：
```
if pair: hero
if solo && empty: emptySection
ForEach sections
```

---

## 7. 文件变动清单

### 7.1 新建（2）

| 路径 | 责任 |
|---|---|
| `Together/Features/Profile/LogbookPairSummaryHero.swift` | Pair hero 组件 + `LogbookPairSummary` struct + 3 档文案逻辑 + relativeTime 格式化 |
| `TogetherTests/LogbookPairSummaryTests.swift` | 3 档文案 + relativeTime 单测 |

### 7.2 修改（4）

| 路径 | 改动 |
|---|---|
| `Together/App/AppRoute.swift` | 新增 `enum HomeRoute { case logbook }` |
| `Together/Features/Home/HomeView.swift` | `headerSection` 加 `book.closed` icon 按钮；顶层 `NavigationStack` 挂 `navigationDestination(for: HomeRoute.self)` |
| `Together/Features/Profile/CompletedHistoryView.swift` | 导航标题 `历史任务` → `日志`；List 最顶部 pair-条件-渲染 hero；`historyRow(for:)` 加 leading avatar 列（pair only）；空态条件分流 |
| `Together/Features/Profile/CompletedHistoryViewModel.swift` | 新增 `isPairMode` / `pairSummary` / `avatarAsset(forUserID:)` / `displayName(forUserID:)` 四个 helper |

### 7.3 可能触及（1）

| 路径 | 原因 |
|---|---|
| `Together/Features/Home/HomeViewModel.swift` | 若当前无 `makeCompletedHistoryViewModel()` 工厂，需新增。实施时确认 |

---

## 8. 测试策略

### 8.1 新增单测（6 个）

`TogetherTests/LogbookPairSummaryTests.swift`：

```swift
@Test func pairSummary_zeroCount_uses起始文案()
@Test func pairSummary_underTen_uses第一件文案()
@Test func pairSummary_tenPlus_uses本月和最近文案()
@Test func relativeTime_justNow_returns刚刚()
@Test func relativeTime_minutesAgo_returnsN分钟前()
@Test func relativeTime_weekPlus_returns月日格式()
```

### 8.2 不破坏的现有测试

- `ProfileViewModelDerivedValuesTests`
- `ProfileTokenContrastTests`
- 全量 regression

### 8.3 手动冒烟

- Solo 进日志 → 无 hero / 无行内 avatar / 布局同原版
- Pair 0 件进日志 → hero 起始文案，无 empty 卡叠加
- Pair 1-9 件 → hero 含第一件 title
- Pair 10+ 件 → hero 含本月 + relativeTime
- Pair 模式行显示 avatar，长按 VoiceOver 读出完成人
- Home `book.closed` icon → push 进日志，haptic 触发
- Dark mode + AX5 Dynamic Type

---

## 9. 已知限制与 follow-up

1. **`lastActionByUserID` 精度损失**：item 完成后被 archive / 其他操作会漂移。MVP 接受；未来可加专用 `completedByUserID: UUID?` 字段 + sync migration（独立 plan）
2. **Stats 聚合性能**：>1000 条 completed item 时 VM load 可能变慢。MVP 不优化；后期用 `#Expression` 或 caching
3. **Home 底栏 dock 不改**：独立 brainstorm
4. **Pair 模式 filter**（"我完成的 / 对方完成的"）不做：用户验证的 scope 是 MVP+a

---

## 10. 实施规模

| 维度 | 估算 |
|---|---|
| 新代码 | ~200 行 |
| 修改代码 | ~60 行 |
| 新测试 | 6 个 |
| Task 拆分 | 4 task，1 batch |
| 实施时长 | 4-6 小时 |

---

## 11. Open decisions

所有核心决策已在 brainstorm 过程中确认：

- 方案 α（Things Logbook 风 + Home 顶栏入口）— 用户确认
- 名称「日志」— 用户确认
- Pair 模式 stats hero 叙事式（C 方案）— 用户确认
- Icon `book.closed` — 用户确认
- Scope MVP + a（行内完成人小头像）— 用户确认
- 无 pair 小红点视觉提示 — 用户确认
- `HomeRoute.logbook` 本地 route — 用户确认
- 20pt avatar / 无白边 / nil fallback — 用户确认
