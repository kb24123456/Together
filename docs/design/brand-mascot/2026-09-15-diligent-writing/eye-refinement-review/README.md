# 眼距与线宽调整 · 已确认接入

用户先要求缩短眼距、加粗眼线并暂缓导出，随后明确“确认执行”。本轮已完成导出、App接入、签名构建、实体iPhone覆盖安装与启动。

- 双眼中心距由170缩短为146画板单位（约14%），保持双眼中点、眼高、角度和长度。
- 双眼线宽由16加粗到20画板单位（25%）。
- 只修改四段书写时间轴的16个既有关键帧，其他关键帧回读一致；表情以外的姿态与运动参数不变。
- [运行资源](deliverables/together_sphere_motion_study.riv)、[内嵌资产的可编辑REV](deliverables/together_sphere_motion_study.rev)；对应App资源与两主题MascotHolding静态图已同步。
- [30pt浅色流程](flow-126-light/preview.mov)、[30pt深色流程](flow-126-dark/preview.mov)，透明持笔静帧见holding-light与holding-dark目录。此次Rive Apple 6.25.1 New Runtime / Metal渲染1562帧，78张PNG边界检查通过；抽查两主题实际眼型。
- Xcode27 / 27A5218g签名设备build、codesign深度/严格验证及diff检查通过。交付、源码与Build57包内Rive资源SHA256一致：`731a86cd92f84705790c71960b4dc0d0b82e9a73e7b3ab67cd2017b697c9c0db`，4269185 bytes。
- devicectl确认覆盖安装并启动实体iPhone17上的 `com.pigdog.Together`。未启动Simulator、未提交推送；实际视觉、连续输入、停续与深浅色切换仍由用户验收，不把安装启动成功作为真机体验通过。
- `before-keyframes.json` / `after-keyframes.json` 保留审批前后的限定改动，`review.json` 记录结果。上一层deliverables与final-*是此前未收紧眼距的版本，不代表当前App资源。
