# Home Interaction Skeleton Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the Together home-screen interaction skeleton in SwiftUI with stable week/month switching, time-sorted collaboration cards, single pinned item behavior, and anchored item expansion editing using mock data.

**Architecture:** Keep Home as a single feature driven by a dedicated `HomeViewModel`, but split calendar display state, card ordering state, and editor presentation state into explicit sub-models so the list, calendar, and editor can evolve independently. Implement week/month mode as the primary content mode, treat year as a lightweight date-jump entry later, and reserve drag-driven calendar expansion as a second-phase enhancement built on the same state model.

**Tech Stack:** SwiftUI, Observation (`@Observable`), NavigationStack, mock repositories, native SwiftUI animation APIs (`withAnimation`, spring, matched geometry only where necessary), safe-area-aware layout.

---

### Task 1: Freeze the interaction contract before coding

**Files:**
- Create: `docs/plans/2026-03-09-home-interaction-skeleton.md`
- Reference: `ARCHITECTURE.md`
- Reference: `DATA_MODEL.md`
- Reference: `STATE_MACHINE.md`

**Step 1: Document the agreed interaction scope**

Write the following into the plan document:
- Home primary modes are only `week` and `month`.
- `year` is only a date-jump entry, not a persistent home layout.
- Item editor uses anchored expansion with background dimming and background scroll lock.
- Cards sort by `pinned first`, then `priority`, then `dueAt ascending`, then fallback to creation time.
- Pinned card is always pink-emphasized.
- Non-priority cards use a warm off-white surface, not pure white.
- Card ownership avatars show `me`, `partner`, or both.

**Step 2: Explicitly defer second-phase enhancements**

Add a “Phase 2” section:
- Pull-to-expand week into month.
- Continuous calendar expansion progress.
- Advanced matched-geometry polish for card expansion.
- Year jump overlay or year selector.

**Step 3: Commit**

```bash
git add docs/plans/2026-03-09-home-interaction-skeleton.md
git commit -m "docs: define home interaction skeleton plan"
```

### Task 2: Extend domain-facing home state for calendar and editor interactions

**Files:**
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Reference: `Together/Domain/Entities/Item.swift`
- Reference: `Together/PreviewContent/MockDataFactory.swift`

**Step 1: Add explicit home interaction types**

Create feature-local types in `HomeViewModel.swift` or extracted files if they grow:
- `HomeCalendarMode` with `week`, `month`
- `HomeDateJumpEntry` placeholder for future year jump
- `HomeCardSurfaceStyle` with `accent`, `muted`
- `HomeEditorDraft` for title, notes, dueAt, locationText, executionRole, priority, isPinned

**Step 2: Add explicit view model state**

Add properties:
- `calendarMode`
- `expandedEditorItemID`
- `editorDraft`
- `pinnedItemID`
- `isEditorPresented`
- `isBackgroundScrollLocked`

**Step 3: Add deterministic sorting helpers**

Implement computed arrays or helper methods:
- `sortedPendingItems`
- `sortedInProgressItems`
- Shared sort key: pinned first, then priority, then nearest due date, then createdAt

**Step 4: Add editor lifecycle methods**

Implement method stubs:
- `toggleCalendarMode()`
- `presentEditor(for:)`
- `dismissEditor()`
- `togglePin(for:)`
- `updateDraftTitle(_:)`
- `updateDraftDueAt(_:)`
- `updateDraftLocation(_:)`
- `updateDraftExecutionRole(_:)`
- `applyDraft()`

Use mock-only in-memory updates for now.

**Step 5: Commit**

```bash
git add Together/Features/Home/HomeViewModel.swift
git commit -m "feat: add home interaction state model"
```

### Task 3: Expand mock data so the interaction skeleton has realistic states

**Files:**
- Modify: `Together/PreviewContent/MockDataFactory.swift`
- Modify: `Together/Services/Items/MockItemRepository.swift`

**Step 1: Enrich mock items for sorting and editing**

Ensure the mock dataset covers:
- One pending pinned/high-priority item
- One normal in-progress item
- One jointly executed item
- One item with location text
- Mixed near/far due dates

**Step 2: Add mock repository mutation support**

Support in-memory mutation for:
- pin/unpin
- updating title
- updating notes
- updating dueAt
- updating executionRole
- updating priority
- updating location text (requires extending Item if not present yet)

**Step 3: Keep relationship semantics intact**

Do not break:
- one-to-one relationship boundary
- execution role semantics
- item state machine assumptions

**Step 4: Commit**

```bash
git add Together/PreviewContent/MockDataFactory.swift Together/Services/Items/MockItemRepository.swift
git commit -m "feat: enrich mock items for home interactions"
```

### Task 4: Update the item model only where required for the editor skeleton

**Files:**
- Modify: `Together/Domain/Entities/Item.swift`
- Modify: `DATA_MODEL.md`

