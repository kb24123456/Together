# 一起 iOS 架构说明

## 1. 结论
- 当前产品主轴：纯单人 Todo 效率工具。
- 当前首页 UI 保留，语义上视为单人模式的 Today 首页。
- 技术架构不再支持或预留 `PairSpace / MultiSpace / Supabase / RevenueCat`。
- 数据真相源为本地 SwiftData；跨设备同步与恢复只使用 CloudKit private database。
- OCR 导入是新增核心链路，必须以“草稿 -> 用户确认 -> 入库”的方式接入任务系统。
- 动效与交互丝滑度是架构约束之一，不是视觉后期。

## 2. 现状判断

### 事实
- 当前仓库已有 `Home / Lists / Projects / Calendar / Profile / Widget` 主链路。
- 当前代码里仍大量存在 `PairSpace / relationshipID / Invite / BindingState / TaskMessage / partner` 等旧双人协作命名。
- 当前代码里仍存在 Supabase Auth、Supabase Sync、Supabase Edge Function、RevenueCat、Paywall、PremiumGate 等旧后端/付费能力。
- 当前 SwiftData 容器已经存在，但 CloudKit 自动同步尚未启用；现有跨设备能力是 CKSyncEngine + Supabase recovery/outbox 混合链路。
- 当前首页静态 UI 可以继续保留，不需要因产品重定位推翻重画。

### 推演
- 旧双人协作与付费代码应按阶段删除，而不是继续加兼容层。
- `Space` 概念不再作为产品或架构目标；如迁移期间必须读取旧 `spaceID`，只能作为临时兼容输入。
- 现有 `HomeView` 可以延续为 Today 首页，只做数据和入口语义迁移。
- `Decisions / Anniversaries / Pairing / TaskChat / Paywall` 不再是当前产品模块。

## 3. 推荐分层
- `App/`
  - `AppContext`
  - `SessionStore`
  - `AppRouter`
  - 纯单人依赖容器
- `Domain/`
  - `Task / TaskList / Project / Reminder / UserProfile / OCRDraft`
  - 对应枚举、协议、状态机
- `Services/`
  - repository 协议
  - SwiftData 持久化
  - CloudKit private database 同步状态
  - 通知、认证、OCR、草稿解析
- `Features/`
  - `Today`
  - `Lists`
  - `Projects`
  - `Calendar`
  - `Profile`
  - `OCRImport`
- `WidgetSupport/`
  - Today widget snapshot
  - 个人任务完成写入
- `Shared/`
  - Design Tokens
  - 通用组件
  - 动画配置与过渡工具
- `PreviewContent/`
  - mock fixtures
  - Preview helpers

## 4. 导航结构

### 当前目标结构
- 一级导航：
  - `Today`
  - `清单`
  - `项目`
  - `日历`
  - `我`
- 全局创建入口：任务创建和 OCR 导入。
- 二级页面：任务详情、任务编辑、项目详情、OCR 草稿确认、筛选排序面板、提醒设置。

### 迁移说明
- 当前代码中的 `HomeView` 保留并继续作为 Today 首页。
- 当前 `Decisions`、`Anniversaries`、`Pairing`、`Paywall` 相关入口应从导航、Profile 与深链入口中移除。
- 不再提供单人/双人模式切换，不再维护 workspace/mode 切换 UI。

## 5. 全局状态建议
- `SessionStore`
  - 当前用户
  - 登录状态
  - 单人资料与设置
  - iCloud 同步状态
- `AppRouter`
  - 当前 Tab
  - 全局创建入口
  - OCR 草稿确认
  - 全局 sheet / fullScreenCover
- Feature ViewModel
  - 页面数据
  - 筛选、排序、分组
  - 加载与错误状态

不要把任务生命周期、OCR 草稿状态、项目状态和 UI 展开状态混在同一个 ViewModel 里。

## 6. 数据与同步策略

### 当前目标
- 本地 SwiftData 是唯一本地数据真相源。
- CloudKit private database 是唯一跨设备同步与恢复能力。
- 不再依赖 Supabase 做 canonical backend、增量恢复、Realtime、Storage、push trigger 或 webhook。
- 不再依赖 RevenueCat / PremiumGate 判断任何功能可用性。

### SwiftData + CloudKit 约束
- CloudKit 同步模型不得使用 `@Attribute(.unique)`。
- 持久化属性必须有默认值或为 optional。
- 关系必须按 CloudKit 兼容方式建模，删除规则和 optional 影响需先评估。
- 若旧 store 允许全部删除，则迁移可选择创建新 schema，而不是为旧双人/Supabase 字段保留复杂迁移。

### OCR 数据策略
- OCR 识别文本和结构化结果先进入短生命周期草稿。
- 草稿确认前不写入真实 Task / Project。
- 识别失败、AI 不可用或结构化失败时，用户仍能从原始文本手动创建任务。

## 7. 数据流
- View 发起事件
- ViewModel 处理输入并调用 repository / service
- repository 返回 domain model
- ViewModel 产出渲染状态
- View 仅负责渲染和轻量交互状态

排序、筛选、分组、OCR 解析等可能影响动画流畅度的计算，应在后台或状态提交前完成，不要在动画帧内做重复重算。

## 8. Widget 架构要求
- Widget snapshot 只是展示缓存，不是业务真相。
- Widget 完成任务必须写入同一个单人 SwiftData 业务真相源，并刷新 snapshot。
- 删除旧 outbox 后，Widget 不能再写 Supabase/SyncChange 专用队列。
- Widget extension 仍不得使用局部 `@Model` 打开完整主 App schema；若继续直接写 SQLite，必须跟随新 schema 做最小事务并测试。

## 9. OCR 架构要求
- 扫描入口优先使用 Apple 原生 VisionKit / Vision。
- 单张图片 OCR 使用 `VNRecognizeTextRequest`，文档扫描可使用 `VNDocumentCameraViewController`。
- OCR 计算不得阻塞主线程。
- 结构化解析优先采用小而可测的规则解析；如接入 Foundation Models，必须使用结构化输出并提供不可用 fallback。

## 10. 动效架构要求
- 动效必须由状态变化驱动，不要写大量分散的硬编码动画。
- 优先使用：
  - `withAnimation`
  - `contentTransition`
  - `matchedGeometryEffect`
  - `phaseAnimator`
  - `symbolEffect`
- 列表切换、周/月切换、任务完成、详情展开、OCR 草稿确认等交互要统一动效节奏。
- 复杂计算、聚合、排序和 OCR 解析不要阻塞主线程；主线程只提交最终 UI 状态。

## 11. 当前实现的迁移建议
1. 保留现有首页 UI 与视觉方向。
2. 先删除产品文档中的双人/多人/付费/第三方后端路线。
3. 再移除 Supabase、RevenueCat、Paywall、Pairing、TaskChat 等装配骨架。
4. 重塑 Task / List / Project / Reminder / OCRDraft 模型。
5. 接入 SwiftData CloudKit private database。
6. 适配 Widget。
7. 最后实现 OCR MVP。

## 12. Open Questions
- OCR 全局入口与任务创建入口是合并为一个菜单，还是保留两个明确按钮。
- 是否需要保留极小的本地账号概念，还是完全使用 iCloud 身份与本地用户资料。
