# DEVELOPMENT_GUIDELINES.md

## 1. 文档职责
- 本文件是项目「一起 / Together」的唯一工程规范主文档。
- 负责：技术约束、架构原则、数据策略、工程组织、测试与验证要求。
- 不负责：产品范围与页面需求；这些以 `PRODUCT_SPEC.md` 为准。

## 2. 技术约束
- 平台：iPhone only。
- 技术：SwiftUI 为主；仅在 SwiftUI 无法合理实现时，局部使用 UIKit。
- 环境：Xcode 26.2，Swift，iOS 18+。
- 当前阶段：纯单人 Todo，迁移到本地 SwiftData + CloudKit private database。
- 长期方案：Apple-only 数据栈；不得继续引入 Supabase、RevenueCat 或其他第三方后端作为核心链路。
- 页面必须支持 SwiftUI Preview 和 mock data。
- 开发时就考虑深色模式、Reduce Motion 和安全区域。

## 3. 代码与 API 约束
- 优先使用 Apple 原生 API 和系统能力，谨慎引入第三方库。
- 不再新增 Supabase、RevenueCat、第三方登录、第三方同步或第三方订阅 SDK 使用。
- Swift 代码默认按 Swift 6.2+ 的现代写法执行；优先 `async/await`，不要继续新增 closure-first 异步接口。
- 默认假设严格并发检查会持续增强；共享状态优先使用 `@Observable`，并优先结合 `@State`、`@Bindable`、`@Environment` 传递。
- 若项目未启用 Main Actor 默认隔离，`@Observable` 类型默认补 `@MainActor`。
- 除非处于低层兼容或历史包袱场景，不新增 `ObservableObject`、`@Published`、`@StateObject`、`@ObservedObject`、`@EnvironmentObject`。
- 不继续新增 `DispatchQueue.main.async` 这类旧式主线程调度；需要切回主线程时优先使用现代 Swift Concurrency。
- 除非属于不可恢复错误，不允许新增 force unwrap 和 force try。
- 优先使用现代 Foundation API 与 `FormatStyle`；不要继续新增 `DateFormatter`、`NumberFormatter`、`MeasurementFormatter` 作为常规方案。
- 字符串、数字、日期格式化默认使用 Swift 原生格式化能力；禁止继续新增 `String(format:)`。
- 文本搜索若面向用户输入，优先使用 `localizedStandardContains()`。
- 文件路径与 URL 处理优先使用 `URL.documentsDirectory`、`appending(path:)` 等现代 API。

