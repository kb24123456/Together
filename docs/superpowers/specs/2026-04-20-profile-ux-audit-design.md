# Profile 页面 UI/UX 全面评估与 L3 Redesign 设计规范

- **日期**: 2026-04-20
- **范围**: `Together/Features/Profile/` 全部文件 + `AppTheme.swift` 局部新增
- **方向**: β — Claude 克制骨架 + Together 双人温度
- **优先级**: A 信息架构 > B 视觉一致性 > C 交互流畅度
- **改造幅度**: L3（评估到位，实施分阶段；本 spec 对应 L3 完整目标）

---

## 1. 背景与问题诊断

### 1.1 当前 Profile 的 3 类问题

1. **信息架构**（优先级 A）
   - 9 个分组，其中「外观」独立成组、「历史任务」错位于通知分组（数据视图而非设置项）、「Pro banner」内嵌于数据分组视觉扎眼
   - 分组顺序与行业共识偏离（安全放在数据前属于非主流）
   - 「双人协作」里的邀请/解绑用填充按钮，与其他分组的 row 语言不统一

2. **视觉一致性**（优先级 B）
   - `ProBannerRow` 深色渐变 + 彩虹 angular gradient 描边——与米白底盘直接冲突
   - 名片区横向 pill 布局 + 右侧「我」字——违反"头像→名字"从上到下阅读动线
   - 外观 capsule tab 用 `sky` 蓝选中、选项行用 `sky` 蓝 checkmark——与 `pairAccent` coral 形成双 accent 混用
   - 退出登录是 filled 按钮样式（浅灰背景 + 阴影），看起来像主操作而非危险操作

3. **交互流畅度**（优先级 C）
   - Disclosure 用 0.2s easeOut，手感略显机械（行业共识是 spring）
   - 模式切换 solo ⇄ pair 时名片区静态变化，缺失视觉过渡

### 1.2 目标美学锚点

- 参考 Claude iOS（暖米白 `#FAF9F5` + coral `#D97757` + hairline divider）
- 参考 Paired（双头像 30% 重叠 + editorial 名字层级 + 纪念日副标）
- **不**引入新字体（保持现有 AppTheme 的 `.rounded` + Han Rounded CN 字体栈）
- **不**追求冷色编辑期刊感（Together 的双人基因要保留温度）

### 1.3 Goals / Non-goals

**Goals**
- 减少视觉噪音，让米白底盘说话
- 统一行级语言，消除"按钮 vs row"混用
- 为未来 Pro 订阅预埋符合编辑气质的入口
- 明确 pair 模式下名片区作为全页唯一 hero

**Non-goals**
- 不触碰 EditProfile / EditPairProfile / InvitePendingSection / CompletedHistoryView 内部实现（这些是 Profile 的子页面，内部自治）
- 不改全局 `AppTheme` token，只新增；已上线模块（Home / Calendar / Decisions）的 `sky` 用法维持不动
- 不引入字体打包（保留现有 PingFang Rounded / Han Rounded CN）
- 不实施 Pro 订阅功能本身——本 spec 仅定义 Pro 入口的视觉与位置

---

## 2. 信息架构（IA）

### 2.1 目标结构（9 → 6 + 名片区 + 退出）

```
名片区（hero，无卡片背景，仅 hairline 分隔）
├─ Pro 入口（独立一行，无分组头）※ Section 5
├─ 1. 双人协作
│   · paired 状态：当前工作空间 / 双人模式 / 纪念日管理 / 解除双人空间（红字）
│   · singleTrial|unbound：发起双人邀请（inline row）/ 输入邀请码（inline row）
│   · invitePending：保留 InvitePendingSection 特殊 UI
│   · inviteReceived：接受 / 拒绝 2 个 row
├─ 2. 执行偏好
│   · 临期任务提醒（toggle） + 提醒时间（disclosure，toggle 开启时展开）
│   · 默认推迟时间（disclosure）
│   · 双人预设留言（disclosure，仅 pair 显示）
│   · 已完成自动归档（toggle） + 归档时间（disclosure）
├─ 3. 通知与外观  ⚠️ 合并（原「通知与权限」+「外观」）
│   · 提醒权限
│   · 权限管理 → 系统设置
│   · 外观 → 子页（浅/深/跟随系统）  ※ capsule tab 废弃
├─ 4. 安全与隐私
│   · 应用锁定（Face ID toggle） + 说明文字
├─ 5. 数据与账号  ※ Pro banner 已移出
│   · iCloud 同步
│   · 清除缓存
│   · 账号注销 → 子页
├─ 6. 关于
│   · 关于 → 子页，右侧显示 v{version}
└─ 退出登录（独立红字行，无分组头，浮于全页最底）
```

