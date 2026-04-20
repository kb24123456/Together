# Logbook Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore user access to completed-task history (removed in Profile L3 redesign) via a new Home top-right "日志" entry, add a narrative pair-mode stats hero, and show a per-row completion avatar in pair mode.

**Architecture:** One new SwiftUI component (`LogbookPairSummaryHero`), four-property extension to `CompletedHistoryViewModel` (pair flag + stats summary + avatar/name helpers), one new `HomeRoute.logbook` case, one icon insertion in `HomeView.headerSection`, and a new `AppContext.makeCompletedHistoryViewModel()` factory so both Home and Profile push into the same screen. `Item.lastActionByUserID` acts as the "completed by" proxy without any schema change.

**Tech Stack:** SwiftUI, Swift Testing (`@Test`), iOS 17+ NavigationStack, `@Observable` ViewModels, AppTheme tokens (hairline / displayLight / textTertiary added in Profile redesign).

**Test Command:**
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Focused:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/<SuiteName>
```

**Branch:** one branch `feat/logbook-entry` off `main`. Every task = 1 commit. Full regression after every task.

---

## File Structure

### Created (2 files)

| Path | Responsibility |
|---|---|
| `Together/Features/Profile/LogbookPairSummaryHero.swift` | `LogbookPairSummary` struct + `LogbookPairSummaryHero` view + 3-tier copy + `relativeTime` formatter |
| `TogetherTests/LogbookPairSummaryTests.swift` | 6 `@Test`s validating tier copy + relativeTime boundaries |

### Modified (5 files)

| Path | Change |
|---|---|
| `Together/App/AppRoute.swift` | Add `enum HomeRoute { case logbook }` |
| `Together/App/AppContext.swift` | Add `makeCompletedHistoryViewModel()` factory at AppContext level so Home + Profile share one wiring |
| `Together/Features/Profile/CompletedHistoryViewModel.swift` | Add `isPairMode`, `pairSummary: LogbookPairSummary?`, `avatarAsset(forUserID:)`, `displayName(forUserID:)`; extend `reload()` to load stats via a separate aggregation fetch |
| `Together/Features/Profile/CompletedHistoryView.swift` | Conditional hero render; per-row completion avatar column (pair only); nav title "历史任务" → "日志"; empty-state branching |
| `Together/Features/Home/HomeView.swift` | Insert `book.closed` icon button in `headerSection`; wire `.navigationDestination(for: HomeRoute.self)` to push `CompletedHistoryView` |

Profile `makeCompletedHistoryViewModel()` still works — its body changes to delegate to the AppContext factory (keeps `ProfileView` call site untouched).

---

## Task 1: `LogbookPairSummaryHero` component + `LogbookPairSummary` model

**Files:**
- Create: `Together/Features/Profile/LogbookPairSummaryHero.swift`
- Create: `TogetherTests/LogbookPairSummaryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TogetherTests/LogbookPairSummaryTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite
struct LogbookPairSummaryTests {

