# ADR-0023: 创建卡消融与列表局部长出

- status: accepted
- date: 2026-08-09
- supersedes: ADR-0022 的保存后跨层落点

## Context

Dock 到根级创建卡的短 Hero、稳定编辑表面和预分配 UUID 已满足交互目标，但保存后的跨层落点需要同时协调目标分组切换、ScrollView 定位、LazyVStack 重排、目标 Frame 捕获和 Overlay 的 CGRect 插值。真机验证显示这些工作集中在同一动画时间窗会产生明显卡顿；继续微调时长无法消除架构上的同步成本。

## Decision

保留根级创建表面与现有详情原地 Morph，只替换创建成功后的 landing：

1. 持久化成功后，根级创建卡在当前位置用约 220ms 将高度收窄到接近零，同时淡出内容、表面和阴影；此阶段列表继续冻结。
2. 消融完成后，用无动画 transaction 切换到最终日期或周期并释放冻结列表。最终 UUID 的真实任务行以高度零、不可交互状态建立。
3. ScrollView 无动画定位目标行；定位提交后才允许该行以约 300ms 从 `height 0 / opacity 0 / scale 0.985` 长到自然高度与完整清晰度。只由这一行的本地状态驱动 LazyVStack 重排，完成后结束会话并恢复交互。

最终阶段不再捕获或保存列表目标 Frame，不做 Overlay 到列表的跨层位移，不使用 matched geometry，也不让 Overlay 与列表同时修改布局。列表行只在自身为当前创建目标时测量一次自然高度；普通行没有新增 Geometry 或动画状态成本。过期 completion 继续由 `HomeMorphSessionToken` 拒绝。

Reduce Motion 跳过 Dock Hero，并将消融和长出缩短为清晰的淡变/高度变化。保存失败保持根级编辑卡、UUID、输入和错误；放弃仍只在当前位置消融，不向 Dock 回飞。

## Consequences

- 牺牲“同一实体真实飞入目标行”的严格空间连续性，换取更稳定的主线程和布局预算。
- 每帧最多只有目标行高度影响 LazyVStack；没有全局 Frame 回传、逐帧 CGRect 插值或滚动与跨层动画并发。
- 跨日期、跨周期和屏外目标先原子切换/定位，再局部长出，视觉属于有意的双阶段欺骗。
- 详情 `.compact <-> .expanded` 架构不变，仍由真实列表行和 ScrollView viewport motion 完成双向外撑。
