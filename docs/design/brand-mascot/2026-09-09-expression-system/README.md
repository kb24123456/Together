# 当前小球的表情与轻量动作扩展

**最新修订：** 写字眼型已改为轻微内倾的圆端直线，并按用户反馈加宽眼线、拉开间距，详见 [最新修订与实际预览](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/README.md)。后续接入使用 [最新 `.riv`](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/focused-writing/wider/deliverables/together_sphere_motion_study.riv)，SHA-256 `dcff4246a01a85142f605b33238437ad239422e8fb8d5916e0d34b27102223c3`；包含上一轮 [7 种闭眼比例修订](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/closed-eye-spacing/README.md)。下文保留最初扩展阶段的说明和证据；控制入口与 28 种表情编号继续适用。

**App 接入更新（2026-09-09）：** 顶部定稿已替换 App 运行资源，深浅色静态持笔图同步更新；无签名编译通过，构建包资源哈希一致，详见 [接入、验证与备份](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/app-integration/README.md)。下文记录初次扩展阶段：已实际修改现有 **Together Sphere Motion Study** 教育空间文件，未新建替代角色或演示项目。

## 文件、备份与交付

- [当前 Rive 文件](https://editor.rive.app/file/together-sphere-motion-study/2564580)，文件 ID `2564580`。
- Artboard：`TogetherSphere`（`0-2`，512 × 512）；状态机：`Mascot`（`0-7`）。
- [初次扩展交付 .riv（已被顶部修订版取代）](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/deliverables/together_sphere_motion_study.riv)：3,848,270 bytes；SHA-256 `5253c970e7855db8ae6ff77fb523051746680d9e520853e56051e63bdcaea4ed`。
- [修改前完整可编辑 .rev 备份](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/backups/together_sphere_motion_study.rev)：7,018,817 bytes；SHA-256 `eaf5dc71578dd6483c9cac229b53d00871542678db9f7fc97ac7744617a4c0a7`。在首次修改前成功导出；恢复时用 Rive 打开这份 .rev，不要用旧运行资源代替完整编辑备份。
- 最终资产已成功导出，无需再手动申请导出。`representative-*`、`candidate-*`、`before-contour-*` 和 `superseded-*` 是过程证据，不是交付版本。

## 实际完成的表情

`expression=0` 沿用原角色和自动行为；1～28 为可单独选择并保持的矢量表情。每个预设均有进入/退出和一次性表现版本；有嘴与无嘴、抬眼与避开视线、哈欠与趴低分别保留。

| 数值 | 表情 | 名称后缀 | 参考来源 |
|---|---|---|---|
| 1 | 待机 | `Calm` | 图1-01 |
| 2 | 柔和开心 | `SoftHappy` | 图1-02 + 图2-05 |
| 3 | 大笑 | `Laugh` | 图1-03 |
| 4 | 兴奋 | `Excited` | 图1-04 |
| 5 | 单眨眼带笑 | `WinkSmile` | 图1-05 |
| 6 | 喜爱 | `Love` | 图1-06 |
| 7 | 害羞·腮红 | `Blush` | 图1-07 |
| 8 | 小得意 | `Smug` | 图1-08 + 图2-06 |
| 9 | 好奇·张嘴 | `CuriousOpen` | 图1-09 |
| 10 | 疑惑·张嘴 | `PuzzledOpen` | 图1-10 |
| 11 | 思考·抬眼 | `ThinkingUp` | 图1-11 |
| 12 | 专注·轻 | `GentleFocus` | 图1-12 |
| 13 | 惊讶 | `Surprised` | 图1-13 + 图2-08 |
| 14 | 尴尬流汗 | `Embarrassed` | 图1-14 |
| 15 | 小生气 | `MildAngry` | 图1-15 |
| 16 | 无语 | `Speechless` | 图1-16 |
| 17 | 犯困·哈欠 | `SleepyYawn` | 图1-17 |
| 18 | 轻松满足 | `Content` | 图1-18 |
| 19 | 难过 | `Sad` | 图1-19 |
| 20 | 委屈·短泪 | `SmallTears` | 图1-20 |
| 21 | 好奇·无嘴 | `CuriousQuiet` | 图2-01 |
| 22 | 思考／疑惑·无嘴 | `PuzzledQuiet` | 图2-02 + 图2-09 |
| 23 | 专注·认真 | `Determined` | 图2-03 |
| 24 | 恍然大悟 | `Realization` | 图2-04 |
| 25 | 害羞·避开视线 | `ShyLookAway` | 图2-07 |
| 26 | 无奈 | `Helpless` | 图2-10 |
| 27 | 小紧张 | `Nervous` | 图2-11 |
| 28 | 犯困·趴低 | `SleepyLow` | 图2-12 |

合并四组接近的表现：图1的弱“微笑”采用图2的无嘴笑眼；两张图的小得意共用一式；弱“惊讶”采用图2的明显椭圆眼；图2的思考/疑惑共用大小不等的胶囊眼，保留两个语义称呼。图1好奇/疑惑的嘴型变体、两种害羞、两种专注、两种犯困均保留。没有复制编号、文字、背景、落地阴影或动作示意线。

已有认可的 `Expression_Wink`、`Expression_Tears`、`Expression_TearsTurn` 保留；新增 `WinkSmile` 是带嘴的参考图变体，`SmallTears` 是短泪变体，不替代原有流泪表情。

## 四个实际动作

| 触发项 | 实际时间轴 | 时长 | 已实现的过程 |
|---|---|---|---|
| `observe` | `Action_Observe` | 0.9秒 | 面部先向侧上方看，身体稍晚探过去，停留后收回 |
| `nod` | `Action_Nod` | 0.7秒 | 面部下移，身体下沉与轻压缩，微回弹后收稳 |
| `celebrateMotion` | `Action_Celebrate` | 1.1秒 | 压缩预备、小幅跃起、落地缓冲、回稳 |
| `poke` | `Action_Poke` | 约0.87秒 | 左侧局部凹陷、面部受力反应、反向回弹、恢复 |

轻戳确实改变单侧轮廓。为保护已有 Ellipse 及其动画，增加同材质的 `PokeBody` 可编辑轮廓，仅在凹陷阶段接替原 Body 的显示；收尾与被其他动作打断时恢复原 Body。没有把旧身体转换成新路径，也没有把局部凹陷用整体压扁代替。当前受力方向为左侧，未新增左右方向选择接口。

## 在 Rive 中实际选择和触发

进入 `TogetherSphere` 的 Animate 模式，播放 **Mascot** 状态机，使用绑定的 **TogetherSphereModel / Instance**。选择相应 Number 或 Trigger 属性即可；不需要修改动画时间轴的关键帧。

| 属性 | 类型 | 操作 |
|---|---|---|
| `expression` | Number | 0 恢复原自动行为；1～28 选择上表并保持 |
| `reaction` | Number | 选择一次性表情的编号，默认2；0也采用柔和开心 |
| `react` | Trigger | 播放 reaction，结束后恢复当前 expression |
| `observe` | Trigger | 探头观察 |
| `nod` | Trigger | 点头确认 |
| `celebrateMotion` | Trigger | 轻庆祝 |
| `poke` | Trigger | 左侧轻戳 |

例如：`expression=2` 后触发 `celebrateMotion` 是笑眼庆祝；改为4后同一个动作变为兴奋庆祝。`expression=6`、`reaction=3` 后触发 `react`，会从喜爱短暂大笑，再恢复喜爱。反应中改变 expression，结束后恢复**最新选择**，不会恢复过期值。expression 为0时单独触发 celebrateMotion，会短暂配柔和开心再回原行为。

原接口继续存在：`mode`、`isTyping`、`acknowledge`、`celebrateRequested`、`remind` 及12个颜色属性。检查原书写/流汗前设 `expression=0`：`mode=1` 且 `isTyping=true` 播放书写，`mode=2` 播放担心流汗，`mode=0` 回原待机和随机眨眼/多方向注视；mode3/4分别保持原思考/打盹。原 acknowledge 仍使用已认可单眨眼。

动作期间再次触发**同一动作会合并为当前这次**，不无限排队；另一动作可以平滑打断当前动作。动作结束返回 Action_Rest，持续表情不会因此回到胶囊眼。连续切换 expression 最终会到达最新数值。

### 两个新增的编辑器总览

- `Preview_Expressions_28`：50.4秒，逐个展示28种表情的进入、保持和退出。
- `Preview_LightActions_4`：约6.17秒，连续展示观察、点头、庆祝、轻戳。

在左侧 Animations 列表选择并播放。若只看到三个旧姿势，检查是否仍停在旧 Preview/静态画板；若列表折叠，可向上拖开左下区域分隔线。总览便于看样式，**组合、持续选择和触发请播放 Mascot**。总览不是 App 正式映射。

## 原结构与属性归属

原 `CharacterRoot (0-14)`、`Body (0-15)` / `Ellipse (0-16)`、黑色渐变、原双眼/手/笔/汗滴及其局部变换保留。新增零变换外层组织动作：

- `LightActionRoot (0-452670)` → `ExpressionPosture (0-452671)` → 原 CharacterRoot。
- CharacterRoot 下新增 `FaceMotion (0-452672)`；内部为 `ExpressionMotion (0-452647)` 与 `LegacyFace (0-452673)`。
- LegacyFace 收纳原 IdleFace、WritingFace、SweatingFace、ExpressionEyes、SleepSymbols；原节点名字和关键帧未改。
- 新增两只共享可编辑眼睛、一个嘴型、汗滴/短泪/少量腮红和 Z 符号，随表情切换轮廓和显隐；未制作28个独立小球。

Mascot 沿用并扩为三层：

| 层 | 控制范围 | 兼容处理 |
|---|---|---|
| Behavior | 原身体与原脸/道具/业务行为 | 原32节点、141转场、1个监听器完整保留 |
| Expressions | 新眼嘴路径、情绪装饰、新姿态外层、LegacyFace显隐 | 先退出旧眼型再进入新眼型，避免双眼/双嘴叠加 |
| LightActions | 动作外层、面部运动外层、轻戳轮廓与原Body显隐 | 不写表情眼型，也不改原书写轨道 |

共128条时间轴，包含保留的33条、28组保持/退出/一次性片段以及控制和总览片段；不是128种独立情绪。视图模型原17属性保留，增加7个控制项后为24个。原12个颜色接口保持，新部件复用这些颜色，绑定的颜色目标从29扩为44个，支持原黑球/白五官与深色模式白球/黑五官配色。

开放眼型以眼睛缩放眨眼，结束恢复当前路径；闭眼、笑眼、心形等特殊眼型暂停自动眨眼。旧自动眨眼只影响被收纳的旧脸，不能覆盖新表情。每个表情都明确控制嘴、汗、泪及 Z 的显隐，退出后清除；短泪左右错峰，睡眠 Z 上浮淡出。

## 实际预览与验证边界

下面是**最终 .riv 经官方 Apple Rive Runtime 6.25.1 连续推进并实际绘制**的输出，不是参考图拼接：

- [28表情浅色回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-all-28-light/preview.mov)
- [28表情深色回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-all-28-dark/preview.mov)
- [小生气实际静帧](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-all-28-light/frame-01395.png) / [白球犯困静帧](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-all-28-dark/frame-01575.png) / [局部轻戳静帧](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-actions/frame-00432.png)
- [四动作回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-actions/preview.mov)
- [笑眼/兴奋庆祝等组合回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-combinations/preview.mov)
- [快速切换、重复触发与原行为回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-rapid/preview.mov)
- [一次性反应恢复回放](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-reaction-restore/preview.mov)
- [48pt浅色](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-48pt-light/preview.mov) / [48pt深色](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-48pt-dark/preview.mov)
- [80pt浅色](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-80pt-light/preview.mov) / [80pt深色](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/final-80pt-dark/preview.mov)

尺寸测试采用48/80pt完整画板、@3x像素输出；原主体占画板约72%，对应主体约34.5/57.5pt。心形、大笑、笑眼、半闭眼、惊讶、困倦、汗/泪等主要类别可区分；轻专注与普通胶囊眼、轻微视线差异在48pt下仍属于细微变体，不承诺用户能凭这些细节读出精确情绪名称。

[最终交付验证汇总](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/delivery-verification.json)记录10套同一最终哈希的连续回放，共18,600帧、470张PNG、10段视频（合计310秒）。28表情视频先展示1.5秒原待机，随后每1.5秒按表中1～28切换，末尾回原待机。静帧与过程证据保存在每个回放文件夹的 `frame-*.png`、`story.json`、`evidence.json`。输入事件与最终资产 SHA-256 一并记录。视频的像素来自实际 GPU 绘制；证据中 `inspectionReplayStateChanges` 是另一个官方实例使用同输入做的逻辑回放，不冒充视频实例的逐帧内部状态，随机待机分支可能不同。

已完成：

- [182项状态机检查](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/verification-final.json)：28种保持、28种一次性反馈、112种表情×动作组合以及快速选择、重复/交叉触发、恢复当前持续状态、旧模式/单眨眼等。
- [旧动画逐条比较](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/legacy-keyframe-compatibility.json)：33条原时间轴、183,528个原关键帧未改。[原行为图比较](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/legacy-graph-compatibility.json)：原32节点/141转场/1监听器未改。
- 编辑器内分批静帧检查和两个新总览的实际播放；官方运行库连续回放全部表情、四动作、代表性组合、旧书写/担心/待机，以及两尺寸两主题。
- 最终运行库回放发现三种斜眼轮廓方向相反导致不显示，已在原项目修正。仅修改三种新增表情的9个片段和对应总览的4,608个几何键，全部读回；[专项实际450帧复验](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/runtime-qa/contour-fixed-3/preview.mov)恢复正确显示，随后重出最终资产并重跑交付回放。
- `git diff --check` 通过。Apple Expert 检索 query 为 Metal 离屏绘制、GPU 完成后的像素读回和确定性动画帧写出，keys/adopted为空，结论“无需 Expert Delta”。

未验证或本轮不做：112种组合均验证状态路径，但没有对每一种组合的每一帧逐一人工视觉评审；iOS真机实际布局、App内交互/30fps表现、耗电/性能、系统Reduce Motion/后台暂停等本轮未重新验收。最终三种轮廓修复后以运行库像素复验，编辑器此前已播放总览，但末次回到编辑器时 Mac 已锁定，未再次在编辑器重播修正版。没有启动 iOS Simulator，也没有因此构建 App。

**App 当前已包含顶部定稿版本**，SHA-256 `dcff4246a01a85142f605b33238437ad239422e8fb8d5916e0d34b27102223c3`，替换了此前 `c8af1b8e…` 多方向注视资源。既有业务映射不变，静态持笔图已同步；新增表情／动作控制项尚未增加业务触发，不等于真机会自动展示全部 28 种新表情。

## 后续维护入口

`rig.json`、`presets.json`、`design.py` 描述可编辑部件与表情；`state-machine-current.json` 是已修正的真实图结构，`source-*` 是修改前快照。`rive_client.py`、导出脚本及 `runtime-qa/sequence.swift` 可复用。`build-rig.py`、`author-batch.py`、`wire-batch.py` 和 `preview-timelines.py` 是已执行的制作过程，不要盲目重跑，以免产生重复节点/路由/时间轴；尤其不要把旧的过程边记录当成当前图。

项目记忆已记录新的Rive状态、交付哈希、验证和App边界。此流程已多次重复，后续适合把备份、限定属性写入、读回、导出哈希和原生像素回放整理成一个专用Rive制作/验收Skill；本轮未额外安装或创建Skill。