### 2.2 关键变动（4 项）

| # | 变动 | 理由 |
|---|---|---|
| A | 「外观」并入「通知与外观」并改为 disclosure + 子页 | 外观是低频操作；行业 10 款 App 中 7 款如此处理 |
| B | 「历史任务」从 Profile 移出 → 首页顶栏入口 | 数据视图，非设置项，语义错位 |
| C | Pro banner 从「数据与账号」移出 → 名片区下独立一行 | 它是账户状态而非数据项；Claude iOS 一致 |
| D | 「纪念日管理」仅 pair 模式显示 | 已是现状，保持 |

### 2.3 保留不变的 3 个决策

1. 退出登录独立红字行浮于最底，无分组头
2. 账号注销 → 子页做两步确认（合规必备）
3. 解除双人空间保留在双人协作分组内，红字 row

---

## 3. 名片区（Identity Card）详细设计

### 3.1 布局

**Solo 模式**：
```
       ○  ← 64pt avatar
      [name]   ← 22pt, weight=.light, tracking=0.3
     [subtitle]   ← 13pt, textTertiary
```

**Pair 模式**：
```
      ○○  ← 两个 92pt avatar，HStack(spacing: -20pt) → ~22% 重叠
          ↑    公式：overlap_ratio = overlap_amount / diameter
               历史实现 bug：早期用 offset=28pt on 56pt 误以为 30%，
               实际为 (56-28)/56 = 50% 重叠；改用 HStack-with-negative-
               spacing 几何更直观，避免再犯
          z-index: self 在下，partner 在上
    [name & partner]   ← 同 Solo 字号
   [space · N 天]   ← 同 Solo 字号
```

### 3.2 文案规格

| 状态 | 主标 | 副标 |
|---|---|---|
| solo | `{displayName}` | `独立工作空间` |
| pair | `{你的名字} & {对方名字}` | `{空间名} · 配对 {N} 天` |

- "&" 使用真正的 ampersand 字符，非"和"或"＆"
- `{N}` 由 `pairDaysCount` 计算属性提供（基于 space `createdAt` 至今的整天数）
- 主标 `maxWidth`: card width - 40pt，超长尾部 truncate

### 3.3 样式规格

```
卡片背景:          无（直接裸露在米白底上）
底部分隔:          hairline divider（新 token），1px
avatar-name gap:  spacing.md (16pt)
name-subtitle gap: spacing.xxs (4pt)
card top padding:  spacing.xl (28pt)
card bottom padding: spacing.lg (20pt)
```

### 3.4 Avatar 状态规则

```
self avatar：
  · 有自定义图片 → 渲染图片
  · emoji/system icon → icon + coral 背景圆
  · 空 → 默认人像 glyph + 浅灰背景圆

partner avatar（仅 pair 模式）：
  · 已上传 → 图片
  · 未自定义 → emoji/icon + 浅 coral 背景
  · 数据同步中 → 虚线边框 + 问号 glyph

solo 模式下删除"虚线加号占位"（邀请入口移到下方分组）
```

### 3.5 交互

- 整卡 `NavigationLink` → `editProfile`（solo）或 `editPairProfile`（pair）
- 点击 haptic: `.selection()`
- 保留现有 `matchedTransitionSource` zoom transition

---

## 4. 分组详细设计

### 4.1 双人协作

