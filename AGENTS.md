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
- 目标：统一产品定位、文档口径、代码方向，减少返工与偏航。

## 2. 当前产品结论
- V1 定位：单人 Todo 效率工具。
- 核心用户：事务密度较高、工作中有持续待办管理需求的个人用户。
- 当前 MVP 主链路：Today 首页、清单、项目、日历、我。
- 当前首页 UI 可继续沿用，默认视为单人模式的 Today 首页，不做推翻式重画。
- V2 差异化：双人模式，通过邀请或分享形成 2 人协作空间，但仍以 Todo 为核心。
- V3 远期方向：多人 Space，仅做底层预留，不写成当前承诺能力。
- 决策、纪念日降级为后续附加模块，不再是首版主功能。
- 动效与交互丝滑度是核心亮点，不是后置装饰。

## 3. 响应原则
- 先给结论，再执行。
- 简单任务直接做；复杂任务先给“目标 / 影响范围 / 方案 / 风险”。
- 不确定时直接问清，不要猜。
- 回复短，但关键信息不能缺。
- 默认只回答用户上一轮刚提出的问题，不重复回顾已经确认或已回答的旧问题；除非新问题明确依赖旧问题，才做最小必要引用。
- 区分事实、推演、开放问题。
- 当已经判断当前方案足够好、无需继续微调时，应直接明确告知用户“当前已足够好，无需再调”；不要为了迎合而机械追加微调建议。
- 当判断当前方向已收敛时，可以直接提出其他更有价值的方向性建议，而不是刻意继续围绕当前细节做建议。

## 4. 首次进入项目必须先读
- `DEVELOPMENT_GUIDELINES.md`
- `DESIGN_GUIDELINES.md`
- 当前 `AGENTS.md`
- `docs/development-progress.md`
- `PRD_正式版_一起.md`
- `页面详细需求清单_一起.md`
- `信息架构与线框说明_一起.md`
- 与本次任务直接相关的 `Features / Models / Services` 文件

如果上述文档缺失或过期，先补齐或更新，再改代码。

## 5. 开发总原则
- 先统一文档与边界，再改实现。
- 优先修改现有文件；仅在缺失关键文档或关键模块时新建文件。
- 所有实现优先简单、清晰、可维护、可被 AI 理解。
- 不做过度抽象，不引入无必要复杂架构。
- 业务逻辑必须和 View 分离。
- 服务层先协议化，再实现具体服务。
- 不允许把业务状态机直接散落在 View 里。

## 6. 产品硬边界
- 当前首版不是情侣产品优先，也不是双人协作产品优先。
- 当前首版必须先把单人 Todo 主链路做成真实可用的效率工具。
- 双人模式不是当前 MVP 主轴；没有明确需求时，不要继续扩绑定流、邀请流、双人决策流。
- 多人模式只允许在数据模型和架构层做轻量预留，禁止写成当前规划功能。
- 决策、纪念日、关系运营能力可以保留为后续附加模块，但不得挤占单人 Todo 主链路优先级。

## 7. 技术与工程约束
- 平台：iPhone only。
- 技术：SwiftUI 为主；仅在必要时局部使用 UIKit。
- 当前阶段：本地数据 + mock 登录 + 可替换服务层。
- 长期后端方向：CloudKit；当前实现不得阻断未来接入。
- 页面必须支持 mock data 和 SwiftUI Preview。
- 开发时就考虑深色模式、Reduce Motion 和安全区域。
- 优先使用 Apple 原生 API 和系统能力，谨慎引入第三方库。
- Swift 代码默认按 Swift 6.2+ 的现代写法执行；只要系统或项目条件允许，优先 `async/await`，不要继续新增 closure-first 异步接口。
- 默认假设严格并发检查会持续增强；共享状态优先使用 `@Observable`，并优先结合 `@State`、`@Bindable`、`@Environment` 传递。
- 若项目未启用 Main Actor 默认隔离，`@Observable` 类型默认补 `@MainActor`，避免状态更新线程语义模糊。
- 除非处于低层兼容或历史包袱场景，不新增 `ObservableObject`、`@Published`、`@StateObject`、`@ObservedObject`、`@EnvironmentObject`。
- 不继续新增 `DispatchQueue.main.async` 这类旧式主线程调度；需要切回主线程时优先使用现代 Swift Concurrency。
- 除非属于不可恢复错误，不允许新增 force unwrap 和 force try。
- 优先使用现代 Foundation API 与 `FormatStyle`；不要继续新增 `DateFormatter`、`NumberFormatter`、`MeasurementFormatter` 这类旧格式化器作为常规方案。
- 字符串、数字、日期格式化默认使用 Swift 原生格式化能力；禁止继续新增 `String(format:)` 这类 C 风格格式化。
- 文本搜索若面向用户输入，优先使用 `localizedStandardContains()`，不要直接用 `contains()` 替代。
- 文件路径与 URL 处理优先使用 `URL.documentsDirectory`、`appending(path:)` 等现代 API。

