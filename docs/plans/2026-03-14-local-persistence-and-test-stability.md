# Local Persistence And Test Stability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a real local persistence backbone for the single-user Todo MVP and make automated tests runnable without being blocked by UITest signing.

**Architecture:** Keep the current protocol-first service boundaries, replace mock-only Todo repositories with SwiftData-backed implementations, and seed deterministic local data for the current single-space flow. Separate unit-test execution from UITest signing so the core model and repository layer can be validated in CI and locally.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Xcode scheme configuration

---

### Task 1: Add SwiftData persistence models and bootstrap

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentSpace.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentTaskList.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentProject.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentItem.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/PersistenceController.swift`

**Steps:**
1. Define SwiftData models for `Space`, `TaskList`, `Project`, and `Item`.
2. Add model mapping helpers between persistent records and domain entities.
3. Create a persistence controller with `shared`, `inMemory`, and seed helpers.
4. Seed the local store from `MockDataFactory` only when the store is empty.

### Task 2: Replace mock-only Todo repositories with live local implementations

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Services/Spaces/LocalSpaceService.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Services/Items/LocalItemRepository.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Services/TaskLists/LocalTaskListRepository.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Services/Projects/LocalProjectRepository.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/MockServiceFactory.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppContext.swift`

**Steps:**
1. Implement local repositories against `ModelContainer`.
2. Keep existing protocols stable for current UI callers.
3. Switch app bootstrap to the live local container for Todo data.
4. Retain mock auth and non-MVP domains to avoid scope creep.

### Task 3: Expand repository contracts for real Todo write paths

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Domain/Protocols/TaskListRepositoryProtocol.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Domain/Protocols/ProjectRepositoryProtocol.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/TaskLists/MockTaskListRepository.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/Projects/MockProjectRepository.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/TaskLists/LocalTaskListRepository.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/Projects/LocalProjectRepository.swift`

**Steps:**
1. Add minimal create/update/archive write methods for lists and projects.
2. Keep method names aligned with product semantics and future AI readability.
3. Ensure local and mock implementations stay behaviorally consistent.

### Task 4: Add repository tests for local persistence

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift`

**Steps:**
1. Add tests that exercise local store seeding and fetches.
2. Add tests for item status update and completion persistence.
3. Add tests for list/project create and archive behavior.

### Task 5: Stabilize Xcode test execution

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together.xcodeproj/xcshareddata/xcschemes/Together-UnitTests.xcscheme`
- Modify: `/Users/papertiger/Desktop/Together/Together.xcodeproj/project.pbxproj`

**Steps:**
1. Create a shared unit-test-only scheme that excludes `TogetherUITests`.
2. Disable signing for `TogetherUITests` target in Debug/Release when possible, or at minimum isolate it from default CLI test runs.
3. Validate `xcodebuild build` and `xcodebuild test -scheme Together-UnitTests`.