### 3.1 SwiftUI 具体规则
- 优先使用 `foregroundStyle()`，不要继续新增 `foregroundColor()` 作为常规文本/图标着色方案。
- 优先使用 `clipShape(.rect(cornerRadius:))`，不要继续新增 `cornerRadius()`。
- 导航统一使用 `NavigationStack` + `navigationDestination(for:)`，不新增 `NavigationView`。
- 除非明确需要点击位置或点击次数，否则点击交互优先用 `Button`，不新增 `onTapGesture()`。
- 不使用 `Task.sleep(nanoseconds:)`，统一使用 `Task.sleep(for:)`。
- 不使用 `UIScreen.main.bounds` 读取布局空间；优先走安全区域、容器尺寸和现代布局 API。
- 复杂视图片段不要长期堆在 computed property 中，优先拆成独立 `View` 结构体。
- 优先使用系统动态字体，不要随意写死字号。
- 图片按钮默认同时提供文本，避免做成不可读的 icon-only 交互。
- 非必要不引入 `GeometryReader`；优先评估 `containerRelativeFrame()`、`visualEffect()` 等新 API。
- 列表与滚动场景避免 `AnyView`。
- SwiftUI 中避免直接使用 UIKit 颜色。
- 只要实现自定义动画，必须由单一交互会话和显式状态驱动。已有任务详情不再使用列表内关键帧 Morph；来源内容与详情 route 必须共享稳定任务 UUID，由根级 `fullScreenCover` 的 `.matchedTransitionSource` / `.navigationTransition(.zoom)` 负责页面连续性。matched source 只挂在任务行内标题、可见备注和属性摘要的真实内容栈，外层全宽行继续负责布局、命中与 Swipe；不得复制来源内容、测量逐帧 frame、叠加列表景深或自定义 viewport 驱动。
- 动画关键路径禁止同步保存、重查询、重排序或无关重布局。详情与创建的 `.zoom` 只负责视图层级连续性，不承载持久化阶段；保存成功后才关闭页面，失败保留当前编辑会话。转场和列表显现均不得引入键盘 / 滚动坐标监听或逐帧 Observation 写入。
- 动画技术按效果、稳定性、帧率与可中断性选择，可使用 SwiftUI、UIKit 或 Core Animation。当前任务详情优先保持系统全屏模态与单一 SwiftUI 页面所有权；只有真机 Instruments 证明明确热点需要处理时才做局部优化，不能为技术偏好复制 SwiftUI 文本、控件或任务身份。
- 首页环境粒子使用单个根级 stitchable Metal `colorEffect`，待办 / 定期切换不得创建第二实例。浅色分支使用约 `12%` 活跃单元、约 `0.5...1.1pt` 主半径和约 `22%...32%` 单点不透明度，以更少、更清晰的冷银灰点匹配深色分支的感知显著度；浅色累计 alpha 上限约为 `32%`，深色现有密度、尺寸、色彩和不透明度保持不变。着色器每像素固定只计算四个当前网格单元，禁止恢复参考实现的 `4 × 3 × 3` 邻域搜索；刷新上限为 `60fps`，不得跟随 ProMotion 提升到 `120fps`。持续时间只进入 GPU uniform，不向 Observation 写逐帧状态，不读取滚动 offset，也不得使用 CPU 粒子数组、Canvas 粒子循环、模糊、发光或多级离屏合成。
- 动态背景必须在页面不可见、场景失活、Reduce Motion、低电量及严重 / 临界热状态下暂停持续刷新；停止完成后 `TimelineView` 必须进入 paused。性能降级顺序固定为“四层降三层 → 降低密度 → 降至 30fps”；如真机仍出现可感知卡顿、持续升温或能耗显著上升，默认关闭效果，不以视觉偏好覆盖性能门槛。
- 待办与定期任务删除不建立专属视觉动画会话：触觉后立即调用 repository / application service，持久化成功后由 ViewModel 在单次 SwiftUI `withAnimation` 事务中同步移除本地展示项，失败保留原行并呈现错误。View 只用待删除 ID 选择原生 `opacity + move(edge: .top)` removal transition，正常时钟约 `200ms`，Reduce Motion 仅约 `120ms` 淡出；不得引入延迟等待、多阶段状态机、逐帧 Observation、Metal shader、CPU 粒子、全屏合成层或拆分持久化与呈现提交，列表收拢继续由真实数据与 `LazyVStack` 身份管理。
- 提醒投递方式是设备级全局偏好，由 `ReminderSchedulerProtocol` 统一读写，默认 `.alarm`；普通待办与定期任务调度不得再读取各定期规则 JSON 中的旧 `reminderDelivery` 作为行为真相。旧字段只为历史 Codable 兼容保留。冷启动和后台维护不得主动弹出 AlarmKit 授权；未授权、拒绝或系统不可用时必须降级为本地通知。用户在 Profile 授权或切换投递方式后，应重建当前空间内已有待办与定期提醒。
- 首页任务流保持不挂载 `.refreshable`；加载与同步继续使用现有 ViewModel 生命周期和显式刷新链路，不在滚动顶部新增竞争手势。
- 已有任务详情由根级 `fullScreenCover` 打开，并在模态内拥有独立 `NavigationStack`。列表行保持紧凑布局，以 `TaskDetailRoute` 和稳定 UUID 标记行内实际内容宽度的 matched transition source；目的页使用单一 `ScrollView` 和系统语义背景，不解析或写入 `UIScrollView.contentOffset`，不主动滚动、不复制任务表面、不改变其他任务的 scale / blur / opacity。进入目的页前由对应 ViewModel 建立唯一编辑 Draft；标题编辑器首帧稳定挂载，页面挂载后一帧立即请求 `FocusState`，不等待 `viewDidAppear`、不使用固定延时或键盘通知。顶部叉号、VoiceOver Escape 与系统左滑交互式关闭直接放弃尚未确认的 Draft；右上角勾号只在标题、备注、子任务或属性 Draft 相对已保存任务发生实际变化时启用，并在提交前统一刷新标题、备注、现有 / 新增子任务的输入法组合文本。保存 / 完成关闭期间通过 `interactiveDismissDisabled` 阻止并发关闭，保存成功才关闭模态，失败留在当前页；完成动作同样先保存。待办与定期底部属性轨道都使用 `safeAreaBar`，每个胶囊按固有内容宽度保留至少 `8pt` 水平内边距，整组可放下时自然排列，不足时由 `ViewThatFits` 回退为单行横向滚动；不得用可压缩的等分 frame 包裹固定宽度文字。待办日期 / 时间 / 提醒继续使用既有 Sheet，定期周期 / 目标日 / 目标时间 / 提醒统一进入一个轻量 Sheet，并只更新当前编辑 Draft。普通字号的紧凑 detent 必须在 Sheet 根层按当前可见行数计算，辅助功能字号改用可滚动 `.large`，不得把 presentation sizing 只挂在条件分支内。定期目标日 JSON 规则允许月度 `weekdayOfMonth` 与月 / 季 / 年 `lastBusinessDay`，新增 case 不修改 SwiftData 字段；计算器必须约束候选日期仍位于当前周期，切换周期时 ViewModel 统一归一化或清除不兼容规则。
- 首页底部入口由 `NavigationStack` 的系统 `.bottomBar` 持有，只使用原生 `ToolbarItem`、`ToolbarSpacer`、`Menu`、`Button` 与 SF Symbols。`+` 作为 matched transition source，以预分配最终 UUID 创建对应 ViewModel 的内存会话，再通过根级 `fullScreenCover` 打开共享 `TaskCreationView`；正常动效使用系统 `.zoom`，Reduce Motion 使用 `.automatic`。创建期间不得向根 `ScrollView / LazyVStack` 注入临时任务、不得复用任务详情 route、不得复制列表焦点景深。创建页使用单一 `NavigationStack + ScrollView`、系统语义背景、带明确无障碍名称的原生叉号取消 / 勾号添加 toolbar 和 `FocusState`；待办与定期分别沿用既有创建会话及应用服务。属性轨道必须只有一个交互实例，由底部 `safeAreaBar` 常驻承载并随系统键盘安全区移动，不监听键盘通知、不读取键盘高度，也不在正文与底栏之间复制或切换控件；待办子任务必须位于属性轨道上方。紧急与关注只更新待办创建会话，并在同一次创建事务中持久化，关注成功后复用既有 Live Activity 协调器。提交必须先刷新输入法组合文本、校验标题并锁定重复请求；保存成功后 finalize 会话、关闭页面并由 ViewModel 在最终位置标记一次真实行插入动画，失败保留 UUID、输入和错误。取消直接 discard 内存会话且不写库；保存期间禁止交互下拉关闭。
- 创建页子任务插入只依赖 `TaskSubtaskDraft.id` 的稳定身份和一次局部 `withAnimation`；输入框及尾部操作槽位不得因插入或清空文本被重建。日期时间 Sheet 的连续选择只写入 View 本地 pending draft，必须在 `onDismiss` 后用一个动画事务更新业务创建 Draft，避免 Sheet 与父级胶囊同时争用布局动画。
- 时间编辑不建立全局独立 Picker 或专用大号 Sheet。待办日期时间 Sheet 和定期属性 Sheet 继续使用系统 compact `DatePicker`；OCR 统一属性 Sheet 继续使用既有 `TaskEditorSingleColumnTimeWheel`，原内联入口继续使用小型系统 wheel Popover。所有入口共享 5 分钟粒度、清除时间同步清除提醒及原提醒提前量语义；不得再接入大号双组件 `UIPickerView`、双 `UITableView` 圆柱滚轮、边缘模糊层或另一套 pending 提交状态机。

