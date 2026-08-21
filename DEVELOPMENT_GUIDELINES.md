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
- 只要实现自定义动画，必须由单一交互会话和显式状态驱动。已有任务详情将真实行高、紧凑内容高度、身份组 X/Y/尺度、交叉淡变与详情级联时间轴拆成独立 Keyframe track：身份组在约 `460ms` 内沿内部轨迹 `(0, 0) -> (-7pt, +14pt) -> (-16pt, -12pt)` 的连续曲线直接到达约 `1.12` 视觉尺度，Y 轴端点补偿展开态新增的 `14pt` 顶部真实间距，使屏幕下潜 / 上升接近等幅；不追加 Overshoot、Spring 或终点回落。详情视觉行从共享时间轴派生 `(+14pt, +24pt) -> (+5pt, +9pt) -> (0, 0)` 曲线和透明度，首行最早约 `480ms` 落定，禁止早于身份组，整组最迟约 `700ms` 完成。收起使用约 `320ms` 的精确反向关键帧，详情级联直接从同一 `layoutProgress` 派生，避免独立时间轴重置导致内容瞬隐；从底部属性开始逆序退出，真实行高不得提前归零。收起结束由单一、可取消且校验会话 token 的生命周期任务驱动，其等待直接复用共享时长常量，不观察动画帧阈值。禁止用多个 `Task.sleep` 拼接视觉阶段，禁止把逐帧进度发布到根级 Observation，也禁止用 `CADisplayLink` 或连续高度监听向 SwiftUI 状态逐帧写值。
- 动画关键路径禁止同步保存、重查询、重排序或无关重布局；创建提交的持久化是明确事务边界，只有保存成功后才允许按冻结落点执行一次受协调的列表让位或必要定位。
- 动画技术按效果、稳定性、帧率与可中断性选择，可使用 SwiftUI、UIKit 或 Core Animation。当前列表详情由 SwiftUI `LazyVStack` 持有真实高度，因此优先保持单一 SwiftUI 布局所有权；只有真机 Instruments 证明局部合成仍是瓶颈时，才对明确热点引入 UIKit / Core Animation，不能为技术偏好复制 SwiftUI 文本、控件或任务身份。
- 首页环境粒子使用单个根级 stitchable Metal `colorEffect`，待办 / 定期切换不得创建第二实例。着色器每像素固定只计算四个当前网格单元，禁止恢复参考实现的 `4 × 3 × 3` 邻域搜索；刷新上限为 `60fps`，不得跟随 ProMotion 提升到 `120fps`。持续时间只进入 GPU uniform，不向 Observation 写逐帧状态，不读取滚动 offset，也不得使用 CPU 粒子数组、Canvas 粒子循环、模糊、发光或多级离屏合成。
- 动态背景必须在页面不可见、场景失活、Reduce Motion、低电量及严重 / 临界热状态下暂停持续刷新；停止完成后 `TimelineView` 必须进入 paused。性能降级顺序固定为“四层降三层 → 降低密度 → 降至 30fps”；如真机仍出现可感知卡顿、持续升温或能耗显著上升，默认关闭效果，不以视觉偏好覆盖性能门槛。
- 首页任务流保持不挂载 `.refreshable`；加载与同步继续使用现有 ViewModel 生命周期和显式刷新链路，不在滚动顶部新增竞争手势。
- 已有任务详情完全由 SwiftUI 列表拥有：`TaskMorphContainer` 只改变当前行的真实高度和局部合成属性，不解析或逐帧写入 `UIScrollView.contentOffset`，不主动滚动、不复制任务表面。普通任务行上下外部 inset 统一为约 `4pt`，行内完成框与主体命中区仍至少 `44pt`。活跃区域整体执行约 `1.05` 合成缩放并用上下各 `14pt` 的真实布局间距撑开相邻内容，身份组最终约 `1.12`；前景后方允许绘制不改变布局且无边界的透明渐变亮度场。所有非活跃任务统一使用 `1.45pt` blur 和 `0.49` opacity；稳定任务序号与焦点行的有符号差值只继续派生 scale、offset 和 delay，scale 从相邻 `0.95` 退到远处 `0.87...0.88`。上方保持 `8...24pt` offset、约 `15ms` 初始延迟、每级约 `60ms` 且最多 `260ms`；下方保持 `12...36pt` offset、约 `20ms` 初始延迟、每级约 `75ms`、最多 `340ms` 强化逐行下移。背景任务使用独立的约 `360ms` 单行动画时长，使级间启动差异保持可读；两侧只增强合成传播，不延迟真实 `LazyVStack` 让位，背景波最晚约 `700ms` 完成。日期 / 周期 Header 使用约 `0.5pt` blur、`0.98` scale 和 `0.52` opacity；顶部与底部 Toolbar 保持系统外观，底部项目在详情期只响应首次点按用于保存并收起。所有详情帧均由 `.scaleEffect / .offset / .blur / .opacity` 合成插值，不读取连续 frame、不向 Environment / Observation 发布滚动坐标。底部滚动边界只使用系统 `.scrollEdgeEffectStyle(.soft, for: .bottom)`，不接入详情状态，也不新增逐行几何、清晰度或命中状态。只有当前活跃行可测量紧凑 / 展开文本和详情自然高度；普通行不得长期运行几何测量。详情正文的视觉行高收紧至约 `32pt`，详情首行通过约 `-20pt` 顶部布局回收靠近标题，属性轨道通过约 `-6pt` 顶部布局回收靠近上一行；真实子任务之间保留约 `3pt` 间隔。交互控件继续使用至少 `44pt` 命中视图，局部负 padding 只回收不可见空白，不压缩实际命中视图；待办与定期使用同一静态轴线、统一系统语义填充的属性胶囊和单行横向属性轨道，不因字段不同复制动效状态机。
- 首页底部入口必须由 `NavigationStack` 的系统 `.bottomBar` 持有，只使用原生 `ToolbarItem`、`ToolbarSpacer`、`Menu`、`Button` 与 SF Symbols；不得再用 `safeAreaInset`、自绘材质、圆形背景、阴影或额外几何状态复制 Dock。`+` 不采集全局 Frame，也不承担创建表面身份。创建必须用预分配最终 UUID 的 UI-only Draft 合并进真实 `ScrollView / LazyVStack`：待办临时行位于今天未完成分组顶部，定期临时行位于当前周期未完成区域顶部；数量、统计与 Gauge 继续只读取持久化任务。临时行先以紧凑态建立，再由 `HomeMorphSession` 在下一渲染阶段激活同一个 `TaskMorphContainer` 的 `.expanded`；此时只启动视觉展开，不递增焦点请求。调用方等待共享的 `TaskExpansionMotionTiming` 完成后，必须以当前 session token 调用输入就绪入口；过期 token、保存、放弃或 phase 变化均不得聚焦。标题实际取得焦点后，只等待键盘稳定时间再对稳定 Draft ID 做一次无动画底部对齐，不监听键盘通知或连续几何。保存 / 取消走详情同款 `.compact` 反向路径，不得新增创建 Overlay、独立创建卡、第二套高度测量或动画常量。草稿使用稳定 UUID 和稳定列表 ID；属性编辑只更新 Draft，直到提交后再决定是否迁移。保存到同一 section / index / presentation ID 时在无动画 transaction 中原子替换；发生变化时才进入 relocation 和既有轻量 reveal。背景命中、Toolbar 与任务点击统一调用 dismiss；显式取消单独调用 discard。保存阶段由 phase 拒绝重复意图，失败恢复 `.active + .expanded` 并保留焦点请求、输入与错误。已有任务与创建详情都保持连续列表背景，不使用圆角卡、描边、阴影、屏幕级暗化或全屏 / 几何驱动模糊；非活跃任务统一使用上述固定模糊与透明度，并临时成为“保存并收起”命中层。

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

