# 一起 iOS 架构说明

## 1. 结论
- 当前产品主轴：单人 Todo 效率工具。
- 当前首页 UI 保留，语义上视为单人模式的 Today 首页。
- 技术架构必须支持未来 `SingleSpace -> PairSpace -> MultiSpace` 的演进，但 V1 UI 不过早暴露复杂空间概念。
- 动效与交互丝滑度是架构约束之一，不是视觉后期。

## 2. 现状判断

### 事实
- 当前仓库已有 `Home / Decisions / Anniversaries / Profile` 的导航壳子。
- 当前代码里仍存在 `PairSpace / relationshipID / Invite / BindingState` 等旧方案命名。
- 当前首页静态 UI 已达到可继续开发的质量，不需要本轮推翻。

### 推演
- 旧的双人优先命名应逐步收敛到更通用的 `Space` 模型。
- 现有 `HomeView` 可以直接延续为新的 Today 首页，只做语义迁移，不急于重画。
- `Decisions / Anniversaries` 应转为附加模块或后续实验模块，不继续占据当前主链路的工程优先级。

## 3. 推荐分层
- `App/`
  - `AppContext`
  - `SessionStore`
  - `AppRouter`
  - 当前激活的 `SpaceSummary`
- `Domain/`
  - `Task / TaskList / Project / Reminder / Space`
  - 对应枚举、协议、状态机
- `Services/`
  - repository 协议
  - mock / local storage
  - 通知、认证、未来同步
- `Features/`
  - `Today`
  - `Lists`
  - `Projects`
  - `Calendar`
  - `Profile`
  - `Extensions`（决策、纪念日、双人协作）
- `Shared/`
  - Design Tokens
  - 通用组件
  - 动画配置与过渡工具
- `PreviewContent/`
  - mock fixtures
  - Preview helpers

## 4. 导航结构

### 当前目标结构
- 一级导航建议：
  - `Today`
  - `清单`
  - `项目`
  - `日历`
  - `我`
- 全局创建入口：悬浮主按钮或系统风格快捷创建入口。
- 二级页面：任务详情、任务编辑、项目详情、筛选排序面板、提醒设置。

### 迁移说明
- 当前代码中的 `HomeView` 保留并继续作为 Today 首页。
- 当前 `Decisions` 与 `Anniversaries` 壳子可以暂留，但应视为非主路径模块。
- 后续双人模式入口应放在 `我` 页或顶部范围切换器，而不是重新做一套独立 App 导航。

## 5. 全局状态建议
- `SessionStore`
  - 当前用户
  - 登录状态
  - 当前激活 Space 摘要
- `AppRouter`
  - 当前 Tab
  - 全局创建入口
  - 全局 sheet / fullScreenCover
- Feature ViewModel
  - 页面数据
  - 筛选、排序、分组
  - 加载与错误状态

不要把任务生命周期、项目状态和 UI 展开状态混在同一个 ViewModel 里。

## 6. Space 演进策略

### 当前做法
- V1 默认只有一个 `SingleSpace` 真正可用。
- 产品层不强调 Space；用户只会感知“我的任务空间”。

### 后续扩展
- V2：新增 `PairSpace`，允许邀请 1 位协作者共享部分任务、列表或项目。
- V3：如有明确商业价值，再扩展 `MultiSpace`。

### 迁移约束
- 新增和重构代码优先使用 `spaceID` 语义。
- 旧代码中的 `relationshipID` 可在兼容层保留，但不要继续作为新模块的首选字段名。

## 7. 数据流
- View 发起事件
- ViewModel 处理输入并调用 repository / service
- repository 返回 domain model
- ViewModel 产出渲染状态
- View 仅负责渲染和轻量交互状态

排序、筛选、分组等可能影响动画流畅度的计算，应尽量在状态提交前完成，不要在动画帧内做重复重算。

## 8. 动效架构要求
- 动效必须由状态变化驱动，不要写大量分散的硬编码动画。
- 优先使用：
  - `withAnimation`
  - `contentTransition`
  - `matchedGeometryEffect`
  - `phaseAnimator`
  - `symbolEffect`
- 列表切换、周/月切换、任务完成、详情展开等交互要统一动效节奏。
- 复杂计算、聚合和排序不要阻塞主线程；主线程只提交最终 UI 状态。

## 9. 当前实现的迁移建议
1. 保留现有首页 UI 与视觉方向。
2. 新功能优先补齐单人模式主链路，不继续扩旧的双人业务流。
3. 涉及旧的 `Pair` 语义时，优先做兼容封装或标记迁移 TODO，而不是继续复制旧模式。
4. 决策与纪念日如继续保留，应明确标注为扩展模块，而非首版主链路。

## 10. Open Questions
- 当前代码层是否在下一轮就启动 `PairSpace -> Space` 的命名迁移，还是先通过兼容层过渡。
- V1 的全局创建入口最终采用单按钮直达，还是展开式快捷菜单。