    @Test func zeroCount_primaryIsStart_secondaryIsOnTheWay() {
        let summary = LogbookPairSummary(totalCount: 0, thisMonthCount: 0, firstItemTitle: nil, lastCompletedAt: nil)
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "一起开始记录")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "你们的第一件任务还在路上")
    }

    @Test func underTen_primaryIncludesCount_secondaryIncludesFirstTitle() {
        let summary = LogbookPairSummary(
            totalCount: 3, thisMonthCount: 2,
            firstItemTitle: "洗衣服", lastCompletedAt: .now
        )
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "我们一起完成了 3 件事")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "第一件：洗衣服")
    }

    @Test func underTen_missingTitle_fallsBackToOnTheWay() {
        let summary = LogbookPairSummary(totalCount: 1, thisMonthCount: 1, firstItemTitle: nil, lastCompletedAt: .now)
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now) == "你们的第一件任务还在路上")
    }

    @Test func tenPlus_secondaryIncludesMonthAndRelativeTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let summary = LogbookPairSummary(
            totalCount: 42, thisMonthCount: 12,
            firstItemTitle: "旧事", lastCompletedAt: twoHoursAgo
        )
        #expect(LogbookPairSummaryCopy.primaryText(for: summary) == "我们一起完成了 42 件事")
        #expect(LogbookPairSummaryCopy.secondaryText(for: summary, now: now) == "本月 12 件 · 最近一次：2 小时前")
    }

    @Test func relativeTime_justNowBucket() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-30), now: now) == "刚刚")
    }

    @Test func relativeTime_minutesAndHoursAndDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-120), now: now) == "2 分钟前")
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-3600 * 5), now: now) == "5 小时前")
        #expect(LogbookPairSummaryCopy.relativeTime(from: now.addingTimeInterval(-86400 * 3), now: now) == "3 天前")
    }

    @Test func relativeTime_sevenDaysPlus_fallsBackToMonthDay() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 20
        let now = calendar.date(from: components) ?? .now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let output = LogbookPairSummaryCopy.relativeTime(from: twoWeeksAgo, now: now)
        #expect(output.contains("4"))
        #expect(output.contains("6"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/LogbookPairSummaryTests
```

Expected: FAIL — `LogbookPairSummary` and `LogbookPairSummaryCopy` unresolved.

- [ ] **Step 3: Implement the model + copy helper + view**

Create `Together/Features/Profile/LogbookPairSummaryHero.swift`:

```swift
import SwiftUI

/// Stats snapshot for the pair-mode Logbook hero.
/// Aggregated once per load from completed items in the pair space.
struct LogbookPairSummary: Equatable, Sendable {
    let totalCount: Int
    let thisMonthCount: Int
    let firstItemTitle: String?
    let lastCompletedAt: Date?
}

/// Copy rules for the Logbook hero. Pulled out of the View to keep the
/// tier logic unit-testable without Snapshot / UIHosting scaffolding.
enum LogbookPairSummaryCopy {
    static func primaryText(for summary: LogbookPairSummary) -> String {
        if summary.totalCount == 0 {
            return "一起开始记录"
        }
        return "我们一起完成了 \(summary.totalCount) 件事"
    }

    static func secondaryText(for summary: LogbookPairSummary, now: Date) -> String {
        if summary.totalCount == 0 {
            return "你们的第一件任务还在路上"
        }

        if summary.totalCount < 10 {
            if let firstTitle = summary.firstItemTitle, firstTitle.isEmpty == false {
                return "第一件：\(firstTitle)"
            }
            return "你们的第一件任务还在路上"
        }

        let lastText: String
        if let lastCompletedAt = summary.lastCompletedAt {
            lastText = relativeTime(from: lastCompletedAt, now: now)
        } else {
            lastText = "暂无"
        }
        return "本月 \(summary.thisMonthCount) 件 · 最近一次：\(lastText)"
    }

    /// Converts a past date into a compact Chinese relative label.
    /// Buckets: <60s → 刚刚; <1h → N 分钟前; <1d → N 小时前;
    /// <7d → N 天前; >=7d → M 月 D 日
    static func relativeTime(from date: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))

        if interval < 60 {
            return "刚刚"
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) 分钟前"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) 小时前"
        }
        if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days) 天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}

/// Pair-mode Logbook hero. Rendered as the first cell inside the
/// CompletedHistoryView List. No card background — sits on the page's
/// warm off-white with a 1px hairline divider at the bottom.
struct LogbookPairSummaryHero: View {
    let summary: LogbookPairSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
            Text(LogbookPairSummaryCopy.primaryText(for: summary))
                .font(AppTheme.typography.displayLight(20))
                .tracking(0.2)
                .foregroundStyle(AppTheme.colors.title)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: summary.totalCount)

            Text(LogbookPairSummaryCopy.secondaryText(for: summary, now: .now))
                .font(AppTheme.typography.sized(13, weight: .regular))
                .foregroundStyle(AppTheme.colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.lg)
        .padding(.top, AppTheme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.colors.hairline)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.spacing.md)
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/LogbookPairSummaryTests
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/LogbookPairSummaryHero.swift TogetherTests/LogbookPairSummaryTests.swift
git commit -m "$(cat <<'EOF'
feat(logbook): add LogbookPairSummary model + hero view

