# Settings Sheet Shell Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable half-sheet shell for task settings, temporarily launched from Home snooze, with shared top navigation, bottom feature switching, and staged edits committed from the top-right confirm action.

**Architecture:** Extend the shared task-editor menu system instead of creating a second parallel container. Add a reusable shell component in shared task-editor code, adapt Home snooze to use local staged state through that shell, and reuse existing date/time/reminder/repeat content where possible while constraining them to the new half-sheet layout.

**Tech Stack:** SwiftUI, Observation, existing shared task editor components, UIKit-backed wheel picker already bridged in shared components.

---

### Task 1: Define reusable settings-sheet shell API

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/TaskEditorSharedComponents.swift`

**Step 1: Add shell component**
- Create a reusable shared container with:
  - top bar: cancel / centered date title / confirm
  - content region
  - bottom icon switcher
  - staged menu switching animation

**Step 2: Support flexible menu sets**
- Allow caller-provided menus instead of only context-derived defaults.
- Keep disabled-menu handling and transition direction logic.

**Step 3: Add layout metrics**
- Centralize header height, bottom bar height, and content safe spacing metrics for the new shell.

### Task 2: Reuse current task-editor subpages inside shell

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/TaskEditorSharedComponents.swift`

**Step 1: Adapt date page for compact shell**
- Add a compact week-strip variant for date selection using the Home week interaction style.

**Step 2: Adapt time page for compact shell**
- Reuse `TaskEditorSingleColumnTimeWheel`.
- Add optional “all day” toggle support and allow hiding the “时间” label.

**Step 3: Keep reminder / repeat pages reusable**
- Reuse existing option list content and clamp layout to the shell height.

### Task 3: Wire Home snooze to the new shell

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeViewModel.swift`

**Step 1: Replace current snooze custom editor**
- Remove the temporary custom snooze editor layout.
- Present the new shared settings sheet shell from Home.

**Step 2: Stage snooze-specific values**
- Keep local staged date/time/all-day values in Home view model.
- Keep confirm action mapped to the Home snooze apply flow for now.

**Step 3: Temporarily map menus**
- Use menus: date / time / reminder / repeatRule.
- Reminder / repeat pages can temporarily reuse existing content without final business wiring.

### Task 4: Validate height and interaction polish

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/TaskEditorSharedComponents.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeView.swift`

**Step 1: Tune detent sizing**
- Ensure content fits the half-sheet without oversized calendar overflow.

**Step 2: Preserve native feedback**
- Reuse Home week-strip haptics and existing menu-selection feedback.

**Step 3: Build validation**
- Run:
  - `xcodebuild -project /Users/papertiger/Desktop/Together/Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

