# 小球体验修订 · 2026-09-09

> 最新增量：用户真机反馈后的[六方向随机注视](../2026-09-09-natural-gaze/README.md)已完成并打包。当前33时间轴/32节点/141转场；53几何、42逐方向中断、47资产、90暂停恢复与最新构建通过。下方左右转向和旧资源哈希保留其阶段记录。

本轮响应首页转向少、90 秒入睡过长、编辑位置突兀和书写表情不够可爱的反馈。编辑位置按用户选择改为顶部标题旁的小尺寸陪伴。Rive 编辑源与 App 运行资产均已更新，视觉喜好及真机表现仍待用户验收。

## 已实现

- 首页静候：旧 `Idle` / `Idle_QuietShort` / `Idle_QuietMedium` 只眨眼，实际转向的 `Idle_Look` 权重仅 10%。现在 `Idle` 约 2 秒开始右转，`Idle_QuietMedium` 约 1.5 秒开始左转，再自然回到中立；保留原随机片段选择和眨眼。眼睛位置、宽度、眼距与倾斜共同变化，呈现贴着球面转动的感觉。
- 入睡：无更高优先级目标且可见闲置 **15 秒**进入打盹。原生滚动阶段（含手指跟踪和减速）保持清醒，结束后重新计时；隐藏、返回和模式切换清理交互状态。有逾期任务时仍优先显示流汗。
- 睡眠：加深、圆润两条闭眼弧；新增三个渐大的 `Z`，依次轻浮并淡出。睡眠进入、循环、唤醒衔接一致，其他动作显式隐藏这些部件。
- 编辑：创建和详情的球体从正文标题区域移到原生导航栏 `.principal` 标题旁，主体 **30pt**，完整画板约 41.7pt。保留取消、保存、原控制器与真实输入映射；正文恢复完整宽度。首页仍是 40pt 主体与 44pt 按钮区域。
- 书写：两条眼线更短、更圆润，眼距收拢并统一轻微下视；保持大圆手、笔与原书写节奏。未增加嘴巴、眉毛或细手臂。
- 深浅色及静态降级：三个 `Z` 绑定现有 `inkColor`。仍为 12 个语义颜色，共 29 个颜色目标。四张持笔/打盹 PNG 均从当前 Rive 原生捕获，已同步至 App Asset Catalog。

## 文件和结构

编辑的是 Education Space 副本 [Together Sphere Motion Study](https://editor.rive.app/file/together-sphere-motion-study/2564580)，原文件 2561771 保留。主画板 `TogetherSphere`、状态机 `Mascot`；30 条时间轴、29 个节点、112 条路由和 17 个模型属性不变。`Preview_All` 已更新，旧历史预览不作为本轮验收入口。

- `build-refinement.py` / `timeline-patches.json`：限定轨道修改及书写静态几何，不自动连接或写入 Rive。
- `runtime-source/together_sphere_motion_study.rev`：本轮原生编辑备份，含完整文件。
- `runtime-source/together_sphere_motion_study.riv`：只导出主画板；与 App 源资源及最终构建包中的文件哈希一致。
- `theme-integrated.json`：本轮完整配色目标。
- `assets/`：512×512 透明 PNG，`WritingHold` 第 0 帧、`Doze` 第 105 帧，两主题原生捕获。
- [静态尺寸校样](review.html)：放大表情与两种使用尺寸；这是素材预览，不是 iOS 截图。

Rive App 对目标目录的文件访问授权不足时，本轮按照 `export_file` 返回的官方方式取得内联导出字节并写入工作区；没有通过其他格式重建 `.riv`。运行文件 1,696,775 字节，SHA-256 为 `7e9cee4db3fdf133f37c03eabb80cbbffce18eb15e17c04e9a43b6a7fd4d2fa1`。

## 验证

- `verification-readback.json`：30 条时间轴的 40,010 个目标关键帧逐项读回一致，非目标轨道保留；状态机完整结构修改前后相同。原生 26 秒模拟覆盖静候、入睡和唤醒。
- `verification-geometry.json` / `verify-refinement.py`：23 项通过。子帧眼线无自交、未越球面；循环、进入和唤醒连续；含描边的 `Z` 均在画板内，其他状态无残留。
- `apple-asset-verification.json`：新导出文件由官方 rive-ios 6.25.1 inspection API 执行，47 项通过，覆盖五类模式、单眨眼、庆祝复位和同实例深浅色读写。
- `feedback-interruption-verification.json`：同一新资产 90 组暂停/恢复轨迹通过；这是状态检查，不代表像素验证。
- `app-verification.json`：19 项独立 Swift Testing 状态/控制器测试实际通过；最新资源与 App 源码通过 Xcode 27 beta 3 通用 iOS 无签名 `build-for-testing`，已核对构建包资源。iOS 测试仅编译，未执行；未启动 Simulator 或安装真机。

Apple Knowledge Runtime query：`SwiftUI toolbar principal stable animated view identity navigation title Dynamic Type onScrollPhaseChange ancestor scroll interaction idle timer`，命中 keys / 实际采用记录均为空，结论 **无需 Expert Delta**。原生布局及滚动语义另核对 Apple `principal` / `onScrollPhaseChange` 文档，链接记录于 `app-verification.json`。

## 真机验收

需先从当前源码签名构建并运行，再检查：无逾期首页前几秒的左右转向、闲置 15 秒入睡、滚动/减速不睡及操作唤醒；创建/详情标题旁小球在键盘、长标题、较大字体下的布局；持续输入与停笔、浅深色和 Reduce Motion。静态校样与无签名构建不能替代这些验收。

本轮复用既有几何制作和资产检查脚本，无需另增 Skill。此前的套餐使用边界未在本轮重新调查。
