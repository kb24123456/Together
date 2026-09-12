# 品牌小球：操作映射与 App 接入

> 最新增量：用户真机反馈后的[六方向随机注视](../2026-09-09-natural-gaze/README.md)已完成并打包。当前33时间轴/32节点/141转场；53几何、42逐方向中断、47资产、90暂停恢复与最新构建通过。下方左右转向和旧资源哈希保留其阶段记录。

更新：2026-09-09。当前 Rive 源文件为 Education Space → Personal Files 的 [Together Sphere Motion Study（2564580）](https://editor.rive.app/file/together-sphere-motion-study/2564580)，原件 2561771 保留。主画板 `TogetherSphere`，默认状态机 `Mascot`。

## 当前进度

**Together App 的操作映射及本轮细化已整合，新资源的最终 App 构建已通过；视觉喜好与真机表现仍待验收。** 主 App 精确锁定官方 `rive-ios 6.25.1`，使用 New Runtime 的 Worker、Rive 与数据绑定接口。本地打包运行文件和 8 姿势 × 浅深主题共 16 张静态 PNG；Widget 不链接 Rive，启动不依赖编辑器、MCP 或网络。最新入口为 [本轮细化与验收说明](../2026-09-09-refinement/README.md)。

首页右上角以约 40pt 主体替代原头像视觉，44pt 原生按钮仍立即进入 Profile；个人资料页用户头像不变。创建与详情页改为顶部原生 principal 导航标题旁的 30pt 主体，完整画板约 41.7pt，放入 44pt 高导航槽；正文恢复全宽标题。原 navigationTitle、两侧取消/保存、完成框、输入会话身份与系统安全区保留。导航文字单行尾截断、VoiceOver 读完整标题，仅紧凑导航文字限至 xxxLarge，正文保留全部辅助功能字号。

本轮细化位于 `../2026-09-09-refinement/`：默认 `Idle` / `Idle_QuietMedium` 约在 2s / 1.5s 后分别轻转向相反方向，保留随机待机选择；书写改为两条更短、更圆润的下视眼弧；打盹改为睡眠眼弧和三个渐大、浮起、淡出的 Z。三个 Z 共用 `inkColor`，当前为 12 个配色属性 / 29 个颜色目标；29 节点、112 转场、30 时间轴、17 属性未变。[本轮几何检查](../2026-09-09-refinement/verification-geometry.json) 23/23、19 项纯状态测试、新资产 47/47 检查和 90/90 组暂停轨迹均通过。[最后一次新资源 build-for-testing](../2026-09-09-refinement/app-verification.json) 已成功，源资源与构建包 `.riv` 的 SHA-256 同为 `7e9cee4db3fdf133f37c03eabb80cbbffce18eb15e17c04e9a43b6a7fd4d2fa1`；真机观感尚未验收。

教育空间的导出文件在技术上可用于 App runtime。Rive [官方 Student Plan 说明](https://rive.app/docs/account-admin/pricing#students)限制个人教育用途，不含商业或团队使用；尚未发布的商业开发也不能据此认定获授权。用户已授权继续技术接入，未替用户购买或宣称已获得商业许可。

## 已实现的操作映射

| App 场景 | Rive 行为 | 实现边界 |
| --- | --- | --- |
| 首页可见、无更高目标 | `mode=0` 静候、眨眼、球面张望 | 原生随机待机继续由 Rive 负责 |
| 点击小球 | `acknowledge` → 约 0.8 秒单眨眼 | 仅静候接纳；立即打开 Profile，不为完整播放延迟导航；遮挡后取消，不返回补播 |
| 创建/编辑任务 | `mode=1` 持笔 | 标题、备注和子任务真实输入时 `isTyping=true`；停顿 0.9 秒后持笔；失焦、保存、退出停止书写 |
| 今日应提示的普通待办逾期 | `mode=2` 流汗 | 复用 `showsOverdueCapsule`；不把定期临近事项当普通逾期 |
| 当前 OCR 会话实际识别 | `mode=3` 思考 | 取 `.processing`；进入草稿确认结束思考，不把 Task 句柄存在当处理中 |
| 可见且无操作 15 秒 | `mode=4` 打盹 | 列表点按和顶部模式切换记录活动；滚动、惯性减速期间保持清醒，结束后重新计时；按最新目标唤醒 |
| 未完成 → 已完成且服务成功 | `celebrateRequested` | 仅 mode 0/2 接纳，短反馈共用 4 秒冷却；失败、恢复、同步、新建和普通保存不庆祝 |
| 轻提醒、流泪 | 保留原文件手动预览 | 尚无已确认的真实自动触发来源，未新增业务路线 |

持续目标优先级为 **编辑 > 真实处理 > 当前逾期 > 可见闲置 > 静候**。动画不能阻塞输入、保存、任务完成或导航。完成事件发生时编辑页仍可见，会按优先级丢弃，不在退出后补播。

## 实现位置

- [MascotBehaviorState.swift](../../../../Together/Features/BrandMascot/MascotBehaviorState.swift)：可独立测试的展示策略，使用单调时钟；不持有任务文本、日期算法或数据库。
- [MascotController.swift](../../../../Together/Features/BrandMascot/MascotController.swift)：每个展示会话的集中控制器，只有下一个有效截止时间的单个可取消等待，不按帧写 Observation。
- [MascotRuntime.swift](../../../../Together/Features/BrandMascot/MascotRuntime.swift) / [BrandMascotView.swift](../../../../Together/Features/BrandMascot/BrandMascotView.swift)：异步本地加载、同实例输入与主题更新、30fps、静态兜底和生命周期。
- [AppRootView.swift](../../../../Together/App/AppRootView.swift) / [HomeView.swift](../../../../Together/Features/Home/HomeView.swift)：首页入口、可见性、原生滚动阶段、真实完成信号与 OCR 当前处理会话。首页可见时每 30 秒重算已有逾期结果，不重载 repository。
- [TaskCreationView.swift](../../../../Together/Features/Shared/TaskCreationView.swift) / [TaskDetailView.swift](../../../../Together/Features/Shared/TaskDetailView.swift)：只在当前焦点所属文本 Binding 的用户写入中记录活动；初始化、回填、trim 和 IME 快照同步不触发。
- [HomeViewModel.swift](../../../../Together/Features/Home/HomeViewModel.swift) / [RoutinesViewModel.swift](../../../../Together/Features/Routines/RoutinesViewModel.swift)：服务返回后确认同任务、同周期的真实完成变化，再发布界面 revision。未改变数据模型、应用服务或 CloudKit 语义。

## 生命周期与降级

可见且允许播放才创建 Worker。加载 generation 在每个异步边界检查，旧取消不会发布实例或覆盖新载入；重试清输入缓存。加载中的主题更新应用于最新实例；加载前的一次性反馈直接丢弃。

后台、导航/模态遮挡、周回顾/逾期/本周完成弹层、App 锁定、Reduce Motion、低电量和严重/临界热状态都停止播放。静态图按持笔、担忧、思考等当前目标及主题选择；用户操作不依赖资源是否加载成功。

暂停时清除已发出的短反馈。New Runtime 没有 trigger clear/reset API，因此对曾发出的反馈在同一实例执行固定四次无绘制推进 `0 / 2 / 0.1 / 0.1s`，走完单次动画与 Resolve 收尾，不运行可见帧循环、不另建计时器或实例。该做法绑定当前状态机契约；如延长反馈时长或修改路由，须复验下列轨迹。

OCR 使用会话 UUID 隔离取消、结果与清理，防止旧识别任务覆盖新会话或残留 Thinking。粘贴文字仍为既有本地解析与草稿确认，不虚构耗时过程。

## 验证与未完成事项

- 本轮 19 项真实执行的 Swift Testing 纯状态检查通过，覆盖当前 15 秒闲置与滚动期间保持清醒的边界；本轮 23 项几何检查通过。前版 14 项展示策略/控制器检查作为上一阶段记录保留。
- Home/Routines 的真实完成 revision 补充测试覆盖成功、恢复、失败、刷新、重复结果及详情完成一次性；整包测试编译/执行状态以本节后续构建记录为准，不能与独立策略测试混为一谈。
- 本轮最新资源与 App 源码已通过 Xcode 27 beta 3 通用 iOS 无签名 `build-for-testing`；App 源 `.riv` 与最终构建包资源哈希一致。[本轮构建和测试记录](../2026-09-09-refinement/app-verification.json) 明确区分 19 项已执行状态测试与仅编译的 iOS 测试，未安装真机。
- 本轮新资产的 [47 项 Apple 检查](../2026-09-09-refinement/apple-asset-verification.json) 与 [90 组暂停/恢复轨迹](../2026-09-09-refinement/feedback-interruption-verification.json) 全部通过，证据独立于下方前版结果；这些仍不是 iOS 像素或真机手感验收。
- **前版资产**的官方 6.25.1 独立 Apple 检查 47/47 通过，暂停收尾 90/90 组轨迹通过，不代表本轮新资源已完成同等验收。两者使用同包的 inspection/Legacy API 观察核心状态机，**不等于新 Runtime 的 iOS 视图或像素验收**。前版 New Runtime API 编译证据另列于 [Apple runtime 验收](apple-runtime-audit/README.md)。
- 前版交叉审查修复：首页两类 Sheet 暂停遗漏、顶部切换未唤醒、短反馈后台补播、加载取消后的输入缓存复用；当时最终代码复核未发现新的确定 P0/P1/P2。
- 未启动 Simulator；未完成真机布局、第三方输入法连续输入、滚动/Swipe 兼容性、低亮度深色轮廓、减少动态效果、CPU/GPU 和能耗验收。

Apple Knowledge Retrieval Evidence：query `SwiftUI Rive UIViewRepresentable stable identity lifecycle visibility scenePhase pause background animation Reduce Motion cancellation`；命中 keys `[]`，实际采用记录 `[]`，**无需 Expert Delta**。新 Runtime 接口以官方 6.25.1 源码为准。

### 前版操作接入构建结果

前版操作接入在 Xcode 27 beta 3（27A5218g、iOS 27 SDK）下，通用 iOS 无签名 `build-for-testing` 已成功，App、Widget 与测试目标均完成编译链接；`.riv` 已进入 `Together.app`，Mascot 测试参与编译。仅该次命令设置 `DEVELOPER_DIR=/Users/papertiger/Downloads/Xcode-beta 3.app/Contents/Developer`，没有切换全局 Xcode、下载组件或启动 Simulator。默认命令行 Xcode 26.6 虽可列出 SDK，却在 iOS destination 检查报平台未安装；不要把该环境错误当作源码错误。该记录不覆盖当前导航小球、15 秒闲置与 Rive 细化的新资源。

该前版构建不代表执行了 iOS 测试或安装真机。当时实际执行 14 项独立策略测试；新增 VM 测试完成编译，尚未运行。编译有既有 Profile、SwiftData/Widget/Mock 和旧测试警告，当时未发现小球模块新增警告。

## Rive 源资产与制作证据

当前细化的 [运行文件 .riv](../2026-09-09-refinement/runtime-source/together_sphere_motion_study.riv) 与 [可编辑备份 .rev](../2026-09-09-refinement/runtime-source/together_sphere_motion_study.rev) 已另存，当前几何与读回记录位于同级 refinement 目录；新运行文件 1,696,775 字节，已核对与 App 源资源及最终构建包一致。完整结果见 [本轮说明](../2026-09-09-refinement/README.md)。

以下为首次教育空间复制与操作接入的历史基线：

[运行文件 .riv](runtime-source/together_sphere_motion_study.riv) 1,638,162 字节；[可编辑备份 .rev](runtime-source/together_sphere_motion_study.rev) 5,734,213 字节。教育空间 Copy/Paste 前后 3 个画板、30 时间轴/139,347 关键帧、29 节点/112 转场、17 属性与 216 完整绑定一致，仅在副本恢复被停用的 Behavior 层。源文件保留，详见 [导出比对](education-export-verification.json)。

Acknowledge 使用认可的 Expression_Wink，以 2 倍状态速度播放约 0.8 秒，原始 1.6 秒时间轴不变；原生点按、密集触发、编辑/处理/逾期/完成打断等 10 组检查通过，既有时间轴未改。[状态验证](verification.json)、[浅色点击](tap-wink-light.jpg)、[深色点击](tap-wink-dark.jpg)为该阶段证据。首次 App 接入没有重新制作五官或改写 Rive 文件；当前细化的眼弧、转向及睡眠符号以上方新资源为准。

## 下一步

本轮新资源与导航布局的最终无签名构建已通过；下一步从当前源码签名安装，按 [本轮真机清单](../2026-09-09-refinement/README.md) 验收：首页 40pt 与 Profile → 导航标题旁 30pt 角色、真实输入与停笔 → 静候转向、15 秒打盹及滚动保持清醒 → 完成/逾期/OCR → 前后台、深浅色与静态降级。不要用前版安装判断本次资源。流泪自动场景与商业用途授权分别确认。
