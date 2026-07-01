# Task Property Chip Adaptive Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep all five new-task property entries visible on one line by showing titles only for configured values.

**Architecture:** Extend the shared chip snapshot/rendered value with explicit title visibility and an optional non-scrolling row mode. The task composer derives visibility from draft state; other existing consumers retain current behavior through default parameters.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, existing Together design tokens.

---

### Task 1: Specify adaptive chip state

**Files:**
- Modify: `Together/Features/Shared/TaskEditorSharedComponents.swift:108-335`
- Modify: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Write the failing state test**

```swift
@Test func taskPropertyChipTitleVisibilityTracksConfiguredValue() {
    #expect(TaskEditorChipSemanticValue.date(.now).hasConfiguredValue)
    #expect(TaskEditorChipSemanticValue.time(nil).hasConfiguredValue == false)
    #expect(TaskEditorChipSemanticValue.reminder(nil).hasConfiguredValue == false)
    #expect(TaskEditorChipSemanticValue.urgent(false).hasConfiguredValue == false)
    #expect(TaskEditorChipSemanticValue.subtasks(0).hasConfiguredValue == false)
    #expect(TaskEditorChipSemanticValue.time(.now).hasConfiguredValue)
    #expect(TaskEditorChipSemanticValue.reminder(900).hasConfiguredValue)
    #expect(TaskEditorChipSemanticValue.urgent(true).hasConfiguredValue)
    #expect(TaskEditorChipSemanticValue.subtasks(2).hasConfiguredValue)
}
```

- [ ] **Step 2: Run test compilation and verify the missing API fails**

Run:

```bash
DEVELOPER_DIR=/Users/papertiger/Downloads/Xcode-beta.app/Contents/Developer xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: failure because `hasConfiguredValue` does not exist.

- [ ] **Step 3: Add explicit presentation state**

Add `showsTitle` with a default of `true` to `TaskEditorChipSnapshot` and `TaskEditorRenderedChip`. Add this semantic helper:

```swift
var hasConfiguredValue: Bool {
    switch self {
    case .date: true
    case let .optionalDate(value): value != nil
    case let .time(value): value != nil
    case let .reminder(value): value != nil
    case let .urgent(value): value
    case let .subtasks(count): count > 0
    case let .periodicReminder(value): value
    case .periodicCycle: true
    }
}
```

Propagate `showsTitle` when converting snapshots into rendered chips.

- [ ] **Step 4: Typecheck the focused state test**

Run the generic build-for-testing command from Step 2.

Expected: build succeeds with only existing repository warnings.

### Task 2: Render the task composer as a non-scrolling adaptive row

**Files:**
- Modify: `Together/Features/Shared/TaskEditorSharedComponents.swift:249-335`
- Modify: `Together/Features/Shared/ComposerPlaceholderSheet.swift:350-530`

- [ ] **Step 1: Add the non-scrolling row option**

Add `allowsHorizontalScrolling: Bool = true` to `TaskEditorChipRow`. Extract the chip `HStack` into one shared builder. When scrolling is disabled, render it directly at the available width; when enabled, preserve the existing horizontal `ScrollView` for all other consumers.

- [ ] **Step 2: Render icon-only and configured variants**

Inside each chip button, always render `TaskEditorAnimatedChipIcon`. Render the title only when `chip.showsTitle` is true. In non-scrolling mode use a one-line `Text` with `minimumScaleFactor(0.7)` so configured values compress before icons disappear. Use coral foreground only for `.urgent(true)`.

- [ ] **Step 3: Derive composer visibility from task draft state**

For task snapshots set:

```swift
showsTitle: semanticValue.hasConfiguredValue
```

The effective rules are: date always titled; time/reminder titled only when set; urgent titled only when enabled; subtasks titled only when count is greater than zero. Call `TaskEditorChipRow(..., allowsHorizontalScrolling: false, ...)` in the composer.

- [ ] **Step 4: Preserve layout animation**

Include `showsTitle` in the rendered chip layout identity used by `applyRenderedChips` and the row animation value, so adding or clearing a value animates between icon-only and icon-plus-text without changing business identity.

### Task 3: Verify and document

**Files:**
- Modify: `DESIGN_GUIDELINES.md`
- Modify: `docs/PROJECT_MEMORY.md`

- [ ] **Step 1: Update design rules**

Document that the new-task property row uses icon-only placeholders and expands configured values, while retaining 44pt touch targets and one-line layout.

- [ ] **Step 2: Run verification**

```bash
git diff --check
DEVELOPER_DIR=/Users/papertiger/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,id=F77C3721-9F5D-4BDC-A880-2DC0E0429B7B' -only-testing:TogetherTests/TogetherTests -quiet
DEVELOPER_DIR=/Users/papertiger/Downloads/Xcode-beta.app/Contents/Developer xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: all tests and build-for-testing pass; existing Swift 6 isolation warnings may remain.

- [ ] **Step 3: Record durable results**

Add the final display rule, changed files, verification commands, and remaining real-device checks to `docs/PROJECT_MEMORY.md`.
