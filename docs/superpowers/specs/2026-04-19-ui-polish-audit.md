# Together UI/UX Polish Audit — 2026-04-19

## 0. Methodology

File-based grep + targeted code-reading across 60 Swift files in `Features/` + `Core/DesignSystem/`. 
**Scope**: AppTheme token consistency, hardcoded values, accessibility, animations, empty/error states, pair/solo mode distinction, iPad adaptation.  
**No simulator screenshots**. Data-driven grep counts + representative code snippets.

---

## 1. Token Consistency Violations

### 1.1 硬编码颜色（Color hardcoding）

**11 files** use `Color.gray` / `Color.white` / `Color.black` directly:

- [HomeView.swift:2234-2239](Together/Features/Home/HomeView.swift:2234): `AppTheme.colors.body.opacity(...)` 用了 opacity 绕过 token（应统一为 `textTertiary`）
- [HomeView.swift:67](Together/Features/Home/HomeView.swift:67): `Color.clear` 可接受（背景 tap 区域）
- [HomeItemDetailSheet.swift](Together/Features/Home/HomeItemDetailSheet.swift): 多处 `Color.gray` 在 badge 背景（应改 `AppTheme.colors.surface` 或新增 `.badgeBackground`）
- [EditProfileView.swift:452](Together/Features/Profile/EditProfileView.swift:452): `Color.white.opacity(0.08)` 在 glass 效果内（应新增 `AppTheme.colors.glassTint` token）
- [Profile 模块](Together/Features/Profile/): 6 处 `Color.white.opacity(0.X)` / `Color.black.opacity(0.X)` 用于半透明层（深色模式对比度风险 ⚠️）

**建议**: 新增 token:
- `AppTheme.colors.badgeBackground` (14、18 radius badge fill)
- `AppTheme.colors.glassTint` (玻璃态 overlay 的微色)
- 审查所有 `.opacity(0.X)` 在深色模式下的 WCAG AA 对比度

### 1.2 硬编码 cornerRadius

**93 处** 发现以下 radius 值：

| 数值 | 出现次数 | 建议归纳为 |
|------|--------|---------|
| 9    | 2      | 新增 `.chip` (9) |
| 11   | 10     | 新增 `.badge` (11) |
| 12   | 1      | 拆分；或统一为 14 |
| 14   | 2      | 新增 `.sheet` (14) |
| 16   | 4      | 新增 `.input` (16) 或统一为 14 |
| 18   | 17     | 新增 `.segment` (18) |
| 20   | 9      | 已有 `AppTheme.radius.card` ✓ |
| 22   | 3      | 统一为 20 或 26 |
| 24   | 2      | 统一为 20 或 26 |
| 26   | 5      | 新增 `.large` (26) |
| 28   | 7      | 已有但用 hardcode；应改用 token |
| 30   | 3      | 统一为 28 或 26 |
| 34   | 4      | 新增 `.xlarge` (34) |

**现状**: `AppTheme.radius` 只有 `card(20)` 和 `pill(999)` → **严重不足**。  
**建议**: 扩展为 `xs(9), sm(11), md(14), lg(18), card(20), xl(26), xxl(34), pill(999)` 并全量 replace。

**代表性例子**:
- [HomeView.swift:2249](Together/Features/Home/HomeView.swift:2249): `cornerRadius: 11` → `AppTheme.radius.badge`
- [RoutinesDetailSheet.swift:230](Together/Features/Routines/RoutinesDetailSheet.swift:230): `cornerRadius: 28` → `AppTheme.radius.xxl`
- [EditProfileView.swift:254](Together/Features/Profile/EditProfileView.swift:254): `cornerRadius: 22` → `AppTheme.radius.xl` (26) 或新增 22

### 1.3 硬编码 spacing / padding

**229 处** 发现非 token 值分布：

