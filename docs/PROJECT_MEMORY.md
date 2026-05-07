# Together Project Memory

> Codex 项目记忆入口。只记录长期有效、可被未来任务复用的事实。不要记录密钥、token、隐私数据或临时噪声。

## 当前状态

- 日期：2026-05-04
- 项目路径：`/Users/papertiger/Desktop/Together`
- Git 根目录：`/Users/papertiger/Desktop/Together`
- 产品主轴：iPhone-only 的单人 Todo 效率工具。
- 当前策略：V1 优先跑通单人 Todo 主链路；V2 再扩展双人协作；V3 多人 Space 仅做底层预留。
- Chronicle：暂不开启；先使用项目文档、AGENTS 和 Skill 机制承接记忆。

## 当前进行中交接

- 分支：`main`
- 当前任务：会员支付主链路已通过真机验收；上架前合规收敛已完成仓库内可控部分，包括法律文案、权限声明、Privacy Manifest、开发者赠权 runbook、App Store Connect 人工核对清单与 ASC 可粘贴送审材料。
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
  - 需要在 App Store Connect 后台替换 App 描述、关键词、IAP 元数据、审核备注和隐私标签，并绑定 build 36。
  - `docs/legal/*.md` 已同步 push 到独立 `together-app-legal` 仓库 commit `6385a3c`；GitHub Pages 线上 Privacy Policy / Terms 已验证显示 2026-05-04 版本。
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
- 2026-05-04 Today 任务 Widget 第一阶段已落地到 `main`：小号 Focus、小号/中号 List 均读 App Group snapshot；显示“还剩 N 项”、任务右侧截止时间、左侧虚线圆角方形完成框；点击完成框运行 `TodayTaskCompletionIntent`，写共享 SwiftData store、记录 `.task/.complete` outbox、更新 snapshot 并 reload widget；其他区域通过 `together://today` 进入 App Today。
- Today Widget 关键文件：`Together/WidgetSupport/*` 负责 App 侧 snapshot/context/write/gateway；`TogetherWidget/TodayWidgets.swift` 负责 Widget UI；`TogetherWidget/TodayTaskCompletionIntent.swift` 负责 extension 内完成动作；`TogetherWidget/TodayWidgetShared.swift` 是 extension-safe DTO/store；`Together.xcodeproj` 已新增 `TogetherWidget` extension target；App 与 extension entitlements 均使用 `group.com.pigdog.together.shared`。
- 2026-05-04 Today Widget 数据一致性修复：App 与 Widget context key 统一为 `today-widget-context`；snapshot 现在保存完整 Today 待办队列，Widget 显示层再按 Focus/List 截断为 1/3 条，因此完成首屏任务后隐藏的第 4 条可自然补位；完成 intent 先写入 `animatingCompletionTaskIDs` 生成勾选填充帧，再由后续 timeline 帧移除任务；App 回到 active 时会刷新 HomeViewModel、重写 widget snapshot、reload widget timelines，并触发当前 space 的既有同步路径推动 widget 写入的 outbox。
- Today Widget 已知边界：带签名的真机/TestFlight 构建前，Apple Developer App ID / provisioning profile 必须开启 App Groups 并包含 `group.com.pigdog.together.shared`；本地 `CODE_SIGNING_ALLOWED=NO` 构建已通过但不等价于签名配置完成。`xcodebuild` 会反复删除 `Together.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，提交前需用 git 恢复，不能提交该删除。
- 已完成并提交：
  - Today Widget：App Group store 迁移、snapshot 生成/刷新、deep link、completion gateway、extension target、真实 Widget UI 与 AppIntent 已分步提交。
  - Task 1：Supabase `task_messages` comment 约束与 RLS guard，提交 `3e5e480`。
  - Task 2 + Task 3：`TaskMessageType`、`TaskMessageCursor`、`PersistentTaskMessage.content`、`PersistentTaskChatReadState`、`TaskMessageRepositoryProtocol`、local/mock repository 和 repository 测试，提交 `7292bbd`。
  - Task 4：应用服务将用户留言写入 `task_messages`，`assignmentMessages` 作为 legacy fallback；Task 4 comment 写入保持 local-only，不记录 `.taskMessage` sync；`sendReminderToPartner` 的 nudge sync 未改，提交 `0796700`。
  - Task 5：`TaskMessagePushDTO` 支持 `content` 和 `sender_supabase_user_id`；新增 `TaskMessagePullDTO`；Supabase catch-up 在 `pullTasks` 后拉取 `task_messages`；Realtime 监听 `task_messages`；`sendTaskComment` 在本地 comment 写入成功后恢复 `.taskMessage` outbox enqueue。
  - Task 6：新增 `TaskChatTimelineEntry` / `TaskChatTimelineBuilder` / `TaskChatViewModel`，聊天面板状态与 Home 卡片保持解耦；ViewModel 支持加载最近消息、发送 comment、500 字上限、本地已读游标。
  - Task 7：Home 卡片预览切到 `task_messages` 最新 comment，`assignmentMessages` 只保留 legacy fallback；`HomeTimelineEntry` 增加 latest comment / unread 状态，留言区域建立 44pt 以上触控入口。
  - Task 8：新增 `TaskChatPanelView`，实现任务聊天面板、头像消息气泡、nudge/system 居中状态、`TextField(axis: .vertical)` composer、Material 背景模糊和 Reduce Motion 降级；Home 使用稳定的 selected chat ViewModel，避免 body 重建导致输入态丢失。
  - Task 9：完成 focused tests、完整单元测试和 simulator build 回归，并记录阶段性项目记忆。
- 最近验证：
  - Today Widget：`git diff --check` 通过；`plutil -lint Together/Info.plist Together/Together.entitlements TogetherWidget/Info.plist TogetherWidget/TogetherWidget.entitlements` 通过；`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；focused widget/persistence test build-for-testing 通过；未做真机 widget 交互验证。
  - Today Widget 数据一致性修复：focused `TodayWidgetSnapshotStoreTests` / `TodayWidgetSnapshotBuilderTests` / `TodayWidgetSnapshotWriterTests` build-for-testing 通过；`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -allowProvisioningUpdates -quiet` 通过；未做真机 widget 交互复测。
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
- iOS widget extension 不能用只包含局部 `@Model` 的 SwiftData `ModelContainer` 打开 app group 里的完整 `Together.store`。这会让扩展用缺少配对、例行任务、项目等实体的 schema 触碰完整库，可能触发主 app 下次启动时 schema/probe 失败并进入危险恢复路径。Today widget 完成任务长期策略：扩展只做最小 SQLite 事务写入 `ZPERSISTENTITEM` / `ZPERSISTENTITEMOCCURRENCECOMPLETION` / `ZPERSISTENTSYNCCHANGE`，app 回前台后 reload Today 并刷新 widget snapshot；未来 widget 新动作也必须沿用“窄动作 + 最小共享写入”或抽出完整共享持久化模块，不能再复制局部 SwiftData 模型。
- `PersistenceController` 不应在完整 store 打不开时静默删除本地库。显式 debug reset 仍可用于开发者有意清空数据；普通启动失败应保留 store 并暴露错误，避免把 schema/迁移问题升级成配对关系、例行任务、项目等真实数据丢失。
- 已验证单人恢复事故模式：本地 SwiftData store 被重建或部分丢失时，`UserDefaults` 中 Supabase solo `migrationCompletedAt / lastPulledAt` 仍可能保留；启动走 `.hasBaseline` 后只按 `updated_at >= lastPulledAt` 拉增量，会漏掉远端旧的 `projects / project_subtasks / periodic_tasks`。修复策略：baseline 账号在当前恢复版本第一次启动时，先推送仍在本地的 outbox，再执行一次 `since:nil` 全量拉取并写入 baseline refresh version；之后恢复增量拉取。