**关键改动**：废弃 `collaborationButtonLabel(title:tint:)` 填充按钮，全部改为 inline row。

| 状态 | 内容 |
|---|---|
| singleTrial / unbound | row「发起双人邀请 >」 + row「输入邀请码 >」 |
| invitePending | 保留 `InvitePendingSection`（二维码 / 倒计时 / 操作复杂，不适合 row 化） |
| inviteReceived | 横向 2 个 row：「接受邀请 >」/「拒绝 >」 |
| paired | row「当前工作空间」{空间名} <br> row「双人模式」双人 <br> row「纪念日管理 >」 <br> row「解除双人空间」（`danger` 色，最后一行） |

**实现注意**：
- 解除空间的文字颜色从 `coral` → `danger`（语义更清晰，避免 coral 过载）
- `createInviteError` 非空时，在 CTA row 下方保留现有红字提示（12pt `danger`）

### 4.2 执行偏好

保持现有 6 行结构。微调：

| 项 | 当前 | 目标 |
|---|---|---|
| Disclosure 展开动画 | 0.2s easeOut | spring(response: 0.32, damping: 0.86) |
| 展开内 divider | `outline.opacity(0.45)` | `hairline` token |
| `ProfileInlineOptionButton` 选中色 | `sky` | `selectionTint`（= `pairAccent`）|
| `ProfileInlineOptionButton` 选中背景 | `sky.opacity(0.1)` | `selectionTint.opacity(0.08)` |
| `ProfileQuickReplyEditor` "保存预设"按钮 | filled button | 单行 row：「保存」右对齐 coral 文字 |

### 4.3 通知与外观（合并）

```
提醒权限                              {已开启 / 去开启 / 未开启} [>]
权限管理                              系统设置 >
外观                                  {跟随系统 / 浅色 / 深色} >
```

**新建 `ProfileAppearanceView`**：
- 3 行 List：跟随系统 / 浅色 / 深色
- 右侧 `checkmark`（`selectionTint` 色）表示当前选中
- 点击切换 + `.selection()` haptic
- `withAnimation(.spring(response: 0.28, dampingFraction: 0.86))` 切换

**删除**：
- `ProfileView.appearanceSection` 中的 capsule tab UI（~25 行）
- 历史任务 NavigationLink（~10 行，移到 Home 层另案处理）

### 4.4 安全与隐私

几乎无改动。微调：

- 说明文字 `sized(13, weight: .medium)` → `sized(12, weight: .regular)`
- 颜色 `textTertiary` → `textTertiary.opacity(0.78)`
- 说明文字与 toggle 间距 `spacing.xxs` → `spacing.xs`

### 4.5 数据与账号

删除 `ProBannerRow`（已移至名片区下）。最终结构：

```
iCloud 同步                已连接
清除缓存                  {cacheSize}
账号注销                          >
```

### 4.6 关于

标题简化：「关于 Together」→「关于」。

```
关于                           v{appVersion} >
```

### 4.7 退出登录（独立，无分组头）

```
                 退出登录            ← 15pt semibold danger，无背景无阴影
```

代码改动：
```swift
Text("退出登录")
    .font(AppTheme.typography.sized(15, weight: .semibold))
    .foregroundStyle(AppTheme.colors.danger)
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
```

删除：`surfaceElevated` 背景 + `shadow(radius: 8, y: 4)` + `RoundedRectangle` 包裹。

---

## 5. Pro 会员入口

### 5.1 方案：单一中性 row + 位置于名片区下方

**位置**：名片区 hairline 分隔线之下，「双人协作」分组之上，独立一行**无分组头**。

### 5.2 视觉规格

```
· Together Pro                       >
  {subtitleCopy}
```

| 元素 | 规格 |
|---|---|
| 行高 | 与普通 row 一致 ~56pt（含 subtitle 时 64pt） |
| 背景 | `surfaceElevated`，与其他 row 一致，不做渐变不做描边 |
| leading glyph | 4pt coral 圆点（`pairAccent`） |
| 主标 | `Together Pro`，15pt semibold，`title` 色 |
| 副标 | 单行 ≤40 char，12pt regular，`textTertiary` |
| trailing | `chevron.right`（统一 chevron 样式） |