Introduces LogbookPairSummary struct (totalCount / thisMonthCount /
firstItemTitle / lastCompletedAt) and the SwiftUI hero view that
renders one of three copy tiers (0 / 1-9 / 10+). Tier + relativeTime
logic extracted into LogbookPairSummaryCopy enum for unit testability
without UIHosting. Hero uses displayLight(20) + hairline divider and
no card background — matches the Profile identity-card language.

Not wired into CompletedHistoryView yet — Task 3 does that after the
VM exposes pairSummary in Task 2.

Per spec 2026-04-20-logbook-entry-design §4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `CompletedHistoryViewModel` extensions + stats aggregation

**Files:**
- Modify: `Together/Features/Profile/CompletedHistoryViewModel.swift`
- Test: `TogetherTests/CompletedHistoryViewModelPairTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `TogetherTests/CompletedHistoryViewModelPairTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct CompletedHistoryViewModelPairTests {

    @Test func avatarAssetForSelfReturnsCurrentUserAsset() {
        let vm = makeVM()
        let currentUser = vm.sessionStoreForTesting.currentUser
        guard let userID = currentUser?.id else {
            Issue.record("Bootstrapped session must have a currentUser")
            return
        }

        let asset = vm.avatarAsset(forUserID: userID)
        let expected = currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        #expect(asset == expected)
    }

    @Test func avatarAssetForUnknownIDFallsBackToGenericPerson() {
        let vm = makeVM()
        let asset = vm.avatarAsset(forUserID: UUID())
        #expect(asset == .system("person.fill"))
    }

    @Test func avatarAssetForNilFallsBackToGenericPerson() {
        let vm = makeVM()
        let asset = vm.avatarAsset(forUserID: nil)
        #expect(asset == .system("person.fill"))
    }

    @Test func displayNameForUnknownIDFallsBack() {
        let vm = makeVM()
        #expect(vm.displayName(forUserID: UUID()) == "未知完成者")
        #expect(vm.displayName(forUserID: nil) == "未知完成者")
    }

    @Test func isPairModeReflectsSessionStore() {
        let vm = makeVM()
        // Bootstrap seeds a paired mock session
        #expect(vm.isPairMode == true)
    }

    // MARK: - Helpers

    private func makeVM() -> CompletedHistoryViewModel {
        let context = AppContext.makeBootstrappedContext()
        return context.makeCompletedHistoryViewModel()
    }
}
```

The test refers to `AppContext.makeCompletedHistoryViewModel()` and `vm.sessionStoreForTesting`. Both do not exist yet. The first gets added in Task 4; for now the helper uses the existing `profileViewModel.makeCompletedHistoryViewModel()`. Adjust step 3 below accordingly.

**Adjusted helper** (use this form until Task 4 lands):

```swift
    private func makeVM() -> CompletedHistoryViewModel {
        let context = AppContext.makeBootstrappedContext()
        return context.profileViewModel.makeCompletedHistoryViewModel()
    }
```

Also `vm.sessionStoreForTesting` doesn't exist. Replace that test's body with one that doesn't depend on session introspection:

```swift
    @Test func avatarAssetForCurrentUserIDReturnsCurrentUserAsset() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        guard let userID = context.sessionStore.currentUser?.id else {
            Issue.record("Bootstrap must seed a currentUser")
            return
        }
        let expected = context.sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        #expect(vm.avatarAsset(forUserID: userID) == expected)
    }
```

Use this version. Delete the `sessionStoreForTesting` reference.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/CompletedHistoryViewModelPairTests
```

Expected: FAIL — `isPairMode`, `avatarAsset(forUserID:)`, `displayName(forUserID:)` unresolved.

- [ ] **Step 3: Extend CompletedHistoryViewModel**

Open `Together/Features/Profile/CompletedHistoryViewModel.swift`.

