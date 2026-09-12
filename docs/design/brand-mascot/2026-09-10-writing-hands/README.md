# 书写手部层次优化 · 2026-09-10

在现有 [Together Sphere Motion Study](https://editor.rive.app/file/together-sphere-motion-study/2564580) 内增量调整。Artboard `TogetherSphere`、状态机 `Mascot`、数据模型 `TogetherSphereModel` 保持原名及接口。

## 最终效果与修改范围

- 持笔组 `Grip` 向左52、向下22画板单位；辅助圆手 `HandFar` 向右50、向下29。保留120/116的原圆手直径，未增加手臂或改球体、眼型。
- 手部只保留少量接触，靠轮廓外移与明暗区分；不是全程具有完整1pt空隙。两手高低错开，避免像球体底部的两个凸起。
- 浅色主题近手渐变改为 `#2C2C2C → #0E0E0E`，远手 `#222222 → #0B0B0B`；深色主题原白球与灰阶手部配色保留。同步现有4个配色数据值及 App `MascotPalette`。
- 笔跟随持笔组移动；为留足画板边距，笔杆、木段、笔尖整体在手中上收6单位，比例不变。笔迹向左52、向下16，保留原笔与笔迹之间的运动关系。
- 仅33条已有时间轴的1390个位置键做常量偏移，包含书写进入/持笔/写入/退出及已有隐藏复位、历史预览。347925个关键帧的ID、时刻、插值不改；其余346535个键完全不变。137条时间轴及完整状态机保持一致，无新状态、新计时器或业务映射。

## App与真机

- 最终资源 `deliverables/together_sphere_motion_study.riv`，4205742字节，SHA256 `f271aa4f51dd5673f273463a6f29d1f1041f5944b214ed6d0f52a12509243691`。
- 已同步 `Together/Resources/BrandMascot/together_sphere_motion_study.riv`，并从同资产实际渲染更新 `MascotHolding` 浅/深色透明静态图。
- Xcode 27 beta 3、Together scheme、Debug签名构建通过，主App/Widget签名、设备profile与App Group核验通过。源资源、交付文件与构建包三方SHA一致。
- 已覆盖安装到已连接iPhone 17并启动，运行进程已确认。版本仍为1.0 / Build50；本轮没有改Widget，未改构建号。新资源以以上SHA和本轮安装为准。
- 未启动Simulator；未进行真机书写视觉、触摸、能耗或帧率验收。安装启动成功不等同用户审美验收。

## 实际预览及检查

- `final-light/preview.mov`：512px、60fps、12秒，包含进入书写、写字、停笔、续写、收笔。
- `final-30pt-light/dark/preview.mov`、`final-40pt-light/dark/preview.mov`：官方Apple Rive 6.25.1 New Runtime / Metal连续渲染，按App首次加载预推进。126/168px画板约对应30/40pt主体@3x；共1440帧和152张关键PNG。
- 已实际播放30pt浅色影片，采样检查待机→书写→恢复；未声称逐帧人工验收。静帧检查涵盖两主题、两尺寸；收笔无手/笔/笔迹残留。152张PNG均未触边，底部至少保留2/3像素余量。
- `scope-verification.json`：实际回读全部关键帧、完整状态机、相关层级/尺寸、数据属性及配色对比。
- `final-small-pixel-bounds.json`、`final-small-visual-review.json`：小尺寸像素边界和目视/实际播放记录。
- `app-verification.json`：签名构建、资源一致性、设备安装与启动；`git diff --check`通过。本轮未改业务逻辑或状态机，未重复旧全量单测。

## 保存与恢复

- 修改前完整可编辑、嵌入所有资产的备份：`backups/before-writing-hands.rev`（12591315字节，SHA256 `cd6246fe456540eb6ec2d5d6bbc6f8448000436d14c020cf810e7193e804f8ef`）。
- 修改后完整可编辑版本：`deliverables/together_sphere_motion_study.rev`。运行格式不是唯一备份。
- `backups/`另存修改前App运行资源、Palette源码、两张Holding静态图，以及动画/数据/结构快照。
- Rive MCP因编辑器沙箱无法直接写工作区，改为导出到编辑器可写Documents，再复制到上述路径；导出真实文件已校验，不绕过套餐或修改权限。
- `apply-hands.py`是本轮基于固定原件的操作记录，不应随意重跑；后续以最终文件为起点。沿用现有原生渲染/检查流程，本轮无需新增Skill。
