# Together 小黑球 v6 操作映射

更新：2026-09-09；行为契约基线：2026-09-08。Rive 文件：**Together Sphere Motion Study**（2561771），画板 `TogetherSphere`，默认状态机 `Mascot`。当前为单层 `Behavior`，29 个总节点（含 Entry / Any / Exit）、112 条转场、12 个原生属性清零动作。本轮保留路由和动作规范；发现 `Behavior` 层停用后恢复启用（flags 属性 754 从 1 改为 0），原生 300 帧常驻 → 书写 → 流汗 → 常驻检查通过，共 11 次转场。

**本轮已完成 Rive 内部行为与主题配色接线；下述 Host 指 App 侧协调逻辑，尚未接入或验证 Apple runtime / 真机。** 制作参数、状态机读回和检查记录不是可运行的 `.riv` 资产。保持已认可的圆球、简洁双眼和圆形手部，不扩展宠物养成或重新设计五官。配色为浅色黑球、深色柔白球与近黑五官；同一套动画使用颜色绑定，不增设行为模式。

当前主画板共有 30 条时间轴。2026-09-09 已将既有 `Acknowledge` 状态改为播放 `Expression_Wink`，状态播放速度为 2，实际轻点击反馈约 0.8 秒；原始表情与总预览中的 1.6 秒版本保持不变。没有增加输入、节点或路由，复用原 `acknowledge`、Body PointerDown、打断和恢复逻辑。`mode=2` 仍为原流汗；两条流泪时间轴仅供手动查看，自动触发场景待用户选择。最新改动、原生检查及 App 导出阻塞见 [操作接入进度](../2026-09-09-operation-integration/README.md)。

## 输入契约

属性来自画板绑定的 `TogetherSphereModel`。这是 ViewModel 属性契约，不应因状态机的传统 Inputs 列表为空而认为没有控制入口。

| 属性 | 类型 / 值 | 含义与接纳范围 |
| --- | --- | --- |
| `mode` | number `0` | 静候；自动选择安静片段与球面张望 |
| `mode` | number `1` | 编辑；拿笔后由 `isTyping` 决定书写或持笔 |
| `mode` | number `2` | 存在应提示的逾期任务；进入着急 / 流汗 |
| `mode` | number `3` | 真实处理过程；进入独立托脸思考 |
| `mode` | number `4` | 角色可见、无更高优先活动且长时间闲置；进入打盹 |
| `isTyping` | boolean | 编辑中实际输入为 `true`，停止输入为 `false`；离开编辑设为 `false` |
| `celebrateRequested` | boolean | 已接纳的真实完成事件锁存；仅当前派生 `mode=0/2` 且通过合并 / 冷却检查后置 `true` |
| `acknowledge` | trigger | 静候点击约 0.8 秒单眨眼；低优先、单次、不排队 |
| `remind` | trigger | 静候轻提醒；低优先、单次、不排队 |

`mode` 必须限制为 `0…4`。`Wake`、`Celebrate`、`Remind`、进出片段及内部选择节点不是新增持久业务模式。初始值为 `mode=0`、`isTyping=false`、`celebrateRequested=false`；触发器仅在对应事件发生时发出一次。

## 主题配色绑定（Rive 已完成）

`TogetherSphereModel`（0-375）的同一 `Instance`（0-376）当前共有 **12 个 `color` 属性，驱动 26 个实际颜色目标**；全部为单向 `toTarget`、`once=false`。本轮在原 11 色 / 24 目标基础上新增 `tearColor` 及两行泪水目标；原 5 个行为属性、190 条行为绑定和状态机路由保留。当前完整名称、颜色、ID 与目标见 [theme-integrated.json](expression-integration/theme-integrated.json)。`theme-v6.json` / `theme-bindings-v6.json` 只记录新增泪色之前的历史基线。

