# 修复深色模式下任务展开卡片的白色边框与高光阴影

## Summary

深色模式下，首页时间线点击任务展开后，焦点态装饰层（`HomeInlineFocusChromeModifier`）出现一圈刺眼白色边框线和白色高光阴影，与深色背景不协调。

根因是 `HomeInlineFocusChromeModifier` 中存在**两处颜色硬编码**：
- 一处明确写死 `Color.white`（line 2000 顶部高光描边）
- 一处使用 `AppTheme.colors.title`，深色模式下该色值为 `0.95, 0.95, 0.96` 近白，导致阴影在深色下变成白色光晕

修复方法：用已有 `AppTheme` 暗色适配 token 替代硬编码白，并降低深色模式下的描边/阴影强度，使焦点态在两种模式下都内敛柔和。

## Current State Analysis

### 视觉现状（截图观察）
展开后任务卡周围出现：
- 一圈明亮的白色边框
- 卡片顶部一道明显的高光描边
- 整体散发的白色光晕（深色背景下尤其刺眼）

### 根因代码
[HomeView.swift:1991-2044](file:///Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift#L1991) `HomeInlineFocusChromeModifier`：

| 行 | 现状 | 深色模式问题 |
|---|---|---|
| 1993 | `fill(focusSurfaceColor.opacity(1))` | `surface` 深色 = `0.16, 0.16, 0.17` 填充尚可 |
| 1996 | `strokeBorder(focusSurfaceColor, lineWidth: 0.8)` | 深色下深灰描边，与白色高光叠加后产生色差感 |
| **2000** | **`strokeBorder(Color.white.opacity(0.34), lineWidth: 1)`** | **硬编码白色 34% 透明 → 深色下明显白色高光环** |
| 2003 | `shadow(.title.opacity(0.13), radius: 34, y: 18)` | `title` 深色 = `0.95, 0.95, 0.96` 近白 → 白色光晕 |
| 2009 | `shadow(.surface.opacity(0.88), radius: 22, y: -10)` | 顶部内阴影用 surface，深色下可接受 |
| 2024-2026 | `topAmbientDimming` 用 `title.opacity(0.10/0.055)` | `title` 深色近白 → 顶部散射白雾 |

### 已有可复用 token
[AppTheme.swift](file:///Users/papertiger/Desktop/Together/Together/Core/DesignSystem/AppTheme.swift) 已定义：
- `outline`（line 108）：`dark: white.opacity(0.10)` — 浅描边
- `outlineStrong`（line 130）：`dark: (0.36, 0.36, 0.38)` — 较强描边
- `hairline`（line 113）：`dark: white.opacity(0.08)` — 极弱发丝线
- `glassTint`（line 105）：`dark: white.opacity(0.06)` — 微亮玻璃调
- `separator`（line 133）：`dark: (0.26, 0.26, 0.28)` — 分隔线

## Proposed Changes

### 1. 改造 [HomeView.swift:1991-2017](file:///Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift#L1991) `focusPlate`

| 当前 | 改为 | 理由 |
|---|---|---|
| `fill(focusSurfaceColor.opacity(1))` | 保留 | 浅色：纯白；深色：深灰 — 合理 |
| `strokeBorder(focusSurfaceColor, lineWidth: 0.8)` | 保留 | 描边色与填充接近，浅色下呈现近白边 |
| **`strokeBorder(Color.white.opacity(0.34), lineWidth: 1)` 顶部 overlay** | 改为 `strokeBorder(AppTheme.colors.outline.opacity(0.5), lineWidth: 0.6)` | 浅色下微弱高光，深色下 `outline` = `white.opacity(0.10)` × 0.5 = `white.opacity(0.05)` 极弱 |
| `shadow(.title.opacity(0.13), radius: 34, y: 18)` | 改为 `shadow(.title.opacity(0.08), radius: 28, y: 14)` | 浅色无感（title 接近黑），深色下从 `0.13` 降到 `0.08` + 半径缩小，减弱光晕 |
| `shadow(.surface.opacity(0.88), radius: 22, y: -10)` | 保留 | 浅色下顶部内白高光，深色下显示深灰，行为正确 |

### 2. 改造 [HomeView.swift:2019-2040](file:///Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift#L2019) `topAmbientDimming`

将 `AppTheme.colors.title.opacity(0.10/0.055)` 改为 `AppTheme.colors.title.opacity(0.06/0.03)`，降低整体散射雾强度：

```swift
LinearGradient(
    colors: [
        .clear,
        AppTheme.colors.title.opacity(isFocused ? 0.06 : 0),
        AppTheme.colors.title.opacity(0.03),
        .clear
    ],
    startPoint: .top,
    endPoint: .bottom
)
```

理由：浅色下 `title` 接近黑，0.06 几乎不可见，保留效果；深色下 `title` 接近白，从 0.10 降到 0.06 显著减弱白雾。

### 3. 不改动的部分
- 外层 `.shadow`（line 1970-1980）保留
- 焦点态的 `opacity / saturation / brightness / blur / scaleEffect`（HomeView.swift:1075-1081）保留
- 展开态的 `transition` 保留
- 浅色模式视觉表现保持近似原样

### 4. 不动 `AppTheme.colors` 全局 token
`title` 在深色模式下作为主标题/前景色接近白是合理设计，不应为了一个组件改全局色值。在组件层做条件处理。

## Assumptions & Decisions

1. **用 `outline` 替代 `Color.white`**：`outline` 深色 = `white.opacity(0.10)`，再乘 0.5 = `0.05` 极弱，浅色下 `outline` = `black.opacity(0.08)` × 0.5 = `0.04` 也极弱。比硬编码 `Color.white.opacity(0.34)` 在两种模式下都柔和得多。
2. **降低阴影透明度而不删除**：删除阴影会失去"卡片浮起"的空间感表达，只降强度。
3. **不引入新 token**：复用现有 `outline` / `title`，符合项目"先复用后新增"原则。
4. **不修改 `HomeInlineTaskDetailView` 内子组件样式**：问题集中在 `HomeInlineFocusChromeModifier` 一处，其它内部按钮/子任务样式不在此次范围。

## Verification Steps

1. **编译验证**：Xcode 编译 Together scheme。
2. **浅色模式验证**：展开任务 → 焦点态应保留柔和浮起感，无明显变化或更内敛。
3. **深色模式验证**（关键）：
   - 展开任务 → 边框应转为接近背景的极弱深灰描边，不再有刺眼白边
   - 顶部高光环应消失或大幅减弱
   - 整体光晕收窄为内敛的"卡片浮起"表达，不应像发光物体
4. **回归测试**：测试 `xcodebuild test -scheme Together` 确认无破坏。
5. **多任务连续展开**：连续点击不同任务，确认切换动画过程中描边/阴影过渡自然。
