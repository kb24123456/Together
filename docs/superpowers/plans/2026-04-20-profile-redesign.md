# Profile L3 Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the L3 Profile redesign defined in `docs/superpowers/specs/2026-04-20-profile-ux-audit-design.md` — direction β (Claude-restrained skeleton + Together pair warmth) — across 17 tasks in 4 batches.

**Architecture:** Strict module scope: only `Together/Features/Profile/*`, `Together/Core/DesignSystem/AppTheme.swift`, `Together/App/AppRoute.swift`, and `TogetherTests/*`. No global token changes; new tokens added additively. All Profile-internal `sky` usages are replaced with a new `selectionTint` alias that resolves to existing `pairAccent`. The `ProBannerRow` (dark gradient) is demolished and replaced by a neutral `ProfileProEntryRow` placed below the identity card, above pair collaboration.

**Tech Stack:** SwiftUI, Swift Testing (`@Test`), iOS 17+ NavigationStack, `@Observable` ViewModel, AppTheme tokens. No new dependencies. No font bundling.

**Test Command:**
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

For per-suite:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/<SuiteName>
```

**Branch strategy:** single branch `feat/profile-redesign` off `main`. Every task = 1 commit. Full regression after every batch boundary (A/B/C/D).

---

## File Structure

### Files Created (4)

| Path | Responsibility |
|---|---|
| `Together/Features/Profile/ProSubscriptionStatus.swift` | Enum for free / trial / active states + subtitle copy |
| `Together/Features/Profile/ProfileProEntryRow.swift` | Neutral Pro entry row (replaces ProBannerRow) |
| `Together/Features/Profile/ProfileAppearanceView.swift` | Subscreen for Light / Dark / System selection |
| `TogetherTests/ProfileTokenContrastTests.swift` | WCAG contrast validation for new tokens in dark mode |

### Files Modified (7)

| Path | Responsibility change |
|---|---|
| `Together/Core/DesignSystem/AppTheme.swift` | Add `colors.hairline`, `colors.selectionTint`, `typography.displayLight(_:)` |
| `Together/App/AppRoute.swift` | Add `case appearance` to `ProfileRoute` |
| `Together/Features/Profile/ProfileUserCard.swift` | Pill → vertical layout; dual-avatar overlap (28pt x-offset); name below avatars; hairline bottom divider; no card background |
| `Together/Features/Profile/ProfileViewModel.swift` | Add `pairDaysCount` / `proSubscriptionStatus` / `proSubtitleText` / `pairDaysLabel`; `pairSpaceCreatedAt` reader |
| `Together/Features/Profile/ProfileSettingsRow.swift` | Accept optional `titleColor` for destructive red rows; `selectionTint` replaces `sky` on toggle tint |
| `Together/Features/Profile/ProfileView.swift` | Major surgery: demolish appearance capsule tab; delete ProBannerRow; collaboration CTAs → inline rows; inline "解除双人空间" danger row; delete history entry; disclosure animation → spring; "关于 Together" → "关于"; sign-out row flat; sky → selectionTint (4 sites); Pro entry section inserted below identity card |
| `TogetherTests/AppThemeTokenTests.swift` | Extend with 3 new-token existence + identity checks |

---

## Batch A — Token Layer (Tasks 1–2)

Establishes foundation: new tokens + Pro status model. Nothing visible yet.

---

### Task 1: Add 3 new AppTheme tokens + extend AppThemeTokenTests

**Files:**
- Modify: `Together/Core/DesignSystem/AppTheme.swift`
- Modify: `TogetherTests/AppThemeTokenTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TogetherTests/AppThemeTokenTests.swift` (inside the `AppThemeTokenTests` struct, after the existing `pairAccentDistinctFromSoloAccent` test):

```swift
    @Test func hairlineTokenDefined() {
        // Hairline divider must exist and render something visible in both modes
        let lightColor = AppTheme.colors.hairline
        #expect(lightColor != Color.clear)
        // Confirm it's not accidentally equal to the heavier outline token
        #expect(AppTheme.colors.hairline != AppTheme.colors.outline)
    }

    @Test func selectionTintAliasesToPairAccent() {
        // selectionTint is a deliberate alias — Profile selection must track pair warmth
        #expect(AppTheme.colors.selectionTint == AppTheme.colors.pairAccent)
    }

    @Test func displayLightFontProducesLightWeight() {
        // displayLight(22) must return a usable Font value (not crash)
        let font = AppTheme.typography.displayLight(22)
        #expect(String(describing: font).contains("CTFont") || String(describing: font).contains("Font"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/AppThemeTokenTests
```

Expected: 3 new tests FAIL with "cannot find 'hairline'/'selectionTint'/'displayLight' in scope".

- [ ] **Step 3: Add the new color tokens**

In `Together/Core/DesignSystem/AppTheme.swift`, inside `enum colors { ... }`, insert after the `outline` definition (~line 101):

```swift
        /// Ultra-thin divider for editorial separation between identity card and groups.
        /// Weaker than `outline` and `separator`.
        static let hairline = Color(light: .init(red: 0.16, green: 0.18, blue: 0.19).opacity(0.10),
                                    dark: .white.opacity(0.08))

        /// Profile-module alias for selection accent. Aliases to `pairAccent` so Profile's
        /// selected states (options, checkmarks) stay on the pair-warm coral rather than sky.
        /// Do NOT use outside Profile module.
        static let selectionTint = pairAccent
```

- [ ] **Step 4: Add the new typography helper**

In `Together/Core/DesignSystem/AppTheme.swift`, inside `enum typography { ... }`, insert after the `sized(_:weight:)` function (~line 157):

```swift
        /// Editorial large-display helper. Pins weight to `.light` so name card titles
        /// feel airy and restrained rather than bold. No font bundling — relies on
        /// system rounded Chinese fallback configured in `uiFont(size:weight:)`.
        static func displayLight(_ size: CGFloat) -> Font {
            Font(uiFont(size: size, weight: .light))
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/AppThemeTokenTests
```

Expected: all `AppThemeTokenTests` PASS (original 5 + new 3 = 8).

- [ ] **Step 6: Commit**

```bash
git add Together/Core/DesignSystem/AppTheme.swift TogetherTests/AppThemeTokenTests.swift
git commit -m "$(cat <<'EOF'
feat(theme): add hairline / selectionTint / displayLight tokens

Additive tokens for Profile L3 redesign. hairline is weaker than outline
for editorial separators between identity card and groups; selectionTint
aliases to pairAccent so Profile-scope selection stays on the warm coral
rather than mixing sky + coral accents; displayLight pins weight to .light
for airy identity-card names without font bundling.

Per spec 2026-04-20-profile-ux-audit-design §6.1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Create ProSubscriptionStatus enum

**Files:**
- Create: `Together/Features/Profile/ProSubscriptionStatus.swift`
- Test: `TogetherTests/ProSubscriptionStatusTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/ProSubscriptionStatusTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite
struct ProSubscriptionStatusTests {

    @Test func freeStatusSubtitleIsStatic() {
        let status = ProSubscriptionStatus.free
        #expect(status.subtitleText == "共享仪式、更长历史、自定义主题")
    }

    @Test func trialStatusSubtitleIncludesDaysAndDate() {
        let renewal = date(2026, 5, 25)
        let status = ProSubscriptionStatus.trial(daysLeft: 5, renewalDate: renewal)
        let subtitle = status.subtitleText
        #expect(subtitle.contains("试用剩余 5 天"))
        #expect(subtitle.contains("2026"))
        #expect(subtitle.contains("5"))
    }

    @Test func activeStatusSubtitleIncludesRenewalDate() {
        let renewal = date(2026, 5, 20)
        let status = ProSubscriptionStatus.active(renewalDate: renewal)
        let subtitle = status.subtitleText
        #expect(subtitle.contains("订阅中"))
        #expect(subtitle.contains("2026"))
    }

    @Test func accessibilityStateLabel() {
        #expect(ProSubscriptionStatus.free.accessibilityStateLabel == "升级订阅")
        let active = ProSubscriptionStatus.active(renewalDate: date(2026, 5, 20))
        #expect(active.accessibilityStateLabel.contains("订阅中"))
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ProSubscriptionStatusTests
```

Expected: FAIL with "cannot find 'ProSubscriptionStatus' in scope".

- [ ] **Step 3: Implement the enum**

Create `Together/Features/Profile/ProSubscriptionStatus.swift`:

```swift
import Foundation

/// Subscription status for the Pro entry row in Profile.
///
/// Rendered by `ProfileProEntryRow`. When the user subscribes, the row persists
/// and its subtitle transforms — it does NOT disappear. This avoids the
/// industry-reported "ghost upgrade CTA after paying" anti-pattern.
enum ProSubscriptionStatus: Equatable {
    case free
    case trial(daysLeft: Int, renewalDate: Date)
    case active(renewalDate: Date)

    /// Short, single-line subtitle copy for the Pro entry row.
    /// Kept under 40 Chinese chars to avoid wrapping on narrow devices.
    var subtitleText: String {
        switch self {
        case .free:
            return "共享仪式、更长历史、自定义主题"
        case let .trial(daysLeft, renewalDate):
            return "试用剩余 \(daysLeft) 天 · \(Self.shortDateFormatter.string(from: renewalDate)) 续费"
        case let .active(renewalDate):
            return "订阅中 · 下次续费 \(Self.shortDateFormatter.string(from: renewalDate))"
        }
    }

    /// VoiceOver suffix for the Pro row. Describes the subscription state explicitly.
    var accessibilityStateLabel: String {
        switch self {
        case .free:
            return "升级订阅"
        case let .trial(daysLeft, _):
            return "试用中，剩余 \(daysLeft) 天"
        case let .active(renewalDate):
            return "订阅中，下次续费 \(Self.shortDateFormatter.string(from: renewalDate))"
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f
    }()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ProSubscriptionStatusTests
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProSubscriptionStatus.swift TogetherTests/ProSubscriptionStatusTests.swift
git commit -m "$(cat <<'EOF'
feat(profile): add ProSubscriptionStatus model for Pro entry row

Enum with free/trial/active states; each produces its own subtitle copy
(under 40 chars) and VoiceOver label. Ships with DateFormatter pinned to
zh_CN locale and 'yyyy 年 M 月 d 日' format to match the warm editorial
tone. Not wired into ViewModel yet — Task 4 does that.

Per spec 2026-04-20-profile-ux-audit-design §5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Full regression**

Run full test suite:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED. Commit is the Batch A boundary marker.

---

## Batch B — Identity Card (Tasks 3–5)

Rebuilds the hero of the page. After Batch B the visible result is just the name card; the rest of Profile is unchanged.

---

### Task 3: Add `pairDaysCount`, `pairDaysLabel`, `proSubscriptionStatus`, `proSubtitleText` to ProfileViewModel

**Files:**
- Modify: `Together/Features/Profile/ProfileViewModel.swift`
- Modify: `Together/Features/Profile/ProfileViewModel.swift` (new computed properties only — no behavioral change)
- Test: `TogetherTests/ProfileViewModelDerivedValuesTests.swift` (new)

- [ ] **Step 1: Inspect the sessionStore shape for pair space created-at**

Run:
```
grep -rn "pairSpaceSummary\.\|sharedSpace\.createdAt\|pairSpace\.createdAt" Together/Services/Pairing/ Together/Domain/ | head -30
```

Expected: locate the property on `SharedSpace` or `PairSpace` that holds the pair creation timestamp. The value is typically under `sessionStore.pairSpaceSummary?.sharedSpace.createdAt` or `sessionStore.currentPairSpace?.createdAt`. Use whichever exists; prefer `sharedSpace.createdAt` if available because it represents the moment both members joined.

- [ ] **Step 2: Write the failing test**

Create `TogetherTests/ProfileViewModelDerivedValuesTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct ProfileViewModelDerivedValuesTests {

    @Test func pairDaysCountReturnsZeroWhenNotPaired() {
        let vm = makeViewModel()
        #expect(vm.pairDaysCount == 0)
    }

    @Test func pairDaysLabelIsEmptyWhenNotPaired() {
        let vm = makeViewModel()
        #expect(vm.pairDaysLabel.isEmpty)
    }

    @Test func proSubscriptionStatusDefaultsToFree() {
        let vm = makeViewModel()
        #expect(vm.proSubscriptionStatus == .free)
    }

    @Test func proSubtitleTextMatchesStatusSubtitle() {
        let vm = makeViewModel()
        #expect(vm.proSubtitleText == ProSubscriptionStatus.free.subtitleText)
    }

    // MARK: - Helper

    private func makeViewModel() -> ProfileViewModel {
        let context = AppContext.makeBootstrappedContext()
        return context.profileViewModel
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ProfileViewModelDerivedValuesTests
```

Expected: FAIL — `pairDaysCount` / `pairDaysLabel` / `proSubscriptionStatus` / `proSubtitleText` undefined.

- [ ] **Step 4: Add computed properties to ProfileViewModel**

In `Together/Features/Profile/ProfileViewModel.swift`, add a new stored property near the top (after `isAccountDeletionInProgress`, ~line 61):

```swift
    /// Pro subscription status. Defaults to `.free`. Will be driven by StoreKit 2
    /// in a future feature — for now the Pro entry row always renders the free
    /// CTA subtitle. Wiring real StoreKit state is an out-of-scope follow-up
    /// (see spec §11.1).
    var proSubscriptionStatus: ProSubscriptionStatus = .free
```

Then add these computed properties at the end of the struct's "var ..." section (safe place: right after `cacheSizeString` around line 323):

```swift
    /// Number of whole days since the shared pair space was created.
    /// Returns 0 when not paired (UI branch will hide the "{N} 天" segment).
    var pairDaysCount: Int {
        guard
            sessionStore.hasActivePairSpace,
            let createdAt = sessionStore.pairSpaceSummary?.sharedSpace.createdAt
        else {
            return 0
        }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: createdAt, to: .now)
            .day ?? 0
        return max(0, days)
    }

    /// Empty string when not paired; "配对 N 天" when paired.
    var pairDaysLabel: String {
        guard pairDaysCount > 0 else { return "" }
        return "配对 \(pairDaysCount) 天"
    }

    /// Subtitle for the Pro entry row. Derived from `proSubscriptionStatus`.
    var proSubtitleText: String {
        proSubscriptionStatus.subtitleText
    }
```

**Note:** if Step 1 found the path is `sessionStore.currentPairSpace?.createdAt` instead of `sessionStore.pairSpaceSummary?.sharedSpace.createdAt`, substitute accordingly.

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ProfileViewModelDerivedValuesTests
```

Expected: all 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/ProfileViewModel.swift TogetherTests/ProfileViewModelDerivedValuesTests.swift
git commit -m "$(cat <<'EOF'
feat(profile): add pair-days / Pro-status derived properties to VM

Adds pairDaysCount (whole-day span since pair space createdAt), pairDaysLabel
('配对 N 天' when paired, empty otherwise), proSubscriptionStatus (defaults
to .free), and proSubtitleText (passes through to ProSubscriptionStatus).
No behavioral change — wiring to UI happens in Task 4 (identity card
rebuild) and later Pro-row task.

Per spec 2026-04-20-profile-ux-audit-design §3.2 + §5.4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Rebuild ProfileUserCard — vertical layout, dual-avatar overlap, hairline divider

**Files:**
- Modify: `Together/Features/Profile/ProfileUserCard.swift` (full rewrite)
- Test: manual via Xcode Preview (SwiftUI view — no unit test)

- [ ] **Step 1: Open Xcode preview for ProfileUserCard before edits**

Note current visual: horizontal pill, avatar cluster on left, name on right, "我" displayed when secondary name nil. Keep this in mind so you can spot regressions.

- [ ] **Step 2: Rewrite ProfileUserCard.swift**

Replace the ENTIRE file contents with:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileCardAvatar: Hashable {
    let displayName: String
    let avatarAsset: UserAvatarAsset
    let overrideImage: UIImage?

    static func == (lhs: ProfileCardAvatar, rhs: ProfileCardAvatar) -> Bool {
        lhs.displayName == rhs.displayName && lhs.avatarAsset == rhs.avatarAsset
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(displayName)
        hasher.combine(avatarAsset)
    }
}

enum ProfileCardSecondaryAvatarState: Hashable {
    case placeholder
    case user(ProfileCardAvatar)
}

/// Identity card at the top of Profile. Vertical layout: avatars on top,
/// name below, subtitle under name. In solo mode shows a single 64pt
/// avatar; in pair mode shows two 56pt avatars overlapping ~30% with
/// self on the left (bottom z-order) and partner on the right (top).
///
/// The card has NO background — it sits directly on the page's warm
/// off-white and is separated from the first group by a hairline divider.
struct ProfileUserCard: View {
    private let soloAvatarDiameter: CGFloat = 64
    private let pairAvatarDiameter: CGFloat = 56
    private let pairOverlapOffset: CGFloat = 28    // 50% of pairAvatarDiameter
    private let nameTopGap: CGFloat = AppTheme.spacing.md
    private let subtitleTopGap: CGFloat = AppTheme.spacing.xxs

    let primaryName: String
    let secondaryName: String?
    let primaryAvatar: ProfileCardAvatar
    let secondaryAvatarState: ProfileCardSecondaryAvatarState
    /// Subtitle displayed beneath the name. E.g. "独立工作空间" or
    /// "我们的小家 · 配对 124 天".
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            avatarCluster
                .padding(.bottom, nameTopGap)

            Text(displayTitle)
                .font(AppTheme.typography.displayLight(22))
                .tracking(0.3)
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing.lg)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            if subtitle.isEmpty == false {
                Text(subtitle)
                    .font(AppTheme.typography.textStyle(.footnote, weight: .regular))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, subtitleTopGap)
                    .padding(.horizontal, AppTheme.spacing.lg)
            }
        }
        .padding(.top, AppTheme.spacing.xl)
        .padding(.bottom, AppTheme.spacing.lg)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.colors.hairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Avatar cluster

    @ViewBuilder
    private var avatarCluster: some View {
        if case .user(let partnerAvatar) = secondaryAvatarState, secondaryName != nil {
            pairAvatars(partner: partnerAvatar)
        } else {
            singleAvatar
        }
    }

    private var singleAvatar: some View {
        avatarBadge(primaryAvatar, diameter: soloAvatarDiameter, fillColor: AppTheme.colors.avatarWarm)
    }

    private func pairAvatars(partner: ProfileCardAvatar) -> some View {
        let selfBadge = avatarBadge(primaryAvatar, diameter: pairAvatarDiameter, fillColor: AppTheme.colors.avatarWarm)
        let partnerBadge = avatarBadge(partner, diameter: pairAvatarDiameter, fillColor: AppTheme.colors.avatarNeutral)

        return ZStack(alignment: .leading) {
            selfBadge
                .zIndex(1)
            partnerBadge
                .offset(x: pairOverlapOffset)
                .zIndex(2)
        }
        .frame(width: pairAvatarDiameter + pairOverlapOffset, height: pairAvatarDiameter)
    }

    private func avatarBadge(_ avatar: ProfileCardAvatar, diameter: CGFloat, fillColor: Color) -> some View {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: diameter,
            fillColor: fillColor,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(diameter * 0.38, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
        .overlay {
            Circle()
                .stroke(AppTheme.colors.background, lineWidth: 2)
        }
    }

    // MARK: - Derived copy

    private var displayTitle: String {
        if let secondaryName {
            return "\(primaryName) & \(secondaryName)"
        }
        return primaryName
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if let secondaryName {
            let suffix = subtitle.isEmpty ? "" : "，\(subtitle)"
            return "\(primaryName) 和 \(secondaryName)\(suffix)"
        }
        let suffix = subtitle.isEmpty ? "" : "，\(subtitle)"
        return "\(primaryName)\(suffix)"
    }

    private var accessibilityHint: String {
        secondaryName == nil ? "编辑个人资料" : "编辑双人资料"
    }
}
```

- [ ] **Step 3: Update the call site in ProfileView.swift to pass `subtitle`**

In `Together/Features/Profile/ProfileView.swift`, inside the identity-card `NavigationLink` (around lines 23-36), replace the `ProfileUserCard` init call so it passes `subtitle`:

```swift
                    NavigationLink(value: viewModel.isPairMode ? ProfileRoute.editPairProfile : ProfileRoute.editProfile) {
                        ProfileUserCard(
                            primaryName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                            secondaryName: viewModel.profileCardSecondaryName,
                            primaryAvatar: ProfileCardAvatar(
                                displayName: currentUser?.displayName ?? viewModel.profileCardPrimaryName,
                                avatarAsset: currentUser?.avatarAsset ?? .system("person.crop.circle.fill"),
                                overrideImage: nil
                            ),
                            secondaryAvatarState: viewModel.profileCardSecondaryAvatarState,
                            subtitle: viewModel.identityCardSubtitle
                        )
                        .id(appContext.sessionStore.userProfileRevision)
                        .matchedTransitionSource(id: ProfileTransitionSource.profileCard, in: profileTransition)
                    }
```

- [ ] **Step 4: Add `identityCardSubtitle` computed property to ViewModel**

In `Together/Features/Profile/ProfileViewModel.swift`, add near other display-derived properties (next to `spaceSummary`, ~line 228):

```swift
    /// Subtitle displayed below the name in the identity card.
    /// Solo: "独立工作空间". Pair: "{space name} · 配对 {N} 天" (days segment
    /// omitted when 0).
    var identityCardSubtitle: String {
        guard isPairMode else {
            return "独立工作空间"
        }
        let spaceName = pairSpaceDisplayName
        if pairDaysCount > 0 {
            return "\(spaceName) · \(pairDaysLabel)"
        }
        return spaceName
    }
```

- [ ] **Step 5: Build + launch Preview**

In Xcode, navigate to `ProfileView.swift`, activate the `#Preview("Profile")` preview. Verify:
- Avatars are vertically centered above the name
- Single avatar in solo mode (64pt), two overlapping avatars in pair mode if mock has pair state
- Name renders in weight `.light` (visibly thinner than the old bold)
- Subtitle shows in small textTertiary
- A thin hairline sits at the bottom of the card, above "双人协作" group

If the preview launches with paired state showing, confirm the overlap by measuring roughly 30% of the right avatar is hidden behind the left.

- [ ] **Step 6: Run the full test suite**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED. No new unit tests, but the VM property must compile and existing suites must stay green.

- [ ] **Step 7: Commit**

```bash
git add Together/Features/Profile/ProfileUserCard.swift Together/Features/Profile/ProfileView.swift Together/Features/Profile/ProfileViewModel.swift
git commit -m "$(cat <<'EOF'
refactor(profile): rebuild identity card as vertical Paired-style hero

Replaces horizontal pill layout with vertical stack: avatars on top,
name in displayLight(22), subtitle in footnote textTertiary. Pair mode
renders two 56pt avatars with 28pt x-offset (~30% overlap, self under,
partner over). Solo mode renders a single 64pt avatar. Card has no
background — sits directly on warm off-white, separated from first
group by a 1px hairline divider.

Subtitle text moves to VM.identityCardSubtitle ('独立工作空间' for solo,
'{space} · 配对 {N} 天' for pair).

Name text pinned to dynamicTypeSize(...xxxLarge) so AX5 cannot blow up
the card height. ampersand is the ASCII '&' not the Chinese '和'.

Per spec 2026-04-20-profile-ux-audit-design §3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Drop solo-mode placeholder avatar + pair-transition animation

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`
- Manual: verify avatar-cluster transition when switching solo → pair

- [ ] **Step 1: Add onChange bindingState watcher**

In `Together/Features/Profile/ProfileView.swift`, inside the `.onChange(of: viewModel.bindingState)` block (currently around line 132), change the body to also animate the identity card by notifying via `@State` flag. Add a new `@State` near the top of `ProfileView`:

```swift
    @State private var pairCardAnimationID: Int = 0
```

And replace the existing `onChange`:

```swift
        .onChange(of: viewModel.bindingState) { oldState, newState in
            if oldState != .paired, newState == .paired {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    pairCardAnimationID &+= 1
                }
            }
        }
```

- [ ] **Step 2: Wire the animationID into the identity card**

In the identity-card `NavigationLink` block, apply the animation trigger by changing `.id(...)` modifier to be composite. Find:

```swift
                        .id(appContext.sessionStore.userProfileRevision)
```

Replace with:

```swift
                        .id("\(appContext.sessionStore.userProfileRevision)-\(pairCardAnimationID)")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
```

- [ ] **Step 3: Manual verification**

Run the app in the simulator. If you have seed data that lets you transition `.unbound` → `.paired` (e.g., via debug section), observe:
- When pairing completes, the identity card fades/slides in with a 0.32s spring
- Solo → pair transition is visibly animated (not an instant swap)
- Page scroll position is preserved (no jump)

If you don't have a convenient way to trigger the transition, skip live verification — the code path is self-contained and the static preview is enough.

- [ ] **Step 4: Run the full test suite**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
feat(profile): animate identity card on solo → pair transition

Adds a @State pairCardAnimationID that increments when bindingState
transitions into .paired. The identity card's .id bakes in the counter,
forcing a rebuild with a 0.32s spring + trailing-edge move + opacity
transition so the partner avatar slides in rather than popping.

Per spec 2026-04-20-profile-ux-audit-design §7.2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Full regression (Batch B boundary)**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED. Batch B done; visual smoke check (Xcode Preview + simulator) should show the new identity card but the rest of Profile is still the old layout.

---

## Batch C — IA Restructure (Tasks 6–13)

The bulk of the work. After Batch C, every group below the identity card is rebuilt and the appearance capsule tab / ProBannerRow / history entry are deleted.

---

### Task 6: Add `ProfileRoute.appearance` and create `ProfileAppearanceView`

**Files:**
- Modify: `Together/App/AppRoute.swift`
- Create: `Together/Features/Profile/ProfileAppearanceView.swift`
- Modify: `Together/Features/Profile/ProfileView.swift` (navigationDestination route switch)

- [ ] **Step 1: Add the route case**

In `Together/App/AppRoute.swift`, inside `enum ProfileRoute`, add `case appearance` (place it with the other preference-like routes):

```swift
enum ProfileRoute: Hashable {
    case editProfile
    case editPairProfile
    case notificationSettings
    case completedHistory
    case futureCollaboration
    case privacyPolicy
    case termsOfService
    case accountDeletion
    case subscription
    case feedback
    case about
    case appearance          // NEW
}
```

- [ ] **Step 2: Create the subscreen**

Create `Together/Features/Profile/ProfileAppearanceView.swift`:

```swift
import SwiftUI

/// Appearance subscreen accessed via the "通知与外观" group's "外观" row.
/// Replaces the former capsule-tab picker that lived inline on the
/// Profile main scroll. Three options: 跟随系统 / 浅色 / 深色.
///
/// Persists via `AppearanceManager.mode` (identical to the old capsule tab).
struct ProfileAppearanceView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                    row(for: mode)

                    if index < AppearanceMode.allCases.count - 1 {
                        Divider()
                            .overlay(AppTheme.colors.hairline)
                            .padding(.leading, AppTheme.spacing.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.lg)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for mode: AppearanceMode) -> some View {
        let isSelected = appContext.appearanceManager.mode == mode
        return Button {
            HomeInteractionFeedback.selection()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                appContext.appearanceManager.mode = mode
            }
        } label: {
            HStack(spacing: AppTheme.spacing.md) {
                Text(mode.title)
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.typography.sized(14, weight: .bold))
                        .foregroundStyle(AppTheme.colors.selectionTint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
```

- [ ] **Step 3: Wire the route into ProfileView navigationDestination**

In `Together/Features/Profile/ProfileView.swift`, locate the `.navigationDestination(for: ProfileRoute.self)` switch (around line 77). Add a case:

```swift
            case .appearance:
                ProfileAppearanceView()
```

Insert after the `.about` case for logical grouping.

- [ ] **Step 4: Verify build**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Together/App/AppRoute.swift Together/Features/Profile/ProfileAppearanceView.swift Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
feat(profile): add Appearance subscreen + ProfileRoute.appearance

Creates ProfileAppearanceView — a three-row list (跟随系统 / 浅色 / 深色)
on surfaceElevated with hairline dividers and selectionTint checkmark.
Writes into existing AppearanceManager.mode so the behavior is
functionally identical to the old inline capsule tab (capsule tab
removal happens in Task 7).

Per spec 2026-04-20-profile-ux-audit-design §4.3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Merge 通知与权限 + 外观 → single "通知与外观" group; delete capsule tab + history row

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: Rewrite the notifications group**

In `Together/Features/Profile/ProfileView.swift`, replace the entire `notificationsAndHistorySection` computed property (around lines 414-470) with:

```swift
    // MARK: - 通知与外观

    private var notificationsAndAppearanceSection: some View {
        ProfileSettingsGroupCard(title: "通知与外观") {
            if viewModel.notificationAuthorization == .authorized {
                ProfileSettingsRow(
                    title: "提醒权限",
                    value: "已开启"
                )
            } else {
                Button {
                    HomeInteractionFeedback.selection()
                    if viewModel.notificationAuthorization == .denied {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    } else {
                        Task { await viewModel.requestNotifications() }
                    }
                } label: {
                    ProfileSettingsRow(
                        title: "提醒权限",
                        value: viewModel.notificationAuthorization == .denied ? "去开启" : "未开启",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                HomeInteractionFeedback.selection()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                ProfileSettingsRow(
                    title: "权限管理",
                    value: "系统设置",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: ProfileRoute.appearance) {
                ProfileSettingsRow(
                    title: "外观",
                    value: appearanceValueLabel,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    HomeInteractionFeedback.selection()
                }
            )
        }
    }

    private var appearanceValueLabel: String {
        appContext.appearanceManager.mode.title
    }
```

- [ ] **Step 2: Delete the old appearanceSection**

Still in `ProfileView.swift`, find and DELETE the entire `appearanceSection` computed property (around lines 559-585 — the capsule-tab block):

```swift
    // MARK: - 外观（紧凑样式）
    private var appearanceSection: some View { ... }
```

Also delete the "MARK: - 外观" comment if present.

- [ ] **Step 3: Remove old section call-sites in body; rename**

In `ProfileView.body`, locate the VStack (around line 44-55):

```swift
                    collaborationSection
                    executionPreferencesSection
                    notificationsAndHistorySection    // rename
                    securitySection
                    dataAndAccountSection
                    aboutRow
                    appearanceSection                  // delete
```

Change to:

```swift
                    collaborationSection
                    executionPreferencesSection
                    notificationsAndAppearanceSection
                    securitySection
                    dataAndAccountSection
                    aboutRow
```

(Temporary ordering — Pro row insertion happens in Task 10. After Batch C the order will be: identity card → Pro row → collaboration → preferences → notifications+appearance → security → data → about → sign out.)

- [ ] **Step 4: Verify build**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED. If a compile error complains about a dangling reference to the deleted `appearanceSection` or `notificationsAndHistorySection`, fix by renaming (steps above).

- [ ] **Step 5: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
refactor(profile): merge '通知与权限' + '外观' into '通知与外观' group

Renames notificationsAndHistorySection → notificationsAndAppearanceSection.
Appearance row replaces the inline capsule tab; tapping pushes to
ProfileAppearanceView (added in Task 6). Value shown right-aligned is
the current AppearanceMode.title.

History row removed — 历史任务 is a data view, not a setting. Entry
migrates to Home top bar (separate follow-up, not in this plan).

Per spec 2026-04-20-profile-ux-audit-design §2.2 (change A + B) / §4.3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Collaboration section — replace CTA buttons with inline rows; danger row for 解除

**Files:**
- Modify: `Together/Features/Profile/ProfileSettingsRow.swift` (add optional `titleColor`)
- Modify: `Together/Features/Profile/ProfileView.swift` (rewrite collaborationActionRow)

- [ ] **Step 1: Extend ProfileSettingsRow to accept `titleColor`**

In `Together/Features/Profile/ProfileSettingsRow.swift`, modify the struct to accept an optional `titleColor`. Replace the stored properties + inits block (around lines 9-39) with:

```swift
    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let showsChevron: Bool
    private let chevronSystemName: String
    private let titleColor: Color?

    init(
        title: String,
        value: String,
        isEnabled: Bool = true,
        showsChevron: Bool = false,
        chevronSystemName: String = "chevron.right",
        titleColor: Color? = nil
    ) {
        self.title = title
        self.style = .value(value)
        self.isEnabled = isEnabled
        self.showsChevron = showsChevron
        self.chevronSystemName = chevronSystemName
        self.titleColor = titleColor
    }

    init(
        title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.style = .toggle(isOn)
        self.isEnabled = isEnabled
        self.showsChevron = false
        self.chevronSystemName = "chevron.right"
        self.titleColor = nil
    }
```

Then update `rowShell` (around line 70) to use `titleColor` when set:

```swift
    private func rowShell<Accessory: View>(@ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            Text(title)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle((titleColor ?? AppTheme.colors.title).opacity(isEnabled ? 1 : 0.42))
                .lineLimit(2)

            Spacer(minLength: AppTheme.spacing.md)

            accessory()
        }
        .padding(.vertical, AppTheme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.76)
    }
```

- [ ] **Step 2: Rewrite `collaborationActionRow` in ProfileView**

In `Together/Features/Profile/ProfileView.swift`, locate `collaborationActionRow` (around lines 227-303). Replace the entire computed property with:

```swift
    @ViewBuilder
    private var collaborationActionRow: some View {
        switch viewModel.bindingState {
        case .singleTrial, .unbound:
            Button {
                HomeInteractionFeedback.selection()
                Task { await viewModel.createInvite() }
            } label: {
                ProfileSettingsRow(
                    title: "发起双人邀请",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            if let err = viewModel.createInviteError {
                Text(err)
                    .font(AppTheme.typography.sized(12, weight: .medium))
                    .foregroundStyle(AppTheme.colors.danger)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, AppTheme.spacing.xs)
                    .padding(.bottom, AppTheme.spacing.xs)
            }

            Button {
                HomeInteractionFeedback.selection()
                viewModel.inviteCodeEntryPresented = true
            } label: {
                ProfileSettingsRow(
                    title: "输入邀请码",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

        case .invitePending:
            InvitePendingSection(
                invite: viewModel.activeInvite,
                onCopy: { code in
                    UIPasteboard.general.string = code
                    HomeInteractionFeedback.selection()
                },
                onCheckAccepted: {
                    await viewModel.checkInviteAccepted()
                },
                onCancel: {
                    await viewModel.cancelCurrentInvite()
                },
                onRegenerate: {
                    await viewModel.cancelCurrentInvite()
                    await viewModel.createInvite()
                }
            )

        case .inviteReceived:
            Button {
                HomeInteractionFeedback.selection()
                Task { await viewModel.acceptInvite() }
            } label: {
                ProfileSettingsRow(
                    title: "接受邀请",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            Button {
                HomeInteractionFeedback.selection()
                Task { await viewModel.declineInvite() }
            } label: {
                ProfileSettingsRow(
                    title: "拒绝邀请",
                    value: "",
                    showsChevron: false,
                    titleColor: AppTheme.colors.danger
                )
            }
            .buttonStyle(.plain)

        case .paired:
            Button {
                HomeInteractionFeedback.warning()
                Task { await viewModel.unbindPairSpace() }
            } label: {
                ProfileSettingsRow(
                    title: "解除双人空间",
                    value: "",
                    showsChevron: false,
                    titleColor: AppTheme.colors.danger
                )
            }
            .buttonStyle(.plain)
        }
    }
```

- [ ] **Step 3: Delete the now-unused helper**

In `ProfileView.swift`, DELETE the `collaborationButtonLabel(title:tint:)` function (around lines 305-319).

- [ ] **Step 4: Verify build**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED. If there's a reference to `collaborationButtonLabel` elsewhere, search and remove.

```
grep -n "collaborationButtonLabel" Together/Features/Profile/
```

Expected: no matches.

- [ ] **Step 5: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/ProfileSettingsRow.swift Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
refactor(profile): unify collaboration CTAs as inline rows

Deletes collaborationButtonLabel filled-button helper. Every
non-InvitePending collaboration action now uses ProfileSettingsRow:
- '发起双人邀请' / '输入邀请码' (singleTrial, unbound): chevron rows
- '接受邀请' / '拒绝邀请' (inviteReceived): chevron row + danger row
- '解除双人空间' (paired): danger row at the bottom of the group

Adds optional titleColor: Color? to ProfileSettingsRow so the
destructive rows can render in danger without duplicating the row
shell. InvitePendingSection (QR + countdown) stays untouched — it's
too specialized to flatten.

Per spec 2026-04-20-profile-ux-audit-design §4.1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Delete ProBannerRow + history entry; rewrite dataAndAccountSection

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: Delete ProBannerRow struct**

In `Together/Features/Profile/ProfileView.swift`, locate and DELETE the entire `private struct ProBannerRow` block (around lines 676-734). Delete the accompanying `// MARK: - Pro Banner` comment too.

- [ ] **Step 2: Rewrite dataAndAccountSection**

In `ProfileView.swift`, replace the existing `dataAndAccountSection` (around lines 495-537):

```swift
    // MARK: - 数据与账号

    private var dataAndAccountSection: some View {
        ProfileSettingsGroupCard(title: "数据与账号") {
            ProfileSettingsRow(
                title: "iCloud 同步",
                value: viewModel.iCloudStatusSummary
            )

            Button {
                HomeInteractionFeedback.selection()
                showsClearCacheAlert = true
            } label: {
                ProfileSettingsRow(
                    title: "清除缓存",
                    value: viewModel.cacheSizeString
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: ProfileRoute.accountDeletion) {
                ProfileSettingsRow(
                    title: "账号注销",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded { HomeInteractionFeedback.selection() }
            )
        }
    }
```

- [ ] **Step 3: Verify build**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED. Confirm no leftover references to `ProBannerRow`:

```
grep -rn "ProBannerRow" Together/
```

Expected: no matches.

- [ ] **Step 4: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
refactor(profile): delete ProBannerRow + history entry; slim 数据与账号

Removes the dark-gradient-with-angular-rainbow ProBannerRow that
clashed with the warm off-white base. Pro entry moves above pair
collaboration (Task 10 adds it there as a neutral row).

Also removes the '历史任务' NavigationLink from the notifications group
(handled in Task 7 rewrite). Surviving rows in 数据与账号: iCloud 同步,
清除缓存, 账号注销.

Per spec 2026-04-20-profile-ux-audit-design §4.5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Create ProfileProEntryRow + insert it below identity card

**Files:**
- Create: `Together/Features/Profile/ProfileProEntryRow.swift`
- Modify: `Together/Features/Profile/ProfileView.swift` (insert after identity card)

- [ ] **Step 1: Create the row component**

Create `Together/Features/Profile/ProfileProEntryRow.swift`:

```swift
import SwiftUI

/// Pro subscription entry. Placed immediately below the identity card and
/// above the collaboration group. Neutral row style — no gradients, no
/// dark chips — per β direction. When subscribed, the row does not
/// disappear; the subtitle transforms (see `ProSubscriptionStatus`).
struct ProfileProEntryRow: View {
    let status: ProSubscriptionStatus
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HomeInteractionFeedback.selection()
            onTap()
        }) {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Circle()
                    .fill(AppTheme.colors.pairAccent)
                    .frame(width: 4, height: 4)

                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text("Together Pro")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .lineLimit(1)

                    Text(status.subtitleText)
                        .font(AppTheme.typography.sized(12, weight: .regular))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: AppTheme.spacing.md)

                Image(systemName: "chevron.right")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.36))
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Together Pro，\(status.subtitleText)")
        .accessibilityHint(status.accessibilityStateLabel)
    }
}
```

- [ ] **Step 2: Insert the Pro row into ProfileView body**

In `Together/Features/Profile/ProfileView.swift`, locate the VStack in `body` (around lines 19-55). Modify the section order so that Pro row comes right after the identity card:

```swift
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    ProfileScrollOffsetProbe()

                    // MARK: - 名片区
                    NavigationLink(value: viewModel.isPairMode ? ProfileRoute.editPairProfile : ProfileRoute.editProfile) {
                        ProfileUserCard( ... )   // unchanged
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HomeInteractionFeedback.selection()
                        }
                    )

                    // MARK: - Pro 入口
                    ProfileProEntryRow(status: viewModel.proSubscriptionStatus) {
                        // Route to existing subscription screen
                        appContext.appRouter.profile.append(.subscription)
                    }

                    // MARK: - 分组设置
                    collaborationSection
                    executionPreferencesSection
                    notificationsAndAppearanceSection
                    securitySection
                    dataAndAccountSection
                    aboutRow
                    ...
                }
```

**Important:** This plan assumes a `appContext.appRouter.profile` NavigationPath binding exists. If the router exposes a different API, substitute with the correct navigation mechanism — commonly:
```swift
@State private var profilePath = NavigationPath()  // or a shared AppRouter path
```

Inspect the existing routing pattern by running:
```
grep -rn "profile.append\|ProfileRoute.subscription" Together/ | head -20
```

Use whichever NavigationStack-push mechanism the app already uses. If no path binding is available, wrap the row in a `NavigationLink(value: ProfileRoute.subscription)` instead:

```swift
                    // MARK: - Pro 入口
                    NavigationLink(value: ProfileRoute.subscription) {
                        ProfileProEntryRow(status: viewModel.proSubscriptionStatus) {}
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded { HomeInteractionFeedback.selection() }
                    )
```

In that case, remove the `onTap` action body inside the row (pass an empty closure) and let `NavigationLink` handle the push.

- [ ] **Step 3: Build**

```
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Full regression**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Visual smoke (Xcode Preview)**

Launch Profile preview. Verify:
- Pro row appears immediately below identity card, above "双人协作" group
- Small coral dot leads the row
- "Together Pro" bold, subtitle below in grey
- Chevron right-aligned, thin (11pt semibold)
- Row height ≈ 64pt
- Tapping routes to subscription screen

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Profile/ProfileProEntryRow.swift Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
feat(profile): add neutral Pro entry row below identity card

ProfileProEntryRow replaces the demolished ProBannerRow. Neutral row
with small coral leading dot, bold title, subtitle derived from
ProSubscriptionStatus, thin chevron. No gradient, no angular rainbow
border, no dark chip. Row persists in subscribed state with its
subtitle transforming to '订阅中 · 下次续费 {日期}'.

Position: directly below identity card's hairline divider, above
pair collaboration group — matches Claude iOS pattern and the
industry consensus for editorial-aesthetic subscription entry.

Routes to existing ProfileRoute.subscription subscreen.

Per spec 2026-04-20-profile-ux-audit-design §5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Simplify About row + 退出登录 flat style

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: Simplify the About row label**

In `Together/Features/Profile/ProfileView.swift`, locate `aboutRow` (around lines 541-555). Change the title from `"关于 Together"` to `"关于"`:

```swift
    private var aboutRow: some View {
        ProfileSettingsGroupCard(title: "") {
            NavigationLink(value: ProfileRoute.about) {
                ProfileSettingsRow(
                    title: "关于",
                    value: "v\(viewModel.appVersionString)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded { HomeInteractionFeedback.selection() }
            )
        }
    }
```

- [ ] **Step 2: Flatten the sign-out row**

In the same file, locate `signOutFooter` (around lines 589-607). Replace the entire computed property:

```swift
    // MARK: - 退出登录

    private var signOutFooter: some View {
        Button {
            HomeInteractionFeedback.selection()
            showsSignOutAlert = true
        } label: {
            Text("退出登录")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.spacing.lg)
        .accessibilityHint("退出后需要重新登录")
    }
```

- [ ] **Step 3: Build + test**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Visual smoke**

In simulator / preview confirm:
- "关于" row shows "v1.0 (1)" right-aligned (no "Together" in the label anymore)
- Sign-out row is just red text, centered, no grey background, no shadow, no pill shape
- Tapping still opens the confirmation alert

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
style(profile): simplify About label + flatten sign-out row

'关于 Together' → '关于' (value line '\(version)' already identifies
the product). Sign-out row drops the surfaceElevated background +
shadow 'filled CTA' styling; now rendered as a lone danger-color
semibold text, centered, 44pt min-height, no container. Industry
convention for sign-out rows (Claude iOS, Bear, Linear, Notion).

Per spec 2026-04-20-profile-ux-audit-design §4.6 + §4.7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Security section helper text tweak + Quick reply editor inline save

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: Soften the security helper text**

In `Together/Features/Profile/ProfileView.swift`, locate `securitySection` (around lines 474-491). Modify the helper Text block:

```swift
            if viewModel.appLockEnabled {
                Text("切到后台时自动锁定，需要\(viewModel.biometricTypeName)或密码解锁")
                    .font(AppTheme.typography.sized(12, weight: .regular))
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.78))
                    .padding(.horizontal, AppTheme.spacing.xs)
            }