### 7.1 SwiftUI 具体规则
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

### 7.2 SwiftData 与测试规则
- 只要当前模块使用 SwiftData，就优先沿用 SwiftData，不要随手回退到 Core Data 方案。
- 若 SwiftData 最终接 CloudKit：不要使用 `@Attribute(.unique)`。
- 若 SwiftData 最终接 CloudKit：模型属性必须提供默认值或声明为 optional。
- 若 SwiftData 最终接 CloudKit：关系属性默认按 CloudKit 兼容性处理，改动前先确认 optional 与数据迁移影响。
- 单元测试优先于 UI 测试；只有核心逻辑无法通过单测覆盖时，才补 UI 测试。
- 若项目已采用 Swift Testing，新测试优先使用 Swift Testing；UI 测试仍按 XCTest 体系处理。

### 7.3 工具与工程卫生
- 若仓库启用了 `Localizable.xcstrings`，新增用户可见文案优先走字符串目录，不要把文案硬编码散落在页面中。
- 若仓库已安装 SwiftLint，提交前必须保证没有新增 warning 或 error。
- 若 Xcode MCP 可用，优先使用其构建、预览、问题列表、文档查询能力，而不是退回到更弱的通用手段。

## 8. UI 与动效规则
- 视觉方向：现代简洁、黑白粉、克制、轻生活感，但表达应服务于效率工具，不做廉价情侣风。
- 继续沿用当前首页 UI 的骨架与气质，不做本轮大改版。
- 任何新的 UI 页面、UI 重构、交互动效、转场、组件视觉样式调整，在执行实现前必须先征求用户意见。
- 征求意见时，先让用户明确期望的 UI 风格、交互逻辑、参考方向；再结合当前主流案例给出建议；确认方案后才能开始实现。
- 未经用户确认，不得擅自生成新的页面样式、交互逻辑或动画表现。
- 原生 iOS 组件优先采用 iOS 26 液态玻璃原生组件与样式；优先使用系统提供的 `glassEffect`、`GlassEffectContainer`、原生 glass button style，并提供旧系统 fallback。
- 动效优先使用 SwiftUI 原生 API 和系统级过渡。
- 处理 UI 动画时，必须先拆清“布局 / 内容 / 动画”三层职责：先保证静态布局正确、测量与渲染一致，再给内容和容器分别加动画；禁止用动画去补结构或测量问题。
- 动效必须服务任务完成、列表层级切换、周/月视图切换、主按钮展开、详情展开/收起、筛选排序切换。
- 禁止堆砌式、廉价、掉帧的动画；禁止在主线程做重计算。

## 9. 默认执行顺序
1. 读文档与相关代码
2. 明确影响范围
3. 先模型与状态
4. 再服务与数据流
5. 再 Today / 首页
6. 再清单 / 项目 / 日历
7. 再详情、创建入口、筛选与排序
8. 再我页与设置
9. 最后处理双人扩展与附加模块

## 10. 复杂任务输出模板
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

