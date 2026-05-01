# Task Card Chat Design

日期：2026-05-01

## 1. 结论

双人任务卡片新增“任务内聊天”能力。用户可以从 Today 的双人任务卡片进入一个由卡片 morph 出来的聊天面板；只要任务未完成，双方都可以继续发送消息。任务完成后聊天历史可查看，但输入入口禁用；如果任务重新打开，则恢复可发送。

数据上以 `task_messages` 作为聊天主数据源；`assignmentMessages` 仅作为旧数据兼容和预览 fallback，不再承载新聊天主链路。

## 2. 目标

- 让双人任务不只是“指派/接受/提醒”，而是能围绕任务持续沟通。
- 保持 Today 首页卡片简洁，卡片只显示最新真实留言的单行预览。
- 聊天面板使用 iOS 原生质感的连续转场、系统 Material 背景和键盘适配。
- 数据层支持推送、离线恢复、重装恢复、分页、未读和未来扩展。

## 3. 非目标

- 不做全局私聊功能。
- 不做多人群聊。
- 不把系统状态全部写成消息表记录。
- 不在 Today 卡片中展开完整聊天列表。
- 不在本轮引入第三方聊天 SDK 或动画库。
- 不把个人自用任务强行变成聊天任务。

## 4. 用户体验方案

### 4.1 卡片静态态

双人任务卡片底部保留现有头像区域和右侧动作区。

留言入口位于头像右侧、提醒/完成按钮左侧的视觉空白区：

- 显示最新一条真实用户留言。
- 格式为 `你：内容` 或 `对方名：内容`。
- 严格单行显示。
- 超出后省略号截断。
- 不允许换行。
- 不允许因为留言内容撑高卡片。
- 不显示系统状态消息。
- 触控热区不小于 44pt 高度，不能只让文字本身可点。
- VoiceOver 读作“任务留言，最后一条来自...，点按打开聊天”。

卡片点击行为：

- 点按留言入口：进入任务聊天面板。
- 点按卡片标题/主体：保留现有任务详情行为。
- 右侧提醒/完成按钮：保持现有动作，不被留言入口覆盖。

### 4.2 可聊天任务范围

聊天入口只出现在双人协作任务上：

- 当前 space 必须是 active pair space。
- 任务 `assigneeMode` 必须是 `.partner` 或 `.both`。
- `assigneeMode == .self` 的个人任务不显示任务聊天入口。
- 已完成的双人协作任务仍可打开聊天面板查看历史，但输入框禁用。

### 4.3 Morph 聊天面板

采用方案 A：Hero Overlay Morph。

交互结构：

1. 用户点按卡片留言区域。
2. 当前任务卡片从原位置连续 morph 成聊天面板。
3. Today 列表留在背景中，作为上下文。
4. 背景使用中等强度系统 Material / blur 处理。
5. 聊天面板包含任务摘要、消息列表和底部输入框。

实现偏好：

- 优先 SwiftUI 原生状态驱动动画。
- 优先 `matchedGeometryEffect`、`withAnimation`、`safeAreaInset`、系统 `Material`。
- Reduce Motion 开启时降级为轻量淡入/淡出和位置切换。
- 键盘出现时只调整聊天面板内部布局，不重排 Today 列表。
- 聊天面板中的消息正文允许多行，并支持 Dynamic Type；只有卡片预览强制单行。

### 4.4 聊天列表

聊天面板里的真实用户消息使用类似微信的结构：

- 对方消息：左侧头像 + 左侧气泡。
- 我的消息：右侧气泡 + 右侧头像。
- 头像和左右方向都从 `senderID` 推导。
- 不只依赖颜色区分发送者。

系统状态只在聊天面板中显示，卡片中不显示。

系统状态规则：

- 只显示关键状态：指派、接受、拒绝、提醒、完成。
- 系统状态用居中弱提示展示。
- 系统状态不占用发送者头像。
- 派生自任务状态、响应历史和 nudge 事件，不作为普通用户聊天消息展示。
- 同一时间戳下排序优先级固定为：系统状态、nudge、comment、id，确保“已指派”先于初始留言。

### 4.5 任务完成后的聊天权限