```

Changes: font went from `13 .medium` → `12 .regular`; color went from `textTertiary` → `textTertiary.opacity(0.78)`; horizontal padding went from `xxs` → `xs`.

- [ ] **Step 2: Flatten ProfileQuickReplyEditor's save button**

In the same file, locate the `ProfileQuickReplyEditor` struct (around lines 738-781). Replace the `Button("保存预设") { ... }` block + its chained modifiers with an inline row styled as a right-aligned coral text button:

```swift
            HStack {
                Spacer()
                Button("保存") {
                    HomeInteractionFeedback.selection()
                    onSave(messages)
                    messages = NotificationSettings.normalizedPairQuickReplyMessages(messages)
                }
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.selectionTint)
            }
            .padding(.top, AppTheme.spacing.xs)
```

Remove the old filled-button style (frame maxWidth, padding, surfaceElevated background, rounded rect).

- [ ] **Step 3: Build + test**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
style(profile): soften security helper text + flatten quick-reply save

Security helper text drops a weight (.medium → .regular), drops a size
(13 → 12), gains 0.78 opacity on textTertiary — reads as caption
rather than body. Horizontal inset loosens xxs → xs.

ProfileQuickReplyEditor's '保存预设' filled button becomes '保存'
right-aligned selectionTint text. Matches Claude iOS / Bear — save
affordances inside editors shouldn't look like primary CTAs.

Per spec 2026-04-20-profile-ux-audit-design §4.2 + §4.4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Full regression + Batch C boundary

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full suite**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED. If any test fails, halt and fix before continuing.

- [ ] **Step 2: Simulator smoke checklist**

Boot the app in simulator. Walk through:
- Profile tab opens, identity card renders in vertical layout (not the old pill)
- Pro row sits below identity card
- Tapping Pro row navigates to subscription screen
- Collaboration group: invite/input-code are inline rows (not filled buttons)
- Execution preferences disclosures expand / collapse with spring feel
- Notifications + Appearance group has 3 rows: 提醒权限 / 权限管理 / 外观
- Tapping 外观 pushes to ProfileAppearanceView with 3 options + checkmark on current
- Security section: single toggle + softened helper text
- Data section: 3 rows only (iCloud / 缓存 / 注销)
- About row: label is "关于", value is "v1.0 (1)"
- Sign-out is flat red text at the bottom, no shadow
- History entry is gone (no "历史任务" row anywhere in Profile)

- [ ] **Step 3: No commit needed (verification only)**

This is a gate, not a code change.

---

## Batch D — Visual Convergence + Tests (Tasks 14–17)

---

### Task 14: Profile module sky → selectionTint replacement

**Files:**
- Modify: `Together/Features/Profile/ProfileSettingsRow.swift`
- Modify: `Together/Features/Profile/ProfileView.swift`
- Modify: `Together/Features/Profile/CompletedHistoryView.swift`
- Modify: `Together/Features/Profile/ProfileSubscriptionView.swift`
- Modify: `Together/Features/Profile/ProfileAboutView.swift`

- [ ] **Step 1: Inventory the Profile-scope sky usages**

Run:
```
grep -n "colors\.sky" Together/Features/Profile/
```

Expected output (already captured during planning):
- `ProfileSettingsRow.swift:49` — Toggle tint
- `ProfileView.swift:578, 897, 904, 912` — option inline button (selected text + checkmark + selected background)
- `CompletedHistoryView.swift:33` — tint
- `ProfileSubscriptionView.swift:38, 47, 102, 119`
- `ProfileAboutView.swift:14`

- [ ] **Step 2: Replace each site**

For each file listed, perform a textual replacement: `AppTheme.colors.sky` → `AppTheme.colors.selectionTint`.

Safe to do with:
```
cd Together/Features/Profile && for f in ProfileSettingsRow.swift ProfileView.swift CompletedHistoryView.swift ProfileSubscriptionView.swift ProfileAboutView.swift; do sed -i '' 's/AppTheme\.colors\.sky/AppTheme.colors.selectionTint/g' "$f"; done
```

Then verify:
```
grep -n "colors\.sky" Together/Features/Profile/
```

Expected: no matches in Profile. (Home/Calendar etc. still use sky — do NOT touch them.)

- [ ] **Step 3: Tighten inline-option selected-background opacity**

The sed pass replaces `sky.opacity(0.1)` with `selectionTint.opacity(0.1)`, but spec §6.3 specifies `0.08` for the selection background. Open `Together/Features/Profile/ProfileView.swift` and find the `ProfileInlineOptionButton` struct (around lines 887-917). Locate:

```swift
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .fill(isSelected ? AppTheme.colors.selectionTint.opacity(0.1) : .clear)
            )
