# Today 焦点卡片窄混合架构实施计划

状态：历史实施草案，已由 ADR-0020 的统一首页焦点架构取代；不得作为当前运行时实现依据。

历史依据：`CONTEXT.md` 与 ADR-0019。当前实现、契约与验收以 ADR-0020、三份主文档和现行代码为准。ADR-0020 明确创建卡不必从 Dock `+` 形变，四类焦点对象共用唯一根级 Session、Host 与落地语法。

## 1. 目标

在不重写任务业务、编辑器和时间线的前提下，替换当前“SwiftUI Seed 运输 + 列表局部焦点表面 + 多段完成回调”架构，实现：

- 点击任务行后，同一任务身份从真实来源原位抬升并展开为详情卡，关闭严格返回。
- 点击自定义 Dock `+` 后，同一创建表面直接展开到稳定、键盘安全的创建焦点位，不经过列表紧凑停靠点。
- 创建成功后，同一表面直接进入最终任务行，列表在提交后才让出空间。
- 顶部 Toolbar、时间线和底部 Dock 视觉上形成一个统一景深背景；状态栏与键盘保持系统实时呈现。
- 打开、关闭和放弃支持从当前可见进度与速度反向；创建提交是唯一不可逆阶段。
- 全程没有双重任务身份、空白卡壳、背景穿透点击、键盘遮挡和多段动画停顿。

## 2. 非目标

- 不完整重写 UIKit 页面、时间线或任务编辑器。
- 不修改任务、子任务、提醒、SwiftData 或 CloudKit schema。
- 不恢复模板、待办、定期的创建类型切换或任何模板数据。
- 不把系统顶部 Toolbar 变成自定义 Morph 来源。
- 不使用系统 Sheet、导航 Zoom 或 `matchedGeometryEffect` 作为首页焦点主转场。
- 不保留旧动效作为运行时 Feature Flag、兼容分支或 fallback。
- 不在动画过程中驱动业务 IO、全量 reload 或逐帧 SwiftUI Observation 更新。

## 3. 不可破坏的不变量

1. 同一时刻只有一个首页焦点交互会话。
2. 任意呈现帧只有一个可见任务身份；来源、前景表面和落点不得交叉显示。
3. SwiftUI 持有业务真相与真实页面；UIKit 只持有瞬态呈现。
4. UIKit 只动画自己拥有的子视图，不直接修改 SwiftUI 布局管理的 Representable Frame。
5. 一次可逆转场只有一条主视觉进度；边界、圆角、阴影、内容揭示和背景景深由同一协调器推进。
6. 编辑期间背景时间线不滚动、不预留最终空位、不跟随草稿排序变化。
7. 创建保存成功前不显示任务行或落点空位；保存失败不离开创建焦点位。
8. 背景点击只产生关闭或放弃意图，不向下命中另一任务。
9. 系统状态栏、键盘和系统属性 Sheet 不进入冻结或缩放背景。
10. Reduce Motion 与 Reduce Transparency 是同一状态机的视觉策略，不另建旁路流程。

## 4. 最终所有权结构

| 层级 | 所有者 | 职责 |
| --- | --- | --- |
| 真实应用背景 | SwiftUI `HomeRootContent` | NavigationStack、顶部 Toolbar、时间线、自定义 Dock、业务交互 |
| 持久根容器 | UIKit `HomeRootContainerController` | 持有背景 Hosting Controller 与焦点呈现 Controller，提供同一稳定坐标空间 |
| 景深与命中层 | UIKit `HomeFocusPresentationController` | 背景缩放、真实模糊、暗化、背景点击屏障 |
| 唯一前景表面 | UIKit 容器 + SwiftUI `UIHostingController` | 卡片几何、裁切、圆角、阴影、身份内容与编辑内容 |
| 会话协调 | `HomeFocusPresentationCoordinator` | 生命周期、冻结几何、主 Animator、反向、原子交接、Recovery |
| 业务草稿与保存 | `HomeViewModel` | 详情 Draft、创建 Session、持久化、错误与最终落点描述 |

`HomeRootContainerController` 持久存在，不在用户点按时临时寻找窗口或重新建立坐标系。它由一个 `UIViewControllerRepresentable` 放入 SwiftUI App 根部；SwiftUI 只决定外层 Controller 的布局，UIKit 在其内部合法管理并动画背景与前景两个子控制器。

## 5. 计划新增组件

建议放在 `Together/Features/Home/FocusPresentation/`：

### 5.1 `HomeFocusSession.swift`

纯状态与意图模型，不导入 UIKit 动画实现。