### 3.2 SwiftData 与测试约束
- 只要当前模块使用 SwiftData，就优先沿用 SwiftData，不要随手回退到 Core Data。
- SwiftData 必须接 CloudKit private database：不要使用 `@Attribute(.unique)`。
- SwiftData + CloudKit 模型属性必须提供默认值或声明为 optional。
- SwiftData + CloudKit 关系属性默认按 CloudKit 兼容性处理，改动前先确认 optional 与数据迁移影响。
- 允许删除旧 Supabase / 双人 / 付费数据，不要求为旧远端数据做迁移；但本地 schema 改动仍必须能被当前构建安全打开或明确走受控清库路径。
- 单元测试优先于 UI 测试；只有核心逻辑无法通过单测覆盖时，才补 UI 测试。
- 若项目已采用 Swift Testing，新测试优先使用 Swift Testing；UI 测试仍按 XCTest 体系处理。

### 3.3 OCR 与 AI 约束
- OCR 默认使用 Apple 原生 Vision / VisionKit。
- Vision 请求不得阻塞主线程。
- OCR 结果必须先进入草稿确认流，不允许直接创建真实任务或项目。
- 多行文字导入必须使用用户主动触发的 SwiftUI `PasteButton`；禁止通过 `UIPasteboard.general` 预读、轮询或后台监听剪贴板。
- 粘贴文字与 OCR 识别文本共用本地确定性解析器和草稿确认流，不依赖 Apple 智能、Foundation Models 或自然语言日期推断。
- 若使用 Foundation Models 做结构化解析，必须检查可用性，使用结构化输出，并提供本地规则 fallback。

