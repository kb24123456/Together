---
status: accepted
supersedes: ADR-0020
---

# 首页任务采用列表拥有的原地 Morph 容器

## 决策

首页待办与定期任务统一由 `ScrollView + LazyVStack` 承载。每个业务 UUID 只对应一个 `TaskMorphContainer`，容器在 `.compact / .editing / .expanded` 之间改变真实布局高度和内部内容。详情不再进入根级 Modal、窗口级 Overlay 或独立 Sheet。

已有任务展开采用“准备接管 + 真实行高 + 真实视口位移”的双向外撑。打开事件先在无动画 transaction 中让同一 UUID 的容器取得活跃所有权、保持 `.compact` 几何，并预挂载裁切为零高的详情；下一次渲染才以统一 spring 执行 `p: 0 -> 1`。任务内容不参与整组 opacity 淡入；卡片背景、描边、圆角、阴影、内边距、详情裁切和外部呼吸间距随 `p` 连续显现。关闭保持所有权不变并用同一端点执行 `p: 1 -> 0`，到达紧凑端点后才原子释放，因此是展开的严格逆向。

容器在列表中增加完整高度 `ΔH`，其中包括活动容器自身真实参与 `LazyVStack` 布局的 top / bottom 呼吸间距；局部 UIKit Viewport Driver 同步把底层 `UIScrollView.contentOffset` 写为 `openingOffset + U × p`。因此来源上方的可见内容实际随滚动上移 `U × p`，来源下方的内容因列表重排下移 `(ΔH - U) × p`；两侧运动都来自真实布局与真实滚动，不给相邻任务添加独立 `offset`，也不创建等高占位或前景副本。`U` 默认取新增高度约 40%，并受吸附分组标题和顶部可用空间限制；列表顶部空间不足时允许自然退化为较少上撑。收起反向撤销本次 Morph 引入的 `U`，保留用户在展开期间产生的滚动距离。禁止用 `onGeometryChange` 反推动画 presentation progress，也禁止通过声明式 `ScrollPosition.scrollTo` 逐帧补偿；两者与 `LazyVStack` 重排不共享确定的提交时序。

UIKit 桥接只负责解析当前 SwiftUI `ScrollView` 对应的底层 `UIScrollView` 并执行无附加动画的 O(1) offset 写入，不拥有任务视图、详情表面、背景景深、业务状态或生命周期。逐帧 progress 只存在于活动行的 `AnimatableModifier` 并直接更新 offset，不得写入首页级 `@Observable` / `@State`、不得广播给所有列表行，也不新增常驻 `CADisplayLink`、`UIVisualEffectView`、全屏暗化层或卡片形 mask。卡内放大与非活跃任务缩小只使用 SwiftUI 合成变换，不参与布局。因此列表仍保持稳定 UUID、`LazyVStack` 懒加载与原生 pinned header；真机 60/120Hz 结果仍以 Instruments 和视觉验收为准。

创建从第一次点击开始就是列表中的任务。入口立即预分配最终 UUID，并把紧凑 Draft Seed 插入当前日期或当前周期的临时首位；Draft 在编辑期间占据真实列表槽位，属性变化不移动槽位。Dock `+` 是唯一可选的跨层 Hero 来源：根层只用显式来源与 Seed Frame 运输短暂实体，不跨 `LazyVStack` 使用 `matchedGeometryEffect`。Hero 原子交给真实容器后，后续编辑、收缩和详情展开全部由该容器本地完成。空态、深链与 Reduce Motion 直接建立并展开 Draft，不播放 Hero。

## 会话与落点

`HomeMorphSession` 只允许一个活跃对象，并区分 `.heroEntering / active / saving / collapsing / relocating`。`TaskMorphSubject` 同时表达待办或定期的 Draft/已持久化身份；`TaskMorphPlacement` 保存临时 section、最终 section、排序 index 与展示 ID。异步保存和动画完成都携带 session revision，过期回调不得修改当前会话。

保存成功后保持同一 UUID：先在临时槽位完成 `.editing -> .compact`，再进入独立的 `.relocating` 阶段释放临时 placement，按最终日期、紧急排序或周期移动。已有任务的保存、完成和属性重排遵循同一“先收缩、后移动”顺序。保存失败保留同一对象、UUID、Draft、槽位、输入与错误；放弃创建只在列表内收缩后移除，不飞回 Dock。

## 交互与可访问性

展开期间外层列表保持可滚动，不增加详情内嵌滚动。非活跃任务的完成框、Swipe、菜单以及 Dock 操作暂停；点击另一任务主体、可见 Toolbar 控件或日期/周期标题只请求保存并收起当前任务，不自动打开第二项或执行原控件动作。Toolbar、列表、安全区与 Dock 布局保持稳定；真实活动卡片是唯一圆角表面，并使用轻微实体抬升、连续圆角、克制阴影与约 `1.05` 的 X / Y 等比内容合成缩放；其他可见任务、可见 Toolbar 控件及日期/周期标题用约 `0.94` 等比合成缩放和 `0.62` 不透明度后退，系统状态栏与导航栏空白区域仍由系统持有，活动行同时提升同一列表层级，使双向外撑和间距变化仍清楚可见。展开表面的基础卡内边距为水平 `20pt`、垂直 `16pt`，为等比放大后的内容保留稳定留白。行高、内容揭示、卡片表面显现、真实外部呼吸间距与 Morph 引入的视口位移必须共享活动行的同一个显式 presentation progress；内部编辑内容不得再启动第二套异步高度或整组透明度动画。

标题在 Hero 交接和展开完成后聚焦。Dynamic Type 依赖外层列表滚动获得空间；VoiceOver Escape 请求保存/放弃并收起；Reduce Motion 跳过跨层 Hero，保留短促高度与清晰度变化。SwiftData、CloudKit schema 和应用服务不因本 ADR 改动，创建继续调用支持预分配 UUID 的 `createTask(id:)`。

## 删除与否决方案

- 删除 `HomeFocusPresentationController`、`HomeFocusPresentationCoordinator`、`HomeFocusSurfaceView`、`HomeRootContainer`、背景景深层与详情 Overlay。
- 不保留 ADR-0020 的 Feature Flag、兼容分支或回退 Host。
- 不让保存与大跨度重排同时发生。
- 不维护 Row、Editor、Detail 三个互相替换的顶层列表对象；它们只能作为同一容器内部的状态内容。
- 不通过相邻行假位移、透明 runway、重复快照或固定静态 padding 模拟双向外撑；只允许活动容器自身、由统一进度驱动且计入真实行高的外部呼吸间距。
- 不锁定外层 `ScrollView`，也不为长内容新增嵌套详情滚动。