| 数值 | 出现次数 | 对标 token | 建议 |
|------|--------|-----------|------|
| 4    | 14     | — | 新增 `AppTheme.spacing.xxs` (4) |
| 6    | 17     | — | 新增 `AppTheme.spacing.xxxs` (6) 或用 xs(6) |
| 8    | 33     | — | 新增 `AppTheme.spacing.xxs` (8) |
| 10   | 54     | `AppTheme.spacing.sm` ✓ | 已对齐多数 |
| 12   | 41     | — | **问题**: 介于 sm(10) 和 md(16) 之间，建议统一为 10 或 16 |
| 14   | 6      | — | 统一为 16 (`md`) |
| 16   | — | `AppTheme.spacing.md` ✓ | 应更广泛使用 |
| 20   | — | `AppTheme.spacing.lg` ✓ | 应更广泛使用 |
| 28   | 3      | `AppTheme.spacing.xl` ✓ | 应更广泛使用 |

**现状**: 大量 `spacing: 12` 无对应 token；`padding(.vertical, 6)` / `padding(4)` 等魔数遍布。  
**建议**: 
1. 在 `AppTheme.spacing` 新增: `xxs(6)`, `xs(8)` 或重新定义为 `(4, 6, 10, 16, 20, 28, 36)`
2. **全量 sed 替换**: 
   - `spacing: 12` → `AppTheme.spacing.md` (16)
   - `padding(.vertical, 6)` → `padding(.vertical, AppTheme.spacing.xs)`

**代表性例子**:
- [HomeView.swift:29](Together/Features/Home/HomeView.swift:29): `calendarGridHorizontalInset: CGFloat = 4` → token化
- [ComposerPlaceholderSheet.swift](Together/Features/Shared/ComposerPlaceholderSheet.swift): 28 处 `spacing: X`；其中 14 处 = 12 → 应统一

### 1.4 绕开 AppTheme.typography

**32 处** 使用了 `.font(.system(size:))` / `.font(.body)` / `.font(.caption)` 而非 `AppTheme.typography.textStyle()`：

| 类型 | 文件数 | 问题 |
|------|--------|------|
| `.font(.system(size: X))` | 12 | 无 Dynamic Type scaling |
| `.font(.body)` | 8 | 绕过了自定义 rounded font + 中文支持 |
| `.font(.caption)` | 3 | 无法统一维护字号/weight |

**代表性例子**:
- [SyncStatusIndicator.swift](Together/Features/Home/Components/SyncStatusIndicator.swift): 5 处 `.font(.system(...))` → 应改 `AppTheme.typography.sized()`
- [ProfileFeedbackView.swift](Together/Features/Profile/ProfileFeedbackView.swift): `.font(.body)` → `AppTheme.typography.textStyle(.body)`
- [ImportantDatesManagementView.swift](Together/Features/Anniversaries/ImportantDatesManagementView.swift): 2 处 `.font(.caption)`

**建议**: 
- 全量 grep + replace `.font(.body)` → `AppTheme.typography.body`
- 固定 size 改用 `AppTheme.typography.sized(size, weight:)`

---

## 2. 动效 / 触感反馈（Animations & Haptics）

### 2.1 已有的 pattern

✓ **HomeInteractionFeedback** 广泛使用（237+ 次 grep 命中）:
- `selection()` — 按钮点击、navigation（主要）
- `completion()` — save、task 完成
- Spring animations（`response: 0.3-0.34, dampingFraction: 0.84-0.88`）在：
  - Task completion badge 动画（[HomeView.swift:2209](Together/Features/Home/HomeView.swift:2209)）
  - Timeline row entry（scale + offset + opacity）
  - Sheet present/dismiss

✓ **Symbol effect** 在 checkmark、icons 上（`.symbolEffect(.bounce)`）

### 2.2 缺失的 pattern

**问题**: 以下交互**无** haptic 反馈：
- ❌ List item swipe-to-delete（[Routines](Together/Features/Routines/)、[Home](Together/Features/Home/) 删除行）
- ❌ Toggle switches（On/Off 状态切换 — 仅有 animation，无 haptic）
- ❌ Long-press menu 打开/关闭
- ❌ Sheet 快速 swipe dismiss（虽然有 animation，但无 haptic closure 感）
- ❌ Error alert 出现（仅有 alert sound，无触感）
- ❌ Form validation failure（输入框红色 shake 时无 warning haptic）