**3a. Add the stored property for pair summary** near the other `var` declarations (after `canLoadMore = true` around line 27):

```swift
    /// Aggregated stats for the Logbook pair-mode hero. Nil when solo.
    /// Populated during `reload()` via a separate full-count fetch.
    private(set) var pairSummary: LogbookPairSummary?
```

**3b. Add `isPairMode` computed property** (near the top, after `pairSummary` or next to the existing private properties):

```swift
    var isPairMode: Bool { sessionStore.hasActivePairSpace }
```

**3c. Add the avatar + name helpers**. Place them next to `subtitle(for:)` around line 164:

```swift
    /// Returns the avatar asset for a given user ID. Resolves:
    /// - currentUser.id → currentUser.avatarAsset
    /// - partner user ID → partner.avatarAsset
    /// - nil or unknown → `.system("person.fill")`
    func avatarAsset(forUserID userID: UUID?) -> UserAvatarAsset {
        guard let userID else { return .system("person.fill") }
        if userID == sessionStore.currentUser?.id {
            return sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        }
        if let partner = sessionStore.pairSpaceSummary?.partner, partner.userID == userID {
            return partner.avatarAsset
        }
        return .system("person.fill")
    }

    /// Resolves a display name for VoiceOver. Mirrors `avatarAsset`'s lookup.
    func displayName(forUserID userID: UUID?) -> String {
        guard let userID else { return "未知完成者" }
        if userID == sessionStore.currentUser?.id {
            return sessionStore.currentUser?.displayName ?? "我"
        }
        if let partner = sessionStore.pairSpaceSummary?.partner, partner.userID == userID {
            return partner.displayName
        }
        return "未知完成者"
    }
```

**3d. Extend `reload()` to populate `pairSummary`**. Edit the method body (around line 74). After the existing `do { ... } catch { ... }` block, add:

```swift
        await refreshPairSummaryIfNeeded(spaceID: spaceID)
```

**3e. Add the private aggregation helper** (near `runAutoArchiveIfNeeded` around line 226):

```swift
    private func refreshPairSummaryIfNeeded(spaceID: UUID) async {
        guard isPairMode else {
            pairSummary = nil
            return
        }

        // Bounded full-fetch for stats. `fetchCompletedItems` with a large
        // limit returns every completed item in the pair space, including
        // archived ones (the cursor logic includes archived via
        // historySortDate). Typical user has <1000 items; acceptable.
        let allItems: [Item]
        do {
            allItems = try await itemRepository.fetchCompletedItems(
                spaceID: spaceID,
                searchText: nil,
                before: nil,
                limit: Int.max
            )
        } catch {
            pairSummary = nil
            return
        }

        let now = Date()
        let monthComponents = calendar.dateComponents([.year, .month], from: now)

        let thisMonthCount = allItems.filter { item in
            guard let completedAt = item.completedAt else { return false }
            let comps = calendar.dateComponents([.year, .month], from: completedAt)
            return comps.year == monthComponents.year && comps.month == monthComponents.month
        }.count

        let firstItem = allItems.min { a, b in
            let aDate = a.completedAt ?? a.updatedAt
            let bDate = b.completedAt ?? b.updatedAt
            return aDate < bDate
        }

        let lastCompletedAt = allItems
            .compactMap { $0.completedAt }
            .max()

        pairSummary = LogbookPairSummary(
            totalCount: allItems.count,
            thisMonthCount: thisMonthCount,
            firstItemTitle: firstItem?.title,
            lastCompletedAt: lastCompletedAt
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/CompletedHistoryViewModelPairTests
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/CompletedHistoryViewModel.swift TogetherTests/CompletedHistoryViewModelPairTests.swift
git commit -m "$(cat <<'EOF'
feat(logbook): extend CompletedHistoryViewModel for pair mode

Adds isPairMode / pairSummary / avatarAsset(forUserID:) /
displayName(forUserID:). On reload, the VM runs one extra bounded
full-count fetch via fetchCompletedItems(limit: .max) and aggregates
totalCount / thisMonthCount / firstItemTitle / lastCompletedAt into
a LogbookPairSummary. Nil in solo mode. Avatar/name helpers resolve
self vs partner vs fallback (`person.fill`).

Stats aggregation is best-effort: typical user <1000 items, so
one-shot full fetch is acceptable. If the user has thousands of
completed items the load may be slow — spec §9 flags this follow-up.

Per spec 2026-04-20-logbook-entry-design §4.8 + §5.4 + §5.5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Integrate hero + row avatar into `CompletedHistoryView` + rename nav title

**Files:**
- Modify: `Together/Features/Profile/CompletedHistoryView.swift`

- [ ] **Step 1: Rename nav title**

Open `Together/Features/Profile/CompletedHistoryView.swift`. Find (around line 56):

```swift
        .navigationTitle("历史任务")
