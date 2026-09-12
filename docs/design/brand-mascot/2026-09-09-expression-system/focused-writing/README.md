# 专注书写眼型修订

**最新版本已按用户反馈加宽眼线并拉开眼距，见 [间距修订与最新资源](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/README.md)。** 下文保留首版直线眼型的过程记录，接入请使用后续版本。

已在原 [Together Sphere Motion Study](https://editor.rive.app/file/together-sphere-motion-study/2564580) 中修改共用书写眼型。Artboard `TogetherSphere`、状态机 `Mascot` 和所有对外属性保持不变。

两条向下弯的短弧改为**圆端直线、轻微向内下倾**，表达认真书写。保留原线粗 17／16、下视高度、近远眼差异和无嘴造型；稍增加长度与间距。没有添加眉毛、嘴巴或装饰，手、笔、身体及书写节奏不变。

![修改后的真实书写帧](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/final-light/frame-00180.png)

## 实际文件和预览

- [最新 `.riv`](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/deliverables/together_sphere_motion_study.riv)：**3,848,190 bytes**；SHA-256 `e476454430f09a0109e1abcdf9535a97c84feae7a244f282cacd83765382ff4a`。包含上一轮已认可的 7 种闭眼比例修订。
- [浅色连续预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/final-light/preview.mov)／[深色连续预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/final-dark/preview.mov)：静候 → 进入书写 → 停笔持笔 → 继续写 → 收笔 → 流汗 → 静候，共 21 秒。
- [修改前同节奏对照](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/before-light/preview.mov) 使用上一轮已交付的 `ede42794…4249` 资源；不是本次导出失败的临时文件。
- 在 Rive 中直接播放 `Writing` 或 `WritingHold`；状态机入口仍为 `expression=0`、`mode=1`，`isTyping=true` 写字、`false` 持笔，`mode=0` 收笔回静候。

## 修改范围与恢复

仅修改六个既有节点的 Design 属性：`WritingEyeNear 0-44`、`WritingEyeFar 0-50` 的横向位置／旋转，以及原路径顶点 `0-46/47/52/53`。两端和控制柄共线，仍为原 `CubicDetachedVertex`，没有转换节点类型。中心线长度 46／42，眼中心横坐标 −59／42，角度 +12°／−12°，原纵坐标 32／27 和线粗保持。

`WritingEnter`、`Writing`、`WritingHold`、`WritingExit` 和旧总预览共用这些部件，因此进入、持笔、续写和退出均同步生效；不需要复制或改写时间轴。

- 修改前完整可编辑备份：Rive `Revision History` → **`Before focused writing eyes · 2026-09-09`**。
- 修改后保存点：**`Focused writing eyes · 2026-09-09`**。两个条目均已在原生编辑器确认。
- 本地保存了修改前属性、相关完整关键帧、全部时间轴摘要及状态机／数据模型快照，见 `backups/`。本地当前完整 `.rev` 没有新增导出，不将 JSON 或运行资源称为完整编辑备份。
- 导出最初超时并持续报告有任务占用；确认修改后云端保存点后重启 Rive、重新连接 MCP 并打开同一文件，导出成功。重开后已核实新几何保留。
- 后续若复用早期 `2026-09-09-refinement/build-refinement.py`，应保留本目录 `eye-patch.json` 的新眼型，避免旧 `writingBase` 弧线覆盖已认可修订。`apply-focused-writing.py` 带修改前值校验，不能盲目覆盖外部新改动。

## 验证边界

- 修改前后 **128 条时间轴、317,430 个关键帧**摘要完全一致，完整状态机和数据模型比较一致；六节点目标属性读回通过，其他已检查眼部属性不变。
- 5 项实际 MCP 检查通过：书写、持笔、继续书写、退出回静候、书写切换流汗。见 `compatibility.json`、`readback.json`、`state-checks.json`。
- 已在编辑器实际播放书写；最终 `.riv` 的官方 Apple Rive Runtime 6.25.1 连续回放覆盖上述流程及深浅色，关键静帧核对新旧眼型、停笔和继续书写。
- 小尺寸专项记录见 `visual-verification.json`。原生离线画面不等于 iPhone 真机审美、系统缩放、帧率或功耗验收。
- **本轮未替换 App 内 `.riv` 或静态降级素材，未修改 App 业务代码，未启动 Simulator、构建或验真机。** 手机仍是此前打包版本，不能直接用于验收本次新写字眼型。
