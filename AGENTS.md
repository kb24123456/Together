# Repository Instructions

- 本仓库 `Together` 的 GitHub 远端仓库固定为 `https://github.com/kb24123456/Together.git`
- 默认 `origin` 应指向上述地址
- 后续在本仓库内进行提交、推送、分支协作时，均以该远端仓库为唯一目标
- 如需变更远端，必须先得到用户明确确认，不能擅自切换到其他 GitHub 仓库
- 本仓库所有 iOS UI 设计与前端实现，必须优先遵循 Apple 官方设计规范与安全区域约束
- 设计稿、Pencil 线框、高保真视觉稿、SwiftUI 页面实现，均必须预留顶部和底部安全区域，避免与动态岛、状态栏、Home Indicator、底部系统手势区域、Tab Bar 发生遮挡或误触冲突
- 底部导航条、悬浮按钮、顶部返回按钮、胶囊按钮等系统级控件，默认按 iOS 原生布局习惯放置，不允许仅为了视觉效果侵入安全区域
- 液态玻璃风格组件优先复用或贴近 Apple 标准导航和控件行为，避免做出与系统层级冲突的高饱和装饰性假玻璃
- 具体规则与来源维护在 `/Users/papertiger/Desktop/Together/DESIGN_GUIDELINES.md`，后续所有 UI 设计与实现默认遵循该文件

# AGENTS.md

## 1. 作用
- 本文件用于约束 Codex 在项目「一起 / Together」中的执行方式。
- 目标：统一 Codex 的执行口径、文档读取顺序与修改边界，减少返工与偏航。

## 2. 文档职责与优先级
- `PRODUCT_SPEC.md`：唯一产品规格主文档，负责产品定位、MVP 范围、信息架构、页面需求。
- `DEVELOPMENT_GUIDELINES.md`：唯一工程规范主文档，负责技术约束、架构原则、测试与提交流程。
- `DESIGN_GUIDELINES.md`：唯一设计规范主文档，负责视觉基线、安全区域、动效与专项页面设计规则。
- `AGENTS.md`：只负责 Codex 的执行规则、提问条件、输出方式与文档读取要求。
- 若内容重复，以上三份主文档优先于本文件中的摘要描述。

## 3. 首次进入项目必须先读
- `PRODUCT_SPEC.md`
- `DEVELOPMENT_GUIDELINES.md`
- `DESIGN_GUIDELINES.md`
- 当前 `AGENTS.md`
- 与本次任务直接相关的 `Features / Models / Services` 文件

如果上述文档缺失或过期，先补齐或更新，再改代码。

## 4. 响应原则
- 先给结论，再执行。
- 简单任务直接做；复杂任务先给“目标 / 影响范围 / 方案 / 风险”。
- 不确定时直接问清，不要猜。
- 对用户的 UI、交互、动效偏好不做默认假设；只要执行前尚未获得用户明确确认，就必须先提问确认需求，再开始实现。
- 回复短，但关键信息不能缺。
- 默认只回答用户上一轮刚提出的问题，不重复回顾已经确认或已回答的旧问题；除非新问题明确依赖旧问题，才做最小必要引用。
- 区分事实、推演、开放问题。
- 当已经判断当前方案足够好、无需继续微调时，应直接明确告知用户“当前已足够好，无需再调”；不要为了迎合而机械追加微调建议。
- 当判断当前方向已收敛时，可以直接提出其他更有价值的方向性建议，而不是刻意继续围绕当前细节做建议。

## 5. 开发总原则
- 先统一文档与边界，再改实现。
- 优先修改现有文件；仅在缺失关键文档或关键模块时新建文件。
- 所有实现优先简单、清晰、可维护、可被 AI 理解。
- 不做过度抽象，不引入无必要复杂架构。
- 工程、设计、产品细则统一以下沉文档为准，不在本文件重复展开。

## 6. 执行边界
- 若任务涉及新增或重构 UI、交互、动效，在用户偏好和验收标准未明确前必须先问。
- 若需求与 `PRODUCT_SPEC.md` 冲突，先指出冲突并确认，不得擅自改方向。
- 若用户提出的 UI、交互或动效需求与 iOS 原生框架、系统控件行为或安全区域机制冲突，必须先指出冲突点、系统约束和可选取舍，得到确认后再实现；禁止在未说明框架冲突的情况下反复局部修补。
- 若需要改动核心数据模型、状态机、信息架构、第三方依赖、用户数据迁移，必须先问。

## 7. 默认执行顺序
1. 读文档与相关代码
2. 明确影响范围
3. 先模型与状态
4. 再服务与数据流
5. 再 Today / 首页
6. 再清单 / 项目 / 日历
7. 再详情、创建入口、筛选与排序
8. 再我页与设置
9. 最后处理双人扩展与附加模块

## 8. 复杂任务输出模板
- 任务目标
- 影响模块
- 实现方案
- 风险与边界
- 需要确认的问题（如有）

完成后输出：
- 已完成内容
- 影响范围
- 未完成内容
- 下一步建议