```

Change to:

```swift
        .navigationTitle("日志")
```

- [ ] **Step 2: Insert hero as the first row (pair mode only)**

Inside the `List` body, above the `if viewModel.sections.isEmpty { ... }` branch (around line 8-9), insert:

```swift
        List {
            if viewModel.isPairMode, let summary = viewModel.pairSummary {
                LogbookPairSummaryHero(summary: summary)
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.sections.isEmpty {
                emptySectionIfNotHandledByHero
            } else {
```

**Also**: rename the existing `emptySection` usage so it only fires when the hero is not already covering the empty state. Replace the existing `emptySection` call (currently inside `if viewModel.sections.isEmpty`) with:

```swift
            if viewModel.sections.isEmpty {
                if viewModel.isPairMode == false {
                    emptySection
                }
            } else {
```

So the final List prefix looks like:

```swift
        List {
            if viewModel.isPairMode, let summary = viewModel.pairSummary {
                LogbookPairSummaryHero(summary: summary)
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.sections.isEmpty {
                if viewModel.isPairMode == false {
                    emptySection
                }
            } else {
                ForEach(viewModel.sections) { section in
                    // … existing body unchanged …
                }

                if viewModel.isLoading {
                    loadingRow
                }
            }
        }
```

- [ ] **Step 3: Add per-row completion avatar column (pair mode only)**

Find `historyRow(for:)` around line 95. Replace the ENTIRE function body with:

```swift
    private func historyRow(for item: Item) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            if viewModel.isPairMode {
                completionAvatar(for: item)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(item.title)
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)

                Text(viewModel.subtitle(for: item))
                    .font(AppTheme.typography.textStyle(.subheadline))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))

                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(viewModel.completedDateText(for: item))
                    if viewModel.isArchived(item) {
                        Text(viewModel.archivedDateText(for: item))
                    }
                }
                .font(AppTheme.typography.textStyle(.caption1))
                .foregroundStyle(AppTheme.colors.body.opacity(0.64))
            }
        }
        .padding(.vertical, AppTheme.spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pairModeAccessibilityLabel(for: item))
    }

    @ViewBuilder
    private func completionAvatar(for item: Item) -> some View {
        let completerID = item.lastActionByUserID
        let asset = viewModel.avatarAsset(forUserID: completerID)
        let displayName = viewModel.displayName(forUserID: completerID)
        UserAvatarView(
            avatarAsset: asset,
            displayName: displayName,
            size: 20,
            fillColor: AppTheme.colors.avatarWarm,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(10, weight: .semibold),
            overrideImage: nil
        )
        .padding(.top, 2)
    }

    private func pairModeAccessibilityLabel(for item: Item) -> String {
        let completer = viewModel.displayName(forUserID: item.lastActionByUserID)
        let completedDate = viewModel.completedDateText(for: item)
        if viewModel.isPairMode {
            return "\(completer) 完成 · \(item.title) · \(completedDate)"
        }
        return "\(item.title) · \(completedDate)"
    }