- `HomeFocusSubject`
  - `.task(itemID:)`
  - `.creation(sessionID:)`
- `HomeFocusPhase`
  - `.idle`
  - `.preparing`
  - `.transitioningIn`
  - `.focused`
  - `.transitioningOut`
  - `.saving`
  - `.preparingLanding`
  - `.landing`
  - `.recovering`
- `HomeFocusIntent`
  - 打开任务、创建、关闭、放弃、提交、反向、场景失活。
- 会话 ID 与 revision 阻止旧回调修改新会话。
- 状态只发布离散生命周期；逐帧进度只留在 UIKit Animator，避免 SwiftUI 每帧重算。

### 5.2 `HomeFocusGeometryRegistry.swift`

- 以窗口统一坐标记录可见任务行、Dock `+`、时间线 viewport 与安全区域。
- 只接受有限、非空、与当前 window 匹配的 Frame。
- 点按时同步读取最后有效来源，开始转场后冻结。
- 活跃会话中普通几何更新不得重定向动画。
- 尺寸级变化、旋转、Scene 失活走显式 Recovery，不静默修改目标。
- 提供纯函数计算：详情目标、创建焦点位、键盘最小修正、落点可见性。

### 5.3 `HomeRootContainer.swift`

- `HomeRootContainerController` 持有：
  - `UIHostingController<HomeRootContent>` 背景子控制器；
  - `HomeFocusPresentationController` 前景子控制器。
- 保持系统顶部 Toolbar 与自定义 Dock 都在背景 Hosting Controller 内。
- 不改变外层 Representable 的 Frame / bounds / transform。
- 环境值、`AppContext`、色彩模式和动态字体显式传入 `HomeRootContent`。
- 现有根层 Sheet、PhotosPicker、相机与导航路径保持原语义；焦点卡内部触发的系统 Sheet 从前景 Hosting Controller 正常呈现。

### 5.4 `HomeFocusPresentationController.swift`

固定图层顺序：

1. 透明背景命中屏障；
2. `UIVisualEffectView` 景深层；
3. 独立暗化层；
4. 唯一前景表面容器；
5. 必要的系统属性呈现锚点。

要求：

- `UIVisualEffectView.alpha` 始终为 1，通过 `effect` 插值建立和解除模糊。
- 背景 Hosting Controller 的缩放、模糊和暗化由同一主 Animator 推进。
- 前景表面使用实体背景、连续圆角、描边和阴影；阴影路径随边界同步。
- 表面内部预先布局最终内容，通过容器 bounds / mask 揭示，避免 SwiftUI 每帧重排。
- 前景 Hosting Controller 在转场开始前完成布局，但只允许一个可见身份。
- 完成后清理 Animator、Hosting Controller、屏障、隐藏来源和临时可访问性状态。

### 5.5 `HomeFocusPresentationCoordinator.swift`

- `@MainActor` 单一会话协调器。
- 持有唯一 `UIViewPropertyAnimator`；支持 pause、reverse、continue 和 Recovery。
- 管理来源隐藏、前景建立、背景退让和端点原子交接。
- 打开途中再次点击当前对象或背景：从 presentation 进度和当前速度反向。
- 详情活跃时点击其他任务：只关闭当前详情，不缓存或自动打开目标。
- 创建编辑期间其他任务不接受焦点意图。
- 创建 `.saving` / `.landing` 阶段锁定重复提交与反向；失败恢复 `.focused`。
- Animator completion 必须校验 session ID、revision 与目标端点。
- Scene 失活、来源删除、尺寸变化和 Hosting 失败均进入确定 Recovery，不能残留隐藏来源或命中屏障。

### 5.6 `HomeFocusSurfaceView.swift`

统一 SwiftUI 前景内容入口：

- 任务详情复用 `TaskSharedContent`、`HomeInlineTaskDetailCard` 与现有编辑 Draft。
- 创建复用 `HomeTaskCreationCard`，但分离“视觉已挂载”和“允许输入”。
- 任务身份区在紧凑态与展开态使用相同排版和内容列。
- 详情内容预挂载在卡片内部，由外层边界揭示，不再使用独立 `.transition` 延迟入场。
- 创建起点的 `+` 与标题内容位于同一实体表面内；`+` 收束、标题清晰度建立和表面生长服从主进度。
- 只有 `.focused` 才允许 TextField、按钮和内部滚动命中。

### 5.7 `HomeFocusMotionProfile.swift`