```

Change `0.1` to `0.08`:

```swift
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .fill(isSelected ? AppTheme.colors.selectionTint.opacity(0.08) : .clear)
            )
```

- [ ] **Step 4: Build + test**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/
git commit -m "$(cat <<'EOF'
style(profile): converge Profile accents sky → selectionTint (coral)

Profile module internally replaces AppTheme.colors.sky with
AppTheme.colors.selectionTint (an alias to pairAccent, introduced in
Task 1). Affected: toggle tints, inline option selected text +
checkmark + background, subscription screen highlights, about
screen version tint, completed history tint.

Global sky token usage in Home/Calendar/etc. is intentionally untouched.
Pro entry leading dot continues to use pairAccent directly for clarity
(it's a brand mark, not selection state).

Per spec 2026-04-20-profile-ux-audit-design §6.3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Upgrade disclosure animation to spring + hairline divider

**Files:**
- Modify: `Together/Features/Profile/ProfileView.swift`

- [ ] **Step 1: Upgrade the disclosure animation**

In `Together/Features/Profile/ProfileView.swift`, locate `ProfilePlainDisclosureGroupStyle` (around lines 859-885). Change the animation inside the Button action:

```swift
            Button {
                HomeInteractionFeedback.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                ...
            }
```

- [ ] **Step 2: Swap the divider color in expanded content**

In `ProfileExpandableDisclosureRow` (around lines 835-842), change the divider overlay from `outline.opacity(0.45)` to the new `hairline`:

```swift
            VStack(spacing: AppTheme.spacing.xs) {
                Divider()
                    .overlay(AppTheme.colors.hairline)
                    .padding(.bottom, AppTheme.spacing.xxs)

                content
            }
            .padding(.top, AppTheme.spacing.sm)
