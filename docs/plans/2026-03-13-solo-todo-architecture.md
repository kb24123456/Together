# Solo Todo Architecture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 收敛项目到单人 Todo 主链路的前后端骨架，避免后续开发继续围绕旧的双人优先结构发散。

**Architecture:** 保留现有首页 UI 与旧双人模块作为兼容层；新增 `Space / TaskList / Project` 领域骨架、对应 repository 与 mock，并把 App 根导航切到 `Today / Lists / Projects / Calendar / Profile`。`SessionStore` 增加当前单人空间上下文，新页面先用轻量 ViewModel 与 placeholder 骨架承接后续开发。

**Tech Stack:** SwiftUI, Observation, Swift Testing, mock repository, file-system-synced Xcode project

---

### Task 1: 建立领域与服务骨架

**Files:**
- Create: `Together/Domain/Entities/Space.swift`
- Create: `Together/Domain/Entities/TaskList.swift`
- Create: `Together/Domain/Entities/Project.swift`
- Create: `Together/Domain/Protocols/SpaceServiceProtocol.swift`
- Create: `Together/Domain/Protocols/TaskListRepositoryProtocol.swift`
- Create: `Together/Domain/Protocols/ProjectRepositoryProtocol.swift`
- Create: `Together/Services/Spaces/MockSpaceService.swift`
- Create: `Together/Services/TaskLists/MockTaskListRepository.swift`
- Create: `Together/Services/Projects/MockProjectRepository.swift`
- Modify: `Together/Domain/Entities/AuthSession.swift`
- Modify: `Together/PreviewContent/MockDataFactory.swift`

**Step 1:** 定义 `Space`、`TaskList`、`Project` 领域模型，字段只覆盖当前 MVP 必需骨架。  
**Step 2:** 定义 `SpaceContext`、`SpaceServiceProtocol`、`TaskListRepositoryProtocol`、`ProjectRepositoryProtocol`。  
**Step 3:** 用 mock service / repository 产出单人工作空间、清单、项目假数据。  

### Task 2: 收敛 Session 与依赖注入

**Files:**
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/App/SessionStore.swift`
- Modify: `Together/Services/MockServiceFactory.swift`
- Modify: `Together/Domain/Entities/User.swift`

**Step 1:** 为容器增加新的 space / list / project 依赖。  
**Step 2:** `SessionStore` 增加 `currentSpace`，并在 bootstrap 时优先载入单人空间上下文。  
**Step 3:** mock bootstrap 改成单人模式默认进入，不再默认 seed 为已绑定双人。  
**Step 4:** 将用户通知偏好字段收敛到单人 Todo 语义。  

### Task 3: 重组 App 根导航

**Files:**
- Modify: `Together/App/AppTab.swift`
- Modify: `Together/App/AppRoute.swift`
- Modify: `Together/App/AppRouter.swift`
- Modify: `Together/App/AppRootView.swift`
- Modify: `Together/Features/Shared/ComposerPlaceholderSheet.swift`

**Step 1:** 根导航切到 `Today / Lists / Projects / Calendar / Profile`。  
**Step 2:** 创建入口语义改为 `newTask / newProject`。  
**Step 3:** 保留 sheet 与 router 结构，但更新命名，避免旧决策页继续主导入口定义。  

### Task 4: 增加 Feature 骨架并接入首页

**Files:**
- Create: `Together/Features/Lists/ListsView.swift`
- Create: `Together/Features/Lists/ListsViewModel.swift`
- Create: `Together/Features/Projects/ProjectsView.swift`
- Create: `Together/Features/Projects/ProjectsViewModel.swift`
- Create: `Together/Features/Calendar/CalendarView.swift`
- Create: `Together/Features/Calendar/CalendarViewModel.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Profile/ProfileView.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift`

**Step 1:** 首页继续沿用现有 UI，但改为从 `currentSpace` 读取任务。  
**Step 2:** 新增清单、项目、日历占位页面与基础 ViewModel，保证后续开发有明确落点。  
**Step 3:** 我页显示当前工作空间、通知与未来双人模式入口说明。  

### Task 5: 基础测试与验证

**Files:**
- Modify: `TogetherTests/TogetherTests.swift`

**Step 1:** 增加 `SpaceService` / `SessionStore` / list/project mock 的基础断言。  
**Step 2:** 运行 `xcodebuild -project Together.xcodeproj -scheme Together -destination "platform=iOS Simulator,name=iPhone 16" test`。  
**Step 3:** 如果测试环境不可用，至少运行一次 `xcodebuild build` 并记录结果。  