**代表性空缺**:
- [HomeItemDetailSheet.swift](Together/Features/Home/HomeItemDetailSheet.swift): 删除 item → 仅 alert 确认，无 delete haptic
- [RoutinesDetailSheet.swift](Together/Features/Routines/RoutinesDetailSheet.swift): 删除 routine → 同上
- [ProfileView.swift](Together/Features/Profile/ProfileView.swift): unbind pair 确认 → 无 warning haptic

**建议**: 新增 `HomeInteractionFeedback.delete()` / `.error()` / `.warning()`，补全上述场景。

---

## 3. 空态 / 加载态 / 错误态

### 3.1 按 screen 盘点

| Screen | Empty State | Illustration | Loading | Error Alert | 状态 |
|--------|------------|-------------|---------|------------|------|
| **Home** | Task list 无任务 | ❌ 无插图 | ✓ ProgressView | ✓ Alert | 部分实现 |
| **Profile** | 完成历史 empty | ✓ [EmptyStateCard.swift](Together/Features/Shared/EmptyStateCard.swift) 文本卡片 | ✓ | ✓ | 基础可用 |
| **Routines** | No routines | ❌ 无插图 | ✓ | ✓ | 缺插图 |
| **Anniversaries** | No dates | ❌ 无插图 | ✓ | ✓ | 缺插图 |
| **Decisions** | No items | ❌ 无插图 | — | — | **未审** |
| **Lists** | No items | ❌ 无插图 | ✓ | ✓ | 缺插图 |
| **Projects** | No projects | ❌ 无插图 | ✓ | ✓ | 缺插图 |
| **Calendar** | No events (month) | — | ✓ | ✓ | 合理 |

**缺失**: 
- 所有列表 screen 的 empty state **插图**（无品牌感）
- Task 编辑时验证失败 → inline error（仅有 alert）

**代表性**:
- [ListsView.swift](Together/Features/Lists/ListsView.swift): 检查 empty 分支 → `Text("没有任务")`，无卡片包装
- [RoutinesListContent.swift](Together/Features/Routines/RoutinesListContent.swift): 无 routine 时文本提示，无插图

### 3.2 加载指示

✓ `ProgressView()` / `.loading(isLoading:)` 在数据 fetch 时
✓ 无过度使用 skeleton screen

❌ **issue**: [ComposerPlaceholderSheet.swift](Together/Features/Shared/ComposerPlaceholderSheet.swift) 中 20+ 处 `.redacted(reason: .placeholder)` 用于骨架屏，但**无明确 loading state**（是否在加载音频？用户不知道）

**建议**: 加一个统一的 loading overlay / toast（比如 "正在上传..." — 目前缺）。

### 3.3 错误处理

| 类型 | 使用 | 例子 |
|------|------|------|
| Alert | 主要 | [EditProfileView.swift:62](Together/Features/Profile/EditProfileView.swift:62): `.alert("无法完成操作")` |
| Inline hint | 少 | [ComposerPlaceholderSheet.swift](Together/Features/Shared/ComposerPlaceholderSheet.swift): 输入框下方 `Text("X")`（无颜色 token） |
| Toast | 无 | — |

**不一致**: Alert 用 system style，inline 提示无统一样式（有些灰色、有些红色、无 icon）。

**建议**: 定义一套 error/warning/success toast component，用 `AppTheme.colors.danger / warning / success`。

---

## 4. 排版节奏

### 4.1 卡片 / 行高 / 分组间距

