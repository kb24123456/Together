# Together Reliability and Core Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve all existing personal data while removing the Apple sign-in gate, eliminating destructive recovery paths, and completing search, OCR review, deletion, and external-entry flows.

**Architecture:** Keep the existing SwiftData schema, store URL, and CloudKit private container unchanged. Introduce small services for persistence startup, personal identity bootstrap, and full-data deletion; keep view models responsible for presentation state only. Deliver the work in eight independently testable commits on `main`, preserving the pre-existing Profile worktree changes.

**Tech Stack:** Swift 6.2+, SwiftUI, Observation, SwiftData, CloudKit private database, WidgetKit, Vision, Swift Testing, XCTest build/test tooling.

---

## File structure

### New files

- `Together/App/AppPersistenceFailureView.swift`: release-safe store failure and retry UI.
- `Together/Services/Identity/PersonalIdentityService.swift`: resolves existing profile/space without ownership mutation and creates a new local identity only after explicit authorization.
- `Together/Services/DataDeletion/PersonalDataDeletionService.swift`: full deletion manifest, execution, verification, and runtime reset result.
- `Together/Features/Home/HomeTaskFilter.swift`: pure search/filter predicate and selected-filter state.
- `Together/App/AppDeepLink.swift`: typed parsing for Today and task URLs.

### Existing files with primary changes

- `Together/Persistence/PersistenceController.swift`: throwing initialization; no automatic file deletion.
- `Together/App/AppBootstrapper.swift`, `Together/TogetherApp.swift`, `Together/App/AppContext.swift`, `Together/App/SessionStore.swift`: persistence failure state and no-login bootstrap.
- `Together/Services/LocalServiceFactory.swift`, `Together/App/AppContainer.swift`: inject identity and deletion services.
- `Together/Services/Spaces/LocalSpaceService.swift`: remove claim and creator-ID rewriting.
- `Together/Features/Home/HomeViewModel.swift`, `Together/Features/Home/HomeView.swift`: load/error state, search, filters, and external-route feedback.
- `Together/Features/Routines/RoutinesViewModel.swift`, `Together/Features/Routines/RoutinesListContent.swift`: loading/error distinction and retry.
- `Together/Features/Profile/ProfileViewModel.swift`, `Together/Features/Profile/ProfileView.swift`, `Together/Features/Profile/ProfileAccountDeletionView.swift`, `Together/Features/Profile/ProfileSettingsDetailViews.swift`: remove sign-out, run verified deletion, and use truthful iCloud copy.
- `TogetherWidget/TogetherWidgetBundle.swift`, `TogetherWidget/TodayWidgets.swift`, `Together/WidgetSupport/TodayWidgetConstants.swift`, `TogetherWidget/TodayWidgetShared.swift`: remove anniversary surface and add typed URLs.
- `Together/Features/OCRImport/OCRImportViewModel.swift`, `Together/Features/OCRImport/OCRImportView.swift`, `Together/Domain/Models/OCRImportDraft.swift`: raw-text review and structural draft operations.
- `TogetherTests/TogetherTests.swift`: regression and feature tests.
- `PRODUCT_SPEC.md`, `docs/PROJECT_MEMORY.md`: authoritative scope and durable completion record.

---

### Task 1: Make persistence startup non-destructive