**Step 1: Add only missing fields needed by the requested editor**

If absent, add minimal fields such as:
- `locationText: String?`
- `isPinned: Bool`

Do not add speculative fields like attachments, repetition, or rich reminders.

**Step 2: Update the data model doc**

Document why these fields exist:
- home sorting
- anchored expansion editor
- card metadata display

**Step 3: Commit**

```bash
git add Together/Domain/Entities/Item.swift DATA_MODEL.md
git commit -m "feat: extend item model for home editor skeleton"
```

### Task 5: Rebuild the home screen layout around stable interaction zones

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`
- Reference: `Together/Core/DesignSystem/AppTheme.swift`

**Step 1: Replace the current sectioned layout with a home-shell layout**

Restructure `HomeView` into these zones:
- top controls row
- compact week/month calendar strip
- timeline + card list area
- bottom floating add button (keep existing if compatible)
- editor overlay layer

**Step 2: Make calendar mode switch stable first**

Implement left-top button behavior:
- tap toggles between `week` and `month`
- animate height/opacity/position with native spring
- no drag gesture yet

**Step 3: Render cards in one unified sorted list**

Stop separating card UI by section for now if it blocks the requested ordering.

Each card should show:
- title
- due time
- priority emphasis color
- ownership avatars
- execution role label
- optional location snippet
- pin affordance

**Step 4: Apply the requested surface logic**

- pinned card: pink emphasis
- high priority card: pink emphasis
- non-priority card: warm off-white
- keep typography and spacing consistent

**Step 5: Lock spacing tokens**

Use a small set of shared constants for:
- horizontal margins
- card internal padding
- card-to-card spacing
- timeline-to-card spacing

**Step 6: Commit**

```bash
git add Together/Features/Home/HomeView.swift
git commit -m "feat: rebuild home layout for interaction skeleton"
```

### Task 6: Implement anchored card expansion editor

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`
- Create: `Together/Features/Home/Components/HomeItemCardView.swift`
- Create: `Together/Features/Home/Components/HomeItemEditorView.swift`

**Step 1: Extract card view and editor view**

Create:
- `HomeItemCardView`
- `HomeItemEditorView`

**Step 2: Add expansion presentation flow**

Card tap should:
- freeze background scroll
- dim background
- animate selected card into expanded editor state
- reserve keyboard space using safe-area-aware bottom handling

**Step 3: Keep editor fields minimal and aligned with current request**

Editor includes:
- title text field
- notes text area
- due time editor
- location editor
- execution role selector
- priority selector
- pin toggle
- close / save controls

**Step 4: Choose stable animation primitives**

Use:
- `withAnimation(.spring(...))`
- `safeAreaInset(edge: .bottom)` or keyboard-aware bottom spacing
- avoid heavy blur animation and avoid full-screen geometry recalculation on every frame

**Step 5: Commit**

```bash
git add Together/Features/Home/HomeView.swift Together/Features/Home/Components/HomeItemCardView.swift Together/Features/Home/Components/HomeItemEditorView.swift
git commit -m "feat: add anchored item expansion editor"
```

### Task 7: Prepare the architecture for phase-two drag expansion without implementing it yet

**Files:**
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `ARCHITECTURE.md`
- Modify: `TODO_NEXT_STEPS.md`

**Step 1: Add reserved state for future drag expansion**

Add placeholders only if useful:
- `calendarExpansionProgress`
- `canTransitionBetweenWeekAndMonth`

Do not wire gestures yet if it destabilizes the first version.

**Step 2: Document why drag expansion is deferred**

Write in docs:
- stronger aesthetic payoff
- higher gesture complexity
- should be built on top of already working mode/state model

**Step 3: Commit**

```bash
git add Together/Features/Home/HomeViewModel.swift ARCHITECTURE.md TODO_NEXT_STEPS.md
git commit -m "docs: prepare phase-two calendar expansion design"
```

### Task 8: Validate behavior and performance baseline

**Files:**
- Modify if needed: `Together/Features/Home/*`
- Verification only: build output

**Step 1: Run build**

Run:
```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS Simulator'
```

Expected:
- Build succeeds with no new errors.

**Step 2: Manual interaction checklist**

Verify:
- week/month toggles cleanly
- cards remain sorted correctly after pinning and editing
- pinned card moves to top immediately
- editor expansion does not overlap keyboard controls
- background scroll locks while editor is open
- animation remains smooth during repeated open/close

**Step 3: Performance sanity check**

Repeat 20 times:
- toggle week/month
- open/close editor
- pin/unpin an item

Expected:
- no visible hitching
- no state desynchronization
- no layout jumps that break safe areas

**Step 4: Commit final home skeleton**

```bash
git add Together
git commit -m "feat: implement home interaction skeleton"
```
