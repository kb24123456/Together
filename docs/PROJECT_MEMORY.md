# Together Project Memory

> Codex 项目记忆入口。只记录长期有效、可被未来任务复用的事实。不要记录密钥、token、隐私数据或临时噪声。

## 当前状态

- 日期：2026-05-03
- 项目路径：`/Users/papertiger/Desktop/Together`
- Git 根目录：`/Users/papertiger/Desktop/Together`
- 产品主轴：iPhone-only 的单人 Todo 效率工具。
- 当前策略：V1 优先跑通单人 Todo 主链路；V2 再扩展双人协作；V3 多人 Space 仅做底层预留。
- Chronicle：暂不开启；先使用项目文档、AGENTS 和 Skill 机制承接记忆。

## 当前进行中交接

- 分支：`main`
- 当前任务：会员支付主链路已通过真机验收；上架前合规收敛已完成仓库内可控部分，包括法律文案、权限声明、Privacy Manifest、开发者赠权 runbook 与 App Store Connect 人工核对清单。
- 当前验证策略：用户已要求后续不做模拟器测试；本阶段只做 `generic/platform=iOS` 编译与 build-for-testing，不启动模拟器。
- 立即续接点：做真机购买 / 恢复购买 / entitlement webhook 端到端验证。Webhook URL：`https://nxielmwdoiwiwhzczrmt.supabase.co/functions/v1/revenuecat-webhook`。
- 会员修复进度：
  - Grace 期不再视为完整 Pro：`PremiumStatus.isPremium` 只对 `.pro` 为 true，`.gracePeriod` 仅允许 `allowsFullLogbook`。
  - Pro quota / 个人同步等 gate 继续读 `isPremium`；Profile 订阅说明等需要展示 grace 的 UI 改读 `isProOrGracePeriod`。
  - `PremiumGate.computeStatus` 在任一权威来源临时失败且无明确 active / grace 结果时优先使用有效缓存，避免 RevenueCat 短暂失败把真实订阅用户降级为 free。
  - 免费 iPhone 恢复是产品认可例外；iPad / Mac 个人同步必须 active Pro。客户端继续用 `SoloSyncGate`，后端新增 `premium_entitlements` 与 `solo_sync_gate_allows` 做服务端兜底。
  - Paywall 已把订阅条款与选中套餐价格说明移动到购买 CTA 附近，并显式处理取消购买 / 等待批准错误状态。
  - RevenueCat webhook Edge Function 已部署为 `revenuecat-webhook` version 1，`verify_jwt=false`，函数内部用 `REVENUECAT_WEBHOOK_AUTHORIZATION` 做自定义 Authorization 校验；未带 Authorization 的请求已验证返回 `401 UNAUTHORIZED`。
  - RevenueCat project `Together` 的 project id 为 `proj9691e26b`；active entitlement `lookup_key=pro` 已存在并绑定当前 App Store / Test Store 产品，与 `RevenueCatConfig.entitlementIdentifier = "pro"` 对齐。
  - RevenueCat webhook integration `Together Supabase Entitlements` 已创建，id 为 `whintgr6c8d5e0e8d`，指向 Supabase `revenuecat-webhook`，覆盖所有 app / environment / event types。
  - 生产 Supabase 已应用 `20260502055454 premium_entitlements_and_solo_sync_gate` 和 `20260502055831 restrict_premium_gate_function_execute`。`anon` 对新增 `SECURITY DEFINER` 函数的执行权已撤销；authenticated 仍可执行必要 RPC/helper，但 entitlement helper 已强制 `auth.uid() = p_user_id`。
  - 真机月订阅购买链路已验证：Free → Apple sandbox 购买弹窗 → 购买成功 → Pro；RevenueCat webhook 写入 `premium_entitlements`，`product_id=com.pigdog.together.monthly1m`、`environment=SANDBOX`、`last_event_type=INITIAL_PURCHASE`、`revoked_at=null`。
  - 已发现并修复退出登录再登录后变 Free 的架构缺口：客户端 `PremiumGate` 不能只依赖 RevenueCat SDK customerInfo 和 `premium_grants`，还必须合并 Supabase webhook 写入的 `premium_entitlements`。生产装配已新增 `SupabasePremiumEntitlementsLoader`，服务器 entitlement 按 `.subscription` 来源参与 Pro / Grace / cache fallback 合并。
  - 已发现并修复购买成功后 Paywall 仍显示购买选项的最终一致性缺口：购买返回 `.success` / `.pending` / `paymentPending` 后，`PaywallViewModel` 会短时间轮询 `PremiumGate.refresh()`，等待 RevenueCat SDK 或 Supabase `premium_entitlements` 任一权威来源转 Pro；Profile 会员页进入 Free 分支前会先 `configurePremiumGate()`，若后端已有 active entitlement 不再显示普通 Paywall。
- 当前未完成：
  - 需要按 `docs/superpowers/runbooks/2026-05-03-app-store-release-readiness.md` 人工核对 App Store Connect、RevenueCat、Supabase 和 TestFlight 真机验收项。
