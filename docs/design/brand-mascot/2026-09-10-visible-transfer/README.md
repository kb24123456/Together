# 品牌小球可见跨页承接

> 9月12日用户真机反馈进入方向有停顿、返回方向顺畅，并确认入场保持首页动作、抵达后再书写。当前入场时序已在[后续修订](../2026-09-12-editor-arrival/README.md)中调整；本文件与 verification.json 保留9月10日实现记录。

2026-09-10：用户反馈仅进入编辑再返回无法感知前阶段改动。本阶段将共享运行实例扩展为同一个真实渲染视图的空间承接；不需要改日期或保存任务才能观察。源码实现已完成，真机观感尚未验收。

## 实现

- 根级 `MascotPlaybackSession` 持有唯一 `MascotVisualTransfer`，后者拥有唯一 `RiveUIView` 与静态兜底。首页和编辑页原生 toolbar 仅注册布局锚点，保留40pt/30pt主体及完整画板边界。
- 进入和返回时，将同一显示视图移入当前 UIWindow 的非交互 UIView 层，连续改变位置与缩放，结束后接回目标锚点。未新增 UIWindow、角色副本、快照交叉淡变或每帧 Observation。
- `MascotNavigationObserver` 只观察编辑页所属原生模态的出现和关闭。动画优先加入 `UIViewControllerTransitionCoordinator.animateAlongsideTransition(in:)`，由系统协调交互进度和取消；目标最终几何通过 presentedView 的局部位置与 presentationController 最终 frame 映射，避免把 Zoom 中的临时位置当终点。
- 新转场继承当前呈现位置并更换 UUID，旧完成回调失效。系统未接纳同步动画或导航栏布局迟到时，页面生命周期确认后才用最多0.34秒、无回弹的 UIKit 动画完成剩余距离，不阻塞页面导航或业务保存。目标暂时不存在时移除临时层、暂停显示，锚点出现后接回同一视图。
- Reduce Motion 和现有节能降级使用静态资源并取消空间动画；后台和应用锁隐藏并暂停。原 Profile Button、原生标题、取消/保存按钮、命中区域及无障碍语义继续由原布局持有。
- 保存/取消决定返回，根级原生 onDismiss 完成编辑所有权交接；交互式关闭取消恢复编辑状态。业务数据、反馈规则及 Rive 资源未改。

关键文件：`MascotVisualTransfer.swift`、`MascotTransferState.swift`、`MascotNavigationObserver.swift`、`MascotPlaybackSession.swift`、`BrandMascotView.swift`，以及创建/详情根视图各一个导航观察接入点。测试位于 `MascotTransferStateTests.swift`。

## 验证与边界

本阶段工程验证见 [verification.json](verification.json)。15项纯所有权、转场状态与几何测试在独立 macOS Swift Testing 宿主执行通过；6项 UIKit 图层回归用例随最终 generic iOS build-for-testing 编译通过，未执行。diff检查通过，构建资源与源码资源哈希一致。测试中的独立隐藏 UIWindow 夹具有2处 `init(frame:)` 弃用警告，未改生产窗口创建方式。纯测试曾遇到编译器/SDK混配，单进程匹配工具链后复跑通过，未改全局设置。源码自查发现并修复：系统拒绝动画注册后返回手势取消未收尾；来源未就绪或目标消失时停靠遗漏。不将编译视为视觉验收。

沿用 Xcode 27 beta 3（27A5218g）、精确锁定 rive-ios 6.25.1 与现有 SourcePackages 缓存，无签名 generic iOS 构建。未启动 Simulator、未安装或启动 Together、未创建 Git 提交或推送；按用户要求不恢复性能/能耗专项测量。当前资源 SHA256 仍为 `7eb9ed8e1ee821322c2a12d70832e0ab969e0d4c394f5450b8e8c18c1eb72bd8`，V1 清单和前阶段资源记录不变。

用户需要在本阶段完成后重新 Xcode Run。重点看首页→编辑→返回时位置/大小是否连续，再检查返回手势中途取消、快速反向与重入、属性 Sheet、浅深色、Reduce Motion、大字号及 VoiceOver。此前已运行版本及 V1 确认均不能代表这次转场验收。

## Apple Knowledge Retrieval Evidence

- query：`SwiftUI fullScreenCover navigationTransition zoom UIKit transitionCoordinator alongsideTransition shared UIView overlay interactive dismissal cancellation toolbar anchor finalFrame`
- 补充 query：`SwiftUI UIViewControllerRepresentable ancestor transitionCoordinator fullScreenCover zoom animate alongside interactive cancellation final frame coordinate conversion`
- 命中 keys：无；实际采用记录：无；结论：`无需 Expert Delta`。
- 官方依据：[UIViewControllerTransitionCoordinator](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator)、[子控制器查找祖先 coordinator](https://developer.apple.com/documentation/uikit/uiviewcontroller/transitioncoordinator)、[在指定视图同步动画与注册返回值](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/animatealongsidetransition(in:animation:completion:))、[最终 presented frame](https://developer.apple.com/documentation/uikit/uipresentationcontroller/frameofpresentedviewincontainerview)、[WWDC24 Zoom 生命周期与快速反向](https://developer.apple.com/videos/play/wwdc2024/10145/)。选择共享视图承接与边界映射属于基于这些公开语义的本项目实现，实际 SwiftUI 模态组合仍待真机验证。

阶段事实同步至 `docs/PROJECT_MEMORY.md`。本次不新增 Skill。
