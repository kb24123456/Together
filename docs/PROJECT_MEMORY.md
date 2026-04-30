# Together Project Memory

> Codex 项目记忆入口。只记录长期有效、可被未来任务复用的事实。不要记录密钥、token、隐私数据或临时噪声。

## 当前状态

- 日期：2026-04-29
- 项目路径：`/Users/papertiger/Desktop/Together`
- Git 根目录：`/Users/papertiger/Desktop/Together`
- 产品主轴：iPhone-only 的单人 Todo 效率工具。
- 当前策略：V1 优先跑通单人 Todo 主链路；V2 再扩展双人协作；V3 多人 Space 仅做底层预留。
- Chronicle：暂不开启；先使用项目文档、AGENTS 和 Skill 机制承接记忆。

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

## 设计与动效记忆

- 所有 iOS UI 设计和 SwiftUI 实现必须遵循 Apple 官方设计规范与安全区域约束。
- 当前视觉基线继续使用 `mobile-02-cleanminimal_light` 的干净留白、轻层次、弱阴影、低饱和方向。
- 产品表达应是“效率优先、带一点温度”，不是“情侣感优先”。
- 自定义动画必须状态驱动，拆成 2 到 3 个连续阶段，避免主线程重计算、同步 IO、动画中重排序。
- 自定义动画需验证 Reduce Motion 降级、连续触发和性能。
- 日志页偏信息浏览场景，不应把完成记录列表包在白色圆角分组卡片里；默认使用直接列表、保留 swipe actions，不再额外弹详情 sheet。随着历史任务变多，打开页应避免全量 hydration，优先 repository 层分页、轻量 aggregate 和 SwiftUI `List` 虚拟化。

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

- 2026-04-29：初始化 Codex 项目记忆、阶段性收尾 Skill、Chronicle 风险评估；未修改业务代码，未运行 Xcode 构建。
- 2026-04-29：build 22 修复接受方 786 云端已配对但本地仍单人 UI 的问题；验证 `PairSpaceSummaryResolverAvatarTests` 与 `LocalPairingServiceUnbindIsolationTests` 通过。
- 2026-04-29：新增发起邀请 loading 状态、纪念日 sheet 内联新增区与纪念日胶囊长按计数切换；双人 APNs/前台 catch-up 与解绑成员校验完成本地实现。验证 `git diff --check`、iOS Simulator build、`profileViewModelExposesInviteCreationLoadingState` 通过；Supabase trigger 已应用，Edge Function 部署需要 `SUPABASE_ACCESS_TOKEN`。
- 2026-04-29：生产后端硬化完成第一轮：Supabase 已加固 `space_members` / `pair_invites` / avatar storage RLS，新增 `accept_pair_invite` 原子接受 RPC、主动过期旧邀请码、关键同步索引、邀请码唯一约束，撤销 trigger function 的客户端可执行权限，将业务表 RLS 从 `public` 收窄到 `authenticated`，补齐缺失外键索引，为核心 enum/status 字段加 DB check constraints，并归档只有过期邀请的旧单人成员 pair shell；客户端接受邀请改走 RPC，双人 avatar 上传路径改用 Supabase `auth.uid()`，并补强 pair 变更不进入 CloudKit 的过滤。验证 `git diff --check`、iOS Simulator build；Edge Function 部署仍需本机 `SUPABASE_ACCESS_TOKEN`。
- 2026-04-29：日志页改为直接 plain list，取消点击行弹详情 sheet，仅保留 swipe 删除/恢复；`CompletedHistoryViewModel.delete` 对 creatorID 漂移的旧完成历史行增加 repository tombstone fallback；`LocalItemRepository.fetchCompletedItems` 初始页改为 active/archived 分路限量候选并合并排序，Logbook hero stats 改用 `fetchCount` 与边界记录查询，避免打开页全量 Item hydration。验证 `git diff --check`、`CompletedHistoryViewModelPairTests`、iOS Simulator build 通过。
- 2026-04-30：修复双人最新空间恢复与生产库多 active pair 残留：`hydratePairSpaceFromCloudIfNeeded` 改为以 Supabase 最新 active pair 为准并补齐本地 shared space；`SpaceDTO` 拉取远端 status/archivedAt；前台 pair 校验会识别远端 space 已 archived；新增 `038_archive_previous_pair_spaces_on_accept.sql`，`accept_pair_invite` 会归档参与者旧 active pair spaces。生产库已归档同一对用户的 11 个旧 active pair spaces，只保留最新双人成员空间 active；最新空间内任务和纪念日均保留。验证 `git diff --check`、`PairSpaceSummaryResolverAvatarTests`、`LocalPairingServiceUnbindIsolationTests`、iOS Simulator build 通过。

## Open Questions

- 是否启用 Codex Memories 的用户级配置。
- Chronicle 是否在低敏任务中短时试用。
- V1 全局创建入口最终是单按钮直达还是展开式快捷菜单。
- 是否近期启动 `PairSpace -> Space` 命名迁移，还是继续通过兼容层过渡。
