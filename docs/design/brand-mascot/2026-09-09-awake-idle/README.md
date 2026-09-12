# 首页持续清醒与日常随机表情

用户已确认采用克制的日常表情，并取消首页休眠。本轮已修改 App，沿用已定稿的 Rive 资源与角色造型。

**真机反馈后的筛选：** 用户指定移除05「单眨眼带笑」与08「小得意」，首页表情池现仅含02「柔和开心」和21「好奇」。原有点击入口 `acknowledge` 的无嘴单眨眼保留；Rive 源素材未删除。下文四种表情的回放与运行库检查是筛选前的历史证据，不代表当前首页仍会出现05/08。

- 首页普通待机始终为 `mode=0`，停留 15 秒、90 秒、1 小时或更久均不进入休眠。删除 App 的睡眠分支、15 秒计时及 `MascotDoze` 深浅色静态图。
- 原 Rive 多方向转头、呼吸和眨眼继续运行。App 间隔随机 6～11 秒临时选择 `expression=2/21`（柔和开心、无嘴好奇），保持 1～1.5 秒再恢复 `0`，不连续重复。只剩两种且不连续重复，因此表情类型轮换，间隔、持续时间和原转头方向仍随机。
- 滚动期间基础动作继续，暂缓日常表情。编辑、真实处理、逾期、点击或完成反馈立即取消日常表情，原书写、流汗和庆祝保持事件含义。反馈结束且冷却结束后重新安排日常表情。
- 后台、隐藏、App 锁、减弱动态效果、低电量和严重热状态仍暂停；恢复时不补播离开前的表情。只有实际边界才唤醒既有 deadline Task，没有新增逐帧 SwiftUI 状态更新。

Rive 内历史睡眠时间轴保留用于制作回溯，App 已移除其自动入口和静态素材。本轮没有修改 Rive 文件，也没有重建表情：生产 `.riv` SHA-256 仍为 `dcff4246a01a85142f605b33238437ad239422e8fb8d5916e0d34b27102223c3`。接入前生产源码与删除的静态图位于本目录 `backups/`，哈希见 `before.json`。

## 实际验证

- 23 项 Swift Testing 测试、参数展开共30个案例通过，使用实际生产 Behavior/Controller 源码；覆盖长驻不休眠、允许表情与不重复、期限、中断、恢复及原输入语义。
- 官方 Runtime 6.25.1：1,200/1,200 退出／打断检查通过；4 个表情×10个阶段×5个目标×6种清理路径。所有检查均无睡眠、旧表情或旧反馈恢复重放。
- 两主题各80秒、30fps原生像素回放，输入由实际生产策略和固定预览随机种子生成；每段出现8次短表情，四种均覆盖。另有12秒书写打断回放。人工检查主要表情及单眨眼切写字的关键帧，不宣称逐帧审阅全部视频。
- Xcode 27 beta3（27A5218g）通用 iOS 无签名 `build-for-testing` 通过。构建包 `.riv` 哈希一致；实际编译的 `Assets.car` 不含 `MascotDoze`。
- `git diff --check` 通过。Apple Expert query 为 `SwiftUI Observation state-driven idle animation scheduling Task cancellation scenePhase Reduce Motion one-shot deadlines avoid replay after resume`；无命中，无采用记录，结果“无需 Expert Delta”。

[浅色80秒预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-awake-idle/preview-light/preview.mov) · [深色80秒预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-awake-idle/preview-dark/preview.mov) · [表情切书写](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-awake-idle/preview-writing-interruptions/preview.mov)

证据见 `behavior-verification.json`、`runtime-audit/verification.json`、`runtime-audit/review.json` 以及 `verification.json`。原生视频展示 Runtime 实际绘制，不是 iPhone App 录屏；逻辑状态轨迹由同SDK独立检查实例提供，随机转头可能与视频实例不同。

未启动 iOS Simulator、未签名安装真机；iOS 测试目标仅编译未执行。重新从当前工程运行到 iPhone 后，检查首页长驻、随机表情、输入打断和系统暂停行为。低亮度、设备性能和能耗仍须真机验收。