### 5.3 3 种状态

| 状态 | 副标文案 |
|---|---|
| Free | 「共享仪式、更长历史、自定义主题」（静态或 3 条轮换） |
| Trial | 「试用剩余 {N} 天 · {续费日期} 续费」 |
| Active | 「订阅中 · 下次续费 {renewalDate}」 |

**订阅后 row 不消失，仅变形**（符合行业反模式规避）。

### 5.4 ViewModel 扩展

新增枚举（现阶段默认为 `.free`，未来 Pro 功能实装时接入真实数据）：

```swift
enum ProSubscriptionStatus {
    case free
    case trial(daysLeft: Int, renewalDate: Date)
    case active(renewalDate: Date)
}
```

### 5.5 次级入口（仅 spec 备注，本次不实施）

未来 feature-gate 半屏（iOS 15+ `.presentationDetents([.medium])`）：
- 标题：「{feature 名} 是 Together Pro 的一部分」
- 3 条 benefit bullets 与触发功能相关
- 主 CTA「了解 Pro」（coral fill）
- 次 CTA「稍后再说」（plain text）
- 路由到同一 paywall 子页

### 5.6 3 条硬性护栏

1. 不在 Profile tab icon 上加 badge 暗示升级
2. 不在 App 启动时主动弹 paywall（哪怕一次都不要）
3. 不同时存在 banner + row，永远只用 row

---

## 6. 视觉 Token 更新

### 6.1 新增 Token（3 个）

```swift
// AppTheme.swift 新增
extension AppTheme.colors {
    static let hairline = Color(
        light: .init(red: 0.16, green: 0.18, blue: 0.19).opacity(0.10),
        dark: .white.opacity(0.08)
    )

    static let selectionTint = pairAccent  // Profile 选中态统一别名
}

extension AppTheme.typography {
    static func displayLight(_ size: CGFloat) -> Font {
        Font(uiFont(size: size, weight: .light))
    }
}
```

### 6.2 修改 Token

**无**。已有 token 均保留，所有改动通过新增 token + 替换使用点实现。

### 6.3 Profile 模块内 accent 收敛规则

在 `ProfileView.swift` 及其子组件作用域内：

| 场景 | 当前 | 目标 |
|---|---|---|
| 选项选中文字 | `colors.sky` | `colors.selectionTint` |
| 选项选中 checkmark | `colors.sky` | `colors.selectionTint` |
| 选项选中背景 | `sky.opacity(0.1)` | `selectionTint.opacity(0.08)` |
| 外观子页选中 checkmark | —（新建） | `selectionTint` |
| Pro row leading glyph | —（新建） | `pairAccent` |
| 解除双人空间红字 | `coral` | `danger` |
| 退出登录 | `danger` | 保持 `danger` |

**全局 `sky` token 在其他模块的用法不变**，仅 Profile 内部替换。

### 6.4 删除的视觉元素

1. `ProBannerRow` 的所有渐变（LinearGradient + AngularGradient 彩虹描边）
2. 退出按钮的 `surfaceElevated` 背景 + shadow
3. 外观 capsule tab 的 `Capsule.fill(sky)` 及填充按钮样式
4. 双人协作 CTA 的 `collaborationButtonLabel` 整个函数

### 6.5 字号 / 字重 / 间距 定稿

**名片区**：
- avatar: 56pt (pair each) / 64pt (solo)
- avatar overlap amount: 20pt (HStack negative spacing), ~22% overlap
- name: 22pt `.light`, tracking 0.3
- subtitle: 13pt `.regular` `textTertiary`

**分组标题**：title 文字 weight `.medium` → `.regular`，tracking +0.4

**行（Row）**：
- 高度：44pt 最小
- title: 15pt（当前值保持）
- value: 14pt `textTertiary`
- chevron: 12pt `.bold` → 11pt `.semibold`（更细）