### 3.5 真机单 App 工作流
- Debug、Release 与 TestFlight 统一使用正式 `com.pigdog.Together` 身份，以及同一正式 Widget、URL Scheme、App Group、CloudKit 容器和 Associated Domains；不创建或引用 `.dev` App。
- 从 Xcode 真机运行 Development 构建会替换同一 Bundle ID 的 TestFlight / App Store 二进制，但保持同一应用与数据身份，适合在一个 App 中兼顾测试和日常使用。
- Development 签名仍可能受 PPQ 在线验证限制；无法完成验证时，唯一安装的 Together 可能暂时不可启动。当前明确接受该约束，不以双 App 隔离规避。

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
- 动态 Metal 背景发布前必须在支持 120Hz 的真机以 Instruments 验证待办静置、长列表滚动、待办 / 定期快速切换、详情 / 创建反复开合、前后台、低电量及热状态降级；记录 Core Animation 帧时间、GPU/CPU 使用与 Energy Log。泛型构建或模拟器结果只证明编译，不代表帧率、温度或续航验收通过。

## 10. 禁止事项
- 禁止继续把绑定流、邀请流、双人决策流当首版主目标。
- 禁止把当前产品重新做成情侣运营或关系运营工具。
- 禁止把多人模式提前做成当前功能。
- 禁止继续新增 Supabase / RevenueCat / Paywall / PremiumGate 依赖。
- 禁止把 OCR 识别结果未经用户确认直接写入任务或项目。
- 禁止为了快速交付把核心状态写死在 View 层。
- 禁止无理由引入大型第三方状态管理或动画库。