## 11. 禁止事项
- 禁止跳过文档直接写代码。
- 禁止继续按旧的“双人优先 / 情侣优先”逻辑新增功能。
- 禁止擅自新增多人模式实现。
- 禁止为了省事把逻辑硬编码进单个页面。
- 禁止跨模块大改。
- 禁止生成与当前任务无关的大段样板代码。
- 禁止为了视觉效果侵入安全区域或牺牲交互可用性。

## 12. 文件与命名规则
- 命名优先业务语义，不要泛化成 task / manager 式命名。
- 枚举、状态、常量集中定义，避免 magic number。
- 单页面拆为主视图 + 子组件。
- 单个 ViewModel 不承担多个业务域。
- Mock、Preview、Protocol 命名必须统一且可搜索。
- 新增模型和服务命名优先面向 `Task / List / Project / Calendar / Space`，不要继续扩散旧的 `Pair` 语义。

## 13. 提交与修改策略
- 小步修改，小步验证。
- 一次提交只解决一个清晰问题。
- 修改前说明目的；修改后说明影响。
- 若任务只要求评估，不要直接改代码。
- 提交前保证项目可编译、关键 Preview 可运行。
- 若用户要求归档当前对话，必须先更新 `docs/development-progress.md`，再执行归档。
- 更新开发进度文档时，只记录归档前最终成立的结果；中途试错、撤回方案、来回修改过程不得写入。
- 若本轮存在重要功能新增、Bug 修复、UI/交互完善且用户明确归档确认，应将其追加到 `docs/development-progress.md` 的“已归档重要节点”。

## 14. 当存在不确定性时
遇到以下情况必须先问：
- 需求与最新文档冲突
- 影响当前 MVP 信息架构
- 需要改动核心数据模型或状态机
- 需要新增第三方依赖
- 需要删除或迁移用户数据
- 需要把后续能力提前变成当前承诺

## 15. token 控制原则
- 回复优先短格式。
- 只展开与当前任务直接相关的信息。
- 不重复描述已知背景。
- 除非用户要求，不一次性展开过多远期方案。

## 16. Skill 调用规则
- 目标：在合适的时机，自动选择并调用最匹配的 skill，而不是依赖临时判断或遗忘。
- 规则：只要任务明显命中某个 skill 的职责边界，就应优先调用对应 skill，再开始实现或分析。
- 若同一任务同时命中多个 skill，优先顺序为：流程类 skill -> 领域审查类 skill -> 实现类 skill。

### 16.1 默认入口
- 每次进入新任务，优先按 `using-superpowers` 的原则检查是否存在适配 skill。
- 对于小任务，如果没有明显命中任何 skill，可直接执行；但只要命中概率足够高，就不应跳过。

### 16.2 当前仓库保留 skill 的触发场景
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

### 16.3 组合调用规则
- SwiftUI 页面 + 并发状态问题：先 `swiftui-pro`，再 `swift-concurrency-pro`。
- SwiftUI 页面 + SwiftData 数据流：先 `swiftui-pro`，再 `swiftdata-pro`。
- SwiftData + CloudKit 约束：直接调用 `swiftdata-pro`。
- 测试失败或需要补测试：先 `systematic-debugging` 判断问题，再按需要调用 `swift-testing-pro`。
- 动效问题：先在 `ios-animation-codex-skill` 与 `ios-fluid-animation` 中选最贴近的一个；若同时涉及设计意图和性能落地，可组合使用。
- 深色模式问题：直接调用 `global-dark-mode-delivery`，不要把它降级成普通样式修补。
- 超过一次会话、里程碑较多、容易上下文丢失的任务：尽早调用 `long-horizon-codex`，不要等到上下文混乱后再补文档。

### 16.4 禁止事项
- 不要在明显命中 skill 的情况下绕过 skill 直接凭记忆执行。
- 不要同时拉起多个职责高度重叠的 skill 造成规则冲突。
- 不要把 `long-horizon-codex` 用于一次性小修。
- 不要在未完成根因分析前跳过 `systematic-debugging` 直接修 bug。
