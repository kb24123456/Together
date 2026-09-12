# 闭眼类表情的宽度与间距修订

后续已完成 [专注书写直线眼型修订](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/README.md)，该修订包含本页全部成果。接入请用后续版本；本页文件保留为本阶段证据。

已在原 [Together Sphere Motion Study](https://editor.rive.app/file/together-sphere-motion-study/2564580) 中完成修订，Artboard `TogetherSphere`、状态机 `Mascot`、`TogetherSphereModel / Instance` 及全部控制接口保持不变。本轮只调整双眼的横向轮廓和位置，保留嘴型、眼线厚度、球体、道具、原有胶囊眼及已认可的单眨眼和流泪动画。

## 已修改的 7 种表情

| expression | 表情 / 时间轴后缀 | 调整 |
|---|---|---|
| 2 | 笑眼 `SoftHappy` | 双眼外移，弧线稍加长，保留弧高 |
| 3 | 大笑 `Laugh` | 闭眼折线横向展开，拉开间距，保留原嘴型 |
| 16 | 无语 `Speechless` | 横眼由 49 加长到 63，双眼中心距由 98 增至 124 |
| 17 | 犯困／哈欠 `SleepyYawn` | 半闭眼由 41 加宽到 58，双眼中心距增至 124；小嘴与眼嘴上下距离不变 |
| 18 | 满足 `Content` | 下弧眼略加长，双眼中心距增至 120，保留弧高 |
| 26 | 无奈 `Helpless` | 与无语相同的横向展开，保留轻微倾斜区别 |
| 28 | 趴低 `SleepyLow` | 与无语相同的横向展开，保留低位面部和原身体姿态 |

尺寸单位为 512 × 512 画板单位，原球径 368。没有将所有表情统一放大；单眨眼、小得意、疑惑等一开一闭的混合眼型保持原样。

## 查看与触发

- 在 Rive 中播放 `Mascot`，把 `expression` 设为上表数值即可保持对应表情；设为 `0` 恢复原自动行为。
- 设置 `reaction` 后触发 `react`，可查看一次性表现及返回；结束时回到最新的持续表情选择。
- 四个动作仍用 `observe`、`nod`、`celebrateMotion`、`poke`，可与表情组合。
- `Preview_Expressions_28` 和 `Preview_LightActions_4` 已同步修订。本轮没有新建或重命名接口。
- [深浅色、48／80pt 实际尺寸校样](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/size-check.html)。图片来自下面同一份最终 `.riv` 的原生渲染；48／80pt 指完整画板，球体约占 72%。
- [7 种表情浅色连续预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/final-all-7-light/preview.mov)、[深色连续预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/final-all-7-dark/preview.mov)。按表格顺序各 3 秒，最后恢复自动行为。
- [切换、动作打断、旧书写与流汗回归预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/final-mixed-interactions/preview.mov)。

## 保存与恢复

- [本轮最终 `.riv`](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/deliverables/together_sphere_motion_study.riv)：**3,848,210 bytes**，SHA-256 `ede427945e365e1dee3342326c116b9deea7171072170c167c8aa2f8fb194249`。
- **修改前完整可编辑备份在 Rive 云端版本历史**：同一文件的 `Revision History` → **`Before closed-eye spacing · 2026-09-09`**。已通过原生编辑器创建并目视确认条目后才开始修改。
- [本轮修改前 `.riv`](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/backups/together_sphere_motion_study.riv) 为运行资源辅助备份；另有 23 条受影响时间轴的完整修改前关键帧、状态机及数据模型快照。它们不代替上面的完整可编辑云端备份。
- **本轮当前文件的本地完整 `.rev` 未导出**：Rive 对目标路径写入被自身沙箱拒绝，11,705,230 bytes 又超过 MCP 的 8 MiB 内联上限。此前扩展前的本地 `.rev` 是更早阶段，不能冒充本次修订前版本。详见 [恢复记录](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/backups/recovery.json)。
- App 内资源与业务代码未替换；手机仍使用此前多方向注视版本。后续接入应采用本轮最终文件，不能误用上一级目录的早期交付版本。

## 验证与边界

- 23 条时间轴共 **10,026 个眼部值**定向更新并读回；其他关键帧字段、嘴、身体、道具及所有时间节奏保持不变。状态机和数据模型与修改前完整比较一致。[验证记录](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/verification.json)
- 7 个持续表情及 7 个一次性返回检查均通过，共 **14 项实际 MCP 状态机模拟**。
- 官方 Apple Rive Runtime 6.25.1 对最终同哈希资产进行了 7 套连续像素回放：大图两主题、48／80pt 两主题，以及混合交互，共 **10,080 帧、151 张 PNG**。其中 32 帧无变化复用上一帧，其余均实际 GPU 绘制。不是 PNG 轮播动画。
- 编辑器已实播 `Expr_SleepyLow` 和更新后的 `Preview_Expressions_28`；静帧另核对持续表情恢复、动作中横眼、旧书写、旧流汗。原生运行记录里的 `inspectionReplayStateChanges` 是独立逻辑回放，不能冒充视频实例的逐帧状态追踪。
- 以上证明实际资源的内容及切换；不等于 iPhone 真机审美、系统缩放或性能验收。本轮未启动 Simulator、未构建或安装 App，未宣称设备帧率、功耗通过。

修订只解决已经确认的闭眼比例问题，没有新增表情或扩大动作范围。