### 3.4 工程卫生
- 若仓库启用了 `Localizable.xcstrings`，新增用户可见文案优先走字符串目录，不要把文案硬编码散落在页面中。
- 若仓库已安装 SwiftLint，提交前必须保证没有新增 warning 或 error。
- 若 Xcode MCP 可用，优先使用其构建、预览、问题列表、文档查询能力。

### 3.5 真机单 App 工作流
- Debug、Release 与 TestFlight 统一使用正式 `com.pigdog.Together` 身份，以及同一正式 Widget、URL Scheme、App Group、CloudKit 容器和 Associated Domains；不创建或引用 `.dev` App。
- 从 Xcode 真机运行 Development 构建会替换同一 Bundle ID 的 TestFlight / App Store 二进制，但保持同一应用与数据身份，适合在一个 App 中兼顾测试和日常使用。
- Development 签名仍可能受 PPQ 在线验证限制；无法完成验证时，唯一安装的 Together 可能暂时不可启动。当前明确接受该约束，不以双 App 隔离规避。

### 3.6 每日摘要调度
- 每日摘要只使用本机 `UNUserNotificationCenter`，不引入 APNs 服务端、第三方后端或 `BGTaskScheduler` 的准点承诺。09:00 早间摘要与 18:00 晚间总结使用两个稳定标识的每日 `UNCalendarNotificationTrigger`；旧版单一 18:00 标识必须在重排时清理。
- 统计口径复用任务 `appearsOnHome(for:includeOverdue:)` 语义：只统计当前个人空间中未归档、未完成、逾期或通知所属本地日期到期的任务；未来任务不计入。普通任务写入层保证计划日期存在，历史缺失日期在统计前归一化。零任务仍安排摘要，并使用明确零状态文案。
- 摘要内容在 App 启动、回到前台、任务变更、设置变更与 CloudKit 成功导入后重算；时区和自然日边界使用注入的 `Calendar`，禁止固定加减 24 小时。重复通知在 App 长期未运行时只能保留最近一次重算内容，这是 iOS 本地通知无法在触发瞬间读取 SwiftData 的平台边界，不得声称为服务端实时统计。
- “任务提醒”关闭时同时取消任务提醒、早间摘要、晚间总结与旧摘要；“每日摘要”关闭后，后续任务写入不得重新安排摘要。通知权限只在用户主动开启相关功能时按需请求；拒绝后由 Profile 就地进入系统通知设置。