## 设计与动效记忆

- 所有 iOS UI 设计和 SwiftUI 实现必须遵循 Apple 官方设计规范与安全区域约束。
- 当前视觉基线继续使用 `mobile-02-cleanminimal_light` 的干净留白、轻层次、弱阴影、低饱和方向。
- 产品表达应是“效率优先、带一点温度”，不是“情侣感优先”。
- 自定义动画必须状态驱动，拆成 2 到 3 个连续阶段，避免主线程重计算、同步 IO、动画中重排序。
- 自定义动画需验证 Reduce Motion 降级、连续触发和性能。
- 日志页偏信息浏览场景，不应把完成记录列表包在白色圆角分组卡片里；默认使用直接列表、保留 swipe actions，不再额外弹详情 sheet。随着历史任务变多，打开页应避免全量 hydration，优先 repository 层分页、轻量 aggregate 和 SwiftUI `List` 虚拟化。
- Today 重要日期胶囊采用单层胶囊分页，不在静止态露出叠放层；只有多个候选日期时显示 4pt 轻量分页点；横向切换优先使用 SwiftUI 原生横向 ScrollView 分页、scrollTargetBehavior 和 scrollTransition，不在核心文字内容上使用 blur，也不对分页内容叠加横向 offset，避免相邻胶囊互相压住。计数方式切换改为点按视觉上的计数区域，只有支持累计天数的纪念日才暴露为 Button，命中区域至少 44x44pt，生日/节日等不可切换日期显示为静态文本。Today 顶部内容区不再用渐变遮罩压住列表，列表初始内容不保留额外 10pt 空白首行。
- 双人任务聊天面板已放弃自定义 morph overlay 和手写 keyboard metrics。当前长期方向是用 SwiftUI 原生 `.matchedTransitionSource` + `.navigationTransition(.zoom)`：任务卡片作为 zoom source，聊天页作为 `NavigationStack` destination；键盘、安全区和返回转场优先交给系统处理，避免再叠加自定义全屏 overlay / GeometryReader / keyboard observer。
- Today widget 完成动画采用 snapshot 中的 `animatingCompletionTaskIDs` 驱动：第一帧保留被点任务并显示虚线框填充 + 勾选，第二帧再移除整行并让隐藏队列自然补位。即使最后一项完成后 `remainingCount == 0`，也必须先展示完成动画，再切换到空态，避免勾图标单独消失或最后一行直接跳空态。
- Today widget 补位动画采用独立 `appearingTaskIDs` transient state：被勾选任务整行消失后，补位任务先占位为透明和轻微下移，再做出现动画；持久化 snapshot 不应保存出现态，避免下次 reload 反复入场。widget 空态插画应使用 Today 主列表同款 `EmptyCalendar` 小猫占位图，不再使用 `EmptyList` 笔记本插画。
- Widget 使用 `.contentMarginsDisabled()` 后，背景和内容必须分层：背景通过 `.containerBackground(for: .widget)` full-bleed 铺满，前景内容必须显式读取 `@Environment(\.widgetContentMargins)` 并设置最小 padding，不能让标题、勾选框、计数或头像贴到圆角裁切边缘。WidgetKit `placeholder(in:)` 只承担结构占位；真实桌面数据必须来自非预览 `getSnapshot` / `getTimeline`，preview demo 只能在 `context.isPreview` 下出现，不能进入真机 timeline 或真实空态 fallback。
- 真机桌面 widget 可能在同一 `CFBundleVersion` 下复用旧 timeline 渲染缓存。排查 widget 数据/渲染问题时，如果 Console 已证明 provider 读到真实 snapshot，但桌面仍显示旧 UI、探针文案或骨架，应先提升主 App 与 widget extension 的 `CURRENT_PROJECT_VERSION` 重新安装，或删除重加 widget / 重启，再继续判断业务代码。

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