```

- [ ] **Step 3: Build + test**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Manual check**

In simulator, toggle any disclosure ("临期任务提醒" → expand "提醒时间"). Expected:
- Spring feel (slight overshoot before settling)
- Divider above the options is noticeably thinner than before
- Transition duration feels ~0.3s (not 0.2s)

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProfileView.swift
git commit -m "$(cat <<'EOF'
refactor(profile): upgrade disclosure animation + hairline divider

Disclosure expand/collapse goes from 0.2s easeOut to
spring(response: 0.32, dampingFraction: 0.86) — softer overshoot
matches Claude iOS / Paired disclosure feel.

Expanded-content divider swapped from outline.opacity(0.45) to the
dedicated hairline token (0.10 on light, 0.08 on dark) — thinner,
more editorial, consistent with identity-card bottom divider.

Per spec 2026-04-20-profile-ux-audit-design §4.2 + §7.2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Add ProfileTokenContrastTests

**Files:**
- Create: `TogetherTests/ProfileTokenContrastTests.swift`

- [ ] **Step 1: Write the new tests**

Create `TogetherTests/ProfileTokenContrastTests.swift`:

```swift
import SwiftUI
import Testing
import UIKit
@testable import Together

@Suite
struct ProfileTokenContrastTests {

    // MARK: - hairline visibility