### 3.7 App Intents 边界
- 当前不注册用于新建任务的 `AppIntent`、`AppShortcutsProvider`、Siri / Spotlight phrase 或进程内 handoff 队列。应用内创建由 `AppRouter` 与独立 `TaskCreationView` 负责；`together://new-task` 仍作为 Widget 等现有入口的前台深链，并复用同一创建页。
- Widget 完成与 Live Activity 完成仍保留各自的 `AppIntent`，并继续遵守统一应用层完成语义、最小共享事务、失败关闭和回到 App 的既有约束。
- 未经新的产品决策与完整系统入口验收，不得重新增加系统级创建 Shortcut、`AppEntity`、Core Spotlight 内容索引或后台数据库写入。

## 4. 架构原则
- 业务逻辑与 View 分离。
- 状态机不得直接散落在 View 中。
- 服务层先协议化，再实现具体服务。
- 数据模型、状态流转、页面路由必须清晰可追踪。
- 新增模型应优先面向 `Task / TaskList / Project / Reminder / UserProfile / OCRDraft` 抽象。
- 当前代码里旧的 `PairSpace / relationshipID / Invite / TaskMessage / Premium / Supabase` 命名属于待删除历史包袱；新开发不得继续扩散这些语义。

## 5. 数据策略
- 产品层只暴露单人任务空间，不再强调或预留复杂 Space 概念。
- 技术层目标是干净的单人 SwiftData schema。
- CloudKit private database 是唯一跨设备同步与恢复能力。
- Supabase 只作为旧代码删除对象，不再作为 canonical backend、恢复源、推送触发、头像存储或同步通道。
- RevenueCat / Paywall / PremiumGate 只作为旧代码删除对象，不再作为功能门禁。

### 5.1 待办履历数据架构

- 采用 `docs/adr/0024-append-only-task-lifecycle-events.md`：现有 `PersistentItem` 继续是任务当前状态的唯一真相；新增独立、追加式的 `PersistentTaskLifecycleEvent` 保存计划语义事实。推迟次数、累计推迟时长、恢复次数和趋势均由事件派生，不在任务记录上维护可竞争累加的权威计数器。
- 事件模型只使用 CloudKit 兼容的标量字段，不依赖 required relationship、`.unique` 或数据库级 cascade。建议字段为：稳定 `id`、`taskID`、`spaceID`、`kindRawValue`、`occurredAt`、前后 `dueAt`、前后 `hasExplicitTime`、可选未完成子任务数量以及 schema version；不保存 UI 入口、按钮来源或展示文案。
- 事件类型为 `created / firstScheduled / postponed / movedEarlier / completed / reopened`；`scheduleCleared / rescheduled` 仅为历史记录解码兼容，不再由当前普通任务写入路径产生。未知 raw value 必须安全忽略并保留记录，不能导致整个任务无法读取。
- `PersistentItem.dueAt` 为兼容既有 SwiftData + CloudKit schema 继续保持 optional，但普通任务的创建、更新和改期应用服务必须将 `nil` 归一化为操作日本地零点，并同时清除时间精度和提醒。启动身份恢复及 CloudKit 导入后的仓储迁移只更新 `dueAt == nil` 的未完成普通任务；已完成旧记录不得回填，以免改写历史复盘口径。迁移必须幂等、逐空间执行、参与 CloudKit upsert，且不得经过普通 `saveItem` 生命周期分类器或补写事件。
- 逾期批量迁移逐任务调用既有应用服务；每项日期、提醒、生命周期事件与本地保存保持单项原子。批量允许部分成功，不建立跨任务数据库事务或新的批量事件类型。原提醒不存在则保持不存在；按原提醒提前量重算后仍在未来才保留，否则清除。
- 新任务成功创建时，在一个 `ModelContext` 保存中同时写入任务与 `created`；若创建时已有日期，同时写入 `firstScheduled`。创建失败时两者均不得落库。
- 后续编辑先比较已持久化的 before / after 快照，再生成至多一条净排期事件；提醒变化、标题变化、同一语义值重复保存和保存前撤回均不产生事件。任务状态没有实际变化时，完成或恢复请求必须幂等，不追加事件。
- 普通待办的完成、恢复、排期变化与对应事件必须在同一个本地数据库事务中提交；任一写入失败则整体回滚。应用服务负责权限、提醒和同步协调，repository 负责当前任务与事件的原子持久化，View / ViewModel 不自行分类事件。
- Widget 的 `AppIntent` 继续遵守最小共享 SQLite transaction 路线，禁止用局部 SwiftData schema 打开主库。事务必须在更新 `ZPERSISTENTITEM` 的同时插入完成事件并更新现有 sync outbox；若事件表或必需列尚不可用，必须失败关闭并深链回 App，不能产生“任务已完成但履历缺失”的部分成功。
- App 内、通知与 Live Activity 的完成操作必须复用同一应用服务 / repository 语义。Widget 虽使用低层 SQLite 写入，也必须复用同一状态转换条件、事件字段和幂等规则；入口来源不进入数据模型。
- 多设备合并后先按事件 `id` 去重，再按 `occurredAt + id` 稳定排序并通过任务生命周期状态机重放；没有中间恢复的重复完成、没有中间完成的重复恢复等无效重复不计入指标。当前任务记录仍决定最终当前状态与当前 `completedAt`，派生缓存随时可从当前任务与有效事件重建。
- 归档只更新任务当前状态，不删除事件；永久删除必须在同一 repository 操作中显式删除该 `taskID` 的全部事件，再删除任务。恢复、备份、CloudKit schema probe 和数据导出链路必须包含事件模型。
- 写路径应扩展现有 `ItemRepositoryProtocol` 的原子 mutation 能力，而不是让一个独立 event repository 在任务保存后补写。读路径可独立为 `TaskLifecycleReviewRepository`，向 ViewModel 返回 `TaskLifecycleSummary / TaskLifecycleTimeline / PlanningReviewSnapshot` 等不可变投影；ViewModel 不直接查询 `PersistentTaskLifecycleEvent`。
- 事件存储至少按 `taskID` 与 `occurredAt` 支持高效检索；计划复盘先筛出周期内的候选任务，再批量读取这些任务的事件，禁止页面打开时 hydration 全库全部事件。若后续增加摘要缓存，必须带计算版本并可删除重建。