**Pro row**：
- title: 15pt `.semibold`
- subtitle: 12pt `.regular` `textTertiary`
- 行间距: spacing.xxs

---

## 7. 交互与动效

### 7.1 Haptic 验收清单

现有 `HomeInteractionFeedback` 已足够。Profile redesign 只需验收：

| 操作 | 预期 haptic |
|---|---|
| 点击任意 row / CTA / 选项 | `.selection()` |
| 确认退出登录 | `.warning()` |
| 确认清除缓存 | `.delete()` |
| 确认解除双人空间 | `.warning()` |
| 配对成功 | `notificationOccurred(.success)` |
| 账号注销确认 | `.delete()`（ProfileAccountDeletionView 内）|

### 7.2 动效规格

| 元素 | 动效 |
|---|---|
| Disclosure 展开/收起 | spring(response: 0.32, damping: 0.86)  ⚠️ 从 0.2s easeOut 升级 |
| Row insertion on toggle | 保留现有 `profileListRowTransition` |
| 名片区 zoom transition | 保留 `matchedTransitionSource` + `.navigationTransition(.zoom)` |
| Pair 模式切换名片区 | partner avatar 从右滑入，0.32s spring。触发：`onChange(bindingState)` from `.singleTrial/.unbound` → `.paired`（每次会话内解绑再绑也触发） |
| Appearance 子页切换 | checkmark 淡入 0.2s |
| Top chrome 渐变 mask | 保留现有 0.18s easeOut |
| 订阅状态变化（future） | row label 0.28s spring crossfade |

### 7.3 空态 / 错误态 / Loading

- `currentUser == nil`：名片区 skeleton shimmer（灰圆 + 两行灰条，0.8s 呼吸）
- avatar 加载中：保留 `AvatarPhotoView.reloadTick` 现有逻辑
- partner avatar 未上传：coral fallback icon（已在 §3.4 规定）
- ViewModel 首次 load：所有分组保留骨架占位，避免布局抖动
- `createInviteError`：CTA row 下方 12pt `danger` 红字提示（现有实现保留）

### 7.4 Accessibility

**VoiceOver labels**：

| 元素 | label |
|---|---|
| 名片区（solo） | `"编辑个人资料，{姓名}，独立工作空间"` |
| 名片区（pair） | `"编辑双人资料，{名字} 和 {对方名字}，{空间名}，配对 {N} 天"` |
| Pro row（未订阅） | `"Together Pro，{副标}，升级订阅"` |
| Pro row（已订阅） | `"Together Pro，订阅中，下次续费 {日期}，管理订阅"` |
| 外观 row | `"外观，当前 {跟随系统/浅色/深色}"` |
| 退出登录 | `"退出登录"` + hint `"退出后需要重新登录"` |
| 纪念日管理 | `"纪念日管理"` + hint `"查看和添加重要日期"` |
| 解除双人空间 | `"解除双人空间"` + hint `"将结束与对方的同步"` |

**Dynamic Type**：
- 名片区 22pt 主标用 `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` 限制，避免 AX5 撑破
- 其他 row 沿用 `textStyle(.body)` 自动 scale

**Reduce Motion**：
- Disclosure spring fallback 到 linear 0.2s
- 名片区 zoom transition 由 iOS 系统自动 fallback 到 fade

### 7.5 Dark Mode 验证

| 元素 | 验证重点 |
|---|---|
| hairline divider | dark 下 `white.opacity(0.08)` 是否可见 |
| coral selection 背景 | dark 下 `pairAccent.opacity(0.14)` 是否可见 |
| Pro row glyph | `pairAccent dark` 对比度 ≥ 4.5:1 |

新增 `ProfileTokenContrastTests.swift`，4 个 `@Test`：
1. `hairline` light / dark 对背景对比度 ≥ 3:1（非文本，WCAG 1.4.11）
2. `selectionTint` on surfaceElevated light / dark 对比度 ≥ 4.5:1
3. `displayLight(22)` 渲染不 crash 且 weight 正确
4. Pro row subtitle on surfaceElevated light / dark 对比度 ≥ 4.5:1