**Files:**
- Create: `Together/App/AppPersistenceFailureView.swift`
- Modify: `Together/Persistence/PersistenceController.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/App/AppBootstrapper.swift`
- Modify: `Together/TogetherApp.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add a failing store policy test**

Add a pure policy seam so the test can prove that ordinary open/probe failures never request file deletion:

```swift
@Test func persistenceFailurePolicyNeverDeletesStoreAutomatically() {
    #expect(PersistenceFailurePolicy.shouldDeleteStoreAfterOpenFailure == false)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

```bash
xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TogetherTests/TogetherTests/persistenceFailurePolicyNeverDeletesStoreAutomatically
```

Expected: compile failure because `PersistenceFailurePolicy` does not exist.

- [ ] **Step 3: Replace automatic reset with a throwing startup result**

Implement:

```swift
enum PersistenceFailurePolicy {
    static let shouldDeleteStoreAfterOpenFailure = false
}

struct PersistenceStartupFailure: LocalizedError, Equatable {
    let summary: String
    var errorDescription: String? { "无法安全打开本地数据，请重试。" }
}
```

Make `PersistenceController.init(inMemory:)` throw `PersistenceStartupFailure` after the first failed full initialization. Keep `deleteStoreFiles()` available only for the existing explicit DEBUG reset coordinator; never call it from normal initialization.

- [ ] **Step 4: Propagate failure to the app root**

Add `AppBootstrapper.Phase.persistenceFailed(PersistenceStartupFailure)`, make `AppContext.makeContext()` and `LocalServiceFactory.makeContainer()` throwing, and render `AppPersistenceFailureView` with a retry button in `TogetherApp`.

- [ ] **Step 5: Run focused tests and generic build**

```bash
xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TogetherTests/TogetherTests/persistenceFailurePolicyNeverDeletesStoreAutomatically
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git diff --check
```

- [ ] **Step 6: Commit the persistence safety change**

```bash
git add Together/Persistence/PersistenceController.swift Together/App/AppPersistenceFailureView.swift \
  Together/Services/LocalServiceFactory.swift Together/App/AppContext.swift Together/App/AppBootstrapper.swift \
  Together/TogetherApp.swift TogetherTests/TogetherTests.swift
git commit -m "fix: preserve store on persistence startup failure"
```

### Task 2: Separate loading, empty, and failure states

**Files:**
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/Features/Routines/RoutinesViewModel.swift`
- Modify: `Together/Features/Routines/RoutinesListContent.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add failing view-model state tests**

Use throwing repository doubles to verify:

```swift
@Test func homeReloadFailurePreservesLastSuccessfulItems() async {
    // Load one item, switch repository to failure, reload, assert item remains and loadState is failed.
}

@Test func routinesFailureIsNotPresentedAsEmptyState() async {
    // Repository throws before first successful load; assert loadState is failed and tasks remain empty.
}
```

- [ ] **Step 2: Run the two tests and confirm RED**

Run both with `-only-testing` and expect the home test to observe cleared items and the routines presentation policy to be missing.

- [ ] **Step 3: Implement explicit state preservation**

Add `loadState` and `operationErrorMessage` to `HomeViewModel`. On reload failure, keep `items` and set `.failed(message)`. Add shared presentation policies that render loading, failure/retry, filtered-empty, and true-empty states distinctly. Replace user-triggered empty `catch` blocks with a retained error message.

- [ ] **Step 4: Add native retry UI**

Home and routines failure UI must use a `Button("重试")` that invokes the existing reload method. A failure with cached content uses a compact non-blocking banner; a failure with no content uses a full empty-state-sized error surface.

- [ ] **Step 5: Verify tests, build, and diff**

Run the two focused tests, `git diff --check`, then generic `build-for-testing`.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Home/HomeViewModel.swift Together/Features/Home/HomeView.swift \
  Together/Features/Routines/RoutinesViewModel.swift Together/Features/Routines/RoutinesListContent.swift \
  TogetherTests/TogetherTests.swift
git commit -m "fix: distinguish task loading failures from empty states"
```

### Task 3: Remove the Apple sign-in gate without changing data IDs

**Files:**
- Create: `Together/Services/Identity/PersonalIdentityService.swift`
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/App/SessionStore.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/App/AppBootstrapper.swift`
- Modify: `Together/TogetherApp.swift`
- Modify: `Together/Services/Spaces/LocalSpaceService.swift`
- Modify: `Together/Features/Profile/ProfileView.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Delete: `Together/Features/Auth/SignInView.swift`
- Delete: `Together/Services/Auth/AppleAuthService.swift`
- Delete: `Together/Services/Auth/MockAuthService.swift`
- Delete: `Together/Domain/Protocols/AuthServiceProtocol.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add failing identity resolution tests**

Cover existing matching profile/space, existing data-bearing space without owner rewrite, and fully empty store:

```swift
@Test func identityResolutionPreservesExistingProfileAndSpaceIDs() async throws { }
@Test func spaceLookupDoesNotClaimOrRewriteCreatorIDs() async throws { }
@Test func emptyIdentityRequiresExplicitLocalStart() async throws { }
```

- [ ] **Step 2: Confirm RED**

Run the three focused tests. Expected: missing `PersonalIdentityService` and current claim behavior violates the second test.

- [ ] **Step 3: Implement `PersonalIdentityService`**

Return one of:

```swift
enum PersonalIdentityResolution {
    case ready(user: User, space: Space)
    case waitingForCloudRestore
    case requiresLocalStart
}
```

Never rewrite an existing profile ID, space ID, owner ID, or creator ID. Create profile/space only from an explicit `startLocally()` call or after a successful initial CloudKit import proves the store is empty.

- [ ] **Step 4: Replace auth bootstrap**

Remove `.needsAuth`, `handleSignIn`, and sign-out transitions. `SessionStore` becomes a personal runtime session with `.signedIn` used only as legacy internal compatibility until the enum is removed in a later cleanup. The app renders restore/start-local UI instead of `SignInView`.

- [ ] **Step 5: Observe initial CloudKit import**

Use `NSPersistentCloudKitContainer.eventChangedNotification` only to trigger another identity query after a successful import event. Ten seconds updates the message to “恢复时间较长” but never creates a second space automatically.

- [ ] **Step 6: Remove ownership claim and sign-out UI**

Delete `claimSingleSpaceIfNeeded`, Apple-auth services, sign-out button, and account-auth wording. Preserve the current Profile redesign and its uncommitted reminder settings work.

- [ ] **Step 7: Verify**

Run the identity tests, the existing SessionStore tests, full `TogetherTests`, generic build-for-testing, and `rg -n "SignInWithApple|signInWithApple|退出登录|needsAuth" Together TogetherTests`.

- [ ] **Step 8: Commit**

Commit only after confirming the current Profile work is compatible and included intentionally:

```bash
git add Together TogetherTests PRODUCT_SPEC.md
git commit -m "refactor: use local iCloud identity without sign in"
```

### Task 4: Implement verified personal-data deletion and remove anniversary Widget

**Files:**
- Create: `Together/Services/DataDeletion/PersonalDataDeletionService.swift`
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Modify: `Together/Features/Profile/ProfileAccountDeletionView.swift`
- Modify: `TogetherWidget/TogetherWidgetBundle.swift`
- Modify: `TogetherWidget/TodayWidgetShared.swift`
- Modify: `Together/WidgetSupport/TodayWidgetConstants.swift`
- Delete: `TogetherWidget/AnniversaryWidgets.swift`
- Delete: `TogetherWidget/AnniversaryWidgetShared.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add failing deletion-manifest tests**

Seed every persistent model plus Widget files, avatar data, and notification doubles. Assert that a successful deletion leaves no manifest entities and that an injected failure returns `.failed` without reporting completion.

- [ ] **Step 2: Confirm RED**

Run focused deletion tests; expect missing service failures.

- [ ] **Step 3: Implement deletion service**

Use one `ModelContext` transaction for persistent entities, explicit file cleanup for avatars/Widget files, and an injected reminder scheduler. Return:

```swift
enum PersonalDataDeletionResult: Equatable {
    case completed(newUser: User, newSpace: Space)
    case failed(message: String)
}
```

Verify the manifest after save before creating the replacement empty profile/space.

- [ ] **Step 4: Wire deletion UI**

Keep the page visible on failure, show a retry action, and return to the new empty task home only after `.completed`. Change copy to “本机删除完成后，iCloud 会继续同步删除”.

- [ ] **Step 5: Remove anniversary Widget surface**

Remove its bundle registration and sources. Keep legacy SwiftData models unchanged. Remove unreferenced anniversary snapshot constants and assets only when target membership/search proves no remaining consumer.

- [ ] **Step 6: Verify**

Run focused deletion tests, full tests, Widget/main generic build-for-testing, `git diff --check`, and residual search.

- [ ] **Step 7: Commit**

```bash
git add Together TogetherWidget TogetherTests
git commit -m "feat: verify full personal data deletion"
```

### Task 5: Add active-task search and four composable filters

**Files:**
- Create: `Together/Features/Home/HomeTaskFilter.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/App/AppRootView.swift`
- Modify: `PRODUCT_SPEC.md`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add parameterized failing filter tests**

Test title, notes, subtask localized search plus urgent, overdue, unscheduled, and reminder filters independently and in combination.

- [ ] **Step 2: Confirm RED**

Run focused tests; expect missing `HomeTaskFilter`.

- [ ] **Step 3: Implement pure filtering**

Use `localizedStandardContains` and a `Set<HomeTaskFilterOption>`:

```swift
enum HomeTaskFilterOption: String, CaseIterable, Hashable {
    case urgent, overdue, unscheduled, hasReminder
}
```

Filtered items continue through the existing grouping/sorting pipeline.

- [ ] **Step 4: Add native search/filter UI**

Use `.searchable` on the root task surface and a native bottom/top toolbar filter `Menu` or fitted sheet. Starting search first saves and collapses the current inline draft. Provide a specific filtered-empty state.

- [ ] **Step 5: Resolve Lists scope in product documentation**

Remove claims that Lists is a completed MVP surface, retain its persistence model as legacy/schema compatibility, and do not add a Lists navigation route.

- [ ] **Step 6: Verify and commit**

Run focused filter tests, full tests, build-for-testing, diff check, then commit:

```bash
git add Together/Features/Home Together/App/AppRootView.swift TogetherTests/TogetherTests.swift PRODUCT_SPEC.md
git commit -m "feat: search and filter active tasks"
```

### Task 6: Complete OCR structural review

**Files:**
- Modify: `Together/Domain/Models/OCRImportDraft.swift`
- Modify: `Together/Features/OCRImport/OCRImportViewModel.swift`
- Modify: `Together/Features/OCRImport/OCRImportView.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add failing structural-operation tests**

Test top-level add/delete/move, adjacent merge, subtask split, original raw text preservation, and selection integrity.

- [ ] **Step 2: Confirm RED**

Run the focused OCR tests and expect missing view-model operations.

- [ ] **Step 3: Implement draft operations in the view model**

Operations mutate only `draft.taskDrafts`, refresh `updatedAt`, and never call application services before `apply(to:)`.

- [ ] **Step 4: Add raw-text and structural controls**

Add a collapsed-by-default `DisclosureGroup("识别原文")` with selectable text, an add-task button, deletion context/swipe actions, `EditButton`-driven move support, merge action for non-first rows, and split action on subtask rows.

- [ ] **Step 5: Verify and commit**

Run focused OCR tests, full tests, generic build, diff check, then commit:

```bash
git add Together/Domain/Models/OCRImportDraft.swift Together/Features/OCRImport TogetherTests/TogetherTests.swift
git commit -m "feat: add structural OCR draft review"
```

### Task 7: Type and validate external entry routes

**Files:**
- Create: `Together/App/AppDeepLink.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/App/AppRouter.swift`
- Modify: `Together/App/AppRootView.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/WidgetSupport/TodayWidgetConstants.swift`
- Modify: `TogetherWidget/TodayWidgetShared.swift`
- Modify: `TogetherWidget/TodayWidgets.swift`
- Modify: `Together/App/AppNotificationDelegate.swift`
- Test: `TogetherTests/TogetherTests.swift`

- [ ] **Step 1: Add failing route parser tests**

Test `together://today`, `together://task/<uuid>`, malformed UUID, unknown host, and missing task fallback.

- [ ] **Step 2: Confirm RED**

Run focused tests; expect missing `AppDeepLink`.

- [ ] **Step 3: Implement typed parsing and routing**

```swift
enum AppDeepLink: Equatable {
    case today
    case task(UUID)
}
```

Today resets the root surface. Task routes reload, verify existence, and then publish a single pending highlight. Missing tasks produce a user-visible retry message rather than silently scrolling to nowhere.

- [ ] **Step 4: Update Widget and notifications**

Use root Today URL for widget background and task URLs for tappable non-completion regions where WidgetKit interaction rules permit. Keep completion checkbox actions isolated to `TodayTaskCompletionIntent`. Route notification taps through the same typed task path.

- [ ] **Step 5: Verify and commit**

Run focused route tests, Widget snapshot/completion tests, full tests, generic build, diff check, then commit:

```bash
git add Together/App Together/Features/Home Together/WidgetSupport TogetherWidget TogetherTests/TogetherTests.swift
git commit -m "fix: validate widget and notification deep links"
```

### Task 8: Final scope audit, documentation, and verification

**Files:**
- Modify: `PRODUCT_SPEC.md`
- Modify: `docs/PROJECT_MEMORY.md`
- Modify: any file identified by the authoritative residual audit

- [ ] **Step 1: Run requirement-by-requirement residual searches**

```bash
rg -n "SignInWithApple|signInWithApple|needsAuth|退出登录|AnniversaryWidget|双人纪念日" Together TogetherWidget TogetherTests PRODUCT_SPEC.md
rg -n "catch \{\}|deleteStoreFiles\(\)" Together --glob '*.swift'
rg -n "已连接|同步完成|所有数据已上传" Together/Features/Profile Together/Services
```

Classify every hit as required legacy schema/migration evidence or unfinished work; remove unfinished product/runtime hits.

- [ ] **Step 2: Run complete verification**

```bash
git diff --check
plutil -lint Together/Info.plist Together/Together.entitlements TogetherWidget/Info.plist TogetherWidget/TogetherWidget.entitlements
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Review all changes for P0/P1/P2 issues**

Inspect the full diff, test coverage, store/schema invariants, Widget target membership, and user-visible copy. Fix and re-run affected verification for every finding.

- [ ] **Step 4: Update project memory**

Record durable decisions, changed entry points, validation commands/results, and the remaining true-device-only checks in `docs/PROJECT_MEMORY.md`.

- [ ] **Step 5: Commit final documentation**

```bash
git add PRODUCT_SPEC.md docs/PROJECT_MEMORY.md
git commit -m "docs: record reliability and core flow completion"
```

- [ ] **Step 6: Produce the true-device acceptance checklist**

List upgrade retention, same-iCloud second-device restore, reinstall restore, offline-first merge, iCloud-account isolation, remote deletion propagation, Widget interactions, and OCR camera/input checks as unverified until each is run on physical devices.