- 集中定义正常、Reduce Motion、Reduce Transparency 三种视觉策略。
- 默认使用近临界阻尼、无明显过冲的实体落定感。
- 背景不回弹；详情与创建使用同一景深节奏。
- 参数先作为集中 token，最终值必须由真机录屏和 Instruments 校准，不能散落在 View 中。
- 创建提交是非交互阶段；SwiftUI 列表让位与 UIKit 前景落点使用同一 Animation 描述和同一主线程提交时刻。

## 6. 详情展开与收起流程

### 6.1 打开

1. 任务行按下当帧显示极轻压实反馈。
2. 抬手后从 Registry 读取并冻结来源 Frame。
3. ViewModel 建立详情 Draft，但不触发列表 reload 或滚动。
4. 前景 Hosting 内容在来源坐标完成最终布局测量。
5. 同一提交周期内：前景身份变为可见，真实来源身份隐藏；来源外层仍保留紧凑行高度。
6. 主 Animator 从进度 0 推进到 1：
   - 表面由来源边界轻微横向扩展并主要向下生长；
   - 身份区保持坐标、字号和不透明度稳定；
   - 详情内容被边界揭示；
   - 背景整体缩小、真实模糊和暗化；
   - 背景命中立即被屏障接管。
7. 到达稳定端点后才开启编辑、内部滚动和属性操作。

### 6.2 关闭

1. 当前卡片、背景点击、重复点击或 VoiceOver Escape 发出关闭意图。
2. 详情 Draft 保存成功后从当前 presentation 状态反向；失败保持焦点卡并展示错误。
3. 详情内容随边界收敛，背景同步恢复。
4. 进度回到 0 时原子显示真实来源身份并移除前景表面。
5. 清理会话；本次背景点击不得继续传给下层任务。

## 7. 创建进入与放弃流程

### 7.1 进入

1. Dock `+` 按下当帧显示极轻压实反馈。
2. 抬手后立即分配最终任务 UUID，冻结 `+` 来源 Frame。
3. 创建焦点位由容器安全区域与设计高度计算，不依赖草稿最终排序位置。
4. 同一提交周期内由前景表面接管 `+` 像素，真实按钮只隐藏视觉，Dock 高度不变。
5. 主 Animator 将同一实体表面从圆形按钮直接变形成创建卡；不创建列表占位，不停靠紧凑任务行。
6. 卡片到达稳定焦点位后才允许标题输入并请求键盘。
7. 键盘若将遮挡卡片，只按键盘系统节奏执行最小必要垂直修正；不重新选点、不滚动背景。

### 7.2 放弃

1. 清除前景输入焦点，与键盘下沉同一时刻启动主 Animator 反向。
2. 编辑内容随边界收敛，表面返回 `+`；背景同步恢复。
3. 到达来源后原子显示真实 `+`，再销毁未持久化 Session。
4. 不插入任务行、不显示中间状态、不保留草稿。

## 8. 创建提交与列表接纳

1. 用户提交后进入 `.saving`，冻结任务 UUID、Draft 和排序语义，禁止重复触发。
2. 卡片保持焦点端点；保存成功前不创建列表空位、不启动回程。
3. `HomeViewModel.commitTaskCreation()` 调整为返回可测试的提交结果与 `HomeTaskLandingDescriptor`，描述 section、排序位置和任务 ID；不由 View 猜测落点。
4. 保存失败：恢复 `.focused`，保留全部输入、键盘策略和错误状态。
5. 保存成功：
   - 时间线加入仅用于接纳的无身份落点占位；
   - 若落点不可见，在背景仍深度退让时执行一次连续定位；
   - 邻近任务按统一 Motion Profile 让出紧凑行高度；
   - 同一前景表面同步收束并进入该空位；
   - 键盘下沉与卡片运动同时开始。
6. 到达后原子将可见身份交给真实任务行，再解除背景景深、移除占位和创建 Session。
7. 普通 `insertedListItemMotion` 不得再次作用于该任务，避免二次插入动画。

## 9. 背景平面与 Toolbar

- 顶部系统 Toolbar 保留现有导航、模式选择和头像行为。
- 焦点期间不再对 ToolbarItem 分别调用 SwiftUI 景深 modifier；整个背景 Hosting Controller 与 UIKit 模糊层共同表达景深。
- 自定义底部 Dock 保持挂载、安全区高度和原生 `Button` / `Menu` 语义。
- Dock 不独立淡出或位移；其视觉随背景统一退让。
- 创建来源 `+` 在前景接管后原子隐藏，OCR 按钮仍留在背景但停止命中。
- 背景屏障覆盖所有应用内容；点击任何背景位置只关闭当前对象。
- 状态栏与系统键盘不缩放、不冻结、不纳入模糊快照。