---

## 8. 文件级改动清单

### 8.1 修改（Modified）

| 文件 | 改动 |
|---|---|
| `Together/Features/Profile/ProfileView.swift` | 重构 body：名片区垂直化；删除 appearanceSection / 历史任务入口 / ProBannerRow 使用点；新增 Pro row section；退出登录样式简化；双人协作 CTA 改 inline row；关于简化；所有 `sky` → `selectionTint` |
| `Together/Features/Profile/ProfileUserCard.swift` | 重构：横向 pill → 垂直布局；双头像重叠；新增 `pairDaysText` 属性；支持 hairline bottom divider |
| `Together/Features/Profile/ProfileViewModel.swift` | 新增 `pairDaysCount: Int` 计算属性；新增 `proSubscriptionStatus: ProSubscriptionStatus`（默认 `.free`）；新增 `proSubtitleText: String` 计算 |
| `Together/Features/Profile/ProfileSettingsRow.swift` | 新增可选 `titleColor: Color?` 参数，用于"解除"、"退出"红字 row |
| `Together/Core/DesignSystem/AppTheme.swift` | 新增 `colors.hairline`、`colors.selectionTint`、`typography.displayLight(_:)` |

### 8.2 新建（New）

| 文件 | 内容 |
|---|---|
| `Together/Features/Profile/ProfileProEntryRow.swift` | Pro 入口独立组件，3 状态渲染 |
| `Together/Features/Profile/ProfileAppearanceView.swift` | 外观子页（3 行 List + checkmark） |
| `Together/Features/Profile/ProSubscriptionStatus.swift` | 订阅状态枚举 + 副标文案计算 |
| `TogetherTests/ProfileTokenContrastTests.swift` | 4 个 `@Test` 验证 dark mode 对比度 |

### 8.3 删除（Deleted）

| 代码块 | 行数 | 原因 |
|---|---|---|
| `ProfileView.appearanceSection` capsule tab | ~25 行 | 已改为 row + 子页 |
| `ProfileView.ProBannerRow` 整个 struct | ~60 行 | 移至名片区下 + 中性 row 化 |
| 历史任务 `NavigationLink` wrapper | ~10 行 | 移出 Profile |
| `collaborationButtonLabel(title:tint:)` 函数 | ~15 行 | 改 inline row 后废弃 |
| 退出登录 `surfaceElevated` 背景 + shadow | ~6 行 | 改为无背景红字 row |

**共计：约 120 行删除，约 200 行新增（含 3 个新组件 + 测试）**。

---

## 9. 测试策略

### 9.1 单元测试（新建）

`ProfileTokenContrastTests.swift`（4 tests）— 见 §7.5。

### 9.2 单元测试（现有覆盖）

- `ProfileViewModelTests`（若存在）：加 `pairDaysCount` / `proSubtitleText` 计算正确性测试
- `AppThemeTokenTests`：加 3 个新 token 的存在性 + 值合理性测试

### 9.3 UI / 视觉回归

- iPhone 17 Pro simulator：Light / Dark / AX5 三档冒烟
- 真机 haptic 验收：退出 / 清除缓存 / 解除空间 / 账号注销 4 条路径
- pair 模式切换动画：solo → pair 首次进入 Profile 播放 partner avatar 滑入
- VoiceOver 全路径 play-through（8 个关键 label）

### 9.4 Regression

- 全套 `xcodebuild test -scheme Together`（~150 tests）全绿
- `ProfileDebugSection` DEBUG 行为不受影响

---

## 10. 实施顺序建议（由 plan 具体化）

本 spec 定稿后，由 writing-plans skill 产出详细 plan。实施建议分 4 批：

**Batch A — Token 层**：
1. AppTheme 新增 3 个 token + `AppThemeTokenTests` 扩测
2. 新建 `ProSubscriptionStatus.swift`

**Batch B — 名片区**：
3. 重构 `ProfileUserCard`（垂直布局 + 双头像重叠）
4. `ProfileViewModel` 新增 `pairDaysCount`
5. 名片区 Dynamic Type 限制 + VoiceOver label

