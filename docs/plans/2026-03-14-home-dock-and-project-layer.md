# Home Dock And Project Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将首页改造成 Today 主屏 + 三按钮 Dock，并建立右侧项目层、左侧我页、全屏添加页与事件详情 Sheet 的完整主链路。

**Architecture:** 取消当前 5-tab 主导航，改为自定义根容器。根容器常驻 Today 首页，底部放三按钮 Dock；右侧按钮切换项目层，左侧按钮全屏进入我页，中间按钮全屏打开添加页。事件详情使用可编程 detent 的原生 sheet，并把重复事件纳入当前事件模型。

**Tech Stack:** SwiftUI, Observation, SwiftData, native sheet detents, safeAreaInset, fullScreenCover

---

### Task 1: Root Shell

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppRootView.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppRouter.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppRoute.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Features/Shared/HomeDockBar.swift`

**Step 1:** 把根视图从 `TabView` 改成自定义 Today shell。
**Step 2:** 给 router 增加项目层与我页的展示状态。
**Step 3:** 接入底部三按钮 Dock。
**Step 4:** 让 Dock 与首页安全区和项目层切换联动。

### Task 2: Event Model And Repeat Rule

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Domain/Entities/ItemRepeatRule.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Domain/Entities/Item.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentItem.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Application/Tasks/TaskDraft.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Sync/CloudKitTaskRecordCodec.swift`

**Step 1:** 给事件模型加 `repeatRule`。
**Step 2:** 把 SwiftData 和同步编解码补齐。
**Step 3:** 让 `TaskDraft` 支持重复规则。

### Task 3: Today Home Flow

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeViewModel.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeItemDetailSheet.swift`

**Step 1:** 把首页数据源切到 `TaskApplicationService`。
**Step 2:** 让首页按选中日期展示当天事件，并纳入重复事件。
**Step 3:** 加入勾选完成、点击打开详情 Sheet、右滑完成动作。
**Step 4:** 详情 Sheet 支持中/大 detent、自动保存、键盘弹出升到大屏。

### Task 4: Project Layer And Composer

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Projects/ProjectsView.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Projects/ProjectsViewModel.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/ComposerPlaceholderSheet.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppContext.swift`

**Step 1:** 把项目页适配成石墨灰项目层。
**Step 2:** 保持现有项目数据流，只做入口和表面切换。
**Step 3:** 把添加页替换成真实的新建事件表单。

### Task 5: Verify

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift`

**Step 1:** 为重复事件匹配、首页任务完成、详情自动保存补单测。
**Step 2:** 跑 `build` 和 `build-for-testing`。