```

- [ ] **Step 4: Build + test**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/CompletedHistoryView.swift
git commit -m "$(cat <<'EOF'
feat(logbook): wire pair-mode hero and per-row completion avatar

CompletedHistoryView now:
- renders LogbookPairSummaryHero as the first List cell when pair
  mode + pairSummary exists
- suppresses the 'empty' card in pair mode when sections is empty
  (hero handles the zero-state copy)
- wraps each history row in an HStack with a 20pt leading avatar
  column resolving the completer via item.lastActionByUserID
- combines accessibility into one label per row: '{completer} 完成 ·
  {title} · {completedDate}'
- renames nav title 历史任务 → 日志

Per spec 2026-04-20-logbook-entry-design §4 + §5 + §6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Home top-right entry + `AppContext` factory

**Files:**
- Modify: `Together/App/AppRoute.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: Add `HomeRoute.logbook`**

In `Together/App/AppRoute.swift`, add a new enum at the end of the file:

```swift
enum HomeRoute: Hashable {
    case logbook
}
```

(If `HomeRoute` already exists for other reasons, add `case logbook` to it instead.)

- [ ] **Step 2: Add `makeCompletedHistoryViewModel` factory to AppContext**

Open `Together/App/AppContext.swift`. The class already has `profileViewModel: ProfileViewModel` and access to `sessionStore` + repositories. Near the other factory helpers, add a new method on `AppContext`:

```swift
    /// Creates a new CompletedHistoryViewModel wired to the shared
    /// dependencies. Used by both ProfileView and HomeView so the
    /// two Logbook entries share a single source of truth for wiring.
    @MainActor
    func makeCompletedHistoryViewModel() -> CompletedHistoryViewModel {
        let vm = CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: container.itemRepository,
            taskApplicationService: container.taskApplicationService,
            taskListRepository: container.taskListRepository,
            projectRepository: container.projectRepository
        )
        vm.onTaskMutated = { [weak self] spaceID in
            self?.profileViewModel.onTaskMutated?(spaceID)
        }
        vm.onSharedMutationRecorded = { [weak self] change in
            self?.profileViewModel.onSharedMutationRecorded?(change)
        }
        return vm
    }
```

(If the exact dependency field names differ — e.g., `container.items` instead of `container.itemRepository` — grep `ProfileViewModel.makeCompletedHistoryViewModel` implementation at line ~642 and mirror its wiring exactly.)

- [ ] **Step 3: Update ProfileViewModel factory to delegate**

In `Together/Features/Profile/ProfileViewModel.swift`, find `makeCompletedHistoryViewModel()` around line 642. Currently it builds the VM inline. Change the body to delegate (but keep the method signature — `ProfileView` already calls it):

Option A (simplest, keep as-is): leave it untouched. The Profile path continues to use the local factory; only Home uses `AppContext.makeCompletedHistoryViewModel()`. There's minor duplication (~10 lines) but zero behavior change.

Option B (DRY): extract the AppContext factory first, then make ProfileViewModel's version call into it. Requires ProfileViewModel to hold a reference to AppContext, which isn't the case today.

**Choose Option A** for simplicity. Skip this step. Keep ProfileViewModel unchanged.

- [ ] **Step 4: Add icon + route in HomeView**

Open `Together/Features/Home/HomeView.swift`. Find `headerSection` around line 200. Inside the top-right Spacer block, before `headerAvatarButton(compact: isOverlayModeActive)`, insert a new icon button:

```swift
            Spacer(minLength: 0)

            logbookEntryButton(compact: isOverlayModeActive)

            headerAvatarButton(compact: isOverlayModeActive)
        }
```

Also in the alternative path around line 289 (`headerTopRow(compact:)` if it renders the avatar there), insert the same button before the avatar if both paths render icons.

Add the helper function near `headerAvatarButton(compact:)` (around line 383):

```swift
    private func logbookEntryButton(compact: Bool) -> some View {
        NavigationLink(value: HomeRoute.logbook) {
            Image(systemName: "book.closed")
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .foregroundStyle(headerPrimaryColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                HomeInteractionFeedback.selection()
            }
        )
        .accessibilityLabel("日志")
        .accessibilityHint("查看已完成任务")
    }
```

- [ ] **Step 5: Wire the navigation destination in HomeView**

