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
- 只要实现自定义动画，必须由单一交互会话和显式状态驱动；同一次焦点转场的几何、裁切、阴影、内容揭示和背景景深服从一条主视觉进度，不得用独立延迟、多个互不知情的完成回调或临时视图状态拼接。
- 动画关键路径禁止同步保存、重查询、重排序或无关重布局；创建提交的持久化是明确事务边界，只有保存成功后才允许按冻结落点执行一次受协调的列表让位或必要定位。
- 自定义动画默认优先 SwiftUI 原生 API；仅当原生能力无法合理实现时，才局部补充 UIKit。
- 首页焦点动效采用窄混合边界：SwiftUI 持有真实时间线、任务行、编辑内容、业务状态和持久化；根控制器或窗口拥有的 UIKit 瞬态呈现 Host 只在交互会话期间持有稳定背景平面、背景命中屏障、唯一前景任务容器、来源与落点几何以及可中断主进度。前景 SwiftUI 内容通过 `UIHostingController` 承载；不得让 SwiftUI 和 UIKit 同时修改同一受 SwiftUI 布局管理视图的 Frame，也不得让 UIKit 接管长期页面或业务状态。
- 自定义底部 Dock 必须始终挂载并保留固定安全区高度，但 `+` 只发送创建意图，不是任务表面的视觉来源；顶部系统 Toolbar 保留导航职责，也不作为独立 Morph 参与者。焦点期间 Toolbar、列表和 Dock 只作为同一稳定背景 Host 的组成部分。来源、最终落点和可见所有权交接必须由同一根会话管理，任意呈现帧只允许一个任务身份可见；详情关闭与创建落地共用可中断的 `1 -> 0` 任务表面语法，持久化提交是唯一锁定冲突交互的阶段。

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
- 若使用 Foundation Models 做结构化解析，必须检查可用性，使用结构化输出，并提供本地规则 fallback。

### 3.4 工程卫生
- 若仓库启用了 `Localizable.xcstrings`，新增用户可见文案优先走字符串目录，不要把文案硬编码散落在页面中。
- 若仓库已安装 SwiftLint，提交前必须保证没有新增 warning 或 error。
- 若 Xcode MCP 可用，优先使用其构建、预览、问题列表、文档查询能力。

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

## 10. 禁止事项
- 禁止继续把绑定流、邀请流、双人决策流当首版主目标。
- 禁止把当前产品重新做成情侣运营或关系运营工具。
- 禁止把多人模式提前做成当前功能。
- 禁止继续新增 Supabase / RevenueCat / Paywall / PremiumGate 依赖。
- 禁止把 OCR 识别结果未经用户确认直接写入任务或项目。
- 禁止为了快速交付把核心状态写死在 View 层。
- 禁止无理由引入大型第三方状态管理或动画库。