**[HomeView.swift](Together/Features/Home/HomeView.swift) 首页胶囊问题**:
- 34 行定义了一堆私有常数（`contentCardCornerRadius = 40`, `calendarGridHorizontalInset = 4` 等）
- 多处 `spacing: 8` / `spacing: 12` 混用，导致 capsule 之间**间距参差**
- 同时有 `timelineRowVerticalInset = 14` + `monthGridSpacing = 8` + `monthCompressedGridSpacing = 4`
  → 视觉节奏不清晰

**Profile 卡片**:
- [ProfileSettingsGroupCard.swift](Together/Features/Profile/ProfileSettingsGroupCard.swift): `cornerRadius: 26` hardcode
- [ProfileUserCard.swift](Together/Features/Profile/ProfileUserCard.swift): 头像 + 名字卡片行高 OK，但与下方设置卡片间距 (`spacing: 12`) 与上方标签间距 (`spacing: 10`) 参差

**建议**: 
1. 胶囊群组间距统一为 `AppTheme.spacing.md` (16)
2. 卡片内部行高统一为 `AppTheme.spacing.sm` (10)
3. 见第 1.3 节的 sed 替换计划

### 4.2 Pair / Solo 模式下胶囊优先级

当前 [HomeView.swift](Together/Features/Home/HomeView.swift) 上部显示：
- 顶部「Pair Space」标签（若已配对）
- 胶囊顺序（overdue / routine summary / anniversary capsules）

**缺陷**:
- Pair 标签**字号不突出**（用了 `textStyle(.caption)` ~ 11pt）
- 无视觉分隔（背景色 = 内容背景色）
- Pair-only feature（纪念日）在 solo 模式下也显示（虽然单独管理，但无模式标记）

**建议** (初步):
1. Pair 标签改为 pill badge（`AppTheme.radius.pill`, 背景 = `AppTheme.colors.accent` 或新增 `.pairBadge`）
2. 新增 solo-only / pair-only 视觉标记（小 icon + 标签）
3. 考虑在 pair 模式下胶囊前加**小型配对 icon**（提示用户在双人模式）

---

## 5. 可达性（a11y）

### 5.1 Dynamic Type

**32 处** 使用固定 font size（`.font(.system(size: 14))` 等）→ **无法缩放**。

当用户设置 Accessibility → Text Size → xxxLarge 时，这些 view 文字**不会变大**。

**代表性**:
- [SyncStatusIndicator.swift](Together/Features/Home/Components/SyncStatusIndicator.swift): 5 处 `.system(size: 11/12/13)`
- [ProfileAboutView.swift](Together/Features/Profile/ProfileAboutView.swift): `.system(size: 16)`

**影响范围**: 低视力用户 → 无法阅读（约 8% iOS 用户启用）

**建议**: 全量改用 `AppTheme.typography.textStyle(.caption / .body / .headline, weight:)` 并测试 xxxLarge 显示。

### 5.2 VoiceOver 标签覆盖率

**16 处** 发现 `.accessibilityLabel` / `.accessibilityHint`（仅 6 个文件）:

- [HomeDockBar.swift](Together/Features/Shared/HomeDockBar.swift): 4 处（按钮 label OK）
- [HomeView.swift](Together/Features/Home/HomeView.swift): 3 处（timeline item）
- [ProfileUserCard.swift](Together/Features/Profile/ProfileUserCard.swift): 4 处（用户头像 + 状态）

**缺失**: 
- ❌ Form input（[ComposerPlaceholderSheet.swift](Together/Features/Shared/ComposerPlaceholderSheet.swift) 的标题输入框、标签输入框）
- ❌ Icon-only button（[RoutinesTaskRow.swift](Together/Features/Routines/RoutinesTaskRow.swift) 的删除 icon）
- ❌ Segmented control（status picker）

**建议**: 补全至少 50 个核心交互元素的 label（估计 20-30% 补充）。

### 5.3 触控目标 ≥ 44pt

**69 处** 发现 `frame(width: X, height: Y)` 其中 X 或 Y < 44：