Find the outer NavigationStack / `.navigationDestination(for:)` declaration in HomeView. If it already has `.navigationDestination(for: ...)` cases, add a new one for `HomeRoute`:

```swift
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .logbook:
                CompletedHistoryView(viewModel: appContext.makeCompletedHistoryViewModel())
            }
        }
```

If HomeView does NOT have any `.navigationDestination(for:)` yet, add the modifier to the outermost `NavigationStack` content in the body. Grep `navigationDestination` in HomeView.swift to find existing spots. The modifier must attach to the NavigationStack or a view inside it.

- [ ] **Step 6: Build + test**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED.

Then:

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 7: Manual simulator smoke**

Launch the simulator. On the Home screen:
- Top-right now shows `book.closed` icon left of the avatar toggle
- Tap → pushes into the Logbook (formerly "历史任务", now "日志")
- Pair mode: hero shows at top, per-row avatars visible
- Solo mode: no hero, no per-row avatar, layout matches the old Profile → History view

- [ ] **Step 8: Commit**

```bash
git add Together/App/AppRoute.swift Together/App/AppContext.swift Together/Features/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat(logbook): add Home top-right 日志 entry + shared factory

Adds HomeRoute.logbook local route and a book.closed icon button in
HomeView.headerSection, left of the existing avatar toggle. Tapping
pushes into CompletedHistoryView (now titled '日志'). The factory
AppContext.makeCompletedHistoryViewModel() lets both Home and Profile
push into the same screen with shared mutation callbacks.

Leaves ProfileViewModel.makeCompletedHistoryViewModel() unchanged
(minor duplication is cheaper than threading AppContext into the VM).

Closes the Profile L3 redesign regression where 历史任务 had no entry.

Per spec 2026-04-20-logbook-entry-design §3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**

- §1 Background — rationale threaded through task commit messages
- §2 Goals / Non-goals — implemented as one feature, no schema change, no dock change
- §3 Entry point (icon, route, accessibility) — Task 4 (steps 1, 4, 5)
- §4 Pair stats hero — Task 1 (component + copy) + Task 2 (VM summary) + Task 3 (wire)
- §5 Per-row avatar — Task 2 (VM helpers) + Task 3 (row integration)
- §6 Naming + empty state — Task 3 (steps 1 + 2)
- §7 File change list — Task 1 / 2 / 3 / 4 each own their files
- §8 Testing — Task 1 (6 hero tests), Task 2 (5 VM tests)
- §9 Known limits flagged in Task 2 commit message
- §11 Open decisions — all resolved in spec

**Placeholder scan:** No "TBD", no vague "add error handling", no "similar to Task N" references. Every code block contains actual content.

**Type consistency:**

- `LogbookPairSummary` struct: declared Task 1, consumed in Task 2 (`pairSummary` property) and Task 3 (hero render)
- `LogbookPairSummaryCopy.primaryText / secondaryText / relativeTime` — defined Task 1, referenced only inside the Task 1 view body
- `isPairMode` / `pairSummary` / `avatarAsset(forUserID:)` / `displayName(forUserID:)` — defined Task 2, consumed Task 3
- `HomeRoute.logbook` — defined Task 4 step 1, consumed Task 4 step 4 + 5
- `AppContext.makeCompletedHistoryViewModel()` — defined Task 4 step 2, consumed Task 4 step 5

No dangling references.

**Flagged plan assumption:** Task 4 Step 5 asks the engineer to grep for existing `.navigationDestination` attachments in HomeView and add there. This is because HomeView is 3500+ lines and the exact NavigationStack structure varies; the plan gives enough guidance without prescribing a specific line number.

---

## Deferred (out of scope)

- **Proper `completedByUserID` schema field** (currently proxy via `lastActionByUserID` which can drift on post-completion edits)
- **Stats aggregation optimization** for users with >1000 completed items (one-shot full fetch is MVP-acceptable; caching / `#Expression` is follow-up)
- **Pair-mode filter** (我完成的 / 对方完成的 segmented control)
- **Month / week grouping strategy** change (sections stay monthly as currently implemented)
