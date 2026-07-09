# Home–Routines Mode Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reversible, same-canvas transition between the ordinary task view and routines view.

**Architecture:** Keep both content layers mounted in `HomeView` and drive their visual states from `isRoutinesModePresented`. Keep navigation chrome choreography in `AppRootView`; keep dimension-header and task-row cascade local to `RoutinesListContent`.

**Tech Stack:** SwiftUI, SF Symbols, Swift Testing.

---

### Task 1: Define deterministic transition timing

**Files:**
- Modify: `Together/Features/Routines/RoutinesListContent.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [x] Add a pure timing helper that caps the cascade at five rows, delays entry from first to last, reverses delay order on exit, and returns zero under Reduce Motion.
- [x] Add Swift Testing assertions for entry ordering, exit ordering, cap behavior, and Reduce Motion.
- [x] Run the focused timing assertions; the Xcode test runner remains blocked by the local platform destination issue.

### Task 2: Choreograph native navigation chrome

**Files:**
- Modify: `Together/App/AppRootView.swift`

- [x] Animate the top-left routine symbol rotation, scale, and active tint from the existing route state.
- [x] Replace the static navigation title swap with a stable principal title container using 2pt blur and opacity over 0.42 seconds, without scale; fall back to opacity for Reduce Motion.
- [x] Keep existing routing, accessibility labels, and haptic behavior unchanged.

### Task 3: Build reversible same-canvas surface motion

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/Features/Routines/RoutinesListContent.swift`
- Modify: `Together/Features/Routines/RoutinesView.swift`

- [x] Keep the routines content layer mounted while hidden and disable its hit testing and accessibility when inactive.
- [x] Apply a subtle scale, offset, blur, and opacity exit to ordinary tasks.
- [x] Apply the inverse entrance to routines content with a short delay, while leaving the grid background unchanged.
- [x] Add a background-display parameter so the embedded routines layer does not crossfade a duplicate grid; preserve the standalone routines background.
- [x] Animate the fixed dimension header with the routines surface and cascade the first five rows using Task 1 timing.
- [x] Remove spatial effects in Reduce Motion.

### Task 4: Verify the complete interaction

**Files:**
- Modify only if verification exposes a defect in files listed above.

- [x] Run `git diff --check`.
- [x] Run focused transition timing assertions; Swift Testing execution is unavailable without an eligible iOS destination.
- [x] Run Swift syntax parsing and full main-App iPhoneOS SDK typecheck.
- [x] Run `xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`; it stops before compilation because Xcode reports the iOS 26.5 platform destination as unavailable.
- [x] Review rapid toggling, Reduce Motion, toolbar accessibility, hidden-layer hit testing, and reverse transition symmetry; physical motion still requires device acceptance.
