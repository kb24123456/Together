# 首页球面与眼型连续性修订

已在现有 Rive 文件 2564580 修改，并将最终资源接入 Together App。

- Artboard：`TogetherSphere`（`0-2`）
- 状态机：`Mascot`（`0-7`），原 Behavior / Expressions / LightActions 三层保留
- View Model：`TogetherSphereModel`，现在 25 个属性
- 当前 137 条时间轴，包含历史、逻辑和预览，不代表 137 种表情
- 最终资源：`deliverables/together_sphere_motion_study.riv`，4,205,737 bytes
- SHA256：`80c812a991054ac6aad3e5bc9626d938d34368f838ced7a4084bcaebc40ea9a7`
- App 资源：`Together/Resources/BrandMascot/together_sphere_motion_study.riv`

## 本轮变化

六个方向仍使用原随机选择规则。主要转向的目标相对中性方向增大约18%，起步/停止使用五次平滑曲线，横纵错峰与短暂停留保留。主要片段现在为4.2～5.6秒；安静段3.6→2.7秒，左下短瞥1.6→2.0秒，使短瞥更舒展。综合片段时长估计平均转向频率比旧版提高约17%；实际间隔仍随机，并非固定轮流播放。

首页只保留用户认可的无嘴好奇和柔和开心。新增可编辑 HomeFace 四个矢量形状，复用原球面投影参数；胶囊轮廓和眨眼仍按球面投影，笑眼继承同一朝向但不受普通眨眼挤压。好奇用约0.25秒局部位移、倾斜与眼高变化；开心用约0.30秒收眼、可见细线衔接与展开笑弧。没有对不匹配路径直接插值，也没有在首页表情切换时淡空整张脸。

原有基础身体、道具、写字眼型、材质和28种通用表情未重做。120条原时间轴的原关键帧逐项保留，其中3条仅新增 HomeFace 隐藏保护；其余8条首页运动/选择时间轴按本轮节奏更新。全部298条原转场保留，原状态机/外部控制没有删除或重命名。

## 控制与属性归属

- 新的可选 `idleFace`：默认 `-1` 使用旧行为；`0` 首页胶囊、`2` 柔和开心、`21` 无嘴好奇。
- App 首页写 `idleFace=0/2/21`，通用 `expression` 始终为0；编辑、处理、逾期、反馈和禁播先写 `idleFace=-1`。
- 原 `expression=1…28`、`reaction/react`、`mode`、`isTyping`、`acknowledge`、`celebrateRequested`、轻动作和12个配色属性仍有效。
- Behavior 只控制 HomeNear/FarGaze 的朝向与 HomeCapsule 的球面几何；Expressions 只控制 HomePose、眼型缩放和显隐。LightActions 保持原 FaceMotion 归属，没有新层争抢同一属性。
- Home 的进入/退出是有限短片段；普通快速改值在当前短段完成后按最新目标分流，重复同值不重启。
- `Home_Acquire` 保留旧脸0.9秒，允许旧 WritingExit / ThinkingExit / 点击等动作收尾，再接回匹配朝向的 Home_Calm；不会暂停旧身体或阻塞 App 导航。
- 首次发布运行实例前固定推进 `[0,0.15]`，跨过旧 Entry/Resolve 初始空脸；这是运行库推进而非等待。隐藏后的固定清理：首页 `[0,0.3,0.3,0.1]`，已发反馈 `[0,2,0.1,0.1]`。

在 Rive 检查本轮效果：播放 **Mascot**，在 Instance 将 `mode=0`、`expression=0`，`idleFace` 设为0、2或21。检查旧通用表情时将 `idleFace=-1`。旧 `Idle_Orient` / `Preview_All` 是历史制作总览，本轮没有重写；检查最新首页节奏应使用 Mascot 或下列实际导出回放。

## 实际预览与验证

- `app-preview-light/preview.mov`：按当前 App 调度和首次加载步骤，80秒浅色、30fps、168px画板（约40pt球体@3x）。
- `app-preview-dark/preview.mov`：同样输入策略的深色独立实例；方向随机，因此不能逐帧比对两主题方向。
- `app-preview-transitions/preview.mov`：512px、60fps，开心/好奇与进入、退出书写的连续检查。
- 每个目录有实际 PNG、输入故事与 `evidence.json`。像素来自官方 Apple Rive 6.25.1 New Runtime / Metal，未使用截图轮播或重画角色。
- `qa/routing-final.json`：1456项官方原生路由/恢复检查通过，包含 Acquire各阶段、快速改值、重复同值、反馈、书写/流汗/思考、暂停与原28表情。该项验证状态执行，不冒充逐帧像素覆盖。
- `qa/startup-final.json`：首页/持笔/书写/流汗/思考首帧、首次点击与庆祝7个新流程通过；旧流程空脸对照复现，验证预推进必要。
- `verification-scope.json`：原时间轴、转场与接口保留检查。
- `verification-app.json`：Swift Testing、无签名通用iOS构建与导出/源码/构建包同hash检查。

已检查连续渲染及关键静帧，并实际播放抽查转向。未签名安装或检查 iPhone 真机；实际手感、屏幕刷新与能耗仍须用包含本轮修改的新设备构建验收。没有启动 Simulator。静态降级图、本轮首页两种表情的随机间隔6～11秒及其余业务映射不变。

## 保存与恢复

完整可恢复原件已在 Rive 原生 Revision History 创建并目视确认：
`Before smooth home motion · 2026-09-09`。

完成版本另存为 `Smooth home motion · 2026-09-09`，两条版本均已在历史中目视确认。

`backups/` 保存本轮前 App `.riv`、品牌模块源码和结构/关键帧快照。JSON与运行 `.riv` 不能替代完整可编辑版本；完整恢复以该 Rive 历史版本为准。导出时编辑器沙箱拒绝直接写入，已用工具返回的官方内联导出流程落盘，未绕过套餐或改文件权限。

制作脚本只作用于已识别的现有文件。`create-home-rig.py`、`author-home-faces.py`、`wire-home.py`、`refine-handoff.py` 为本次分阶段操作记录，不可整套重复执行；已有对象ID在 `rig.json`、`home-clips.json`、`home-edges.json` 中。
