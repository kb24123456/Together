# A4 书写动作评审 · 2026-09-10

后续状态：用户已认可本片。正式书写四段与 App 接入结果见 `../2026-09-10-writing-a4-integration/README.md`；以下为当时独立评审阶段的记录。

用户已确认 `../2026-09-10-writing-concepts/writing-A4-raised-eyes.png` 的静态形象。本轮已用原 Rive 可编辑部件制作短书写动画，等待用户对动作的视觉确认。尚未接入 App，尚未安装真机。

## 查看

- `review.html`：静态参考与实际 Rive 短片对照，可原速/半速播放，同时观察球体 30、40、64pt 的浏览器显示效果。
- `pass1-512/preview.mov`：512px 原生渲染，7.2 秒，包含两个 3.6 秒循环。
- `pass1-30pt/preview.mov`、`pass1-40pt/preview.mov`：按现有 512 画板/368 身体比例输出的 3× 原生小尺寸片段。
- 上述目录同时保存关键帧 PNG 和实际渲染证据 `evidence.json`。

## 实际制作

文件为 Together Sphere Motion Study，fileId `2564580`：https://editor.rive.app/file/together-sphere-motion-study/2564580 。

沿用 `TogetherSphere`（`0-2`）内的 Body、WritingEyeNear/Far、Grip、HandFar、PencilShaft/Wood/Nib 和 WritingScribble。只新增一条评审时间轴 `Review_Writing_A4`（`0-893641`）及同名独立评审状态机（`0-896281`），共 2256 个新关键帧。评审状态机只有一层、一个播放状态，经 Entry 自动进入循环，不需要新增业务输入。Rive 中选择该时间轴或同名状态机即可预览。

短片为“展示持笔姿态 → 两组不等长书写，中间停笔 → 轻抬笔尖并收稳”。宽直线眼型全程保持，身体轻微延后跟随，远手稳定；不叠加眨眼、嘴、装饰或额外四肢。路径及动画属性均可编辑，未使用概念 PNG 作为播放素材。

原 `Mascot`（`0-7`）仍为默认状态机。未修改原状态机、原有动画或基础设计值；评审关键帧只在选中评审时间轴/状态机时生效。

## 文件与备份

- `deliverables/writing-a4-review.riv`：实际导出的评审资源，包含原系统和独立评审动画；**不作为已批准的 App 正式替换资源**。
- `deliverables/writing-a4-review.rev`：当前文件的完整可编辑版本，包含内嵌素材。
- `backups/before-a4-motion.rev`：制作前完整可编辑备份，12591321 bytes，SHA256 `1ff58ccf554e4f7806fad3ee0f62541dd13765e7c764751a04b661f46202adf0`。
- `backups/`：同时保存制作前层级、属性、状态机、137 条时间轴及 347925 个关键帧快照。
- 原始导出也保留在 `/Users/papertiger/Library/Containers/app.rive.editor/Data/Documents/writing-a4-review-20260910/`。

## 验证与边界

`verification.json` 记录实际比对：137 条原时间轴、347925 个原关键帧完全一致，原 Mascot 状态机一致，基础几何值一致，App `.riv` SHA256 仍为 `f271aa4f51dd5673f273463a6f29d1f1041f5944b214ed6d0f52a12509243691`。

原生渲染共 864 帧；检查大图及 30/40pt 关键静帧，双眼、手笔关系与确认稿基本相符，未发现明确穿帮。浏览器实际播放四个视频，确认解码就绪、播放头推进、原速与半速控件可用。循环两端姿态相同，运动由连续缓动采样得到。

这不等于用户审美或真机验收。小尺寸的身体跟随、抬笔很轻微，最终是否自然可爱、是否需要加强，仍由用户查看短片确认。未验证物理 iPhone 性能或能耗，未运行 Simulator。确认动态后才同步原书写状态、过渡、主题与 App 静态降级素材。
