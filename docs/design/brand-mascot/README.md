# Together 品牌小球

2026-09-12：当前代码修复首页进入编辑时直接跳动：入场离开 SwiftUI 暂时关闭 UIKit 动画的布局事务后启动，保留同一真实渲染视图、原生落点和返回协调方式；移动途中自然拿笔，不再等待停靠。Mac Catalyst 隔离复现已记录修复前无中间位置、修复后连续中间位置，用户随后确认连续多次切页的 iPhone 真机复测保持正常；[复测记录](2026-09-12-repeat-switch-diagnostics/README.md)保留此前暂停现象及未确认的根因。此前 V1 造型、书写幅度及完整使用流程的验收不代表新版已验收。

当前入口：[入场直跳修复](2026-09-12-entrance-start/README.md)。历史阶段：[入场与抵达后书写](2026-09-12-editor-arrival/README.md)；[可见跨页承接](2026-09-10-visible-transfer/README.md)；资源制作：[连续性与改期提示](2026-09-10-continuity/README.md)。

## 正式资源

- App资源：[`together_sphere_motion_study.riv`](../../../Together/Resources/BrandMascot/together_sphere_motion_study.riv)
- 可交付 `.riv`：[下载](2026-09-10-continuity/deliverables/together_sphere_motion_study.riv)
- 完整可编辑 `.rev`：[下载](2026-09-10-continuity/deliverables/together_sphere_motion_study.rev)
- 最后一次修改前完整备份：[before-continuity.rev](2026-09-10-continuity/backups/before-continuity.rev)
- 运行资源SHA256：`7eb9ed8e1ee821322c2a12d70832e0ab969e0d4c394f5450b8e8c18c1eb72bd8`，4269590 bytes。
- [Rive原项目](https://editor.rive.app/file/together-sphere-motion-study/2564580)：`TogetherSphere` / `Mascot` / `TogetherSphereModel`。

## App中的正式行为

| 场景 | 表现与现有控制入口 |
| --- | --- |
| 首页静候 | `mode=0`，随机球面转向、呼吸、眨眼；`idleFace=0/2/21` 对应基础、柔和开心、好奇 |
| 编辑输入 | `mode=1`、`isTyping=true`；A4宽直线眼、大圆手、3.6秒不等长书写，增强挥笔幅度 |
| 编辑停顿 | 停止输入约0.9秒后 `isTyping=false`，保持持笔姿态 |
| 今日逾期 | `mode=2`，流汗 |
| OCR处理中 | `mode=3`，思考 |
| 完成反馈 | `celebrateRequested`，沿用成功完成事件与结束恢复逻辑 |
| 轻回应 | `acknowledge` Trigger，沿用原入口 |
| 跨日期改期成功 | 返回首页显示简短结果，稍后 `noticeResult` Trigger 产生一次 0.9 秒左下注视，保留原脸与逾期状态 |
| 跨页交接 | 唯一真实渲染视图在首页40pt与编辑标题旁30pt之间移动、缩放；入场保留首页动作，实际停靠后才拿笔；返回继续跟随原生转场 |
| 暂停与降级 | 页面不可见、后台、应用锁、减少动态效果、低电量及严重热状态时暂停，使用对应主题静态素材 |

上述输入由根级 `MascotPlaybackSession` 统一协调 `MascotBehaviorState`、`MascotController`、`MascotRuntime` 与 `BrandMascotView` 管理。首页不进入休眠，也不再随机播放05、08；流泪和轻提醒不自动触发。浅色黑球白五官，深色白球黑五官；原取消、保存和Profile导航语义保持。

`Review_Writing_A4` 是旧幅度评审片，其他历史预览不代表当前生产表现。检查现行书写应使用 `Mascot` 的 `Writing`；不删除历史片段或重命名对外接口。

## V1 验收基线与后续

- 用户确认：此前 V1 真机视觉及完整使用流程无问题，新版不沿用该确认。验收来源为用户报告，未将未逐项说明的项目扩写为独立测试结果。
- 已有工程证据：[A4接入](2026-09-10-writing-a4-integration/README.md)、[幅度增强](2026-09-10-writing-amplitude/README.md)；签名构建、资源一致性、原生回放和静帧检查已通过，当时的 V1 已安装并启动，本轮新版尚未安装。
- V1 归档当时只更新文档和资源清单。本轮实现、构建与未完成的真机验收记录见上方连续性入口。
- 用户于2026-09-10明确取消性能与能耗专项检查，认可当前体验。准备阶段安装了相同V1资源的Release构建；首轮采样连接超时，没有取得有效测量数据，未做性能优化。后续不继续采样，也不将取消记为测量通过。
- 设计阶段收敛，后续只针对实际缺陷或新业务需求调整，不继续无目标微调。未创建Git提交、标签或推送。

制作流程已多次复用，后续若继续扩展，可将“完整备份→限定修改→原生小尺寸回放→资源一致性→真机安装”整理成专用Rive Skill；本次不新增工具或流程文件。
