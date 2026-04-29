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

## 设计与动效记忆

- 所有 iOS UI 设计和 SwiftUI 实现必须遵循 Apple 官方设计规范与安全区域约束。
- 当前视觉基线继续使用 `mobile-02-cleanminimal_light` 的干净留白、轻层次、弱阴影、低饱和方向。
- 产品表达应是“效率优先、带一点温度”，不是“情侣感优先”。
- 自定义动画必须状态驱动，拆成 2 到 3 个连续阶段，避免主线程重计算、同步 IO、动画中重排序。
- 自定义动画需验证 Reduce Motion 降级、连续触发和性能。

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

## Open Questions

- 是否启用 Codex Memories 的用户级配置。
- Chronicle 是否在低敏任务中短时试用。
- V1 全局创建入口最终是单按钮直达还是展开式快捷菜单。
- 是否近期启动 `PairSpace -> Space` 命名迁移，还是继续通过兼容层过渡。