| 属性 | 浅色模式 | 深色模式 |
| --- | --- | --- |
| bodyLight / bodyShade | #101010 / #030303 | #F0F0F0 / #D5D5D5 |
| handLight / handShade | #141414 / #060606 | #F0F0F0 / #BDBDBD |
| farHandLight / farHandShade | #080808 / #080808 | #E8E8E8 / #B8B8B8 |
| eyeColor | #FFFFFF | #1B1B1B |
| sweatColor | #FFFFFF | #686868 |
| penBodyColor | #F2EEE6 | #767676 |
| penTipColor | #111111 | #ADADAD |
| inkColor | #777777 | #929292 |
| tearColor | #88CFF3 | #347FA6 |

颜色均不透明。PencilWood恒定为#DED6CA，无需绑定。远手保留Shape 0-40、Ellipse 0-41及Fill 0-42，内部纯色替换为径向渐变0-169089，色标0-169090/91；原SolidColor 0-43已删除，不再使用其旧ID。渐变局部坐标沿用近手的(-24,-28)→(35,39)。浅色两端同值保持原黑球，深色使用认可渐变。

App 接入时在首帧前向**同一实例**写入所选主题的全部 **12 种颜色**；后续主题变化也只更新颜色，不切换 ViewModel 实例、不重建角色、不改 mode 或触发 Idle，不触碰反馈锁存。存储默认值仍为浅色；原 v6 原生编辑器通过播放值切换白球预览。MCP 的 555/556 分别是编辑器存储值/播放值键，不是 Apple runtime API，App 应按运行时支持的颜色属性接口接入。

原 v6 的两主题各 8 组原生模拟（共 16 次）完整行为轨迹一致；实际编辑器同次播放黑/白书写后，mode=1、isTyping=true、实例 ID 未变，思考/流汗/打盹及真实点击回应也已检查。模拟工具不支持在 inputs 中注入 color，因此**不能用其警告被跳过的输入宣称验证了播放中主题切换**；该部分历史证据来自实际编辑器，见 `verification-theme-v6.json` 与 `theme-evidence/`，不覆盖新增的 `tearColor`。

新增表情的两主题静态校样已纳入 8 姿势 / 16 张 PNG，31 项素材检查及 5 组浏览器视觉检查通过，见 [显示校样说明](../2026-09-08-display-review/README.md)。这是 PNG 与离线页面的显示证据，不代表新泪色的 Apple runtime 动态切换、Reduce Motion 接入或真机验收。

## Host 如何派生操作

角色可见时，持续目标优先级为：**编辑 > 真实处理中 > 逾期 > 长时间闲置 > 静候**。每次从当前业务事实重新派生目标，不保存“播放反馈前的旧 mode”供返回使用。

- **编辑**：编辑页显示时进入 `mode=1`；输入变化驱动 `isTyping`，停止输入的去抖计时由 Host 负责。持笔等待仍属于编辑，不映射成独立 Thinking。
- **处理中**：仅绑定 App 已有、真实执行的处理过程。没有合适业务来源时保留手动验收入口，不因普通保存、等待用户输入或闲置虚构“正在思考”。
- **逾期**：使用 App 现有逾期业务结果，动画不另建任务真相或自行判断完成与截止时间。
- **打盹 / 唤醒**：闲置计时由 Host 负责；普通互动使目标恢复 `mode=0/2`，由 Rive 唤醒后读取最新目标。开始编辑或处理可经短收束直接进入对应行为，不等待完整 Wake。
- **轻提醒**：仅响应已确认的真实提醒事件，按事件标识去重并设置冷却。只在静候接纳；着急时已有流汗，不再叠加提醒。没有明确来源时不自动播放。
- **不可见 / 后台**：取消待处理反馈、停止闲置计时并暂停播放；恢复时重新派生目标，不回放隐藏期间积累的事件。Reduce Motion 的降级和暂停策略仍需在 Host 接入时实现。

Home 保留原 Profile 按钮的点击和导航行为，角色替代头像视觉。编辑页角色放在标题附近，保留取消、保存按钮与安全区域。**导航、输入、保存、取消和任务完成都不等待装饰动画结束。**

当前 Rive Body 的 `PointerDown` 只发出 `acknowledge`，由既有状态播放约 0.8 秒单眨眼；它不修改 `mode`，也不是 App 闲置计时或唤醒的业务来源。App 必须在同次真实互动中更新活动记录和持续目标。`acknowledge` / `remind` 在非静候、转场期间或片段边界可以丢弃；两者同帧到达可以择一，不承诺顺序或补播。