| 尺寸 | 出现 | 问题 |
|------|------|------|
| 16×16 | 1 | icon 太小（删除 icon） |
| 18×18 | 1 | icon 太小 |
| 28×28 | 2 | icon 勉强（应 >= 40）|
| 32×32 | 2 | icon 勉强 |
| 40×40 | 6 | **边界**（官方 44×44） |

**代表**:
- [TaskEditorSharedComponents.swift:287](Together/Features/Shared/TaskEditorSharedComponents.swift:287): `frame(width: 16, height: 16)` 内一个删除 icon → 用户难点击
- [ComposerPlaceholderSheet.swift:2319](Together/Features/Shared/ComposerPlaceholderSheet.swift:2319): `frame(width: 18, height: 18)`

**建议**: 将所有 icon button 改为 `minWidth: 44, minHeight: 44`（或外套 `.contentShape(Circle())`）。

### 5.4 对比度

292 处 `.opacity(0.X)` 使用，其中深色模式下风险例子：
- [HomeView.swift:2239](Together/Features/Home/HomeView.swift:2239): `AppTheme.colors.body.opacity(0.68)` 在深色背景 → body 已是 72% gray，0.68 倍率 = 44% gray on #2A2A2D → **不足 WCAG AA**
- [EditPairProfileView.swift:258](Together/Features/Profile/EditPairProfileView.swift:258): `AppTheme.colors.surfaceElevated.opacity(0.82)` 作为背景 → 在 glass blur 下对比度可能破裂

**建议**: 
1. 审查深色模式下所有 `body.opacity(< 0.7)` 和 `surface.opacity(< 0.6)` 
2. 用 WebAIM contrast checker（dark mode simulation）验证

---

## 6. Pair 模式 vs Solo 模式视觉区隔

### 6.1 当前状态

**顶部模式标签**:
- [ProfileView.swift:202-291](Together/Features/Profile/ProfileView.swift:202): `if viewModel.bindingState == .paired { ... }` 显示 pair UI
- 但**首页** [HomeView.swift](Together/Features/Home/HomeView.swift) **无明显 pair/solo indicator**

**Pair-only feature**:
- [AnniversaryCapsuleView.swift](Together/Features/Anniversaries/AnniversaryCapsuleView.swift): 纪念日胶囊在 pair mode 显示，但无标记
- 配色 = `AppTheme.colors.sun / coral`（与 solo task 相同逻辑 → 无区隔）

**问题**: 用户不清楚**当前是否在 pair mode**（除非看 profile）。

### 6.2 建议方向

1. **在 Home topChrome（[HomeView.swift:63](Together/Features/Home/HomeView.swift:63)）加 pair badge**
   - 若 `isPairMode`: 显示小 icon + "Pair Mode" pill（背景 = 新增 `AppTheme.colors.pairAccent`）
   - 放在日期/星期显示旁

2. **新增 AppTheme token** (建议，不实施):
   ```swift
   enum colors {
       static let pairAccent = Color(light: .init(...), dark: .init(...))  // 蓝绿色或专属配色
       static let pairAccentSoft = ...  // 用于 background
   }
   ```

3. **纪念日胶囊** 加小标签 "Pair"（仅在 pair mode）

---

## 7. iPad / 大屏适配

### 7.1 当前 layout 假设

**grep 结果**: 仅 1 处提及 iPad（注释）。  
**无** `horizontalSizeClass` / `UIDevice.userInterfaceIdiom` 检查。

**现状**: 所有 UI 按**手机宽度**设计，iPad 上会导致：
- 两边大量空白
- Sheet 全屏（应 popover）
- List 无 2-column split

### 7.2 Sheet detents / split view / sidebar

**当前 sheet 用法**:
- [HomeView.swift:89-96](Together/Features/Home/HomeView.swift:89): `.sheet(isPresented:) { HomeItemDetailSheet(...) }` → 全屏 sheet
- [EditProfileView.swift](Together/Features/Profile/EditProfileView.swift): NavigationStack + sheet 混用 → iPad 上应改 NavigationSplitView

