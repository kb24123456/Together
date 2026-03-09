# 一起 iOS 架构说明

## 1. 技术理解摘要

### 1.1 事实
- 产品不是普通 Todo，也不是社交产品，而是面向共同生活阶段情侣/夫妻的一对一双人协作 App。
- 首版核心对象只有 3 类：事项、决策、纪念日。
- 首页不是信息流，而是双人事项流，优先级为：待回应事项 > 进行中事项 > 纪念日轻提示。
- 登录方式只有 Sign in with Apple。
- 关系模型只有一对一绑定。
- 首版闭环重点是：发起事项 -> 对方反馈 -> 进入进行中 -> 完成留痕。
- 决策对象必须支持三类模板：买不买、吃不吃、去不去。
- 未绑定状态只能体验和创建轻度草稿，不能形成真实双人闭环。
- 解绑后旧双人数据不能迁移给新对象，重新绑定必须从零开始。

### 1.2 核心对象
- 事项型对象：承接请求、知情、共同执行三类双人协作语义。
- 决策型对象：承接模板化、低成本、可再次提醒的双人表态流程。
- 纪念日对象：承接关系日期记录和提醒。
- 绑定对象：承接单人试用、邀请、接受邀请、已绑定、解绑后的数据边界。

### 1.3 首版必须支持
- Apple 登录入口和认证层边界。
- 一对一绑定状态管理。
- 事项 4 态状态机。
- 决策 4 态状态机。
- 首页 / 决策 / 纪念日 / 我 四个一级导航骨架。
- 本地可运行的 mock 数据与协议化服务层。

### 1.4 首版明确不做
- 多人家庭 / 多人协作。
- 社区、内容流、开放社交。
- 工作任务管理能力。
- 位置、电量等状态监控。
- 复杂相册、情侣社区、游戏化系统。

### 1.5 Assumptions
- 当前仓库先按单 target、单模块代码组织推进，不在第一步拆 Swift Package。
- 第一阶段先用 mock / in-memory repository 驱动 UI，真实后端与持久化后接。
- 首版详情页、表单页、邀请接收页先只保留路由占位，不实现完整业务。

### 1.6 Open Questions
- 邀请接受是通过 Universal Link、邀请码，还是 App 内扫码，文档未明确。
- 用户昵称、头像是否允许自定义，文档未明确。
- 解绑后旧关系数据是彻底本地删除、还是仅从当前活跃空间剥离，文档未明确。

## 2. 技术方案

### 2.1 技术栈建议
- UI：SwiftUI
- 状态观察：Observation（`@Observable`）
- 导航：`TabView` + `NavigationStack`
- 架构：轻量 Clean + Feature-first MVVM
- 数据层：Repository Protocol + Domain Model
- 本地存储：后续建议 SwiftData 做草稿、缓存、离线镜像；本轮先用 in-memory mock
- 网络层：后续建议 URLSession + APIClient 协议化封装；本轮先不接真实接口
- 通知：UserNotifications，本轮只定义服务协议和 mock
- 认证：AuthenticationServices（Sign in with Apple），本轮先放在 AuthService 边界后

### 2.2 为什么不直接上 TCA
- 事实：产品当前还处于 0 到 1，需求主轴是建立清晰的关系模型和状态机，不是先引入复杂框架。
- 取舍：TCA 非常适合复杂状态流，但第一步就引入会增加学习和样板成本。
- 当前建议：先采用 Feature-first MVVM + Repository + 显式状态机。这样首版落地快，后续若状态复杂度继续上升，再局部迁移到更强约束的单向数据流也不晚。

### 2.3 模块划分
- `App/`：App 入口、依赖容器、路由、全局会话
- `Core/`：设计 tokens、基础支持类型
- `Domain/`：实体、枚举、协议、状态机
- `Services/`：认证、绑定、事项、决策、纪念日、通知的 mock / stub 实现
- `Features/`：Home / Decisions / Anniversaries / Profile 的 View + ViewModel
- `PreviewContent/`：统一 mock data

### 2.4 路由与导航
- 一级导航：`TabView`
- 二级详情：各 Tab 内独立 `NavigationStack`
- 全局浮层：`AppRouter.activeComposer`
- 原因：
  - 首页、决策、纪念日、我的二级流转相对独立
  - 新建请求 / 新建决策属于全局动作，适合挂在全局 router 上

### 2.5 状态管理
- 全局会话：`SessionStore`
- 全局路由：`AppRouter`
- 依赖注入：`AppContainer`
- Feature 状态：各自 `ViewModel`
- 核心规则：
  - 绑定状态、当前用户、当前 PairSpace 属于全局状态
  - 列表过滤、当前 tab、当前模板筛选属于 feature 局部状态
  - 状态机规则不写在 View 层，只放 `Domain/StateMachines`

### 2.6 提醒与通知接入
- 本轮：`NotificationServiceProtocol` + mock
- 后续：
  - 事项：新事项、临近截止、提醒时间、状态变化
  - 决策：新决策、再次提醒、一致结果
  - 纪念日：倒计时、当天提醒
- 策略：提醒调度由 Domain 产出 `AppNotification`，基础设施层负责落地到本地通知或未来云推送

### 2.7 Sign in with Apple 接入位置
- 认证入口放在 `Services/Auth`
- ViewModel 只依赖 `AuthServiceProtocol`
- 真实实现应封装 `AuthenticationServices`，不要把 Apple 登录细节散到 View 层

### 2.8 一对一绑定的数据建模
- 活跃双人空间实体：`PairSpace`
- 邀请实体：`Invite`
- 当前关系状态：`BindingState`
- 所有共享对象都带 `relationshipID`
- 数据边界通过 `PairSpace.id` + `dataBoundaryToken` 双重表达

### 2.9 数据同步策略
- 当前建议：本地优先、云端同步的混合策略
- 原因：
  - 首页和待回应事项需要低延迟打开
  - 决策、纪念日、提醒都适合有本地镜像
  - 关系型数据仍需要云端保证双端一致
- 第一阶段工程做法：
  - Domain Model 与 Repository 协议先稳定
  - 先用 mock repository 驱动
  - 第二阶段接本地持久化
  - 第三阶段再接真实后端同步

### 2.10 本轮哪些先 mock / stub
- 先 mock：
  - 事项仓库
  - 决策仓库
  - 纪念日仓库
  - 绑定服务
  - 通知服务
- 先定义协议：
  - AuthService
  - RelationshipService
  - Repository 系列
  - NotificationService
- 暂不实现真实逻辑：
  - Apple 登录
  - 邀请发送与接收
  - 本地通知调度
  - 云端同步

## 3. 当前工程初始化结果
- 已建立目录骨架和 feature 分层
- 已建立首页 / 决策 / 纪念日 / 我 四个一级导航壳子
- 已建立基础 theme / design token
- 已建立核心模型、协议、状态机
- 已建立 mock data、mock service、feature view model
- 已保留全局新建入口的占位 sheet

## 4. 后续建议
- 先补真实详情页与新建表单，但继续沿协议层推进，不要直接把业务写死在 View 内
- 第二步优先实现绑定流和事项闭环，再做决策转事项
- 在真实后端未确定前，不要过早把 SwiftData 模型与接口 DTO 耦死