**Batch C — IA 重组**：
6. 新建 `ProfileAppearanceView` + 废弃 capsule tab
7. 双人协作 CTA 改 inline row + 废弃 `collaborationButtonLabel`
8. 删除历史任务入口（Home 层配套工作另案）
9. Pro row 新建 `ProfileProEntryRow`
10. 数据与账号删除 ProBannerRow
11. 关于简化
12. 退出登录样式简化

**Batch D — 视觉收敛 + 动效 + 测试**：
13. Profile 模块内 sky → selectionTint 替换
14. Disclosure 动画升级 spring
15. 新建 `ProfileTokenContrastTests`
16. Dark mode 冒烟 + VoiceOver 巡检
17. E2E: solo / pair / trial / active 4 状态手动走查

每个 Batch 结束 commit + full regression 绿灯。

---

## 11. 开放问题 / 延后项

### 11.1 延后（独立 follow-up）

- **历史任务移到 Home 层**：需要 Home 顶栏增加入口、路由迁移、深链适配。本 spec 仅从 Profile 删除，Home 层配套工作另开 plan。
- **Pro 订阅功能实施**：StoreKit 2 接入、paywall 子页、feature gate 半屏、后端验证——独立大 feature。本 spec 仅定义 Pro 入口视觉位置。
- **字体升级到思源宋体**：若未来视觉要再往 Claude 原教旨靠拢，再考虑 bundle Noto Serif SC Light。

### 11.2 已确认无分歧（brainstorming 过程记录）

- 方向 β（Claude 骨架 + Together 温度） — 用户确认
- 9 → 6 分组 + 历史任务移出 — 用户确认
- Pro 采用中性 row 而非 banner — 用户确认
- 订阅后 row 不消失仅变形 — 用户确认
- 字体保留现有 AppTheme（无 serif 打包）— 用户确认
- 名片区垂直布局 + 双头像重叠 — 用户确认
- 解除空间用 `danger` 而非 `coral` — 用户确认
- 退出登录去除 filled 样式 — 用户确认
- capsule tab 外观 → disclosure + 子页 — 用户确认
- `sky` → `selectionTint` 仅在 Profile 模块内 — 用户确认

---

## 12. Appendix — 调研引用

### 12.1 Profile/Settings pattern 调研（10 款 App）

参照文档内引用：Claude iOS、Bear、Paired、Things 3、Linear、Arc Search、Notion、Apple Reminders、Structured、Craft Docs。主要结论：
- 编辑气质 App 全部用中性 row 而非 banner（Claude / Bear / Craft / Day One / Fantastical）
- 行业共识分组顺序：identity → Pro → preferences → notifications → appearance → security → data → about → sign out
- 双人类 App 仅 Paired 有成熟的"双头像名片"模式（48pt, 30% 重叠）
- 全局反模式：订阅后 banner 不消失（1 星评论头号来源）

### 12.2 Pro 入口调研

参照文档内引用：RevenueCat State of Subscription Apps 2024、Apple Guideline 3.1.2、Bear / Craft / Day One / Paired / Claude iOS 实观。主要结论：
- onboarding paywall + feature-gate 半屏贡献 60-75% 订阅，Profile 入口是 retention surface
- contextual paywall per-impression 转化高 2-3 倍
- Settings banner 在编辑气质 App 中**零例**，全部用 row

### 12.3 Anthropic / Claude.ai 视觉语言

- Typography: Tiempos（serif display）+ Styrene（UI sans）
- Color: `#F4EEE4 ~ #FAF9F5` 暖米白 + `#D97757` coral + `#E4DED3` hairline
- Iconography: 1.5px stroke 线面图标
- Spacing: 大量留白，hairline rule 分隔，无重阴影

中文场景无完美字体对应；本 spec 选择保留现有 AppTheme 字体栈（PingFang Rounded + Han Rounded CN），通过**字重 + 字号 + 留白 + hairline**达成克制感而非引入新字体。