## 10. 无障碍与输入

### Reduce Motion

- 不执行 `+` 跨屏移动。
- 详情只做来源位置上的短高度变化。
- 创建卡直接在安全焦点位建立。
- 背景只暗化，不缩放、不动态模糊。
- 提交只保留短促列表让位与清晰度转换。

### Reduce Transparency

- 不建立动态 Blur Effect。
- 使用更实暗化与清晰的前景实体边界保持层级。

### VoiceOver / Dynamic Type

- 活跃会话期间背景整层 accessibility hidden，前景卡成为唯一可访问区域。
- 保留 VoiceOver Escape。
- 前景建立和销毁时恢复合理焦点，不跳到隐藏来源。
- 最大动态字体下重新计算卡片高度；超过安全高度后只让卡片正文内部滚动。
- 所有操作命中至少 44pt。

### 键盘与中文输入

- 创建卡稳定后才建立第一响应者。
- 使用系统键盘布局与动画信息做最小修正，不用固定 delay 猜测。
- 提交前继续使用现有中文 IME 可见文本快照策略，验证微信输入法 marked text。
- 提交、放弃时卡片返回与键盘下沉同时启动，不等待键盘完全消失。

## 11. 现有文件修改范围

### `Together/App/AppRootView.swift`

- 拆出 `HomeRootContent`。
- 接入持久 `HomeRootContainer`。
- 删除根层 SwiftUI `taskCreationSeedOverlay`、运输动画和 `Task.sleep(120ms)` 目标稳定逻辑。
- 顶部 Toolbar 删除逐项 `focusDepthEffect`。
- 保留导航、OCR、Profile、Sheet 和 Dock 路由。

### `Together/App/HomeBottomDock.swift`

- 保留自定义 Dock 与原生语义。
- 将 `+` Frame 报告接入统一 Geometry Registry。
- 增加当帧按压反馈和会话驱动的原子视觉隐藏；不再独立执行退场动画。

### `Together/Features/Home/HomeView.swift`

- 移除局部 `activeFocusSurface`、详情/创建卡 ZStack、`FocusDepthEffect`、创建编辑期动态占位和自动 `scrollTo(sessionID)`。
- 真实任务行只负责 Frame 报告、来源占位和原子身份隐藏。
- 增加提交成功后的落点占位与一次性可视定位。
- 背景点击交给 UIKit 屏障，不再叠加多个 SwiftUI `onTapGesture`。
- 保留真实时间线、分组、完成、滑动、菜单和业务绑定。

### `Together/Features/Home/HomeViewModel.swift`

- 保留 `HomeTaskCreationSession` 的 UUID、Draft、保存失败恢复。
- 编辑期间不把创建 Session 插入 `activeTimelineSections`，不参与实时分组和排序。
- 提交成功返回 `HomeTaskLandingDescriptor`，冻结最终 section / index。
- 真实任务行在前景交接完成前保持身份隐藏，交接后再结束创建 Session。

### `HomeTaskCreationCard.swift` / `HomeInlineTaskDetailCard.swift` / `TaskSharedContent.swift`

- 适配统一 `HomeFocusSurfaceView`。
- 去掉与主卡片几何竞争的局部 `.transition` 和独立动画。
- 分离 mounted、revealed、interactive、focused 四种语义，避免挂载即弹键盘。
- 保留输入、属性、子任务和无障碍业务语义。

### 删除

- `Together/Features/Home/HomeInteractionMotionState.swift`
- `Together/Core/DesignSystem/FocusDepthEffect.swift`
- 对应旧状态机测试、Seed 运输测试和不再使用的 helper。

项目使用 File System Synchronized Groups，新 Swift 文件通常无需手工添加 PBXFileReference；仍需检查 target membership 与测试编译。

## 12. 实施阶段与 Review Gate

### 阶段 A：建立可测试会话与根容器

- 先写新状态机、Geometry 纯函数和失败测试。
- 接入持久根容器与空的前景 Controller，确认 Navigation、Sheet、Toolbar、Dock、安全区和环境值无回归。
- Gate：主 App build、现有测试、内存释放检查通过；尚不切换真实动效。

### 阶段 B：迁移普通任务详情

- 接入任务行 Frame、唯一前景 Hosting、来源隐藏、统一背景和可逆 Animator。
- 完成背景点击、重复点击、另一任务点击、保存失败和 Scene Recovery。
- Gate：删除旧详情局部焦点实现后，详情路径 build/test/真机验收通过。

### 阶段 C：迁移创建进入与放弃