- 最近验证：
  - 2026-05-03 上架合规收敛：`git diff --check` 通过；`plutil -lint Together/Info.plist Together/PrivacyInfo.xcprivacy` 通过；旧麦克风/语音识别权限键与旧 Grace 全 Pro 文案无残留；`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
  - `git diff --check` 通过。
  - `xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。
  - `xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。
  - TestFlight build 34 已从当前 `main` archive 并上传到 App Store Connect；`xcodebuild -exportArchive` 返回 `Upload succeeded` / `Uploaded package is processing`。
  - Clean-room 前置状态：测试用户 `bb7a3977-3bbc-447b-989a-3fbe6b8d8eb6` 的 Supabase active `premium_grants` 与 active `premium_entitlements` 均已软撤销为 0；RevenueCat customer `BB7A3977-3BBC-447B-989A-3FBE6B8D8EB6` active entitlements 为空。后续必须使用全新 Apple Sandbox Account 新购，避免旧 Apple 订阅历史污染。
  - Supabase MCP `_list_migrations` 确认 `premium_entitlements_and_solo_sync_gate` 与 `restrict_premium_gate_function_execute` 均已在远端。
  - Supabase SQL 权限检查确认新增函数 `anon_exec=false`。
  - Supabase MCP `_list_edge_functions` 确认 `revenuecat-webhook` active；`curl` 无授权请求确认返回 `401 UNAUTHORIZED`。
  - RevenueCat MCP 确认 webhook integration 已存在；Supabase secrets list 确认 `REVENUECAT_WEBHOOK_AUTHORIZATION` 与 `REVENUECAT_PRO_ENTITLEMENT_ID` 已配置；带授权但缺少 `app_user_id` 的 webhook 请求返回 `400 INVALID_APP_USER_ID`，说明 Authorization 已通过。
  - Build 30 已从当前 `main` archive 并上传到 App Store Connect / TestFlight；`xcodebuild -exportArchive` 返回 `Upload succeeded`。
- 最新功能进度：Task 9 `Full Regression and Project Memory` 已完成；双人任务卡片聊天主链路已完成本地回归；自定义 morph overlay 已废弃，聊天面板改用 SwiftUI 原生 `.navigationTransition(.zoom)`。
- 已完成并提交：
  - Task 1：Supabase `task_messages` comment 约束与 RLS guard，提交 `3e5e480`。
  - Task 2 + Task 3：`TaskMessageType`、`TaskMessageCursor`、`PersistentTaskMessage.content`、`PersistentTaskChatReadState`、`TaskMessageRepositoryProtocol`、local/mock repository 和 repository 测试，提交 `7292bbd`。
  - Task 4：应用服务将用户留言写入 `task_messages`，`assignmentMessages` 作为 legacy fallback；Task 4 comment 写入保持 local-only，不记录 `.taskMessage` sync；`sendReminderToPartner` 的 nudge sync 未改，提交 `0796700`。
  - Task 5：`TaskMessagePushDTO` 支持 `content` 和 `sender_supabase_user_id`；新增 `TaskMessagePullDTO`；Supabase catch-up 在 `pullTasks` 后拉取 `task_messages`；Realtime 监听 `task_messages`；`sendTaskComment` 在本地 comment 写入成功后恢复 `.taskMessage` outbox enqueue。
  - Task 6：新增 `TaskChatTimelineEntry` / `TaskChatTimelineBuilder` / `TaskChatViewModel`，聊天面板状态与 Home 卡片保持解耦；ViewModel 支持加载最近消息、发送 comment、500 字上限、本地已读游标。
  - Task 7：Home 卡片预览切到 `task_messages` 最新 comment，`assignmentMessages` 只保留 legacy fallback；`HomeTimelineEntry` 增加 latest comment / unread 状态，留言区域建立 44pt 以上触控入口。
  - Task 8：新增 `TaskChatPanelView`，实现任务聊天面板、头像消息气泡、nudge/system 居中状态、`TextField(axis: .vertical)` composer、Material 背景模糊和 Reduce Motion 降级；Home 使用稳定的 selected chat ViewModel，避免 body 重建导致输入态丢失。
  - Task 9：完成 focused tests、完整单元测试和 simulator build 回归，并记录阶段性项目记忆。
- 最近验证：
  - Task 2/3：`TogetherTests/TaskMessageRepositoryTests` 通过；一次 review 代理额外跑过完整 `Together` 测试 483/483 通过。
  - Task 4：`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TogetherTests -only-testing:TogetherTests/SendReminderToPartnerTests` 通过；`git diff --check` 通过。
- Task 5：`git diff --check` 通过；`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessagePushDTOTests -only-testing:TogetherTests/TaskMessageSyncTests ...` 通过 DTO / pull DTO 测试；`xcodebuild test-without-building -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TogetherTests` 通过应用层 outbox 相关测试。
- Task 6：`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskChatViewModelTests` 通过；覆盖 timeline 排序、忽略未知消息、load 标记已读、send trim/append/markRead、超长拦截。
- Task 7：`xcodebuild test-without-building -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TogetherTests` 通过，新增 `homeViewModelPairPreviewUsesLatestTaskMessageComment`；`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过；`git diff --check` 通过。
- Task 8：`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过；`git diff --check` 通过。
- Task 9：`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests -only-testing:TogetherTests/TaskMessagePushDTOTests -only-testing:TogetherTests/SendReminderToPartnerTests -only-testing:TogetherTests/TaskChatViewModelTests` 通过；完整 `xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过；`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过。
- 立即续接点：进行真机 UI/交互验收，重点看原生 zoom 转场、聊天页键盘表现、发送后卡片预览/未读刷新、双端 Supabase catch-up/realtime。
- Task 5 后续真机/后端验收：当前只做本地编译与单测，未对生产 Supabase 实际执行 `task_messages` pull/realtime 联调；上线前需要用双端真机验证 comment 离线重试、catch-up 拉回、Realtime 刷新。
- 已知后续风险：
  - `PersistentTaskChatReadState` 当前只存 `lastReadMessageCreatedAt`，未来做 unread 精确计算时可能需要升级为 `(createdAt, messageID)` 游标。
  - Calendar 预览仍读 legacy `assignmentMessages`；后续如要保持跨页面一致，需要单独把 Calendar 侧预览接到 `task_messages`。
  - SwiftData CloudKit 当前未启用；新 read-state model 的非 optional 字段未来启用 CloudKit 前需统一评估默认值/optional 策略。

## 可信上下文来源

- `PRODUCT_SPEC.md`：产品定位、MVP 范围、信息架构、页面需求。
- `DEVELOPMENT_GUIDELINES.md`：工程约束、架构原则、测试与验证要求。
- `DESIGN_GUIDELINES.md`：视觉基线、安全区域、动效和 Pencil 出图规则。
- `ARCHITECTURE.md`：当前架构方向、Space 演进策略、导航结构。
- `DATA_MODEL.md`：Task / TaskList / Project / Reminder / Space 模型方向。
- `TODO_NEXT_STEPS.md`：近期优先级和明确不要做的事项。
- `docs/superpowers/plans/*`：历史计划与阶段执行记录，使用前需和当前代码校验。

## 已落地机制

- 根目录 `AGENTS.md` 已追加项目记忆与阶段性收尾规则。
- `.agents/skills/stage-memory-update/SKILL.md` 已作为阶段性收尾 Skill。
- `docs/CODEX_MEMORY_WORKFLOW.md` 记录 Codex 记忆机制使用方式。
- `docs/CHRONICLE_RISK_ASSESSMENT.md` 记录 Chronicle 风险评估。

## 产品记忆

- 产品定位：以单人工作与日常待办管理为核心，后续可扩展到双人协作。
- V1 一级结构：Today、清单、项目、日历、我。
- Task 是当前 IA 核心对象；清单、项目、日历是不同观察维度。
- 当前首页 UI 保留，语义上作为单人模式 Today 首页继续深化。
- 决策、纪念日、邀请、绑定、关系页属于后续附加模块或旧逻辑遗留，不作为 V1 主链路。
- 当前不做多人模式、社区、内容流、开放社交，也不做只为视觉好看的复杂交互。
- 双人 Today 的重要日期胶囊规则：默认 anchor 为 `.anniversary`（在一起的日子）；手动分页池包含所有仍有下一次发生日期的纪念日，anchor 第一、最新添加的非 anchor 第二；临近自动提示池独立限制为当天或未来 7 天内的非 anchor 日期。临近日期可临时自动顶上来，过期后回到用户手动滑到的日期；用户在临近期间主动滑走时，应尊重当前手动选择。生日不是一次性日期，只能是每年公历或农历重复。

## 工程记忆

- 平台：iPhone only。
- 技术：SwiftUI 优先；仅在 SwiftUI 无法合理实现时局部使用 UIKit。
- 环境目标：Xcode 26.2、Swift、iOS 18+。
- 当前阶段：本地数据 + mock 登录 + 可替换服务层；长期方案需不阻断 CloudKit。
- Swift 代码按 Swift 6.2+ 现代写法推进，优先 `async/await` 和 `@Observable`。
- 新开发优先使用 `spaceID` 语义，不继续扩散 `relationshipID`。
- 旧的 `PairSpace / relationshipID / Invite / BindingState` 属于历史包袱，改造时应兼容迁移，不一次性大拆。
- 状态机逻辑、数据模型转换、repository 行为和关键 ViewModel 行为必须可单测。

## 同步与数据恢复记忆

- 单人模式的稳定恢复主链路应以 Supabase 为 canonical backend；CloudKit 不应作为唯一恢复依据。
- CloudKit 适合 Apple-only 辅助备份或系统级同步，但不适合承载 Together 当前的账号恢复、Pro 权限控制、后台诊断和跨端策略。
- 如果同时存在 CloudKit 与 Supabase，不要让二者共用一个“已确认”语义；CloudKit confirmed 不等于 Supabase 已入库。
- 对单人任务恢复问题，优先按层排查：本地 SwiftData 是否有任务、本地 `PersistentSyncChange` outbox 是否有记录、outbox lifecycle 是 `pending / sending / failed / confirmed` 哪一类、Supabase 是否已有对应 `tasks.id`、设备安装表是否是当前 build。
- 已验证事故模式：任务在本地 SwiftData 存在，CloudKit 也可能已有记录，但 outbox 被 CloudKit 标记为 `confirmed` 或因 `record to insert already exists` 变成 `failed`；如果 Supabase push 只扫 `pending / failed` 或再用 `lastPushedAt` 截断，就会漏推到 Supabase，重装后无法从 Supabase 拉回。
- 最终修复策略：`SupabaseSoloSyncService.pushPending` 对同一 solo space 扫描 `pending / failed / confirmed` 的 outbox；`confirmed` 只按是否支持 solo Supabase push 过滤，不再按 `lastPushedAt` 截断；Supabase upsert 成功后删除对应 outbox。
- 回归测试必须覆盖两类 CloudKit confirmed：晚于 `lastPushedAt` 的任务、早于 `lastPushedAt` 的任务；两者都应补推并清空 outbox。
- 真机验收标准：安装当前 build 后打开 60 秒，Supabase `tasks` 能查到测试任务；删除 App 后从 TestFlight 重装，同一账号打开 60 秒，首页能恢复任务。
- 双人邀请码链路的云端真相优先看 Supabase：`pair_invites.status=accepted`、`spaces.status=active`、`space_members` 是否有两行；如果这些成立，问题通常在本地 session 切换、catch-up 或 profile/avatar 回填。
- 已验证双人配对事故模式：`CloudPairingService` 在返回 `PairingContext` 前同步 await `PairJoinObserver.onSuccessfulPairJoin()`，通知权限弹窗和 Supabase sync 启动会阻塞 `ProfileViewModel.apply(pairingContext:)`，导致接受方云端已配对但 UI 仍显示单人模式。修复策略：先返回 context 让 UI 切到 pair，再异步触发通知权限、catch-up、profile push。
- 双人头像恢复不要只依赖新 pair space 的 `space_members.avatar_url`。用户重装或换机后本地头像原始文件可能缺失，但 `user_profiles` 仍有可复用的 user-scoped signed URL；`.memberProfile` push 在没有本地头像 bytes / 没有刚上传的 signed URL 时，应在 `avatar_asset_id` 匹配时回退使用 `user_profiles.avatar_url`。
- 已验证双人配对本地状态事故模式：Supabase `pair_invites=accepted`、`spaces=active`、`space_members` 两行都正确时，接受方仍可能停留单人 UI；根因是本地 SwiftData 里存在旧的未结束 pending pair residue，`currentPairingContext` / resolver 用无序 fetch 的 first 选中旧 pair，导致 available modes 没有 pair。修复策略：本地 pair 解析统一优先选择未结束、active、最新 activated/created 的 pair space，并用服务层测试覆盖“旧 pending + 新 active”。
- 已验证双人同步事故模式：同一对用户如果在 Supabase 中残留多个 `spaces.type='pair' and status='active'` 的双人成员空间，A 端写入最新空间成功，B 端仍可能停在旧本地 active pair，导致任务/纪念日看不到。修复策略：客户端启动恢复不能因“本地已有 active pair”直接跳过云端校验，必须查询当前用户所属的最新 active pair，补齐本地 `PersistentSpace / PersistentPairSpace / PersistentPairMembership`，并把旧本地 active pair 标记 ended/archived；Supabase `accept_pair_invite` RPC 在接受新邀请的同一事务中归档参与者旧 active pair spaces，生产库也要一次性归档历史旧 active pair spaces。
- 双人任务接收不要只依赖 Realtime。真机测试发现任务已进入 Supabase、Edge Function 也返回 `sent=1` 时，接收方仍可能不刷新；修复方向是让 pair APNs、回前台、下拉刷新都触发 Supabase `catchUp()`，并在 catch-up 后刷新首页/清单/项目/日历等 ViewModel。
- 双人解绑不能只靠在线 Realtime `space_members DELETE`。一方解绑后，另一方需要 APNs `pair_unbound` 事件和前台成员校验兜底：如果当前 pair space 在 Supabase 里已没有对方 `space_members` 行，本地应自动解除配对。
- 双人日志页的红色默认头像通常代表历史记录的 `completedByUserID` / `lastActionByUserID` 已无法解析到当前用户或伴侣；这类旧 pair/profile 迁移残留还可能因为 `creatorID` 漂移被 active-task 删除权限挡住。Logbook swipe 删除应允许对已完成历史行走 tombstone fallback，但不要启动即批量删除未知头像日志，避免误删合法历史。
- 双人任务身份判断不能依赖远端 `creator_id` / `sender_id` 中的设备本地 UUID。重装、TestFlight 更新或多设备会让这些本地 UUID 漂移，导致“我创建并指派给对方”的任务在当前设备被误判成“待我回应”。任务和任务留言 pull 时必须优先用 `creator_supabase_user_id` / `sender_supabase_user_id` 映射回当前设备的本地用户与伴侣用户；已有本地脏数据需要一次性全量身份回填。伴侣头像同理，远端 metadata 一致但本地头像文件缺失时也必须补下载，不能只看 avatar version/asset 是否变化。

## 设计与动效记忆

- 所有 iOS UI 设计和 SwiftUI 实现必须遵循 Apple 官方设计规范与安全区域约束。
- 当前视觉基线继续使用 `mobile-02-cleanminimal_light` 的干净留白、轻层次、弱阴影、低饱和方向。
- 产品表达应是“效率优先、带一点温度”，不是“情侣感优先”。
- 自定义动画必须状态驱动，拆成 2 到 3 个连续阶段，避免主线程重计算、同步 IO、动画中重排序。
- 自定义动画需验证 Reduce Motion 降级、连续触发和性能。
- 日志页偏信息浏览场景，不应把完成记录列表包在白色圆角分组卡片里；默认使用直接列表、保留 swipe actions，不再额外弹详情 sheet。随着历史任务变多，打开页应避免全量 hydration，优先 repository 层分页、轻量 aggregate 和 SwiftUI `List` 虚拟化。
- Today 重要日期胶囊采用单层胶囊分页，不在静止态露出叠放层；只有多个候选日期时显示 4pt 轻量分页点；横向切换优先使用 SwiftUI 原生横向 ScrollView 分页、scrollTargetBehavior 和 scrollTransition，不在核心文字内容上使用 blur，也不对分页内容叠加横向 offset，避免相邻胶囊互相压住。计数方式切换改为点按视觉上的计数区域，只有支持累计天数的纪念日才暴露为 Button，命中区域至少 44x44pt，生日/节日等不可切换日期显示为静态文本。Today 顶部内容区不再用渐变遮罩压住列表，列表初始内容不保留额外 10pt 空白首行。
- 双人任务聊天面板已放弃自定义 morph overlay 和手写 keyboard metrics。当前长期方向是用 SwiftUI 原生 `.matchedTransitionSource` + `.navigationTransition(.zoom)`：任务卡片作为 zoom source，聊天页作为 `NavigationStack` destination；键盘、安全区和返回转场优先交给系统处理，避免再叠加自定义全屏 overlay / GeometryReader / keyboard observer。

## 近期优先级

1. 把单人模式语义落到代码层：Task / List / Project / Calendar 为主，弱化旧双人优先命名。
2. 在当前首页 UI 基础上完成 Today 主链路：任务创建、完成、详情展开、日期切换、筛选与排序。
3. 明确并实现 `TaskStatus`、`ProjectStatus`、提醒策略单测。
4. 补齐清单页、项目页、周/月日历切换、本地持久化与高质量原生动效。

## 明确不要做

- 不先重写当前首页 UI。
- 不先做绑定流、邀请流、双人主链路。
- 不先做多人模式。
- 不把产品重新做成情侣运营或关系运营工具。
- 不为了快速交付把核心状态写死在 View 层。
- 不做只有炫技价值、没有任务效率价值的动画。

## Claude 历史资料处理原则

- `.claude/worktrees/*` 下的内容可作为历史参考，但不自动承认为当前事实。
- 若 Claude worktree、历史计划和当前根目录主文档冲突，以当前根目录主文档和当前代码为准。
- 合并历史经验时必须标注来源，并优先验证当前代码状态。

## 验证记录

- 2026-05-04：基于当前双人任务提醒、底部 toolbar 系统蓝、双人模式 reload 频闪修复、例行任务 per-space 缓存与单人蓝色例行任务胶囊延迟闪出修复，打包上传 TestFlight build 36。构建号从 35 提升到 36；归档路径 `build/TestFlight-20260504-0306-build36/Together.xcarchive`，导出上传使用 `build/exportOptions-TestFlight-upload.plist`；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。验证链路：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release archive、`xcodebuild -exportArchive` 上传通过；未做模拟器或真机 UI 验收。
- 2026-05-04：修复切换双人模式时短时间连续频闪。根因不是数据库刷新本身，而是 Supabase `catchUp` / Realtime 通知会短时间触发多轮 `reloadAfterSync`，首页 `reloadRevision` 又参与 `ScrollView/List` 容器 `.id` 与动画，导致普通同步刷新被放大成整块内容反复销毁重建。处理：`AppContext` 新增 cause-aware single-flight reload 合并器，180ms 内合并 Supabase / pair member / partner avatar / important dates / startup restore 刷新请求，并保留 important dates scheduler 副作用；`HomeViewModel.reload` 新增 `HomeReloadReason`，双人模式切换、同步和启动恢复不再做整页 items spring；`HomeView.tasksContent` 的 startup/empty/timeline identity 移除 `reloadRevision`，只保留日期维度；`SupabaseSyncService.catchUp(notify:)` 允许 Realtime handler 内部补拉不重复广播。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试，仍需 TestFlight/真机切换双人模式确认无连续空态/列表闪烁。
- 2026-05-04：按同一频闪根因排查单人 Today 列表、例行任务列表和头像区域。单人 Today 列表当前没有 `reloadRevision + .id` 的整块重建问题；头像区域保留 `.id(userProfileRevision)` 以支持同名头像文件重读，但 `SessionStore.currentUser` 和 `restorePersistedUserProfileIfNeeded(force:)` 改为用户资料真实变化时才推进 revision，避免同步无变化也重建头像按钮；例行任务列表移除首现 `.task` 与空间 `.task(id:)` 双加载，改为 `RoutinesViewModel.loadIfNeeded()` 和同步 `reload()` 静默刷新，避免普通同步反复进入 loading/empty。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-04：修复切回单人模式时蓝色例行任务胶囊延迟闪出。根因：`RoutinesViewModel.tasks` 是当前空间单份数据，双人同步会把它覆盖成双人空间任务；切回单人时 Today 先读到双人 tasks，`hasPendingTasks=false`，稍后单人 reload 完成后胶囊才突然插入。处理：`RoutinesViewModel` 新增 per-space `tasksBySpaceID` 缓存，切换空间时先同步恢复当前 space 缓存，再静默刷新；本地例行任务创建/更新/完成/删除后同步更新缓存；异步刷新返回时若用户已切到其他 space，只更新缓存不覆盖当前可见 tasks；首页头像模式按钮切换后立即调用 `restoreCachedTasksForCurrentSpace()` 并后台 `loadIfNeeded()`。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-03：继续收敛 Today / Profile / Project / Routines UI 反馈。Today 非当天返回按钮改为与模式胶囊同款的轻量“返回今天”胶囊，黑色文字和浅色背景；例行事务创建会把当前周期 tab 写入 `router.pendingPeriodicCycle` 并传给全局 Composer，周期 tab 的“每季度”加 `lineLimit(1)` 和 `fixedSize` 防止换行；项目标题新增 context menu“编辑标题”，保留展开态点按标题编辑。项目排序从“子任务排序”纠偏为项目级排序：`Project` / `PersistentProject` / Supabase `ProjectDTO` / CloudKit codec / repository / ViewModel 均增加 `sortOrder`，项目列表长按进入排序模式后可上下移动项目；项目子任务排序入口已移除，子任务只保留新增、勾选、编辑。新增 `supabase/migrations/045_add_project_sort_order.sql`，远端 Supabase migration `add_project_sort_order` 已通过 Supabase MCP 应用成功。边界结论：Profile 当前走原生 `NavigationStack` push，LTR 系统语义固定为从右侧进入；“从左侧滑入”属于与原生导航方向冲突的自定义转场需求，不能在现有原生 push 上局部硬改，需单独确认是否接受自定义 overlay / UIKit transition 的稳定性取舍。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-03：完成 Today 返回按钮、模板空状态、Profile 导航和普通任务排序一轮 UI/数据收敛。Today 非当天返回按钮从玻璃按钮改为轻量浅蓝胶囊并保留 44pt 命中区；模板空状态 `EmptyStateCard` 支持中性背景，模板页不再显示绿色背景块；Profile 入口从 `fullScreenCover` 改为 root `NavigationStack` push，使用系统返回手势，Profile 内日志入口保留在 toolbar；普通 Today 任务和例行事务通过长按进入排序模式并使用 `List.onMove`，双人任务卡片不参与排序；项目子任务因位于自定义卡片而非 `List`，使用同一排序模式下的轻量上下移动控件，避免为了原生 move handle 重构项目卡片。新增 `Item.sortOrder` / `PersistentItem.sortOrder` / Supabase `tasks.sort_order` DTO 映射、CloudKit codable 字段、repository reorder 接口，以及迁移 `supabase/migrations/044_add_task_sort_order.sql`；远端 Supabase migration `add_task_sort_order` 已通过 Supabase MCP 应用成功。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-03：完成 App Store 上架前仓库内合规收敛并上传 TestFlight build 35。修复内容：App 内隐私政策 / 服务条款与 `docs/legal/*.md` 对齐；移除未实现语音输入对应的麦克风 / 语音识别权限键；`PrivacyInfo.xcprivacy` 补齐邮箱、头像照片、用户内容、购买历史并修正照片类型键；Grace 条款与代码一致为“仅保留 Logbook 全量访问”；新增开发者赠权 runbook 与 App Store 上架人工核对清单；Profile DEBUG 区域仍受 `#if DEBUG` 隔离。验证：`git diff --check`、`plutil -lint Together/Info.plist Together/PrivacyInfo.xcprivacy`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release archive、`xcodebuild -exportArchive` 上传通过；归档路径 `build/TestFlight-20260503-1238-build35/Together.xcarchive`；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。未做模拟器测试。法律文档已同步到独立 `together-app-legal` GitHub Pages 仓库 commit `513a2f3`，线上 Privacy Policy / Terms 均已验证显示 2026-05-03 版本。剩余人工项：按 `docs/superpowers/runbooks/2026-05-03-app-store-release-readiness.md` 核对 App Store Connect。
- 2026-05-03：执行支付订阅 clean-room 前置流程并上传 TestFlight build 34。新增 runbook `docs/superpowers/runbooks/2026-05-03-subscription-clean-room-validation.md`，明确 Apple Sandbox / RevenueCat / Supabase / App 四层状态边界和阻塞条件；测试用户 `bb7a3977-3bbc-447b-989a-3fbe6b8d8eb6` 的 Supabase active grant / active `pro` entitlement 已软撤销为 0，RevenueCat 对应 customer active entitlements 为空。代码修复包含购买后 pending/entitlement 延迟轮询和会员页进入 Paywall 前强制刷新 PremiumGate。构建号从 33 提升到 34；归档路径 `build/TestFlight-20260503-1016-build34/Together.xcarchive`；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。验证链路：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release archive、`xcodebuild -exportArchive` 上传通过；未做模拟器测试。
- 2026-05-03：基于当前 `main` 未提交修复打包上传 TestFlight build 33，用于验证月订阅购买后退出登录再登录仍保持 Pro。修复内容：`PremiumGate` 合并 RevenueCat SDK、`premium_grants` 与 Supabase webhook 写入的 `premium_entitlements`，新增 `SupabasePremiumEntitlementsLoader` 和回归测试。构建号从 32 提升到 33；归档路径记录在 `build/.last_archive_path`，导出上传使用 `build/exportOptions-TestFlight-upload.plist`；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。验证链路：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release `xcodebuild archive ... -destination 'generic/platform=iOS'`、`xcodebuild -exportArchive ...` 上传通过；未做模拟器测试。
- 2026-05-02：基于当前 `main` 未提交修复打包上传 TestFlight build 32，用于验证 build 31 真机反馈的双人任务身份误判与伴侣头像文件缺失补下载问题。构建号从 31 提升到 32；归档路径为 `build/TestFlight-20260502-1716-build32/Together.xcarchive`，导出上传使用 `build/exportOptions-TestFlight-upload.plist`，App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。验证链路：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release `xcodebuild archive ... -destination 'generic/platform=iOS'`、`xcodebuild -exportArchive ...` 上传通过；未做模拟器测试。真机安装 build 32 后，用户确认伴侣头像与双人任务身份显示均已恢复。
- 2026-05-02：修复 build 31 真机反馈的双人任务身份与头像同步问题。根因：Supabase 中异常任务 `creator_supabase_user_id` 指向当前用户，但本地 UI 仍用历史设备本地 `creator_id` 判断是否可回应，导致创建者侧显示“待我回应 + 接受/拒绝”；伴侣头像远端 `user_profiles/space_members` 有 URL 和版本，但本地缺头像文件时旧逻辑因 metadata 未变化而跳过下载。处理：`SupabaseSyncService` 新增 `SupabaseIdentityMap`，任务/留言 pull 时用 Supabase auth uid 映射本地 user id，并对当前本地 user id 做一次性全量任务/留言身份回填；成员 pull 改为轻量全量校准，头像文件缺失也触发下载。新增任务创建者映射、留言发送者映射、头像缺文件修复测试。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-02：基于 `main` commit `96acb2e` 打包上传 TestFlight build 31，用于替代 build 30 继续真机支付/恢复购买/RevenueCat webhook 端到端验证。归档与上传使用 Release scheme archive：`xcodebuild archive -project Together.xcodeproj -scheme Together -configuration Release -destination 'generic/platform=iOS' -archivePath ...` 和 `xcodebuild -exportArchive ... -exportOptionsPlist build/exportOptions-TestFlight-upload.plist`；App Store Connect 返回 `Upload succeeded`，包进入 processing。后续付费链路测试前需先确认安装来源为 TestFlight/Release 且 build 为 31，Profile 中不应出现 `开发者 (DEBUG)` 区域；若出现 DEBUG 区域，说明仍在运行 Xcode Debug Run 或旧包，不应继续支付验收。未做模拟器测试。
- 2026-05-02：修复双人任务创建后“看不到”的根因：用户标题中的“5点”被无 LLM 的智能提示误判为 05:00，创建后立即成为已超时任务；同时双人模式隐藏逾期胶囊，旧逻辑又把逾期任务从主列表移除，导致任务已写入 Supabase 但创建者 Today 不显示。处理：删除 `ComposerSmartSuggestionBar` 整套智能提示/解析逻辑；创建页新增 `TaskCreationDateValidator`，手动选择过去日期或过去时间时弹提示并阻止创建；双人模式没有逾期胶囊承接时，已存在逾期任务仍保留在主列表可见。验证：Supabase MCP 确认最近双人 task/comment 已入库；`rg` 确认智能提示符号无残留；`git diff --check`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-02：废弃双人任务聊天自定义 morph overlay / keyboard metrics，改为原生 SwiftUI zoom 导航。`PairTimelineCard` 挂 `.matchedTransitionSource(id:entry.id, in: taskChatZoomNamespace)`，聊天页走 `.navigationDestination(isPresented:)` 和 `.navigationTransition(.zoom(sourceID:in:))`；删除 `TaskChatMorphOverlay`、`TaskChatKeyboardMetrics`、卡片 frame preference 链路。验证：`build_sim -quiet` 通过；`build_run_sim -quiet` 启动成功；模拟器停在登录页，未覆盖真实双人任务聊天键盘路径，仍需 TestFlight/真机用真实 pair 数据复测中文键盘、九宫格和表情键盘。
- 2026-05-02：双人任务卡片聊天方案落地：`task_messages` 成为任务聊天主数据源，`assignmentMessages` 仅保留旧数据兼容；新增任务内 comment、nudge/system timeline 聚合、latest comment 卡片预览、本地未读游标和 morph 聊天面板。验证：`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests -only-testing:TogetherTests/TaskMessagePushDTOTests -only-testing:TogetherTests/SendReminderToPartnerTests -only-testing:TogetherTests/TaskChatViewModelTests`、`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过。
- 2026-04-29：初始化 Codex 项目记忆、阶段性收尾 Skill、Chronicle 风险评估；未修改业务代码，未运行 Xcode 构建。
- 2026-04-29：build 22 修复接受方 786 云端已配对但本地仍单人 UI 的问题；验证 `PairSpaceSummaryResolverAvatarTests` 与 `LocalPairingServiceUnbindIsolationTests` 通过。
- 2026-04-29：新增发起邀请 loading 状态、纪念日 sheet 内联新增区与纪念日胶囊长按计数切换；双人 APNs/前台 catch-up 与解绑成员校验完成本地实现。验证 `git diff --check`、iOS Simulator build、`profileViewModelExposesInviteCreationLoadingState` 通过；Supabase trigger 已应用，Edge Function 部署需要 `SUPABASE_ACCESS_TOKEN`。
- 2026-04-29：生产后端硬化完成第一轮：Supabase 已加固 `space_members` / `pair_invites` / avatar storage RLS，新增 `accept_pair_invite` 原子接受 RPC、主动过期旧邀请码、关键同步索引、邀请码唯一约束，撤销 trigger function 的客户端可执行权限，将业务表 RLS 从 `public` 收窄到 `authenticated`，补齐缺失外键索引，为核心 enum/status 字段加 DB check constraints，并归档只有过期邀请的旧单人成员 pair shell；客户端接受邀请改走 RPC，双人 avatar 上传路径改用 Supabase `auth.uid()`，并补强 pair 变更不进入 CloudKit 的过滤。验证 `git diff --check`、iOS Simulator build；Edge Function 部署仍需本机 `SUPABASE_ACCESS_TOKEN`。
- 2026-04-29：日志页改为直接 plain list，取消点击行弹详情 sheet，仅保留 swipe 删除/恢复；`CompletedHistoryViewModel.delete` 对 creatorID 漂移的旧完成历史行增加 repository tombstone fallback；`LocalItemRepository.fetchCompletedItems` 初始页改为 active/archived 分路限量候选并合并排序，Logbook hero stats 改用 `fetchCount` 与边界记录查询，避免打开页全量 Item hydration。验证 `git diff --check`、`CompletedHistoryViewModelPairTests`、iOS Simulator build 通过。
- 2026-04-30：修复双人最新空间恢复与生产库多 active pair 残留：`hydratePairSpaceFromCloudIfNeeded` 改为以 Supabase 最新 active pair 为准并补齐本地 shared space；`SpaceDTO` 拉取远端 status/archivedAt；前台 pair 校验会识别远端 space 已 archived；新增 `038_archive_previous_pair_spaces_on_accept.sql`，`accept_pair_invite` 会归档参与者旧 active pair spaces。生产库已归档同一对用户的 11 个旧 active pair spaces，只保留最新双人成员空间 active；最新空间内任务和纪念日均保留。验证 `git diff --check`、`PairSpaceSummaryResolverAvatarTests`、`LocalPairingServiceUnbindIsolationTests`、iOS Simulator build 通过。
- 2026-04-30：修复 build 25 真机反馈的纪念日累计天数体验：生产 Supabase 已应用 `shows_elapsed_days` 字段迁移并回填现有 anniversary；`AnniversaryCapsuleView` 长按改为与点按互斥的手势，避免长按切换被 Button 吞掉或触发打开 sheet；`ImportantDatesManagementView` 标题改回 inline 原生 toolbar 居中。验证 `git diff --check`、iOS Simulator build、完整 `xcodebuild test` 通过；仍需 TestFlight 真机确认长按手感。
- 2026-05-01：修复 build 27 真机反馈的纪念日胶囊 `.numericText` 生硬跳变、Profile 纪念日管理 sheet 与 Today 不一致、双人 APNs 后台推送不稳定。`AnniversaryCapsuleView` 右侧整段“还有/已经 N 天”改为稳定 Text + 显式 `.animation(..., value:)` + `.numericText(value:)`；`ImportantDatesManagementSheet` 成为 Today/Profile 共用入口；`send-push-notification` Edge Function 已部署到 Supabase，APNs 改为 production endpoint 优先，`BadDeviceToken` 时回退 sandbox，并补齐 task created / accepted / declined / completed / nudge 的事件类型和通用通知 tap 打开任务。验证 iOS Simulator build、Deno check 通过；生产 DB 迁移未执行，当前修复不依赖新 DB 列。
- 2026-05-01：定位并修复 TestFlight 真机 APNs 全部无通知的后端根因。生产库 `tasks INSERT/UPDATE`、`task_messages INSERT`、`space_members DELETE` trigger 存在，`device_tokens` 也有两端 64 位 token；失败点是 `notify_push_on_change()` 通过 `net.http_post` 调 Edge Function 时没有有效 Authorization，`net._http_response` 全部为 `401 UNAUTHORIZED_NO_AUTH_HEADER`。长期修复：`send-push-notification` 改为 `--no-verify-jwt` 部署，但函数内部强制校验 `X-Together-Webhook-Secret`；生产 DB 新增私有 `private.app_secrets` 存储 webhook secret，trigger 函数从私有表读取并带自定义 header。验证：无 header 直调函数返回 401；DB `net.http_post` 带私有 secret 调函数返回 200 `No members`；函数版本 11、`verify_jwt=false`；私有 secret 表对 `anon/authenticated` 无 select 权限；`git diff --check` 通过。下一步可进行 TestFlight 真机 APNs 验收。
- 2026-05-01：实现 Today 重要日期胶囊改版，分支 `codex/today-important-date-capsule`。新增 `ImportantDateStoredRecord` 保留 `createdAt`，`ImportantDateCapsulePlanner` 负责 anchor/手动分页全集/7 天自动提示池/排序/solar+lunar 时区稳定计算，`ImportantDateCapsulePreferences` 负责 per-date 选择、自动提示抑制与计数模式 JSON，`ImportantDateCapsulePagerView` 接入 HomeView。`AnniversaryCapsuleView` 不再用长按或旧全局 count key，倒计时显示使用 planner 传入的 `daysUntilOrToday`，避免回到 `ImportantDate.nextOccurrence` 的 `.current` 时区路径。生日编辑只能选择公历/农历年度重复，保存时兜底把 `.none` 规范化为 `.solarAnnual`。验证：`git diff --check main..HEAD`、iOS Simulator build、`ImportantDateCapsulePlannerTests`、`ImportantDateCapsulePreferencesTests`、`ImportantDateRecurrenceOptionsTests`、`ImportantDatesViewModelCapsuleTests` 通过；`build_run_sim` 在 iPhone 17 Pro simulator 启动成功并截图。仍需带真实 pair 数据做手动滑动、VoiceOver 与大字体视觉验收。
- 2026-05-01：修复真机反馈的 Today 顶部列表遮罩和重要日期胶囊切换问题。`HomeView.topChrome` 移除 20pt 渐变遮罩，`standardTimelineList` / `pairTimelineList` 移除 10pt 空白首行；`ImportantDateCapsulePagerView` 最终改为 SwiftUI 原生横向 `ScrollView` 分页、`scrollTargetBehavior(.paging)`、`scrollPosition` 和 `scrollTransition`，移除自定义 `DragGesture` / settle 状态 / blur / 横向 offset，避免粉色胶囊文字不可读和相邻日期胶囊重叠。验证：`git diff --check`、重要日期相关 22 个测试、iOS Simulator build 通过；仍需真机 pair 数据确认滑动手感。

## Open Questions

- 是否启用 Codex Memories 的用户级配置。
- Chronicle 是否在低敏任务中短时试用。
- V1 全局创建入口最终是单按钮直达还是展开式快捷菜单。
- 是否近期启动 `PairSpace -> Space` 命名迁移，还是继续通过兼容层过渡。