## 9. 禁止事项
- 禁止跳过文档直接写代码。
- 禁止继续按旧的“双人优先 / 情侣优先”逻辑新增功能。
- 禁止擅自新增多人模式实现。
- 禁止为了省事把逻辑硬编码进单个页面。
- 禁止跨模块大改。
- 禁止生成与当前任务无关的大段样板代码。
- 禁止为了视觉效果侵入安全区域或牺牲交互可用性。

## 10. 提交与修改策略
- 小步修改，小步验证。
- 一次提交只解决一个清晰问题。
- 后续默认只在 `main` 上工作，不再为普通功能或修复新建分支；除非用户明确要求创建分支。
- 修改前说明目的；修改后说明影响。
- 若任务只要求评估，不要直接改代码。
- 提交前保证项目可编译、关键 Preview 可运行。

## 11. token 控制原则
- 回复优先短格式。
- 只展开与当前任务直接相关的信息。
- 不重复描述已知背景。
- 除非用户要求，不一次性展开过多远期方案。

## 12. Skill 调用规则
- 目标：在合适的时机，自动选择并调用最匹配的 skill，而不是依赖临时判断或遗忘。
- 规则：只要任务明显命中某个 skill 的职责边界，就应优先调用对应 skill，再开始实现或分析。
- 若同一任务同时命中多个 skill，优先顺序为：流程类 skill -> 领域审查类 skill -> 实现类 skill。

### 12.1 默认入口
- 每次进入新任务，优先按 `using-superpowers` 的原则检查是否存在适配 skill。
- 对于小任务，如果没有明显命中任何 skill，可直接执行；但只要命中概率足够高，就不应跳过。

### 12.2 当前仓库保留 skill 的触发场景
- `swiftui-pro`
  - 用于：SwiftUI 页面开发、SwiftUI 代码审查、现代 API 替换、导航、视图结构、可访问性、Preview 相关问题。
- `swift-concurrency-pro`
  - 用于：`async/await`、actor、Sendable、任务取消、`Task` 使用方式、严格并发警告、并发代码审查。
- `swiftdata-pro`
  - 用于：SwiftData 模型、`@Query`、谓词、关系、删除规则、索引、CloudKit 兼容性、SwiftData 代码审查。
- `swift-testing-pro`
  - 用于：Swift Testing 测试编写、测试重构、从 XCTest 迁移、异步测试、测试结构和断言风格。
- `ios-animation-codex-skill`
  - 用于：高级交互动效设计、页面转场、Hero 动画、展开收起、滚动联动、动效系统设计。
- `ios-fluid-animation`
  - 用于：强调原生质感、丝滑感、性能优先、可降级、可复用的 iOS 动效实现与优化。
- `global-dark-mode-delivery`
  - 用于：全局深色模式改造、主题 token 化、浅深色一致性治理、主题切换和适配审查。
- `systematic-debugging`
  - 用于：任何 bug、崩溃、测试失败、构建失败、行为异常、性能异常；必须先查根因，再谈修复。
- `long-horizon-codex`
  - 用于：多阶段、大范围、跨会话、长链路任务；需要把执行上下文沉淀为 `prompt.md`、`plans.md`、`implement.md`、`documentation.md` 四个控制面文件时。

### 12.3 组合调用规则
- SwiftUI 页面 + 并发状态问题：先 `swiftui-pro`，再 `swift-concurrency-pro`。
- SwiftUI 页面 + SwiftData 数据流：先 `swiftui-pro`，再 `swiftdata-pro`。
- SwiftData + CloudKit 约束：直接调用 `swiftdata-pro`。
- 测试失败或需要补测试：先 `systematic-debugging` 判断问题，再按需要调用 `swift-testing-pro`。
- 动效问题：先在 `ios-animation-codex-skill` 与 `ios-fluid-animation` 中选最贴近的一个；若同时涉及设计意图和性能落地，可组合使用。
- 深色模式问题：直接调用 `global-dark-mode-delivery`，不要把它降级成普通样式修补。
- 超过一次会话、里程碑较多、容易上下文丢失的任务：尽早调用 `long-horizon-codex`，不要等到上下文混乱后再补文档。

### 12.4 禁止事项
- 不要在明显命中 skill 的情况下绕过 skill 直接凭记忆执行。
- 不要同时拉起多个职责高度重叠的 skill 造成规则冲突。
- 不要把 `long-horizon-codex` 用于一次性小修。
- 不要在未完成根因分析前跳过 `systematic-debugging` 直接修 bug。

## 13. 项目记忆与阶段性收尾
- `docs/PROJECT_MEMORY.md` 是 Codex 在本仓库内的统一项目记忆入口。
- 开始复杂任务前，先阅读 `PRODUCT_SPEC.md`、`DEVELOPMENT_GUIDELINES.md`、`DESIGN_GUIDELINES.md`、当前 `AGENTS.md` 和 `docs/PROJECT_MEMORY.md`。
- 完成大功能、长时间 bug 修复、架构调整、迁移、性能优化或复杂调研后，必须更新 `docs/PROJECT_MEMORY.md`。
- 更新项目记忆时只记录长期有效事实：当前进度、已完成事项、关键决策、重要文件、验证命令、遗留问题和下一步。
- 不要把密钥、token、私人数据、临时日志全文或未经验证的推测写入项目记忆。
- Claude 旧 worktree 与历史计划只作为参考，不自动视为当前事实；若与当前根目录文档或代码冲突，以当前根目录文档和代码为准。
- 如果同一类流程重复出现 2-3 次，优先沉淀为 `.agents/skills/` 下的项目 Skill。

