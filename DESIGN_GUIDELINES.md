# Together Design Guidelines

## 结论

本仓库后续所有 UI 设计和实现，默认按 iOS 原生设计规范执行，尤其要遵守安全区域、系统导航层级、底部交互区和标准组件行为。任何视觉稿如果没有考虑安全区域，视为未完成稿。

## 适用范围

- Pencil 线框图和高保真视觉稿
- SwiftUI 页面实现
- UIKit 容器或桥接页面
- 动效设计、导航转场、悬浮操作按钮

## 全局硬规则

1. 顶部内容不得侵入安全区域。
事实：
- 标题、筛选条、周视图、顶部操作按钮都必须从 top safe area 之后开始布局。
- 不允许把主要信息直接顶到状态栏、动态岛或前摄区域下方。

2. 底部内容不得侵入 Home Indicator 与系统手势区域。
事实：
- 底部导航条、悬浮添加按钮、底部工具条都必须为 bottom safe area 预留空间。
- 底部可点击控件不能贴边放置，必须确保点击热区不与系统返回手势、Home Indicator 区域冲突。

3. 滚动内容与固定底部栏必须分层。
事实：
- 若页面有固定底部导航或操作条，滚动内容底部必须额外留出可视缓冲。
- 优先使用 `safeAreaInset(edge: .bottom)` 承载底部栏，而不是把底栏硬覆盖在内容上。

4. 安全区域不是固定像素，而是运行时约束。
事实：
- 不允许在产品规范中写死某台机型的顶部和底部高度。
- 需要根据设备与上下文读取 safe area。

5. 液态玻璃风格必须服从系统层级。
事实：
- 底部导航、顶部按钮、浮层按钮优先做成轻量、半透明、可读的系统感玻璃。
- 不允许为了“像玻璃”而降低文字可读性或削弱信息主次。

## SwiftUI 实现规则

1. 顶部和底部安全区域处理
- iOS 17+ 优先使用 `safeAreaPadding(_:)` 或 `safeAreaPadding(_: _:)` 增加安全区内边距。
- 固定底部栏优先使用 `safeAreaInset(edge:alignment:spacing:content:)`。
- 如果页面需要根据设备动态调整位置，使用 `GeometryProxy.safeAreaInsets` 读取当前容器安全区域。

2. 页面结构建议
- 页面背景可以延伸到边缘，但主要内容容器必须尊重安全区域。
- 胶囊按钮、导航条、悬浮按钮使用“背景可延展，交互元素不越界”的策略。
- 首页这种带底部导航和 FAB 的页面，推荐结构：
  - 背景层：可全屏延展
  - 内容层：受顶部与底部安全区域约束
  - 底部导航层：使用 `safeAreaInset(edge: .bottom)`
  - FAB：锚定在底部导航上方，并额外预留 bottom inset

3. Together 首页专项规则
- 周视图必须避开顶部安全区，不能为了拉高视觉重心而顶到状态栏下。
- 左侧时间线只作为信息辅助轨道，不得贴近屏幕圆角边缘。
- 底部导航条必须位于 bottom safe area 之上，且与 Home Indicator 保持清晰间距。
- 右下角新增事项 FAB 必须悬浮在导航条上方，不能压住导航条点击区域。

## Pencil 出图规则

- 在 Pencil 中绘制 iPhone 页面时，必须显式预留顶部和底部安全区域视觉缓冲。
- 顶部首屏标题、周视图、返回按钮，不得贴到画布上边缘。
- 底部导航和悬浮按钮之间必须有层级间距，不能堆叠成一团。
- 如果 Pencil 不能真实表达系统 safe area 数值，至少要在视觉上体现：
  - 顶部留白足够承载状态栏和动态岛
  - 底部留白足够承载 Home Indicator 和系统手势

## Assumptions

- 首版 Together 以 iPhone 竖屏为主进行设计约束。
- 当前仓库主要页面将以 SwiftUI 为主实现，因此优先采用 SwiftUI 的 safe area API 作为工程落地标准。

## Open Questions

- 是否需要把最小顶部/底部视觉缓冲值进一步量化成设计 token，统一用于 Pencil 和 SwiftUI。
- 是否需要单独为大屏 iPhone 和未来 iPad 适配补一份扩展规范。

## Apple 官方依据

事实：
- Apple `safeAreaInset(edge:alignment:spacing:content:)` 说明：该 API 会为插入内容腾出空间，并同步调整结果视图的 safe area。  
  来源：[safeAreaInset(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l/)

- Apple `safeAreaPadding(_:)` 说明：该 API 会把给定间距加入视图可见的安全区域。  
  来源：[safeAreaPadding(_:)](https://developer.apple.com/documentation/swiftui/view/safeareapadding(_:)-6nbmg/)

- Apple `GeometryProxy.safeAreaInsets` 说明：可读取容器视图的 safe area inset。  
  来源：[GeometryProxy.safeAreaInsets](https://developer.apple.com/documentation/swiftui/geometryproxy/safeareainsets/)

- Apple `Liquid Glass` 技术概览说明：标准导航和控件会自动获得 Liquid Glass 外观与行为，自定义元素也应遵守 Apple 平台层级、一致性与可读性原则。  
  来源：[Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass/)