## 完成庆祝与事件边界

完成反馈只响应用户操作成功造成的**未完成 → 已完成**。列表刷新、同步回放、历史载入、重复保存、撤销完成及失败操作不触发庆祝。Host 按真实完成事件去重；一批快速连续完成只接纳一次。

Host 在接纳时启动冷却，并将整个 `Celebrate` / `CelebrateConcern` 与 `FeedbackDone` 收尾视为同一次反馈。活动期或冷却期内的新完成合并丢弃，不重启片段、不延长正在播放的动作、不排队。冷却与输入去抖的具体时长在 Host 接入时集中配置并验收，当前 Rive 没有实现这些业务计时器。

进入 `mode=1/3/4` 或隐藏时，Host 清除待播 `celebrateRequested`，并拒绝受限期间的新完成反馈。反过来，**当前目标已变为 `0/2` 时，即使旧视觉仍在 `WritingExit`、`ThinkingExit`、`Recover`、`Wake` 或 `Settle` 中，新的合法完成也可以锁存到后续接纳，不能被收尾动作无条件擦除。** 不需要等待旧状态退出回调再提交。

| 场景 | 预期路径 |
| --- | --- |
| 静候完成任务 | `Celebrate → FeedbackDone → Resolve`，再按最新目标继续 |
| 完成一个任务但仍有逾期 | `Concerned → CelebrateConcern → FeedbackDone → Resolve → ConcernEnter` |
| 最后一个逾期任务完成、目标变静候 | `Recover → Resolve → Celebrate → FeedbackDone → Resolve → Idle` |
| 庆祝中开始编辑 / 处理 | `Settle → Resolve`，进入最新编辑 / 处理目标；不补播旧庆祝 |
| 完成与进入编辑 / 处理同帧 | 持续目标优先，完成请求清除 |
| 收笔 / 唤醒 / 收束中收到合法新完成 | 请求保留至 `Resolve`，接纳一次后清除 |

`CelebrateConcern` 已包含从着急姿态恢复再庆祝，避免两组眼睛与汗滴直接叠加。`Resolve` 仅负责读取最新目标，正常静候结束仍使用原有加权选择；无需把每个视觉片段扩为业务状态。

## 必须保留的 Rive 清零与传播边界

12 个清零动作均写 `celebrateRequested=false`：

- `WritingEnter`、`Writing`、`WritingHold`、`ThinkingEnter`、`Thinking`、`DozeEnter`、`Doze`：仅入口清零。
- `Celebrate`、`CelebrateConcern`：入口消费，出口合并活动期重复请求。
- `FeedbackDone`：入口再次清零。

`WritingExit`、`ThinkingExit`、`Recover`、`Wake`、`Settle` 不清零；受限状态的出口也不清零，以保留目标已合法时到达的新事件。

**两个庆祝片段到 `FeedbackDone` 必须使用 16ms 非零混合，禁止提前退出，源片段在 100% 结束处暂停。** `FeedbackDone` 复用 60fps、1 帧、单次的 `Idle_Select`；只有到达结束且条件系统已看到 `celebrateRequested=false` 才以 0ms 返回 `Resolve`。不要改成两个连续的 0ms 瞬时节点，也不要仅把等待增加到 2 帧。

原生模拟曾发现：出口已写 false，但同帧 `Resolve` 尚未看到更新，会重复庆祝。仅 1 帧与 false 守卫在 7 / 24fps 下仍可能提前停止；16ms 混合提供必要的后续推进机会。修复后的 7 / 10 / 24 / 30 / 60 / 120fps 共 18 个结束边界场景已通过。纯静态图检查不能证明该传播时序，必须保留原生模拟证据；这也不等于 App、画面质量或真机性能已验收。

`FeedbackDone` 仍属于庆祝收尾，Host 在此期间继续合并 / 冷却，不能在它已清零后再次强行写入新请求。下一阶段应依此契约接入真实操作，再检查实际显示尺寸、深色模式、连续输入 / 完成与可访问性降级。
