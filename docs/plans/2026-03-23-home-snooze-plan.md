# Home Snooze Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a single snooze action to Today task rows with lightweight secondary options, a return-to-today shortcut, and profile-configurable snooze presets.

**Architecture:** Reuse the existing Home feature state and task editor time-picker components instead of introducing a parallel interaction system. Add a focused snooze option model in the application layer, keep Home row gestures on native `swipeActions`, and store preset minute values in the existing user notification preferences so Profile and Home read from the same source.

**Tech Stack:** SwiftUI, Observation, existing TaskApplicationService, existing task editor date/time picker components, Swift Testing.

---

### Task 1: Plan And Shared Reuse Points

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Profile/ProfileView.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Modify: `Together/Application/Tasks/TaskApplicationServiceProtocol.swift`
- Modify: `Together/Application/Tasks/DefaultTaskApplicationService.swift`
- Test: `TogetherTests/TogetherTests.swift`

**Step 1: Keep native gesture boundaries**

- Leave week paging in the header area.
- Keep row interactions on `swipeActions`.
- Do not add list-wide `DragGesture`.

**Step 2: Reuse existing picker**

- Reuse `TaskEditorDatePickerSheet` / `TaskEditorTimePickerSheet` from shared task editor components.
- Feed Home snooze quick presets from the user preference array already used by the composer and detail sheet.

### Task 2: Application Layer Snooze Support

**Files:**
- Create: `Together/Application/Tasks/TaskSnoozeOption.swift`
- Modify: `Together/Application/Tasks/TaskApplicationServiceProtocol.swift`
- Modify: `Together/Application/Tasks/DefaultTaskApplicationService.swift`
- Test: `TogetherTests/TogetherTests.swift`

**Step 1: Add a snooze option model**

- Introduce a small enum with:
  - `.tomorrow`
  - `.minutes(Int)`
  - `.custom(Date)`

**Step 2: Add a dedicated service method**

- Extend the task application service with `snoozeTask(...)`.
- Keep snooze rules out of `HomeViewModel`.

**Step 3: Implement deterministic snooze rules**

- Incomplete tasks only.
- `.tomorrow`: preserve explicit hour/minute when present, otherwise move to next day start.
- `.minutes(Int)`: move due date forward from now by the requested minutes and mark explicit time true.
- `.custom(Date)`: use the provided date; explicit time should stay true.
- Shift `remindAt` by the same delta when it exists so reminder and due time stay aligned.

**Step 4: Add focused tests**

- Verify tomorrow preserves explicit time.
- Verify relative-minute snooze updates due date and reminder coherently.
- Verify custom snooze writes the requested time.

### Task 3: HomeViewModel State And Actions

**Files:**
- Modify: `Together/Features/Home/HomeViewModel.swift`

**Step 1: Add Home-only presentation state**

- Add state for:
  - currently pending snooze item
  - whether the quick option dialog is visible
  - whether the custom picker sheet is visible
  - staged custom snooze date

**Step 2: Add derived values**

- `isViewingToday`
- `snoozeQuickPresetMinutes`
- `canSnooze(_:)`

**Step 3: Add explicit Home actions**

- `returnToToday()`
- `presentSnoozeOptions(for:)`
- `applySnoozeTomorrow()`
- `applySnooze(minutes:)`
- `presentCustomSnoozePicker()`
- `applyCustomSnooze(date:)`
- `dismissSnoozeUI()`

### Task 4: Home View Integration

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`

**Step 1: Add return-to-today button**

- Show only when selected date is not today.
- Place it in the header area without changing safe area behavior.

**Step 2: Replace row swipe action**

- Only show `推迟` for incomplete rows.
- Trigger a lightweight secondary menu (`confirmationDialog`) with:
  - `30分钟后`
  - `1小时后`
  - `2小时后`
  - `明天`
  - `自定义`

**Step 3: Reuse the shared custom picker**

- Present the shared date/time picker when the user chooses `自定义`.
- Keep dismissal and save flow in `HomeViewModel`.

**Step 4: Preserve animation behavior**

- Reuse the existing list transition and completion feedback style.
- Add soft feedback on snooze success without introducing custom gesture animation.

### Task 5: Profile Preset Configuration

**Files:**
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Modify: `Together/Features/Profile/ProfileView.swift`
- Modify: `Together/Domain/Entities/User.swift`

**Step 1: Expand preset storage constraints**

- Increase normalized preset array count from 3 to 4 if needed by the Home snooze menu.
- Keep 5-minute rounding and 5...180 minute bounds.

**Step 2: Update Profile UI copy**

- Clarify these presets are shared by add/edit time shortcuts and Home snooze quick options.

**Step 3: Ensure defaults match product decision**

- Default to `30 / 60 / 120`.

### Task 6: Verification

**Files:**
- Test: `TogetherTests/TogetherTests.swift`

**Step 1: Run focused tests**

- `xcodebuild test` or the project’s focused test target for task service behavior.

**Step 2: Run build verification**

- Build the app target to catch SwiftUI state or sheet wiring errors.

**Step 3: Manual regression checklist**

- Incomplete task row shows `推迟`.
- Completed task row does not show `推迟`.
- Picking `明天` removes task from Today when appropriate.
- Picking a relative preset updates due/reminder correctly.
- Custom picker saves and dismisses correctly.
- Profile preset changes affect Home snooze options.
