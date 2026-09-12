# 连续切页后动画暂停：用户真机复测通过

2026-09-12 用户反馈：开始测试正常，连续多次切页后，背景粒子停止、首页进入编辑的位移动画消失；小球自身动作仍正常。随后补充手机明显发热，稍后效果恢复。

## 最新复测

用户反馈：“重新测试了，反复多次操作，也保持正常”。据此记录连续多次页面切换的真机复测通过，原暂停现象在本次复测中未再出现。当前无需继续调整动效。没有故障时的设备日志，不把热状态线索升级为已确认根因；本次也不代表完成了能耗测量或未明确覆盖的专项状态验收。

## 已确认与未确认

- 当前粒子和小球均受 scene active、Reduce Motion、低电量和 serious/critical 热状态约束。小球位移复用其动画许可。
- 用户的升温后恢复现象支持热状态降级线索，但“小球自身仍正常”不能直接对应小球全局许可关闭；没有设备 thermalState 日志，尚不能确认同一根因。
- 源码未发现按切页次数停止的计数逻辑，也无应用级 `UIView.setAnimationsEnabled(false)`。粒子消失时暂停 TimelineView，再出现或需求改变时应重新同步；旧减速任务取消后有取消检查。需要真机确认这些回调和实际状态。
- 依据 [Apple thermalState 文档](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)，热状态较高时应减少资源消耗。本轮不放宽热保护，也不凭体感修改帧率或效果。

## 本轮改动

仅在 DEBUG 中增加 `Motion` 类别的 OSLog：

- `BrandMascotView.swift`：播放许可、可见、scene active、遮挡、Reduce Motion、低电量，以及缓存和实时热状态。
- `AmbientParticleBackground.swift`：运动需求、消失暂停、恢复刷新、减速完成暂停。
- `MascotVisualTransfer.swift`：入场准备、首次几何可用、禁动画事务外排队（每次入场最多报告一次）、实际启动时长及动画开关。

日志不包含任务名或任务内容，不逐帧写入；转场标识为临时 UUID。Release 不包含这些诊断。业务、渲染参数、动画时间和策略未由本轮改变；仓库同时进行的提示视图调整不归属本轮。

## 验证与继续方式

`git diff --check` 通过。Xcode27 beta3 `xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 使用既有 SourcePackages/DerivedData 成功，日志在 `/Users/papertiger/Documents/Codex/2026-09-12/together-mascot-repeated-switch-diagnostics/build-for-testing-current.log`。第一次构建撞上同时进行的 TaskUpdateNotice UIKit 接口调整，旧调用不匹配；接口迁移更新后重试通过，本轮未改那部分实现。

本轮只增加诊断，没有新增语义测试，也没有把测试构建当作实际运行。未启动 Simulator、运行 Together 真机、另行运行 Mac Catalyst 复现或执行 Instruments。以上为诊断准备时的工程验证；后续用户真机复测结果见本页最新复测。

当前复测正常，无需为本次问题继续反复测试。若以后再次出现停止，再在 Xcode 调试控制台筛选 `[Motion]`，保留故障前后与恢复时的日志继续定位。若热状态确实触发暂停，还需区分正常压力下的保护与异常持续开销，再决定是否开展能耗测量；此前取消的能耗专项没有自动重启。

## Retrieval Evidence

Query：`SwiftUI fullScreenCover repeated navigation scenePhase TimelineView animation paused thermalState serious UIKit UIViewPropertyAnimator lifecycle recovery`。命中 keys：无；实际采用记录：无；无需 Expert Delta。按 SwiftUI / Xcode27 指引检查状态与生命周期，按构建与能耗排查指引区分编译证据、热状态线索与待测运行事实；未新增技能。
