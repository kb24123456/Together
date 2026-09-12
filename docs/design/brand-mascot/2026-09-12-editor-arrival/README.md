# 小球入场与抵达后书写

2026-09-12：用户真机反馈“首页→编辑移动有卡顿，编辑→首页顺畅”，并要求移动途中保留首页状态，实际抵达后才进入书写。这是对9月10日可见承接实现的修订，未沿用旧阶段的视觉验收结论。

## 本轮调整

- 入场继续使用同一个真实 RiveUIView。首次可用的编辑导航锚点几何驱动一条 UIKit 属性动画，时长取原生转场；不再等原生转场结束后补飞，也不在完成后另接0.34秒入场纠偏。返回保留原生 coordinator 路径与原有业务收笔规则。
- 原生出现和布局回调提供坐标，最早的 didMoveToWindow 不能单独认定布局已就绪；运行中目标变化超过一个物理像素时，使用同一动画的剩余时间更新终点，不重新开始。不在动画闭包里强制整页 `layoutIfNeeded()`。页面导航、键盘、安全区与控制按钮继续交给原生布局。
- `MascotPlaybackOwnership` 区分“已经拥有编辑会话”和“小球已经抵达”。前者立即建立以隔离输入和旧回调，后者只由真实停靠成功触发。`MascotPlaybackSession` 保留出发时首页上下文，直到 onDock 确认同一编辑 UUID 后才切入现有 WritingEnter；页面 didAppear 本身不再成为提前书写的依据。
- 输入期间的原始时间可以跨入场保留，抵达时按原0.9秒停笔期限接续；停止输入、返回或后台降级会清除待接续输入。未输入时进入持笔姿态，真实输入才书写。Rive 造型、原始书写动画和资源均未改变。
- 快速反向、取消、迟到锚点和降级仍通过当前会话身份收尾；旧动画完成回调不能触发新会话书写。没有逐帧 Observation、坐标轮询、额外 UIWindow 或角色副本。

## 问题依据与验证边界

源码证据：旧入场目标不存在时，原生动画闭包直接返回；在途 anchor layout 不参与目标准备，新 UUID 没有位置缓存；原生 completion 后才启动固定0.34秒补动画。已执行过原生移动但剩余距离超过0.5pt时也另起补动画。返回通常已有首页位置缓存，因此两条路径确有不对称。强制整页布局亦已移出动画闭包。这些是可确认的时序/接续问题；没有真机帧时间或 Instruments 证据，不能断言用户所感知的卡顿全部来自这几处，也不能将改完源码称为性能测量通过。

51项纯所有权、转场几何与行为测试执行通过；9项 UIKit 图层/真实 Session 测试仅随 generic iOS build-for-testing 编译，未执行。新增测试覆盖抵达门控、迟到锚点、到达前返回，以及原输入截止时间的保留。隐藏 UIWindow 统一为一个无 scene 夹具，保留一处 iOS26 初始化弃用警告，便于不依赖应用场景的隔离测试；生产没有新增窗口。构建使用 Xcode27 beta3 与 rive-ios 6.25.1，另有未改 ProfileViewModel 的既有 actor 警告。最终测试、构建与资源指纹见 [verification.json](verification.json)。不启动 Simulator、不安装或启动 Together，不恢复此前已取消的性能/能耗专项；本轮没有提交或推送。最终需要用户重新 Xcode Run，检查“移动保持首页姿态→抵达→自然拿笔/输入书写”，再检查快速返回、返回取消、输入抢在到达前、浅深色和 Reduce Motion。

关键文件：`MascotPlaybackSession.swift`、`MascotPlaybackOwnership.swift`、`MascotVisualTransfer.swift`、`MascotNavigationObserver.swift`、`MascotController.swift`，以及对应的所有权、行为与图层回归测试。修改前备份保存在 `/Users/papertiger/Documents/Codex/2026-09-12/together-mascot-arrival/baseline`。

## Apple Knowledge Retrieval Evidence

- query：`UIViewControllerTransitionCoordinator animate alongside first presentation toolbar geometry unavailable viewIsAppearing layoutIfNeeded fallback animation discontinuity SwiftUI fullScreenCover zoom`
- 命中 keys：无；实际采用记录：无；结论：`无需 Expert Delta`。
- [Apple viewIsAppearing 文档](https://developer.apple.com/documentation/uikit/uiviewcontroller/viewisappearing(_:))区分了可以注册 alongside animation 的 willAppear 与几何准确的 viewIsAppearing；实现不在后者晚注册原生转场动画。
- [Apple coordinator 文档](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/animatealongsidetransition(in:animation:completion:))说明注册返回值与 completion 的边界；[UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator)提供可中断的位置/缩放动画。本项目入场选择单独一条原生属性动画，是基于这些语义及现有迟到布局分支的实现取舍。
- [addAnimations 文档](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator/addanimations(_:))支持在 active 状态使用剩余时间更新动画；本轮仅在原生布局目标变化时使用，不在停止后另接动画，也不将该 API 保证扩写为已测得速度或帧率连续。

阶段事实同步至 `docs/PROJECT_MEMORY.md`；本轮不新增 Skill。