### 5.2 迁移与历史完整性

- 在现有 versioned schema 后追加新版本；已发布的旧 schema 保持不可变，只做 additive lightweight migration，不修改旧 model 定义。
- 升级前任务不得伪造历史事件。存在与正式创建时间一致的 `created` 事件才代表完整受管生命周期；否则 UI 将已知 `createdAt / completedAt` 与升级后事件结合展示，并明确标记“更新前未记录”。
- 旧任务在升级后第一次真实变化时只记录该次变化，不反推首次计划、推迟或恢复。缺少 `created` 事件时，即使升级后第一次设置日期可写入 `firstScheduled` 作为“更新后首次记录的计划”，该任务仍属于不完整生命周期，不得把该值冒充全生命周期首次计划，也不得进入首次计划兑现率；不能把升级时已有的当前截止时间擅自反推为历史首次计划。
- 发布前必须在开发环境初始化新增 CloudKit record type / fields，并按现有发布流程部署到 production；本地迁移成功不代表 CloudKit production schema 已可用。

### 5.3 指标计算规则

- `TaskLifecycleEventClassifier` 作为纯领域逻辑接收 before / after schedule，当前写入输出首次计划、推迟、提前调整或 no-op；取消排期 / 重新计划分支仅保留旧数据兼容测试，SwiftUI 不参与日期分类。
- 日期型计划使用用户当前本地 `Calendar` 的自然日边界比较；具体时间计划使用绝对时刻比较。跨夏令时、跨时区、月末、年末与周一计算必须使用 `Calendar`，禁止用固定 `24h` 秒数代替自然日。
- “推迟到明天”和“推迟到下周一”都从操作时本地日期计算目标自然日；若原任务有具体时刻则移植其本地时分，并保持提醒相对截止时间的提前量。逾期任务不能在快捷推迟后仍因沿用旧日期而逾期。
- 单任务统计以有效事件重放结果计算；最终完成时间以当前完成状态和当前 `completedAt` 为准，首次完成取第一条有效完成事件，完成耗时从正式创建时间起算。恢复后未再次完成的任务没有最终完成耗时。
- 缺少完整 `created` 事件的旧任务仍可使用可信的 `createdAt + 当前 completedAt` 计算最终完成耗时，并可使用完成时已知的最后计划计算最终计划按时；推迟 / 恢复只显示“更新后记录值 + 更新前未记录”，首次计划兑现率始终排除。
- 周 / 月复盘按最终完成时间筛选当前仍完成的任务；中位数而非平均数作为耗时中心趋势。两个相邻周期都至少有五项有效完成样本时才计算趋势。
- 当前计划风险单独查询未完成任务并按“逾期、推迟未完成”顺序去重；缺失日期属于迁移兼容问题，不形成新的风险类别。

