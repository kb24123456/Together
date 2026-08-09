# ADR-0022: 根级创建 Morph 与列表原子交接

- status: superseded by ADR-0023
- date: 2026-08-09
- supersedes: ADR-0021 中的创建路径

> 真机验证显示最终跨层 Frame 落点会把滚动定位、`LazyVStack` 重排和 Overlay 几何动画叠加在同一时间窗，引发明显掉帧。该最终落点决策已由 ADR-0023 取代；Dock 到编辑卡的短 Hero 仍保留。

## Context

任务详情已经由列表中的真实 `TaskMorphContainer` 原地展开，真实改变行高并通过统一进度驱动双向外撑。创建流程的交互目标不同：用户点击底部 `+` 后，需要先获得一个稳定、居中且适合键盘输入的创建表面；确认后，这个表面必须继续作为同一视觉实体收缩并落入最终任务行。把完整编辑器放进 `LazyVStack` 的临时 Draft 槽位会让键盘、滚动定位、分组变化和列表懒加载同时参与创建动画，难以维持稳定的可见所有权。

## Decision

待办和定期创建改用根级、纯 SwiftUI 的 `HomeCreationMorphOverlayLayer`。点击 `+` 时立即预分配最终 UUID；同一个根级创建表面从 Dock 来源 Frame 变形为编辑卡，并在编辑、保存、收缩和落点阶段始终保持唯一可见所有权。列表在编辑期间不插入 Draft、不承担创建卡布局，也不复制创建表面。

保存成功后分为三个严格顺序的阶段：

1. 根级创建卡使用同一实体从编辑态收缩为紧凑任务态；
2. 真实持久化任务行在最终 section/index 以独立 smooth transaction 渐进让出列表空间，但在交接前保持不可见且不可交互；reservation 动画完成并进入可见 viewport 后报告全局目标 Frame；
3. 根级实体移动并缩放到目标 Frame，完成帧使用无动画 transaction 原子切换可见所有权：真实行显示，Overlay 移除。

创建期间仍由 `HomeMorphSession` 仲裁唯一活跃对象和过期回调。详情路径不变，继续由列表拥有的 `TaskMorphContainer` 原地展开；根级 Overlay 只服务创建，不承载已有任务详情。保存失败保留同一 UUID、输入和前景表面；放弃只在当前焦点位收束消失，不飞回 Dock。空态、深链和 Reduce Motion 直接进入根级编辑态，不播放 Dock Hero。

跨层过渡不使用跨 `LazyVStack` 的 `matchedGeometryEffect`。来源、编辑卡和最终行均通过显式全局 Frame 协调；动画过程中不执行持久化、排序计算或逐帧几何反推。列表目标尚未布局时 Overlay 保持紧凑态，直到收到有效目标 Frame 才开始交接。

## Consequences

- 创建和详情不再强求同一布局所有者，但继续共享 UUID、表面视觉语法、会话仲裁和状态阶段。
- 创建卡的键盘避让、Dynamic Type 和长内容滚动可在稳定根级区域内处理，不受临时列表分组影响。
- 最终列表行必须支持“参与布局但暂时隐藏”的 landing reservation，并在交接完成时原子接管可见所有权。
- 该方案增加一个短生命周期的根级创建层，但避免同时存在两个可见圆角实体；详情仍保持纯列表内联架构。
- 真机 60/120Hz、键盘、IME 和长内容手感继续由真机验收；自动验证只覆盖状态、过期回调、身份连续性和编译。