- 2026-05-07：所有 widget 深色模式适配。新增 `TogetherWidget/WidgetTheme.swift` 统一 Today 与 Anniversary widget 的深浅色 token；Today widget 的背景、截止时间强调色、完成框、分割线、空态小猫插画在深色模式下自适应；Anniversary widget 的 avatar-derived material background、头像占位渐变、头像描边/阴影、数字强调色、倒计时胶囊和分割线在深色模式下自适应。长期规则已追加到 `AGENTS.md`：新增或修改 widget 时不能只硬编码浅色模式，必须显式处理 `colorScheme`，优先复用 widget theme。构建号提升到 44，避免真机桌面 widget 缓存旧 UI。仍需真机在系统浅色/深色模式下分别删除重加 Today 重点、Today 清单、纪念日三类 widget 验收。
- 2026-05-07：完成纪念日 widget 小号真机修复后的 UI 收尾与经验沉淀。UI：移除纪念日头像组右侧白色圆形心形图标；纪念日累计天数、周年倒计时和下一个节点天数均改用非本地化 `Text(verbatim:)` 展示，避免 SwiftUI `Text` 的本地化数字插值把 `2212` 渲染为 `2,212`。经验：本轮多次返工的核心教训已追加到 `AGENTS.md` Widget 专项规则，包括 snapshot 不得写入原始大图 Data、必须按 family 单独验证小号渲染、添加页 preview 不等于桌面 widget、数字显示需避免隐式本地化格式化。仍需真机安装最新 build 后确认小号纪念日 widget 正式 UI。
- 2026-05-07：继续排查“小号纪念日 widget 桌面纯白、中号/大号正常”。上一轮只移除了小号背景头像模糊，但小号前景头像仍会直接解码 App Group snapshot 中的原始头像 Data；真机历史日志显示两张头像合计约 485KB。新的根因判断：数据层、App Group、provider/timeline 均已排除，问题集中在 `systemSmall` 桌面快照归档时的真实头像解码/渲染成本。处理：`AnniversaryWidgetSnapshotBuilder` 在主 App 写入 snapshot 前把头像转成 widget 专用 320px 方形 JPEG 缩略图；`AnniversaryWidgetView` 对小号旧 snapshot 中过大的头像 Data 做防御性降级，先显示系统头像占位，避免整张小号 widget 被归档成空白；构建号提升到 42，避免 SpringBoard 复用旧 widget timeline 缓存。验证：`git diff --check` 通过；`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/AnniversaryWidgetSnapshotBuilderTests -quiet` 通过，并新增头像缩略图测试；`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过。仍需真机安装 build 42、打开 App 让 snapshot 重写，再删除并重加小号纪念日 widget 验收。
- 2026-05-07：针对“只有小号纪念日 widget 添加到桌面后空白，中号/大号正常”的真机反馈做最小修复。结构对比结论：Today widget 小号没有真实头像 Data 和高斯模糊背景；纪念日三种尺寸共用同一 App Group snapshot/provider/timeline，且中号/大号能显示真实头像与日期，说明后端数据、App Group 和 timeline 不是根因。最小修复只改渲染层：`systemSmall` 纪念日背景不再渲染真实头像高斯模糊层，只保留轻量 fallback gradient；中号/大号保留 avatar-derived background，但给背景头像图片加固定 frame 和 clipped，避免 WidgetKit 桌面快照归档时处理无界大图。验证：`git diff --check` 通过；`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/AnniversaryWidgetSnapshotBuilderTests -quiet` 通过；`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过。仍需真机删除并重加小号纪念日 widget 验收。
- 2026-05-05：定位纪念日小号 / 中号 widget 真机持续显示骨架或旧探针 UI 的真实原因。底层证据来自真机 Console：`[AnniversaryWidget] read snapshot ... exists=true paired=true hasStartDate=true avatars=2 avatarBytes=485435`，说明 App Group snapshot、配对状态、纪念日日期和头像图片均已被 widget extension 成功读取，问题不在后端数据、App Group 同步或 provider timeline。继续用最小探针验证：同一 `CFBundleVersion=36` 反复安装时，桌面 widget 仍可能停在旧骨架 / 旧探针；把构建号提升到 37 后，桌面立即显示新的 `SMALL V2 / MEDIUM V2` 探针，证明根因是 WidgetKit / SpringBoard 对同构建号 extension 的桌面渲染 timeline 缓存没有失效。处理：移除临时探针，恢复正式纪念日 UI，项目构建号提升到 38；保留根视图 `.unredacted()` 作为 placeholder redaction 兜底，但不再把 redaction 当最终根因。后续真机验证 widget UI/provider 改动，必须提升主 App 与 extension `CURRENT_PROJECT_VERSION`，或删除重加 widget / 重启后再判断。验证：`git diff --check`、`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/AnniversaryWidgetSnapshotBuilderTests -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；build 38 已安装到真机，App 与 TogetherWidget appex 的 `CFBundleVersion` 均为 38，构建产物中无 `SMALL V2 / MEDIUM V2` 探针字符串；仍需肉眼确认桌面小号/中号恢复正式 UI。
- 2026-05-04：修复真机添加 widget 后的两项反馈。`TodayFocusWidget` 小号不再复用清单式多行布局，改为“今日重点”单个优先任务视图，保留虚线完成框 AppIntent；`TodayListWidget` 小号继续作为最多 3 条任务的清单。纪念日 widget 骨架图问题按刷新链路加固：`AnniversaryWidgetEntry` 区分 placeholder 并仅对 placeholder 解除系统骨架 redaction；配对状态变化时立即刷新 anniversary snapshot；无当前用户/空间清空 snapshot 时也 reload anniversary timeline；真实纪念日从 `startDate != nil` 判定，支持“在一起 0 天”而不误入空态。验证：`git diff --check`、`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/AnniversaryWidgetSnapshotBuilderTests -only-testing:TogetherTests/TodayWidgetSnapshotBuilderTests -only-testing:TogetherTests/TodayWidgetSnapshotStoreTests -only-testing:TogetherTests/TodayWidgetSnapshotWriterTests -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；仍需真机重新安装/打开 App 后确认纪念日 widget 是否从真实 App Group snapshot 渲染。
- 2026-05-04：落地大号 Today widget 与双人纪念日 widget 第一版。Today 清单 widget 支持 `.systemLarge`，大号显示今日日期/星期并按当前 Today 排序自适应展示最多 6 条任务；小号/中号仍保持既有 3 条展示和完成动画链路。新增纪念日 widget kind `com.pigdog.Together.widgets.anniversary`，主 App 通过 `AnniversaryWidgetSnapshotWriter` 从当前 active pair 的 shared space 重要日期生成 App Group JSON 快照 `anniversary-widget-snapshot.json`，widget extension 只读取 DTO/头像 image data 渲染小/中/大号，不打开主 App SwiftData store；snapshot 保留 `startDate`，extension 按当前时间重算累计天数、周年倒计时和 100 天节点，避免用户不打开 App 时计数停留在旧快照。纪念日视觉采用圆角字体、头像左上覆盖顺序和 avatar-derived blurred background；AppContext 在 Today snapshot 刷新、重要日期变化、无当前用户/空间时同步刷新或清空纪念日 snapshot 并 reload timeline。验证：`git diff --check`、`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/AnniversaryWidgetSnapshotBuilderTests -only-testing:TogetherTests/TodayWidgetSnapshotBuilderTests -only-testing:TogetherTests/TodayWidgetSnapshotStoreTests -only-testing:TogetherTests/TodayWidgetSnapshotWriterTests -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；未做真机 widget 添加、时间线刷新、头像背景和 App Group 签名验收。
- 2026-05-04：修复真机 widget 全部显示假数据/默认头像与背景四周留白。根因是 WidgetKit 在真实桌面加载/失败/刷新前也可能走 `placeholder(in:)`，旧实现把 demo snapshot 用在非预览路径，导致真机短时或长期显示 520、示例日期和默认头像；同时未关闭 WidgetKit 默认 content margins，avatar-derived 背景无法覆盖整个容器。处理：Today/Anniversary provider 的非 preview placeholder 改为读取 App Group snapshot，只有 widget gallery preview 才使用 demo 数据；App Group snapshot 写入失败从静默 `try?` 改为显式日志，便于定位 entitlement/provisioning profile 未包含 `group.com.pigdog.together.shared`；Today/Anniversary widget 配置均加 `.contentMarginsDisabled()`。验证：`git diff --check`、widget snapshot focused tests、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；仍需真机安装新包、打开 App 写入 snapshot 后重加 widget 验收真实数据与背景贴边。
- 2026-05-04：按 WidgetKit 最佳实践修正上一轮真机 widget 方案。Today widget 保留 `.contentMarginsDisabled()` 让背景贴满，但前景内容改用 `widgetContentMargins` + 最小 padding，修复标题、完成框和“还剩 N 项”被圆角边缘裁切。Anniversary widget 不再让真实桌面 `placeholder(in:)` 读取业务数据或 demo 520；`placeholder` 只返回中性结构占位并解除 redaction，`getSnapshot(context.isPreview)` 才返回 demo，非预览 snapshot/timeline 只读取 App Group 真实 snapshot 或真实空态；空头像 fallback 改为中性头像，不再回退 `.placeholder.avatars`。Anniversary 背景移入 `.containerBackground(for: .widget)`，前景内容独立 padding；App 写入和 Widget 读取均记录 snapshot path、file exists、paired、startDate、avatars 和 avatarBytes，便于真机定位卡在写入、读取、解码还是 timeline。验证：`git diff --check`、focused widget snapshot tests、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；仍需安装新包后打开 App 一次、删除并重加 widget 真机验收。
- 2026-05-05：纪念日 widget “正在同步纪念日”排查中间结论。截图证明当时显示来自 `placeholder(in:)`，不是 App Group 真实空态；后续进一步用真机 Console 和最小探针确认，最终根因不是单 kind reload 缺失，而是同 `CFBundleVersion` 下桌面 widget 渲染缓存未失效。保留的长期规则是：`placeholder` 只能提供中性结构或 last-known snapshot，不承诺“打开 App 后会自动更新”；真实修复和验收必须以提升 build number / 删除重加 widget 后的桌面结果为准。
- 2026-05-04：继续修复 Today widget 与恢复链路真机反馈。UI：widget 完成后补位任务改为在被勾选任务彻底消失后再入场；空态资源从 `EmptyList` 改为 Today 同款 `EmptyCalendar`；单人模式标题旁空间名优先显示当前用户昵称；日志页空白根因是 `CompletedHistoryViewModel.isPairMode` 使用 `hasActivePairSpace`，导致只要有配对关系就过滤掉空态，已改为 `isViewingPairSpace` 并在双人空历史时展示中性空态。数据：Supabase solo baseline 增加一次性全量恢复版本，修复旧游标导致远端旧项目、项目子任务和例行事务不恢复的问题；solo recovery 成功后无论是否展示启动恢复 UI 都刷新 Today / Lists / Projects / Calendar / Routines / widget。验证：`git diff --check`、`SupabaseSoloSyncServiceTests`、`TodayWidgetSnapshotStoreTests`、`TodayWidgetSnapshotBuilderTests`、`AppContextSoloMutationSyncTests`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过；未做真机 widget 动画验收。
- 2026-05-04：执行送审阻塞清单中仓库内可控项。修复 Profile Pro 入口旧“自定义主题”承诺；App 内隐私政策 / 服务条款摘要改为个人 Todo 为主、双人协作为可选扩展；`docs/legal/privacy-policy.md` 与 `docs/legal/terms-of-service.md` 更新为 2026-05-04 版本，隐私政策与本地 `PrivacyInfo.xcprivacy` 对齐，不额外声明广告、行为分析、崩溃分析或诊断数据采集；新增 `docs/superpowers/runbooks/2026-05-04-app-store-connect-submission-materials.md`，提供 ASC 描述、关键词、IAP 元数据、审核备注和隐私标签填写口径；更新送审阻塞清单到 build 36，并新增 Universal App / iPad 截图风险。法律文档已 push 到独立 `together-app-legal` commit `6385a3c`，线上 Privacy Policy / Terms 均已验证显示 2026-05-04 版本。验证：`plutil -lint Together/Info.plist Together/PrivacyInfo.xcprivacy` 通过；安全/隐私快扫未发现硬编码密钥、敏感 token 写 UserDefaults/日志、业务明文 HTTP 或 ATT 调用；`PrivacyInfo.xcprivacy` 已声明 UserDefaults 和 SystemBootTime required reason API；`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。未做真机验收。
- 2026-05-04：基于当前双人任务提醒、底部 toolbar 系统蓝、双人模式 reload 频闪修复、例行任务 per-space 缓存与单人蓝色例行任务胶囊延迟闪出修复，打包上传 TestFlight build 36。构建号从 35 提升到 36；归档路径 `build/TestFlight-20260504-0306-build36/Together.xcarchive`，导出上传使用 `build/exportOptions-TestFlight-upload.plist`；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。验证链路：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、Release archive、`xcodebuild -exportArchive` 上传通过；未做模拟器或真机 UI 验收。
- 2026-05-04：修复切换双人模式时短时间连续频闪。根因不是数据库刷新本身，而是 Supabase `catchUp` / Realtime 通知会短时间触发多轮 `reloadAfterSync`，首页 `reloadRevision` 又参与 `ScrollView/List` 容器 `.id` 与动画，导致普通同步刷新被放大成整块内容反复销毁重建。处理：`AppContext` 新增 cause-aware single-flight reload 合并器，180ms 内合并 Supabase / pair member / partner avatar / important dates / startup restore 刷新请求，并保留 important dates scheduler 副作用；`HomeViewModel.reload` 新增 `HomeReloadReason`，双人模式切换、同步和启动恢复不再做整页 items spring；`HomeView.tasksContent` 的 startup/empty/timeline identity 移除 `reloadRevision`，只保留日期维度；`SupabaseSyncService.catchUp(notify:)` 允许 Realtime handler 内部补拉不重复广播。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试，仍需 TestFlight/真机切换双人模式确认无连续空态/列表闪烁。
- 2026-05-04：按同一频闪根因排查单人 Today 列表、例行任务列表和头像区域。单人 Today 列表当前没有 `reloadRevision + .id` 的整块重建问题；头像区域保留 `.id(userProfileRevision)` 以支持同名头像文件重读，但 `SessionStore.currentUser` 和 `restorePersistedUserProfileIfNeeded(force:)` 改为用户资料真实变化时才推进 revision，避免同步无变化也重建头像按钮；例行任务列表移除首现 `.task` 与空间 `.task(id:)` 双加载，改为 `RoutinesViewModel.loadIfNeeded()` 和同步 `reload()` 静默刷新，避免普通同步反复进入 loading/empty。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-04：修复切回单人模式时蓝色例行任务胶囊延迟闪出。根因：`RoutinesViewModel.tasks` 是当前空间单份数据，双人同步会把它覆盖成双人空间任务；切回单人时 Today 先读到双人 tasks，`hasPendingTasks=false`，稍后单人 reload 完成后胶囊才突然插入。处理：`RoutinesViewModel` 新增 per-space `tasksBySpaceID` 缓存，切换空间时先同步恢复当前 space 缓存，再静默刷新；本地例行任务创建/更新/完成/删除后同步更新缓存；异步刷新返回时若用户已切到其他 space，只更新缓存不覆盖当前可见 tasks；首页头像模式按钮切换后立即调用 `restoreCachedTasksForCurrentSpace()` 并后台 `loadIfNeeded()`。验证：`git diff --check`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过；未做模拟器测试。
- 2026-05-04：收敛 Today widget 完成任务后的动画与数据一致性问题。根因：widget extension 过去用局部 SwiftData schema 打开完整 app group store，存在污染/触发主 app 自动删库恢复的风险；同时完成最后一项时 `remainingCount==0` 会跳过打勾动画直接空态。处理：`TodayTaskCompletionIntent` 改为 SQLite 最小事务写入任务完成、重复任务 occurrence completion 与 sync outbox，不再导入 SwiftData 或复制 `@Model`；`PersistenceController` 去掉 schema/probe 失败后的自动删库；widget snapshot 保留完整待办队列并用 `animatingCompletionTaskIDs` 做“填充打勾 -> 整行消失 -> 后续任务补位”；日志空态 `EmptyHistory` 去掉绿色背景块。验证：`git diff --check`、widget snapshot 相关 `xcodebuild test` 通过、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` 通过、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -allowProvisioningUpdates -quiet` 通过；未做真机 widget 手动验收。
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