## 14. Widget 开发专项规则
- 开发 iOS widget 前必须先确认 App Group、主 App entitlement、Widget entitlement、Apple Developer 后台能力和 provisioning profile 一致；当前共享组为 `group.com.pigdog.together.shared`。
- Widget extension 禁止用局部 `@Model` / 局部 SwiftData schema 打开主 App 的完整 SwiftData store。原因是 extension schema 不完整时可能污染或触发主 App store 打开失败，进而造成配对关系、项目、例行事务等数据风险。
- Widget 需要改动任务状态时，只允许采用以下两类路径之一：
  1. 主 App 提供完整、共享、安全的持久化模块；
  2. Widget 只做经过审查的最小共享写入，例如最小 SQLite transaction 写入任务完成状态、occurrence completion 和 sync outbox。
- Widget 的 AppIntent 不能只更新 widget snapshot；凡是“完成任务、恢复任务、删除任务、修改状态”等业务动作，必须同时保证主 App 数据源、同步 outbox、widget snapshot 和回前台 reload 链路一致。
- Widget snapshot 只能作为展示缓存和动画状态，不是业务真相。业务真相必须回到主 App 数据库和 Supabase/同步链路。
- Widget 完成动画必须状态驱动：先保留被点任务展示虚线框填充和勾选，再让整行消失，最后让补位任务执行出现动画；不要让勾选图标单独消失，也不要在最后一项完成时直接跳空态。
- Widget 空态、插画、字号、颜色和文案应优先复用 Today 当前设计语言；如果 Today 使用 `EmptyCalendar` 小猫占位图，widget 不应误用 `EmptyList` 等其他插画。
- 小号 widget 中，只有虚线完成框可触发完成动作；其他区域应进入 App。实现时要明确 Button / widgetURL 的命中边界，避免整行误触完成或完成框无法触发。
- Widget 与 App 同步问题必须同时测三条链路：
  1. App 修改任务后 widget 是否刷新；
  2. Widget 完成任务后 App 前台列表、下拉刷新、切换单双人模式是否一致；
  3. App 恢复已完成任务后 widget 是否重新出现对应待办。
- 如果 widget 或恢复链路曾导致本地 store 重建、schema/probe 失败、数据缺失，排查时必须检查 Supabase solo recovery 的 `lastPulledAt / migrationCompletedAt` 游标；本地库重建但游标仍存在时，只拉增量会漏掉远端旧项目和例行事务，必要时应做一次性 `since:nil` 全量恢复。
- 真机验证 widget UI / provider 改动时，不能在同一 `CFBundleVersion` 下反复安装后直接判断桌面结果。WidgetKit / SpringBoard 可能复用旧 timeline 渲染缓存，添加页 preview 已更新也不代表桌面 widget 已更新。每次改 widget extension 后应提升主 App 与 extension 的 `CURRENT_PROJECT_VERSION`，或删除重加 widget / 重启后再验收。
- Widget extension 的 `Info.plist` 必须包含 App Store Connect 要求的基础 bundle 字段，尤其是 `CFBundleDisplayName`。本地 archive 成功不代表 ASC 上传会通过；上传 TestFlight 前应检查归档内 `TogetherWidget.appex/Info.plist`。
- Widget snapshot 里禁止直接塞未处理的原始头像、相册大图或其他大尺寸图片 Data。主 App 写入前必须生成 widget 专用缩略图，并控制单个 snapshot 总字节量；小号 widget 要有旧 snapshot 大图 Data 的降级兜底，否则可能在桌面宿主快照归档时整块空白。
- Widget 问题排查必须按“数据层 -> timeline/provider -> 各 family 渲染树 -> SpringBoard 缓存”的顺序逐层证伪。中号/大号正常不能证明小号正常；添加页 preview 正常也不能证明桌面 widget 正常。
- Widget 文本中的纯数字如果不希望出现本地化千分位分隔符，必须使用 `Text(verbatim:)` 或提前生成非本地化展示字符串，不要使用 `Text("\(number)")` 这类 SwiftUI 本地化插值。
- 所有 widget 视觉色值必须显式适配 `colorScheme`。背景、强调色、分割线、空态插画、头像占位、头像描边、阴影和完成框都不能只按浅色模式硬编码；新增 widget 前优先复用已有 widget theme。
- 涉及 widget 的修复完成前，最低验证要求是：`git diff --check`、widget snapshot 相关测试、相关同步/恢复测试、`xcodebuild build-for-testing`。真机验收必须覆盖桌面 widget 点击、动画、App 回前台、删除重装恢复和 App Group 签名能力。
