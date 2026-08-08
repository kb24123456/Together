---
status: accepted
supersedes: ADR-0019
---

# 首页详情与创建采用统一可逆任务表面

## 决策

首页待办详情、定期详情、待办创建和定期创建统一进入一个根级 `HomeFocusSession`。SwiftUI 页面、Router、深链和系统回调只发送意图；根级 `HomeFocusPresentationCoordinator` 独占前景表面的几何、背景景深、命中屏障和唯一 `UIViewPropertyAnimator`。SwiftUI 继续拥有任务内容、Draft、校验、持久化、Dynamic Type 和无障碍语义，不发布逐帧动画进度。

任务表面使用唯一规范化语法：紧凑任务行为进度 0，展开详情或创建卡为进度 1。详情打开执行 `0 -> 1`；未改变位置的关闭严格执行 `1 -> 0` 返回来源；详情改变日期、排序或周期、创建成功以及展开态完成操作，都执行相同的 `1 -> 0` 并直接进入最终真实任务行。卡片内容始终保持最终布局，由外层连续圆角边界裁切揭示或收回，不在 SwiftUI 中逐帧重排。

创建入口的 `+` 只表达因果关系，不承担任务身份。创建卡在稳定、键盘安全的焦点位建立，不做跨屏按钮形变；保存成功后才获得最终列表落点并使用统一反向任务表面语法融入列表。编辑期间列表不插入创建占位，也不随 Draft 排序变化移动。

## 根平面与所有权

`HomeRootContainerController` 永久持有完整窗口底板、背景 SwiftUI Host、全屏 blur/dim/命中屏障和唯一前景 SwiftUI Host。底板覆盖状态栏与 Home Indicator 后方；导航内容、Toolbar、头像、模式切换、列表和自定义 Dock 保持同一视图树及安全区占位。焦点期间只变换整个背景 Host：约 `0.985` 缩放、单层系统模糊和自适应暗化。系统状态栏、键盘和属性 Sheet 不加入缩放。

来源行始终保留紧凑高度，但其任务身份像素由前景 Host 独占。保存成功后，目标真实行先建立并保持隐藏；前景到达目标紧凑边界后，同一提交帧恢复真实行并移除前景。全屏命中屏障从转场第一帧起接管背景点击，杜绝穿透到第二个任务。

## 数据与落点

待办和定期创建在进入时预分配最终 UUID。应用服务直接返回保存实体，ViewModel 生成 `HomeFocusLandingDescriptor`，不以全量 reload 驱动落地。描述符包含领域、任务 ID、目标 section、index、展示 ID 和目标页面状态；待办日期变化切换到目标日期，定期周期变化切换到目标周期，再等待目标行提交新几何。

焦点会话在 preparing、focused 和 saving 期间冻结背景可见数据与滚动；外部同步仍可写入数据源。只有进入 `preparingLanding` 才释放快照并建立最终落点。保存失败保留同一 Session、UUID、Draft、键盘和前景表面。

## 中断、键盘与可访问性

Animator 中断时先冻结 presentation layer，再从当前视觉帧反向。窗口尺寸变化或 App 失活进入统一 Recovery，旧 completion 由 Session revision 失效；详情恢复到紧凑端点，未提交创建 Draft 保留供下一次入口继续。键盘只通过 UIKit 调整前景外层容器的纵向位置，卡片内部使用 SwiftUI ScrollView，不改变任务身份和落点。

Reduce Motion 使用短时、短距离的边界与清晰度转换；Reduce Transparency 使用实色暗层。状态语义、唯一像素所有权和最终落点不因辅助功能设置而改变。

## 否决方案

- 不使用 `matchedGeometryEffect` 跨 Lazy 列表、Toolbar、Dock 和窗口级 Overlay。
- 不让系统 Toolbar 或底部 `+` 成为动画实体。
- 不保留待办/定期各自的详情状态机、创建浮层、局部景深或旧动画 fallback。
- 不用完整 UIKit 重写业务表单；UIKit 只负责瞬态外层合成。

本 ADR 取代 ADR-0019。ADR-0019 中“`+` 是创建表面的真实来源”的结论废止。