## 6. 工程组织建议
- `App/`：App 入口、路由、会话、依赖容器
- `Domain/`：实体、枚举、协议、状态机
- `Services/`：repository、本地存储、CloudKit 状态、通知、OCR
- `Features/`：Today、Lists、Projects、Calendar、Profile、OCRImport
- `Shared/`：设计 token、基础组件、动画工具
- `PreviewContent/`：mock data、preview fixture

## 7. 默认开发顺序
1. 文档与边界统一
2. 移除 Supabase / RevenueCat / 双人协作骨架
3. Task / List / Project / Reminder / OCRDraft 模型与状态机
4. 服务协议与 SwiftData / CloudKit 持久化
5. Today 首页主链路
6. 清单与项目
7. 时间与提醒能力
8. 创建入口、详情页、搜索筛选
9. 设置、提醒与 OCR 导入
10. Widget 适配与最终验收

## 8. AI 执行规范
- 复杂任务先给：目标、影响范围、方案、风险。
- 未读文档不要直接写页面。
- 优先更新现有文件；仅在缺失关键文档时新增文件。
- 每次改动先保证可运行，再做精修。
- 所有不确定处必须显式标记为 `Open Questions`。

## 9. 测试与验证
- 状态机逻辑必须可单测。
- 数据模型转换与 repository 行为必须可单测。
- 关键 ViewModel 行为必须可单测。
- 首页 / 例行任务 / 项目关键页面必须有 Preview + mock data。
- 只要涉及动效状态切换，就至少做一次真机构建或 Preview 回归。
- 只要新增或重构自定义动画，就必须验证状态切换、阶段衔接、Reduce Motion 降级和连续触发下无明显掉帧。
- 动态 Metal 背景发布前必须在支持 120Hz 的真机以 Instruments 验证待办静置、长列表滚动、待办 / 定期快速切换、详情 / 创建反复开合、前后台、低电量及热状态降级；记录 Core Animation 帧时间、GPU/CPU 使用与 Energy Log。泛型构建或模拟器结果只证明编译，不代表帧率、温度或续航验收通过。
- 待办履历必须覆盖：所有排期转换矩阵、创建 / 完成 / 恢复幂等、累计推迟与最终偏差、日期型按时边界、DST / 时区 / 周五到周一、旧数据不完整标记、归档保留、永久删除清理及事件重放去重。
- repository 测试必须注入事件写入失败，证明任务当前状态与事件同事务回滚；Widget SQLite 测试必须验证成功事务、schema 缺失时失败关闭、重复点击幂等以及 sync outbox 一致。
- 集成验证必须逐条覆盖 App、通知 action、Widget AppIntent、Live Activity AppIntent 的完成路径，并验证 App 前台、Widget snapshot、CloudKit 导入后的当前状态和履历一致。
- UI 测试或真机验收必须覆盖内联最近三条 / 展开全部、旧数据说明、已完成回顾、周 / 月切换、少样本隐藏趋势、Dynamic Type 单列、VoiceOver 顺序、Reduce Motion 与深浅色。

## 10. 禁止事项
- 禁止继续把绑定流、邀请流、双人决策流当首版主目标。
- 禁止把当前产品重新做成情侣运营或关系运营工具。
- 禁止把多人模式提前做成当前功能。
- 禁止继续新增 Supabase / RevenueCat / Paywall / PremiumGate 依赖。
- 禁止把 OCR 识别结果未经用户确认直接写入任务或项目。
- 禁止为了快速交付把核心状态写死在 View 层。
- 禁止无理由引入大型第三方状态管理或动画库。
