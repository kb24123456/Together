# 小尺寸挥笔幅度增强 · 2026-09-10

验收更新：用户已在最新真机版本上确认“已验证没问题”。现行定稿与正式入口见 [V1 基线](../README.md)；专项性能、能耗仍未测量。

用户真机反馈 A4 挥笔不明显。本轮保留造型、眼型、节奏及停笔姿态，只增强正式 `Writing`（`0-108`）内 `Grip`（`0-23`）的三条运动轨道，手和笔整体移动。

- 水平位移增加为2.4倍，上下位移2.2倍，轻微摆笔角度3倍；最大角度约2.7度。
- 30pt球体下，手部水平活动范围约1.22→2.93pt；笔尖活动范围约3.11×1.24pt。
- 3.6秒循环、首尾姿态和缓动时序不变；书写内其余2616关键帧、状态机及对外接口不变。Holding及其两主题静态图不变。
- 同一Rive文件2564580 / `TogetherSphere` / `Mascot`；`mode=1`、`isTyping=true` 查看新版。原 `Review_Writing_A4` 是旧幅度评审片，保留为历史参考。

资源已同步 `Together/Resources/BrandMascot/together_sphere_motion_study.riv`，SHA256 `8dfea4c3f2655a5de53f4ac8b7777d16d82647d6ea527d49d0a9ad7b3c75d924`。`deliverables/` 提供实际 `.riv` 与完整可编辑 `.rev`。修改前完整备份为 `backups/before-amplitude.rev`，旧App资源为 `backups/app-before.riv`。

浅深色30pt与快速切换共1800帧原生渲染；209张PNG边界检查及关键静帧抽查通过，未见裁切或手笔脱离。`review.html` 提供新旧原速对照。签名真机构建通过，导出、源码与构建包资源哈希一致。安装结果记录在 `verification.json`；用户已确认真实输入与视觉流程无问题，性能和能耗尚未专项测量。无App业务代码修改，未启动Simulator。