- 未完成：双方可发送消息。
- 已完成：历史可读，输入框保留但禁用，并显示“任务已完成，不能继续留言”。
- 重新打开：恢复可发送。

完成态禁发是产品规则，不只是 UI 禁用；应用服务层也必须校验。

## 5. 数据模型方案

### 5.1 主数据源

`task_messages` 是任务聊天的主数据源。

现有 Supabase 表已有可复用字段：

- `id`
- `task_id`
- `sender_id`
- `sender_supabase_user_id`
- `type`
- `content`
- `emoji`
- `rps_result`
- `created_at`

本轮只需要使用：

- `type = 'comment'`：真实用户留言。
- `type = 'nudge'`：提醒事件。

### 5.2 本地域模型

扩展 `TaskMessage`：

- `id: UUID`
- `taskID: UUID`
- `senderID: UUID`
- `type: TaskMessageType`
- `content: String?`
- `createdAt: Date`

新增枚举：

- `.comment`
- `.nudge`
- `.rpsResult` 保留兼容，不进入本轮 UI。

### 5.3 SwiftData 持久化

扩展 `PersistentTaskMessage`：

- 增加 `content: String?`
- 保留现有字段默认值和旧数据兼容。
- 旧 nudge 行 `content == nil` 是合法状态。

### 5.4 assignmentMessages 退场策略

`assignmentMessages` 不再承载新聊天主链路。

兼容规则：

- 新发送的聊天消息不写入 `assignmentMessages`。
- 新建指派任务时的初始留言写入 `task_messages(type='comment')`，不再写入 `assignmentMessages`。
- 编辑任务时如果用户新增指派留言，也写入 `task_messages(type='comment')`。
- 接受/拒绝任务时如果用户附带留言，响应状态仍写入 `responseHistory`，留言正文另写入 `task_messages(type='comment')`。
- “再次发送了这个任务”这类重发提示不写成 comment，而是从任务状态变更派生为系统状态。
- 旧任务中的 `assignmentMessages` 可作为历史导入源展示。
- 卡片预览优先读取最新 `task_messages(type='comment')`。
- 没有 comment 时，fallback 到 `assignmentMessages.last`。
- 后续可做一次性迁移，把旧 `assignmentMessages` 映射为本地只读历史消息；本轮不强制做云端回填。
- 所有仍显示留言预览的任务卡片都应走同一个 latest comment 适配层；Today 之外如果无法接入 latest comment，就不要继续展示会过期的 `assignmentMessages` 新消息预览。

## 6. 应用层与 Repository

### 6.1 TaskMessageRepository

扩展协议能力：

- `insertComment(messageID:taskID:senderID:content:createdAt:)`
- `insertNudge(...)` 保留。
- `fetchMessages(taskID:limit:before:)`
- `fetchLatestComments(taskIDs:)`
- `fetchMessage(messageID:)`

性能约束：

- Today 首页不得逐卡片同步查询聊天。
- 首页进入时批量取当前可见任务的 latest comment，或由 ViewModel 缓存聚合结果。
- 聊天面板打开后再拉完整消息列表。

### 6.2 TaskApplicationService

新增应用层动作：

- `sendTaskComment(in:taskID:actorID:content:)`

服务层职责：

- 校验任务存在。
- 校验任务属于当前 pair space。
- 校验任务未完成。
- 清理空白内容。
- 限制最大消息长度为 500 个字符。
- 写入本地 `PersistentTaskMessage`。
- 记录 `SyncChange(entityKind: .taskMessage, operation: .upsert)`。

不由 View 直接写 repository。

### 6.3 TaskChatViewModel

新增独立 ViewModel，不把聊天状态塞进 `PairTimelineCard`。

职责：

- 加载任务摘要。
- 加载消息列表。
- 发送消息。
- 合并 comment / nudge / derived system event 为 `TaskChatTimelineEntry`。
- 管理输入框状态、发送中状态、失败重试状态。
- 根据完成态禁用输入。
- 维护本地已读状态。

## 7. 同步与后端

### 7.0 本地同步语义更新

`SyncEntityKind.taskMessage` 不再是 push-only nudge 日志。实现时需要同步更新注释和相关命名，使其表达为“任务消息事件流”，包含本地插入、Supabase push、Supabase pull/catch-up。

