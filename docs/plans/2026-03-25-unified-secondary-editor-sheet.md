# Unified Secondary Editor Sheet Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace separate secondary editor sheets with one unified half-sheet container that supports icon-only menu switching, disabled reminder actions without time, and project subtasks in the composer.

**Architecture:** Reuse the existing date/time/option editor content while moving menu switching into a shared container view. Keep task and periodic detail editing on the existing draft flows, and extend project creation draft state with local subtasks that are saved as linked tasks after the project is created.

**Tech Stack:** SwiftUI, Swift Concurrency, existing Task / Project application services, Swift Testing

---

### Task 1: Document the interaction contract

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/docs/plans/2026-03-25-unified-secondary-editor-sheet.md`

**Step 1: Lock menu mappings**

- Periodic: repeat, time, reminder
- Task: date, time, reminder, priority
- Project: due date, priority, subtasks

**Step 2: Lock behavior**

- Use one half-sheet per editor context
- Top bar is icon-only
- Selected icon uses a light capsule, idle icons stay low emphasis
- Reminder requires time and becomes disabled without time
- Project subtask panel shows list, completion toggle, and one-line add input

### Task 2: Build a shared unified menu container

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/TaskEditorSharedComponents.swift`

**Step 1: Add menu metadata**

- Add `subtasks` case to `TaskEditorMenu`
- Add menu icon/title helpers and a shared height profile enum for task/periodic/project containers

**Step 2: Add top icon switcher**

- Build an icon-only capsule toolbar with disabled state support
- Expose selected menu, available menus, and tap callback

**Step 3: Add unified container**

- Render toolbar + active content in one sheet
- Apply stable detents per context
- Use light horizontal transition + opacity between menu content

### Task 3: Rewire composer secondary menu flow

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/ComposerPlaceholderSheet.swift`

**Step 1: Extend project draft state**

- Add local subtask draft list and new subtask input text
- Add helpers for toggling completion, adding, removing, and building child `TaskDraft`s

**Step 2: Replace per-menu sheet presentation**

- Keep one `activeMenu`-driven sheet open
- Present the shared unified container instead of one menu-specific view

**Step 3: Update menu availability and disabled logic**

- Remove project reminder
- Add project subtasks
- Disable reminder when selected category has no time

**Step 4: Save project subtasks**

- After project save, create linked tasks for local subtasks through `TaskApplicationServiceProtocol`

### Task 4: Rewire detail secondary menu flow

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeItemDetailSheet.swift`

**Step 1: Replace per-menu sheet presentation**

- Present the shared unified container for task/periodic detail menus

**Step 2: Remove deferred reminder redirect**

- Delete “reminder opens time first” logic
- Disable reminder icon when no explicit time exists

### Task 5: Validation

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift` (if targeted tests are needed)

**Step 1: Build**

Run: `xcodebuild -project /Users/papertiger/Desktop/Together/Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

**Step 2: Add or adjust focused tests if logic changes require it**

- Project subtasks save flow
- Disabled reminder gating

**Step 3: Re-run the focused verification commands**

Plan complete and saved to `docs/plans/2026-03-25-unified-secondary-editor-sheet.md`.
