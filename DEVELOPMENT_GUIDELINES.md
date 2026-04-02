# DEVELOPMENT_GUIDELINES.md

## 1. 文档职责
- 本文件是项目「一起 / Together」的唯一工程规范主文档。
- 负责：技术约束、架构原则、数据策略、工程组织、测试与验证要求。
- 不负责：产品范围与页面需求；这些以 `PRODUCT_SPEC.md` 为准。

## 2. 技术约束
- 平台：iPhone only。
- 技术：SwiftUI 为主；仅在 SwiftUI 无法合理实现时，局部使用 UIKit。
- 环境：Xcode 26.2，Swift，iOS 18+。
- 当前阶段：本地数据 + mock 登录 + 可替换服务层。
- 长期方案：CloudKit；当前实现不得阻断未来接入。
- 页面必须支持 SwiftUI Preview 和 mock data。
- 开发时就考虑深色模式、Reduce Motion 和安全区域。

## 3. 代码与 API 约束
- 优先使用 Apple 原生 API 和系统能力，谨慎引入第三方库。
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

### 3.2 SwiftData 与测试约束
- 只要当前模块使用 SwiftData，就优先沿用 SwiftData，不要随手回退到 Core Data。
- 若 SwiftData 最终接 CloudKit：不要使用 `@Attribute(.unique)`。
- 若 SwiftData 最终接 CloudKit：模型属性必须提供默认值或声明为 optional。
- 若 SwiftData 最终接 CloudKit：关系属性默认按 CloudKit 兼容性处理，改动前先确认 optional 与数据迁移影响。
- 单元测试优先于 UI 测试；只有核心逻辑无法通过单测覆盖时，才补 UI 测试。
- 若项目已采用 Swift Testing，新测试优先使用 Swift Testing；UI 测试仍按 XCTest 体系处理。

### 3.3 工程卫生
- 若仓库启用了 `Localizable.xcstrings`，新增用户可见文案优先走字符串目录，不要把文案硬编码散落在页面中。
- 若仓库已安装 SwiftLint，提交前必须保证没有新增 warning 或 error。
- 若 Xcode MCP 可用，优先使用其构建、预览、问题列表、文档查询能力。

## 4. 架构原则
- 业务逻辑与 View 分离。
- 状态机不得直接散落在 View 中。
- 服务层先协议化，再实现具体服务。
- 数据模型、状态流转、页面路由必须清晰可追踪。
- 新增模型应优先面向 `Task / List / Project / Calendar / Space` 抽象。
- 当前代码里旧的 `PairSpace / relationshipID / Invite` 命名属于历史包袱；新开发不要继续扩散这些语义。

## 5. 空间与数据策略
- 产品层当前默认只暴露单人工作空间，不对用户强调复杂 Space 概念。
- 技术层允许预留：
  - `SingleSpace`
  - `PairSpace`
  - `MultiSpace`
- V1 可以只让 `SingleSpace` 真正跑通。
- V2 再把双人协作挂到 `PairSpace` 上，而不是反过来把单人模式当试用态。

## 6. 工程组织建议
- `App/`：App 入口、路由、会话、依赖容器
- `Domain/`：实体、枚举、协议、状态机
- `Services/`：repository、本地存储、通知、认证
- `Features/`：Today、Lists、Projects、Calendar、Profile、扩展模块
- `Shared/`：设计 token、基础组件、动画工具
- `PreviewContent/`：mock data、preview fixture

## 7. 默认开发顺序
1. 文档与边界统一
2. Task / List / Project / Space 模型与状态机
3. 服务协议与本地 mock / 持久化
4. Today 首页主链路
5. 清单与项目
6. 日历与时间视图
7. 创建入口、详情页、搜索筛选
8. 设置与提醒
9. 双人扩展与附加模块

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
- 首页 / 日历 / 项目关键页面必须有 Preview + mock data。
- 只要涉及动效状态切换，就至少做一次真机构建或 Preview 回归。

## 10. 禁止事项
- 禁止继续把绑定流、邀请流、双人决策流当首版主目标。
- 禁止把当前产品重新做成情侣运营或关系运营工具。
- 禁止把多人模式提前做成当前功能。
- 禁止为了快速交付把核心状态写死在 View 层。
- 禁止无理由引入大型第三方状态管理或动画库。
