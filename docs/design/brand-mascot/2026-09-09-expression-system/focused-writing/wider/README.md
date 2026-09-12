# 写字双眼加宽与间距修订

**App 接入更新（2026-09-09）：** 用户确认后，本页定稿已替换 App 运行资源，并同步深浅色静态持笔图；构建包哈希一致，无签名编译通过。见 [接入与备份记录](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/app-integration/README.md)。下文“未替换 App”描述的是设计修订阶段。

已在原文件 `2564580`、`TogetherSphere / Mascot` 中，只修改共用写字眼型的 10 个水平几何属性。

- 双眼中心距：101 → **125**；视觉中点不变。
- 近／远眼中心线长度：46／42 → **56／52**；内侧净间隙约 41.5 → **55.7**。
- 保留原来的 ±12° 倾角、17／16 线粗、圆端、下视高度和手笔动作。持笔、续写、进入与退出共用新几何。

![最新写字表情](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/final-light/frame-00180.png)

- [最新 `.riv`](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/deliverables/together_sphere_motion_study.riv)：**3,848,190 bytes**，SHA-256 `dcff4246a01a85142f605b33238437ad239422e8fb8d5916e0d34b27102223c3`。
- [实际连续预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/final-light/preview.mov)：静候、书写、停笔、继续、收笔、流汗及恢复。
- 完整可编辑备份：同一 Rive 文件的 `Revision History` → **`Before wider writing eyes · 2026-09-09`**，修改前已创建并目视确认。另有本地属性与结构快照；没有新增本地完整 `.rev`。

128 条时间轴、317,430 个关键帧及完整状态机／数据模型与本次修改前一致，目标属性读回通过。原生运行库回放与关键静帧检查包含大图及 42pt@3x 深浅色；详见 `verification.json`、`readback.json`、`visual-verification.json`。没有逐帧人工检查全部影片。

导出首次超时；重启 Rive、重开同一文件后，确认新几何保留并成功导出。重启前编辑器显示 0.8.5761，重开后显示 0.8.5779；未手动点击安装更新。实际交付及预览均以本页新哈希为准。

在 Rive 中播放 `Writing`；或播放 `Mascot` 并设 `expression=0`、`mode=1`、`isTyping=true`。`isTyping=false` 持笔，`mode=0` 收笔返回。所有控制入口不变。

**本轮未替换 App 资源或静态素材，未修改 App 业务代码，未构建或验真机。** 本页资源取代上一级目录的首版直线眼型；后续重建应继续应用本目录 `eye-patch.json`，保留本次宽度和间距。