### 7.1 Push

扩展 `TaskMessagePushDTO`：

- 编码 `content`。
- `type='comment'` 时必须带非空 `content`。
- `type='nudge'` 时 `content` 可为空。

Supabase `task_messages` 已有 `content` 字段和 `comment` 推送分支，本轮优先复用。

后端约束：

- 保留已有 `type IN ('nudge', 'comment', 'rps_result')` check。
- 新增或确认 comment 内容约束：`type='comment'` 时 `content` 去空白后必须非空。
- 新增或确认 comment 长度约束：`content` 最多 500 个字符。
- `type='nudge'` 允许 `content == nil`。
- 新增或确认插入权限约束：`comment` 只能插入到未完成、未删除且当前用户可访问的任务上；完成态禁发不能只依赖客户端。

### 7.2 Pull / Catch-up

当前 `task_messages` 基本是 write-only / APNs 事件源。聊天功能必须补 pull。

最低要求：

- pair APNs、前台恢复、手动刷新、聊天面板打开时，都能触发 `task_messages` catch-up。
- 根据当前 pair space 的任务集合拉取消息。
- 只拉当前用户可访问任务的消息。
- 本地按 `id` 去重。
- 按 `created_at` 增量拉取时必须带 overlap window，再用 `id` 去重，避免设备时间偏移或乱序写入导致漏拉。
- 聊天面板分页使用 `created_at < before`，同一时间戳用 `id` 做稳定排序兜底。

父任务顺序约束：

- 新建任务带初始留言时，会产生 parent task upsert 和 child task_message insert。
- Supabase push 必须保证 parent task 先于 task_message 成功，或在 task_message 因 FK 缺失失败时保留 outbox 并重试。
- 不允许因为一次 FK 失败把初始留言永久标记为完成或丢弃。

### 7.3 Realtime

Realtime 可作为在线体验增强，但不能作为唯一可靠来源。

要求：

- 在线时收到新 comment 可立即刷新卡片预览和聊天面板。
- 离线、后台、杀进程后仍依赖 APNs + catch-up 兜底。

### 7.4 RLS 与权限

沿用已有 `task_messages` RLS 思路：

- space member 可以读任务消息。
- space member 可以插入任务消息。
- 客户端 sender 使用本地用户 UUID。
- 同时写入 `sender_supabase_user_id`，用于服务端推送排除发送者自己的设备。

需要在实现阶段复核生产库 policy 名称和当前迁移是否完全一致。

## 8. 未读状态

本轮采用最小未读模型，不做复杂 read receipt。

新增本地-only SwiftData 模型 `PersistentTaskChatReadState`，维护每个任务聊天的已读位置：

- `taskID`
- `lastReadMessageCreatedAt`
- `updatedAt`

规则：

- 打开聊天面板时标记当前消息为已读。
- 卡片可显示轻量未读点或强化留言胶囊。
- 不显示“对方已读”。
- 不同步 per-message read receipt。

## 9. 前端组件边界

### 9.1 PairTimelineCard

只负责：

- 展示任务摘要。
- 展示 latest comment 单行预览。
- 提供进入聊天的入口。
- 保留提醒、完成、接受、拒绝等现有动作。

不负责：

- 拉完整聊天。
- 管理输入框。
- 管理键盘。
- 管理消息发送重试。

### 9.2 TaskChatPanelView

负责：

- morph 后的聊天面板 UI。
- 任务摘要 header。
- 消息列表。
- 系统状态弱提示。
- 输入框。
- 发送中和失败状态。
- 完成态禁用提示。

### 9.3 TaskChatTimelineEntry

前端聚合模型：

- `.comment(TaskMessage, senderAvatar, alignment)`
- `.nudge(actorID, createdAt)`
- `.system(TaskChatSystemEvent)`

这个模型只服务 UI，不替代后端数据模型。

## 10. 错误处理

发送失败：

- 消息先乐观插入本地，显示发送中。
- 同步失败时根据本地 sync outbox 状态显示失败，可重试。
- 本轮不把发送状态同步到 Supabase；发送中/失败是本机 UI 状态。
- 失败消息不影响任务卡片其他操作。

拉取失败：