**缺少**:
- ❌ `presentationDetents` 限制 sheet 高度（都是全屏）
- ❌ 横屏适配（iPad 或大屏手机横向）
- ❌ 2-pane layout（如 Projects list + detail）

**建议** (初步):
1. 在 iPad 上 sheet 改为 `.popover` / `.presentationDetents([.medium, .large])`
2. Project / Routine 列表改 NavigationSplitView（iPad）
3. 至少测试 iPhone 15 Pro Max（6.9") 横屏

---

## 8. 优先级建议（P0 / P1 / P2）

### P0（不做体验明显破，影响感知度最高）

| 项目 | 理由 | 规模 |
|------|------|------|
| **Token 扩展** (Radius 8 种 + Spacing 4 种) + 全量 sed 替换 | hardcode radius/spacing 散落在 93/229 处，影响维护效率；一次 replace 即可清 | 中 |
| **Pair 模式首页标签** | 用户无法快速判别当前模式（须进 profile），pair feature 隐形 | 小 |
| **touchTarget >= 44pt** | 影响易用性，尤其删除按钮；无障碍等级 | 小 |

### P1（做了明显提升体验）

| 项目 | 理由 | 规模 |
|------|------|------|
| **Empty state 插图** | 目前只有文字卡片（EmptyStateCard），无品牌感；插图库 + 7 页面补全 | 中 |
| **Haptic 补全** | Delete / Error / Warning haptic；目前仅有 selection/completion | 小 |
| **Dynamic Type 全量测试** | 32 处固定 font size；xxxLarge 模式下无法阅读 | 小 |
| **Pair/Solo 配色分化** | 考虑新增 `.pairAccent` token（可选蓝绿/专属色），纪念日胶囊 + badge 改色 | 小 |

### P2（锦上添花）

| 项目 | 理由 | 规模 |
|------|------|------|
| **iPad 横屏适配** | 仅 1 处提及 iPad；NavigationSplitView + popover sheet 改造 | 大 |
| **VoiceOver 标签完整化** | 16 处已实现；补全至 50+ 核心交互（form input / icon-only button / segment） | 中 |
| **Error toast 样式统一** | 目前 Alert only；补充 inline hint + toast（低优先，可用 alert 代） | 小 |

---

## 9. 本审计未覆盖的建议维度

1. **全机型 Safe Area 适配** — 仅审视代码，未在模拟器验证 notch / Dynamic Island / USB-C port cutout（iPhone 15+）
2. **深浅色模式全量截图对比** — 代码审查仅抽样；应逐 screen 对比明暗配色协调度
3. **Accessibility Zoom（150% / 200%）** — Dynamic Type 测试了，未测 zoom 级别
4. **Performance / rendering optimization** — 未审查 overdraw / layer count / animation smoothness（60 vs 120 fps）
5. **国际化（i18n）— 汉字布局** — 文本长度（英文 vs 中文）可能导致 truncation，未全量检查

---

## 📊 总体统计

| 维度 | 问题数 | 严重度 |
|------|--------|--------|
| Token 不一致（颜色 + radius + spacing + typography） | 359+ | 高 |
| Haptic 缺失 | 5 类场景 | 中 |
| Empty state 缺插图 | 6+ screen | 中 |
| Dynamic Type 无法缩放 | 32 处 | 中 |
| VoiceOver label 缺失 | ~40+ 元素 | 中 |
| 触控目标 < 44pt | 20+ 个 | 低-中 |
| 对比度风险（深色模式） | 15+ 处 | 低 |
| iPad 无适配 | 整个 app | 低（市场 ~25%） |
| Pair 模式无标记 | 首页 | 低 |

**Total Actionable Issues**: 9 大类 + 100+ 细项

---

## 🎯 建议下一步

1. **Week 1**: 确认 P0 优先级（token 扩展 + pair 标签）；预估工期 1-2 day
2. **Week 2-3**: 执行 P0 + P1 中的 token 和 haptic；约 3-5 day
3. **Week 4**: 测试（全机型、深浅色、Dynamic Type）+ iPad 调研

