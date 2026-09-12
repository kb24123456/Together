# 品牌小球连续性与改期提示

> 此文件保留共享运行实例与改期提示的阶段记录。用户后来通过 Xcode Run 反馈，仅进入编辑再返回看不到变化；固定导航槽间切换承载并未实现可见位置承接。当前跨页显示已由[后续实现](../2026-09-10-visible-transfer/README.md)替代，本目录的资源制作与验证记录仍保留。

2026-09-10：已完成授权范围内的 App 与 Rive 实现。原 V1 造型和 A4 书写保留；本轮新版尚未安装到 iPhone，真实导航观感仍待验收。

## 当前行为

- 主页、创建与详情由根级 `MascotPlaybackSession` 共享同一 Rive 运行实例。不同原生导航栏可以短暂并存，显示注册先暂停旧承载再启用新承载，任一时刻只有一个显示循环推进动画。普通导航暂停不快进基础动作；已过期的短反馈不再造成后续无端快进。
- 编辑会话 UUID 隔离旧输入和迟到回调。取消、保存成功或完成成功后开始收笔，原生 `onDismiss` 才交还首页；交互式返回中途取消继续编辑。业务保存、取消与导航无需等待小球动作。
- 仅详情显式保存成功、同一未完成普通待办的计划日期跨自然日时产生结果。文案使用实际保存返回值中的任务名、日期和可选时间；同日时间调整、普通保存、创建、完成、取消与失败不产生。
- 结果显示在首页内容安全区底部、系统工具栏上方。中性表面、约 6pt 位移、260ms 无回弹淡入；稍后 220ms 触发一次 0.9s 左下注视，约 2.8s 后淡出。VoiceOver 播报完整文本并延长显示；Reduce Motion 仅保留文字淡变。
- 只保留最新结果。离开首页取消可见提示与延迟回应；后台或应用锁既清除已产生结果，也通过保存 generation 使在途旧结果失效，恢复后新保存仍可正常反馈。
- 全局后台、应用锁、减少动态效果、低电量及严重热状态仍暂停小球并使用主题静态素材；静态姿态随业务上下文更新。

## 实现与资源

主要文件：`MascotPlaybackSession.swift`、`MascotPlaybackOwnership.swift`、`BrandMascotView.swift`、`MascotRuntime.swift`、`MascotBehaviorState.swift`、`MascotController.swift`、`TaskRescheduleFeedback.swift`、`TaskRescheduleNotice.swift`，以及 `AppRootView.swift`、`TaskCreationView.swift`、`TaskDetailView.swift` 和 `HomeViewModel.swift` 的接入点。

[完整 Rive 制作与验证记录](RIVE.md)包含可编辑 `.rev`、运行 `.riv`、修改前完整备份、逐键差异和回放。当前资源 SHA256 为 `7eb9ed8e1ee821322c2a12d70832e0ab969e0d4c394f5450b8e8c18c1eb72bd8`。原 `../v1-manifest.json` 继续冻结 V1，不更新为新版指纹，也不继承其真机确认。

## 验证与验收边界

工程验证的最终状态见同目录 `verification.json`。已执行的纯状态/文案测试与仅编译的 iOS 集成测试分别记录。Rive 独立检查为 53/53，浅深色 40pt 各 900 帧回放、48 张关键 PNG 边界检查通过。

Xcode 工具链：Xcode 27 beta 3（27A5218g），`rive-ios` 精确锁定 6.25.1。构建使用 `generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、现有 `-clonedSourcePackagesDirPath`；没有启动 Simulator、安装 App、提交或推送 Git。性能与能耗专项仍按用户要求取消。

真机需验证：主页→编辑→保存/取消的姿态交接、交互式返回中途取消、快速同任务重入、跨日结果与同日修改不提示、异步保存时切后台、浅深色、低电量、Reduce Motion、大字号与 VoiceOver。当前 iPhone 的旧版不能用于验收这些新改动；后续安装包含本轮代码和资源的新构建后再验收。

## Apple Knowledge Retrieval Evidence

- query：`SwiftUI State view identity lifetime fullScreenCover navigationTransition zoom modal source destination animation continuity cancellation`
- 命中 keys：无。
- 实际采用记录：无，`无需 Expert Delta`。
- 框架判断基于当前已锁定 SDK 源码：相同 Rive identity 不重建 native controller，暂停同步传播至 display link，恢复首帧 delta 为 0。没有将静态源码检查或独立回放等同于真实页面视觉验收。

本次继续使用现有 SwiftUI/Rive 边界，未新增或修改 Skill。阶段结果同步至 `docs/PROJECT_MEMORY.md`。