- 接入 Dock `+` 来源、创建焦点位、内容揭示和键盘协调。
- 删除 Seed 紧凑停靠与编辑期列表占位。
- Gate：创建/放弃、键盘、安全区、中文输入、快速反向无 P0/P1/P2。

### 阶段 D：实现保存后列表接纳

- 增加 Landing Descriptor、提交后占位、邻行让位、不可见落点定位和原子交接。
- 禁止同一任务再次播放普通 inserted-row 动画。
- Gate：保存成功、失败、不同日期、紧急排序、首尾落点和屏外落点全部通过。

### 阶段 E：删除旧架构并完成性能验收

- 删除旧状态机、FocusDepthEffect、Seed Overlay、旧测试和失效文档注释。
- 全量残留搜索、build、test、真机与 Instruments。
- 不保留运行时兼容层；若阶段失败，通过 Git 回退整组变更，而不是在产品中维持双架构。

## 13. 自动化测试计划

### 单元测试

- 单一会话与单一可见所有权。
- 打开 / 关闭中途反向保持 session 与 revision。
- 旧 completion 不得关闭新会话。
- 点击其他任务只关闭当前对象。
- 创建放弃严格回到来源且不持久化。
- 保存失败保持 UUID、Draft、焦点和错误。
- 保存成功只在提交后建立落点。
- 可见 / 不可见落点策略与一次性定位。
- 来源 Frame 失效、任务外部删除、Scene 失活与 Recovery。
- Reduce Motion / Transparency 状态路径。
- 键盘最小修正、安全区和超高内容内部滚动计算。

### UI / 集成测试

- 任务列表顶部、中部、底部任务展开与关闭。
- 快速重复点按、打开途中关闭、关闭途中反向。
- 详情活跃时点击背景和另一任务均不得误开目标。
- `+` 进入创建卡、放弃返回、提交到当前可见落点。
- 修改日期 / 时间 / 紧急后提交到不同 section 或屏外落点。
- 保存失败后全部输入仍存在。
- 键盘出现、切换输入区域、收起、再次出现。
- 最大 Dynamic Type、深色模式、VoiceOver、Reduce Motion、Reduce Transparency。
- 微信输入法连续组合输入后直接提交。
- 系统日期 / 时间 Sheet 从前景 Host 正常呈现并返回。

## 14. 性能与视觉验收

- 使用 60fps 录屏按关键转场加密取帧，检查每帧实体连续性。
- 在 ProMotion 真机使用 Core Animation / Instruments 检查 hitch、主线程、离屏渲染和 Blur 成本。
- 动画期间不得出现逐帧 SwiftUI Observation 广播、同步存储、全量 reload 或反复 Geometry 测量。
- 检查 Host、Animator、UIHostingController、键盘观察与 Frame Registry 无泄漏。
- 光栅化或快照只能在 Instruments 证明必要后局部采用，不能作为默认身份交接方案。

## 15. 最终验收清单

- [ ] 任务标题与完成框从来源到详情始终清晰、不透明、坐标连续。
- [ ] 来源行只留下同高安静空位，没有模糊身份副本。
- [ ] 创建 `+` 直接成为创建卡，没有紧凑列表中转或空白卡壳。
- [ ] 卡片稳定后键盘才出现，键盘不遮挡卡片主要区域。
- [ ] 提交后列表平顺让位并接住同一任务表面。
- [ ] 屏外落点只在提交后执行一次连续定位。
- [ ] 顶部 Toolbar、时间线和 Dock 同步进入同一景深背景。
- [ ] 背景结构可辨、文字不再适合阅读；前景始终清晰。
- [ ] 背景点击只关闭当前对象，不打开另一任务。
- [ ] 打开、关闭和放弃可从当前可见状态反向，无速度断点。
- [ ] 无明显过冲、多次回弹、独立背景回弹或终点呼吸。
- [ ] Reduce Motion / Transparency 符合确认的降级视觉。
- [ ] 深浅色、Dynamic Type、VoiceOver、中文 IME 和系统属性 Sheet 正常。
- [ ] `git diff --check`、残留关键词搜索、真实 build、完整 tests 通过。
- [ ] 真机录屏逐帧审查无双重实体、跳位、白壳或键盘分段。
- [ ] Instruments 未发现明确 P0/P1/P2 性能或泄漏问题。

## 16. 完成定义

只有当旧架构被删除、全部自动化验证完成、真机逐帧视觉验收和性能检查通过，才能宣称该动效重构完成。Simulator 流畅、编译成功或单次肉眼观察都不能替代最终验收。
