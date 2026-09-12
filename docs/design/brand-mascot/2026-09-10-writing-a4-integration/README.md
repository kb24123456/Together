# A4 书写形象正式接入 · 2026-09-10

后续小尺寸挥笔增强已接入，当前资源与备份见 [幅度增强记录](../2026-09-10-writing-amplitude/README.md)。以下保留首次A4接入记录。

用户已确认 A4 静态形象及 3.6 秒评审动画。本轮将其同步到正式书写四段、App 运行资源与浅深色 Holding 静态素材，签名构建通过，已覆盖安装实体 iPhone 并成功启动。实际真机观感、输入体验、能耗仍待用户检查。

## 结果与控制方式

- Rive 文件：Together Sphere Motion Study，fileId `2564580`，https://editor.rive.app/file/together-sphere-motion-study/2564580 。
- Artboard `TogetherSphere`（`0-2`）、默认状态机 `Mascot`（`0-7`）、数据模型 `TogetherSphereModel` 均保持原名与接口。
- `mode=1` 进入编辑陪伴；`isTyping=true` 播放新的 Writing，`false` 保持新的 WritingHold。App 既有输入停止约0.9秒后进入Hold的逻辑不变。
- `WritingEnter`（`0-1032`，0.2s）、`Writing`（`0-108`，3.6s循环）、`WritingHold`（`0-1033`，4s轻呼吸循环）、`WritingExit`（`0-1034`，0.2s）统一 A4 眼型、眼高、手位及笔姿态。原先的分阶段拿笔、笔迹显现与收笔显隐保留。
- A4 的身体跟随由已有 `CharacterRoot` 控制；`WritingProps` 与 `WritingFace` 使用父节点逆向缩放补偿，避免与全局 `FaceMotion` 争用属性。笔/手的实际位置与用户认可评审片逐帧相符。
- `Review_Writing_A4` 独立评审片保留，文件共138条时间轴。只改4条正式书写时间轴，其余134条、原状态机、基础图形与所有业务接口未改；没有修改 App Swift 业务代码。

## App 与交付文件

- 正式资源：`deliverables/together_sphere_motion_study.riv`，4266199 bytes，SHA256 `034bc570f48ed845c12721ecd95630513e091fd5229a02fc2948ae8b4fb1b8e4`。
- 已同步 `Together/Resources/BrandMascot/together_sphere_motion_study.riv`；交付文件、源码资源与签名构建包的 SHA256 三方一致。
- `Together/Assets.xcassets/BrandMascot/MascotHolding.imageset/holding.png` 与 `holding-white.png` 均由此正式资源的 Holding 状态原生渲染，保留透明背景。
- 完整可编辑交付：`deliverables/together_sphere_motion_study.rev`，内嵌素材。
- 制作前备份：`backups/before-integration.rev`。`backups/app-before.riv`、`backups/MascotHolding.imageset/` 保存旧 App 素材，同时保留138时间轴、350181关键帧和状态机快照。
- 编辑器原始导出保留在 `/Users/papertiger/Library/Containers/app.rive.editor/Data/Documents/writing-a4-integration-20260910/`。

## 验证

- `verification.json`：确认只改四条时间轴，其他134条完整关键帧及原状态机未变；28个显隐通道原时序保留。对217个采样点验证正式与评审动画的部件坐标一致，最大计算误差约 `5.7e-14`；基础几何未改。
- 最终资源共4082帧官方 Apple Rive New Runtime / Metal 渲染。`final-light/`、`final-dark/` 展示首页→书写→Hold→续写→首页；`final-30pt-*`、`final-40pt-*` 为现有 App 尺寸@3x；`final-edge-transitions/` 覆盖进入中退出、快速停续、转流汗/思考及返回首页。
- 已抽查大图、小尺寸、浅深色静帧及实际浏览器连续播放。`pixel-bounds.json` 检查363张关键PNG，全部在画板内，最小边距10px。未发现由本轮产生的手笔脱离或退出残留。
- 第一轮接入的道具显隐通道覆盖问题已修正，最终预览目录以 `final-*` 为准；旧 `flow-*`/`edge-transitions` 仅保留为修复前记录。
- `review.html` 可原速/半速查看最终状态流程；`final-holding-light/dark/` 为最终透明降级图来源。
- Xcode27 beta3签名设备构建及 `codesign --verify --strict`、`git diff --check` 通过。已覆盖安装并启动 iPhone17，App版本仍为1.0 / Build50；未改Widget，本轮以资源SHA及本次安装为准。
- 未运行 Simulator，未新增业务代码，不重复无关单测。原生离线播放与构建不代表真机手感、连续输入、Reduce Motion切换或能耗已验收；这些由用户在当前已安装版本中确认。

阶段信息已写入 `docs/PROJECT_MEMORY.md`；沿用现有 Rive/原生预览脚本，无需新增Skill。