    @Test func hairlineLightContrastNonZero() {
        let delta = channelDelta(
            AppTheme.colors.hairline.uiColor(style: .light),
            AppTheme.colors.background.uiColor(style: .light)
        )
        #expect(delta > 0.02, "Hairline must differ from background by >2% in light mode")
    }

    @Test func hairlineDarkContrastNonZero() {
        let delta = channelDelta(
            AppTheme.colors.hairline.uiColor(style: .dark),
            AppTheme.colors.background.uiColor(style: .dark)
        )
        #expect(delta > 0.02, "Hairline must differ from background by >2% in dark mode")
    }

    // MARK: - selectionTint on surfaceElevated (for inline options + checkmark)

    @Test func selectionTintContrastLightModeAA() {
        let ratio = luminanceContrastRatio(
            AppTheme.colors.selectionTint.uiColor(style: .light),
            AppTheme.colors.surfaceElevated.uiColor(style: .light)
        )
        #expect(ratio >= 3.0, "Selection tint must meet WCAG AA for graphical objects (3:1) in light mode; got \(ratio)")
    }

    @Test func selectionTintContrastDarkModeAA() {
        let ratio = luminanceContrastRatio(
            AppTheme.colors.selectionTint.uiColor(style: .dark),
            AppTheme.colors.surfaceElevated.uiColor(style: .dark)
        )
        #expect(ratio >= 3.0, "Selection tint must meet WCAG AA for graphical objects (3:1) in dark mode; got \(ratio)")
    }