- 聊天面板显示本地缓存。
- 顶部或列表底部显示轻量错误提示。
- 用户可下拉或点按重试。

权限失败：

- 如果任务已完成或已解绑，输入框禁用。
- 如果远端提示无权限，刷新 pair 状态和任务状态。

## 11. 测试范围

### 11.1 单元测试

- `TaskMessageRepository` 插入 comment / nudge。
- 创建指派任务的初始留言写入 `task_messages(type='comment')`，不再写入 `assignmentMessages`。
- 接受/拒绝任务附带留言时，状态进入 `responseHistory`，留言进入 `task_messages(type='comment')`。
- `TaskMessagePushDTO` 正确编码 `content`。
- `sendTaskComment` 空内容不发送。
- `sendTaskComment` 超过 500 字符时拒绝发送或按产品文案提示用户缩短。
- `sendTaskComment` 已完成任务拒绝发送。
- `sendTaskComment` 记录 `.taskMessage` sync change。
- Supabase policy/check 拒绝对已完成或已删除任务插入 comment。
- `TaskChatTimelineEntry` 合并 comment / nudge / system event 的顺序稳定。
- latest comment fallback：优先 task_messages，缺失时读 assignmentMessages。
- `PersistentTaskChatReadState` 打开聊天后更新 `lastReadMessageCreatedAt`。

### 11.2 同步测试

- 本地 comment push 到 `task_messages`。
- 新建任务初始留言的 push 顺序保证 parent task 先存在；FK 短暂失败时可重试。
- 远端 comment pull 到本地。
- 重复 pull 不产生重复消息。
- APNs/comment 后 catch-up 能刷新 Today 卡片预览。

### 11.3 UI / 交互验证

- 卡片留言单行截断，不撑高卡片。
- 留言入口不覆盖提醒/完成按钮。
- morph 动画连续。
- Reduce Motion 降级可用。
- 键盘出现时输入框不被遮挡。
- 完成态输入禁用。
- 头像左右方向正确。

## 12. 实施顺序建议

1. 扩展 `TaskMessage` / `PersistentTaskMessage` / DTO。
2. 扩展 `TaskMessageRepository`。
3. 增加或确认 Supabase comment 内容/长度约束。
4. 增加 `sendTaskComment` 应用服务，并改造新建指派、编辑指派、接受/拒绝附带留言的写入路径。
5. 补 `task_messages` pull/catch-up。
6. 新增 `TaskChatViewModel` 和 timeline 聚合模型。
7. 实现 `TaskChatPanelView`。
8. 接入 `PairTimelineCard` 留言入口和 latest comment preview。
9. 补未读状态。
10. 做真机动画、键盘、推送回归。

## 13. 风险与约束

- `PersistentTaskMessage` 加字段属于本地模型迁移，需要兼容旧数据。
- `assignmentMessages` 和 `task_messages` 同时存在期间必须避免双写新聊天。
- 新建/编辑/回应任务的旧 `assignmentMessages` 写入路径必须同步迁移，否则会出现一部分留言在任务 JSON、一部分留言在消息表的双真相。
- 新建任务初始留言依赖父任务先入库；必须把 FK 顺序或重试策略作为同步实现的一部分。
- Today 首页 latest comment 必须批量/缓存，不能逐卡片阻塞查询。
- Realtime 不能作为唯一消息来源，必须有 catch-up。
- morph 动画期间不能做同步 IO、重排或重查询。
- Push 文案初期可以保持简单，不在通知里展示完整留言内容，避免隐私泄露。

## 14. 验收标准

- 双人任务未完成时，双方都能从任务卡片进入聊天并发送消息。
- 对方收到 comment 推送后，打开 App 能看到聊天历史和卡片最新预览。
- 断网后发送失败可见且可重试。
- 重装或换机后，通过 Supabase catch-up 能恢复聊天历史。
- 已完成任务不能继续发送消息。
- Today 卡片高度不因留言内容变化。
- 聊天面板有头像、左右气泡、关键系统状态和中等 Material 背景。

## 15. Open Questions

当前无阻塞性开放问题。后续实现中如果发现生产库 RLS 或同步管线与文档不一致，先回到设计确认，不直接绕过权限或写临时兼容逻辑。
