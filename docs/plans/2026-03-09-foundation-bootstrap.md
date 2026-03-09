# Together Foundation Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the first-step iOS foundation for Together, including architecture, domain model, state machines, root navigation shell, and mock-backed feature scaffolding.

**Architecture:** Keep a single iOS target, organize code by feature and domain, and put state transitions behind explicit state machines and repository protocols. Use SwiftUI + Observation for the app shell and mock services to keep the app runnable before real auth, persistence, and sync are implemented.

**Tech Stack:** SwiftUI, Observation, NavigationStack, TabView, repository protocols, in-memory mock services, Xcode Testing

---

### Task 1: Replace the template app entry

**Files:**
- Modify: `Together/TogetherApp.swift`
- Create: `Together/App/AppContext.swift`
- Create: `Together/App/AppContainer.swift`
- Create: `Together/App/SessionStore.swift`

**Steps:**
1. Remove SwiftData template code.
2. Create an app bootstrap context that owns services, session, router, and feature view models.
3. Inject the app context into the SwiftUI environment.

### Task 2: Define the domain layer

**Files:**
- Create: `Together/Domain/Entities/*`
- Create: `Together/Domain/Enums/*`
- Create: `Together/Domain/Protocols/*`
- Create: `Together/Domain/StateMachines/*`

**Steps:**
1. Define entities for User, PairSpace, Item, Decision, Anniversary, Invite, AppNotification.
2. Define enums for auth, binding, item, decision, reminder states.
3. Define repository and service protocols.
4. Encode the item, decision, and binding state machines as separate domain utilities.

### Task 3: Add mock-backed services

**Files:**
- Create: `Together/PreviewContent/MockDataFactory.swift`
- Create: `Together/Services/**/*`

**Steps:**
1. Seed a consistent mock relationship, mock users, and mock entities.
2. Implement mock auth, relationship, item, decision, anniversary, and notification services.
3. Make repositories mutate in-memory state so the shell can demonstrate flow changes.

### Task 4: Build root navigation shell

**Files:**
- Create: `Together/App/AppTab.swift`
- Create: `Together/App/AppRoute.swift`
- Create: `Together/App/AppRouter.swift`
- Create: `Together/App/AppRootView.swift`

**Steps:**
1. Build a four-tab root shell: Home, Decisions, Anniversaries, Profile.
2. Keep feature navigation isolated inside each tab.
3. Reserve a global composer sheet route for “发请求 / 发决策”.

### Task 5: Build feature shells and shared UI

**Files:**
- Create: `Together/Features/Home/*`
- Create: `Together/Features/Decisions/*`
- Create: `Together/Features/Anniversaries/*`
- Create: `Together/Features/Profile/*`
- Create: `Together/Features/Shared/*`
- Create: `Together/Core/DesignSystem/AppTheme.swift`
- Create: `Together/Core/Support/*`

**Steps:**
1. Create one ViewModel per first-level feature.
2. Build low-fidelity but runnable SwiftUI shells for the four first-level tabs.
3. Add shared card, badge, empty, and composer placeholder components.
4. Add a minimal design token layer for spacing, radius, and color.

### Task 6: Add project documentation

**Files:**
- Create: `ARCHITECTURE.md`
- Create: `DATA_MODEL.md`
- Create: `STATE_MACHINE.md`
- Create: `TODO_NEXT_STEPS.md`

**Steps:**
1. Document product understanding and architecture choices.
2. Document domain models and relationship data boundaries.
3. Document state machines and lifecycle transitions.
4. Document follow-up implementation priorities.

### Task 7: Add baseline verification

**Files:**
- Modify: `TogetherTests/TogetherTests.swift`

**Steps:**
1. Add state machine coverage for item and decision transitions.
2. Run the app build or tests to catch compile errors.
3. Fix issues until the project builds cleanly.