    // MARK: - Helpers

    private func channelDelta(_ a: UIColor, _ b: UIColor) -> CGFloat {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) + abs(ag - bg) + abs(ab - bb)
    }

    private func luminanceContrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let (bright, dark) = la > lb ? (la, lb) : (lb, la)
        return (bright + 0.05) / (dark + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Double {
            let vv = Double(v)
            return vv <= 0.03928 ? vv / 12.92 : pow((vv + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

private extension Color {
    /// Resolves this SwiftUI Color as a UIColor under a given interface style.
    /// Used by contrast tests to compare the light and dark flavors of
    /// dynamic tokens.
    func uiColor(style: UIUserInterfaceStyle) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return UIColor(self).resolvedColor(with: traits)
    }
}
```

- [ ] **Step 2: Run the new tests**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ProfileTokenContrastTests
```

Expected: all 4 tests PASS. If a test fails, the token values themselves may need a contrast nudge — do NOT lower the threshold. Either bump the token to meet the ratio, or narrow the test scope with a clarifying comment if the failing case is a known-acceptable non-text surface.

- [ ] **Step 3: Commit**

```bash
git add TogetherTests/ProfileTokenContrastTests.swift
git commit -m "$(cat <<'EOF'
test(profile): add WCAG contrast tests for hairline + selectionTint

Four @Tests guard the accent tokens introduced in Task 1 against
drift: hairline must differ from background by >2% channel delta
(light + dark), selectionTint must meet WCAG AA graphical contrast
(3:1) on surfaceElevated (light + dark). Uses relative-luminance
ratio per WCAG 2.1 formula.

Per spec 2026-04-20-profile-ux-audit-design §7.5 + §9.1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Final regression + PR-ready smoke

**Files:**
- None (verification only)

- [ ] **Step 1: Full test suite**

```
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: TEST SUCCEEDED across all suites.

- [ ] **Step 2: iPhone 17 Pro — Light / Dark manual smoke**

Run the app. Walk through Profile in both Light and Dark mode:
- Identity card: avatars crisp, name in `.light` weight, subtitle visible
- Hairline below identity card visible but subtle in both modes
- Pro row: coral dot readable, text legible, chevron thin
- Collaboration group: CTAs render as rows, no filled buttons
- Disclosures: spring animation feels right
- Options: selected state shows coral (not sky) in both modes
- Appearance subscreen: 3 rows, coral checkmark on current
- Sign-out: flat red text, no background

- [ ] **Step 3: AX5 Dynamic Type smoke**

Settings → Accessibility → Display & Text Size → Larger Text → set AX5. Re-launch app. Walk through Profile:
- Identity card name stays single line (dynamicTypeSize limit works)
- No rows truncate destructively (value text may clip with ellipsis — acceptable)
- Disclosure labels scale
- Pro row stays readable

- [ ] **Step 4: Haptic smoke (real device preferred)**

On a real iPhone, confirm:
- Cache clear → delete haptic
- Sign out → warning haptic
- Unbind pair → warning haptic
- Account deletion confirm → delete haptic
- Row taps → selection haptic

If no device available, trust existing test coverage + Batch C's simulator runs.

- [ ] **Step 5: VoiceOver smoke (simulator)**

Activate VoiceOver. Focus each Profile element in order:
- Identity card reads correctly for solo and pair
- Pro row reads "Together Pro，{subtitle}，升级订阅"
- 外观 row reads "外观，当前 {跟随系统/浅色/深色}"
- Sign-out reads "退出登录" + hint "退出后需要重新登录"

- [ ] **Step 6: Push branch + open PR**

Only if user has asked to push:
```bash
git push -u origin feat/profile-redesign
```

Open a PR with title "feat(profile): L3 redesign (β direction) — 17 tasks" and body pointing to this plan file + the spec.

- [ ] **Step 7: Update project memory**

After merge:
- Update `/Users/papertiger/.claude/projects/-Users-papertiger-Desktop-Together/memory/project_together_progress.md` with a new "Recent Progress" entry summarizing the Profile redesign: files touched, commits merged, visual before/after.

---

## Self-Review Summary

**Spec coverage:**
- §1 Background → not a code requirement, rationale documented in each task
- §2 IA → Tasks 7 (group merge), 8 (collaboration rows), 9 (Pro banner removal + history removal), 10 (Pro insertion), 11 (sign-out + about simplification)
- §3 Identity card → Tasks 3 (VM derived values), 4 (card rewrite), 5 (transition animation)
- §4 Per-group → Tasks 7 / 8 / 9 / 11 / 12
- §5 Pro entry → Tasks 2 (model), 10 (row + insertion)
- §6 Tokens → Task 1 (new tokens)
- §7 Interactions → Tasks 5 (pair transition), 15 (disclosure spring), 16 (contrast tests)
- §8 File change list → reflected in the file table + per-task "Files" blocks
- §9 Testing → Tasks 1 (token tests), 2 (status tests), 3 (VM derived tests), 16 (contrast tests), 13 + 17 (regression smokes)
- §10 Implementation order → Batch A (Tasks 1-2), Batch B (3-5), Batch C (6-13), Batch D (14-17)

**Placeholder scan:** none found. Every step has concrete code, exact file paths, and verifiable expected outcomes.

**Type consistency:**
- `ProSubscriptionStatus` enum values (`free` / `trial` / `active`) consistent across Tasks 2, 3, 10, 16
- `pairDaysCount` / `pairDaysLabel` / `proSubscriptionStatus` / `proSubtitleText` / `identityCardSubtitle` all defined in VM (Task 3 + 4), consumed in Tasks 4, 10
- `titleColor: Color?` added to `ProfileSettingsRow` in Task 8; used in same task
- `selectionTint` added in Task 1; consumed in Tasks 6, 12, 14, 16
- `hairline` added in Task 1; consumed in Tasks 4, 6, 15, 16
- `displayLight` added in Task 1; consumed in Task 4
- `ProfileRoute.appearance` added in Task 6; consumed in Task 7
- No dangling references.

**Scope check:** single-module redesign with clear file boundaries (~11 files touched). The 4 batches map to natural quality gates. No sub-project decomposition needed.

**Known plan assumption flagged:** Task 10 Step 2 depends on how the existing ProfileView presents navigation — the plan offers two implementations (explicit `append` vs `NavigationLink(value:)`) and instructs the executing engineer to pick the one matching the existing pattern. If neither works, the task's goal is still achievable by wrapping the row in whatever the codebase uses to push `ProfileRoute.subscription`.

---

## Deferred (Out of Scope for This Plan)

1. **History entry landing point on Home top bar** — removed from Profile in Task 7; Home layer wiring is a separate plan
2. **StoreKit 2 wiring for `ProSubscriptionStatus`** — the plan ships the UI path with `.free` hardcoded; real subscription logic is a future feature
3. **Feature-gate half-sheet** — spec §5.5 defines the pattern; no implementation until Pro features exist to gate
4. **Noto Serif SC Light bundling** — explicitly not in scope; typography convergence achieved via `displayLight` weight instead
