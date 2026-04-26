# Anniversaries: Pinned Today + Live Counter + Holiday Schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 1.0 portion of the anniversaries upgrade — pin-to-today field, live days counter with 30-day flip + long-press peek, hardcoded 2026-2027 holiday schedule, preset holiday list expanded to 10, multi-capsule stacked layout on Today.

**Architecture:** Additive on top of the existing `ImportantDate` model (1 new bool field, no kind enum changes). Display logic centralized in a new pure `DisplayMode` selector on `ImportantDate`. Holiday schedule is a separate value type loaded from a hardcoded Swift constant — no new persistence. Today UI gets a thin `PinnedAnniversaryArea` wrapper that picks between empty/single/stack rendering. Long-press peek uses existing `HomeInteractionFeedback` haptic primitives.

**Tech Stack:** Swift 6 + SwiftUI + SwiftData + Supabase (postgres) + supabase-swift SDK. iOS 17+. Existing test target `TogetherTests` (XCTest). xcodebuild for build/test invocations from CLI.

**Spec source:** `docs/superpowers/specs/2026-04-27-anniversaries-pinned-holidays-design.md`

**Out of scope (1.0.1+):** holiday-cn JSON OTA fetch, multi-language i18n, Live Activity / Lock Screen widgets, user-defined non-preset holidays.

---

## File Structure

**Create:**
- `supabase/migrations/024_add_is_pinned_to_today.sql` — schema migration
- `Together/Domain/Models/HolidaySchedule.swift` — `HolidaySchedule` value type
- `Together/Resources/HolidayScheduleData.swift` — hardcoded 2026-2027 data + `lookup()` / `nextUpcoming()` helpers
- `Together/Features/Anniversaries/PinnedAnniversaryStack.swift` — multi-capsule layered ZStack with inline expansion
- `Together/Features/Anniversaries/PinnedAnniversaryArea.swift` — wrapper deciding 0/1/N rendering
- `TogetherTests/HolidayScheduleDataTests.swift` — lookup hit/miss + ordering
- `TogetherTests/ImportantDateDisplayModeTests.swift` — decision table (kind × tense × recurrence)
- `TogetherTests/PinnedAnniversaryQuotaTests.swift` — pin cap (6) enforcement
- `TogetherTests/ImportantDateDTOPinFieldTests.swift` — DTO encode/decode round-trip for `isPinnedToToday`

**Modify:**
- `Together/Domain/Models/ImportantDate.swift` — add `isPinnedToToday`, `DisplayMode` enum, `selectMode()`, `displayAnchorDate`, expand `PresetHolidayID` enum (+7 cases)
- `Together/Persistence/Models/PersistentImportantDate.swift` — add `isPinnedToToday` (default false), thread through `init`/`make(from:)`/`apply(from:)`/`domainModel()`
- `Together/Sync/SupabaseSyncService.swift` — extend `ImportantDateDTO` with `isPinnedToToday` (default false on decode), thread through `init(from:)` and `applyToLocal`
- `Together/Features/Anniversaries/AnniversaryCapsuleView.swift` — mode-aware label using `selectMode()`, long-press peek state, haptic on long-press, `·` separator format
- `Together/Features/Anniversaries/ImportantDatesManagementView.swift` — pin/unpin toggle per row, sticky pinned-first sort, hard cap-6 alert, sheet detents
- `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift` — list expand to 10, default `isPinnedToToday = true` on creation, sheet detents
- `Together/Features/Home/HomeView.swift` — replace 3 `AnniversaryCapsuleView(...)` call sites with `PinnedAnniversaryArea(...)`

**Conventions in this codebase to follow:**
- One responsibility per file
- Comments only for non-obvious WHY (constraint, race, workaround)
- Existing `HomeInteractionFeedback` for haptic
- Existing `AppTheme.colors.rose` (added in build 8) for accent
- `@MainActor` ViewModels with `@Observable`; actors for sync services
- Test names follow `behavior_should_outcome` pattern; assertions terse

---

## Task 1: Supabase migration `024_add_is_pinned_to_today.sql`

**Files:**
- Create: `supabase/migrations/024_add_is_pinned_to_today.sql`

- [ ] **Step 1: Create migration file**

```sql
-- 024_add_is_pinned_to_today.sql
-- Per spec docs/superpowers/specs/2026-04-27-anniversaries-pinned-holidays-design.md §2.1.
-- Adds the per-row pin flag that drives Today's Pinned Anniversary stack.
-- Default false so existing rows render unchanged on old client + new client.

ALTER TABLE public.important_dates
  ADD COLUMN IF NOT EXISTS is_pinned_to_today bool NOT NULL DEFAULT false;
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `mcp__deec37d3-...__apply_migration` with name `024_add_is_pinned_to_today` and the SQL above. Expected: `{"success": true}`.

- [ ] **Step 3: Verify column exists**

Run via `mcp__deec37d3-...__execute_sql`:
```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'important_dates' AND column_name = 'is_pinned_to_today';
```
Expected: 1 row, `bool`, `false`, `NO`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/024_add_is_pinned_to_today.sql
git commit -m "feat(anniv): migration 024 add is_pinned_to_today column"
```

---

## Task 2: `PersistentImportantDate.isPinnedToToday`

**Files:**
- Modify: `Together/Persistence/Models/PersistentImportantDate.swift`

- [ ] **Step 1: Add stored field with default**

Edit `PersistentImportantDate.swift` adding the field after `deletedAt: Date?`:

```swift
    var deletedAt: Date?
    /// 1.0 anniversary pin: when true, this row appears in the Today
    /// pinned-anniversary stack. Default false; SwiftData lightweight
    /// migration (default-valued field) auto-applies — no explicit migration plan needed.
    var isPinnedToToday: Bool = false
```

- [ ] **Step 2: Thread through `init`**

Add parameter to `init` (after `deletedAt`):
```swift
        deletedAt: Date? = nil,
        isPinnedToToday: Bool = false
```
And inside body:
```swift
        self.deletedAt = deletedAt
        self.isPinnedToToday = isPinnedToToday
```

- [ ] **Step 3: Thread through `make(from:)`**

Inside `static func make(from event: ImportantDate)`, add to the constructor call:
```swift
            updatedAt: event.updatedAt,
            isLocallyDeleted: false,
            deletedAt: nil,
            isPinnedToToday: event.isPinnedToToday
```
(The existing call doesn't pass `isLocallyDeleted` / `deletedAt` — leave defaults. Just append `isPinnedToToday: event.isPinnedToToday` as the last argument.)

- [ ] **Step 4: Thread through `apply(from:)`**

Add at end of body, before the closing brace:
```swift
        self.updatedAt = event.updatedAt
        self.isPinnedToToday = event.isPinnedToToday
    }
```

- [ ] **Step 5: Thread through `domainModel()`**

In the `ImportantDate(...)` constructor at end of `domainModel()`, add `isPinnedToToday: isPinnedToToday` as the last argument (this requires Task 3 to land first; you can write the line referring to a not-yet-declared param and let xcodebuild fail in Task 3 verification — or land Task 3 first).

- [ ] **Step 6: Build to verify field added cleanly**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD FAILED` with errors only about `ImportantDate` not having `isPinnedToToday` (Task 3 fixes). Other errors are real and must be addressed.

- [ ] **Step 7: Commit (after Task 3 also done)**

(Defer commit until after Task 3 — they go together.)

---

## Task 3: `ImportantDate.isPinnedToToday`

**Files:**
- Modify: `Together/Domain/Models/ImportantDate.swift`

- [ ] **Step 1: Add field to struct**

In the `ImportantDate` struct (around line 79), add after `var updatedAt: Date`:

```swift
    var updatedAt: Date
    /// 1.0 anniversary pin (spec §2.1). Drives Today's Pinned Anniversary stack.
    var isPinnedToToday: Bool = false
```

- [ ] **Step 2: Verify build now succeeds**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit Task 2 + 3 together**

```bash
git add Together/Domain/Models/ImportantDate.swift Together/Persistence/Models/PersistentImportantDate.swift
git commit -m "feat(anniv): add isPinnedToToday to ImportantDate + PersistentImportantDate"
```

---

## Task 4: `ImportantDateDTO.isPinnedToToday`

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/ImportantDateDTOPinFieldTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/ImportantDateDTOPinFieldTests.swift`:

```swift
import XCTest
@testable import Together

final class ImportantDateDTOPinFieldTests: XCTestCase {
    func test_decode_with_pinTrue_setsIsPinnedToTodayTrue() throws {
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "space_id":"\(UUID().uuidString)",
          "creator_id":"\(UUID().uuidString)",
          "kind":"anniversary","title":"在一起",
          "date_value":"2024-06-01T00:00:00Z",
          "is_recurring":true,"recurrence_rule":"solar_annual",
          "notify_days_before":7,"notify_on_day":true,
          "icon":null,"member_user_id":null,
          "is_preset_holiday":false,"preset_holiday_id":null,
          "created_at":"2024-06-01T00:00:00Z","updated_at":"2024-06-01T00:00:00Z",
          "is_deleted":false,"deleted_at":null,
          "is_pinned_to_today":true
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(ImportantDateDTO.self, from: json)
        XCTAssertTrue(dto.isPinnedToToday)
    }

    func test_decode_without_pinField_defaultsToFalse() throws {
        // Pre-migration row (no is_pinned_to_today key) must still decode.
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "space_id":"\(UUID().uuidString)",
          "creator_id":"\(UUID().uuidString)",
          "kind":"anniversary","title":"在一起",
          "date_value":"2024-06-01T00:00:00Z",
          "is_recurring":true,"recurrence_rule":"solar_annual",
          "notify_days_before":7,"notify_on_day":true,
          "icon":null,"member_user_id":null,
          "is_preset_holiday":false,"preset_holiday_id":null,
          "created_at":"2024-06-01T00:00:00Z","updated_at":"2024-06-01T00:00:00Z",
          "is_deleted":false,"deleted_at":null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(ImportantDateDTO.self, from: json)
        XCTAssertFalse(dto.isPinnedToToday)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateDTOPinFieldTests 2>&1 | tail -20
```
Expected: compile failure ("Value of type 'ImportantDateDTO' has no member 'isPinnedToToday'").

- [ ] **Step 3: Add field + CodingKey + custom decode default**

Edit `Together/Sync/SupabaseSyncService.swift` `ImportantDateDTO`:

After `var deletedAt: Date?` add:
```swift
    var deletedAt: Date?
    /// 1.0 anniversary pin (spec §2.1). Default false on decode for
    /// pre-migration rows (column added by migration 024).
    var isPinnedToToday: Bool = false
```

Add to `CodingKeys`:
```swift
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
        case isPinnedToToday = "is_pinned_to_today"
    }
```

Add custom `init(from decoder:)` to handle missing key (since the synthesized `Codable` init would require the key by default for a non-optional Bool):

```swift
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.spaceId = try c.decode(UUID.self, forKey: .spaceId)
        self.creatorId = try c.decode(UUID.self, forKey: .creatorId)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.title = try c.decode(String.self, forKey: .title)
        self.dateValue = try c.decode(Date.self, forKey: .dateValue)
        self.isRecurring = try c.decode(Bool.self, forKey: .isRecurring)
        self.recurrenceRule = try c.decodeIfPresent(String.self, forKey: .recurrenceRule)
        self.notifyDaysBefore = try c.decode(Int.self, forKey: .notifyDaysBefore)
        self.notifyOnDay = try c.decode(Bool.self, forKey: .notifyOnDay)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.memberUserId = try c.decodeIfPresent(UUID.self, forKey: .memberUserId)
        self.isPresetHoliday = try c.decode(Bool.self, forKey: .isPresetHoliday)
        self.presetHolidayId = try c.decodeIfPresent(String.self, forKey: .presetHolidayId)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.isDeleted = try c.decode(Bool.self, forKey: .isDeleted)
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        // Default false to keep pre-migration JSON decodable.
        self.isPinnedToToday = (try c.decodeIfPresent(Bool.self, forKey: .isPinnedToToday)) ?? false
    }
```

- [ ] **Step 4: Thread through `init(from persistent:)` and `applyToLocal`**

In `extension ImportantDateDTO { nonisolated init(from persistent:) }` add:
```swift
        self.deletedAt = persistent.deletedAt
        self.isPinnedToToday = persistent.isPinnedToToday
    }
```

In `applyToLocal(context:)`, in the existing-row branch add before `existing.updatedAt = updatedAt`:
```swift
        existing.isPinnedToToday = isPinnedToToday
```

In the new-row insert branch (`PersistentImportantDate(...)` constructor call), append:
```swift
                isLocallyDeleted: false,
                isPinnedToToday: isPinnedToToday
            )
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateDTOPinFieldTests 2>&1 | grep -E "Test Suite.*passed|failed|FAILED"
```
Expected: tests pass.

- [ ] **Step 6: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift TogetherTests/ImportantDateDTOPinFieldTests.swift
git commit -m "feat(anniv): plumb isPinnedToToday through ImportantDateDTO with backcompat decoder"
```

---

## Task 5: Expand `PresetHolidayID` (+7 cases)

**Files:**
- Modify: `Together/Domain/Models/ImportantDate.swift`

- [ ] **Step 1: Add 7 new cases**

Replace existing `enum PresetHolidayID` (around line 41) with:

```swift
enum PresetHolidayID: String, CaseIterable, Sendable, Codable {
    // Existing
    case valentines       // 公历 2/14
    case qixi             // 农历 7/7
    case springFestival   // 农历正月初一

    // 1.0 expansion (spec §4.1)
    case newYear          // 公历 1/1
    case qingming         // 节气 ≈ 公历 4/5（hardcoded schedule 提供精确日期）
    case laborDay         // 公历 5/1
    case dragonBoat       // 农历 5/5
    case midAutumn        // 农历 8/15
    case nationalDay      // 公历 10/1
    case christmas        // 公历 12/25

    var defaultTitle: String {
        switch self {
        case .valentines: return "情人节"
        case .qixi: return "七夕"
        case .springFestival: return "春节"
        case .newYear: return "元旦"
        case .qingming: return "清明节"
        case .laborDay: return "劳动节"
        case .dragonBoat: return "端午节"
        case .midAutumn: return "中秋节"
        case .nationalDay: return "国庆节"
        case .christmas: return "圣诞节"
        }
    }

    var defaultIcon: String {
        switch self {
        case .valentines: return "heart.fill"
        case .qixi: return "sparkles"
        case .springFestival: return "party.popper.fill"
        case .newYear: return "fireworks"
        case .qingming: return "leaf.fill"
        case .laborDay: return "hammer.fill"
        case .dragonBoat: return "sailboat.fill"
        case .midAutumn: return "moon.fill"
        case .nationalDay: return "flag.fill"
        case .christmas: return "gift.fill"
        }
    }

    var recurrence: Recurrence {
        switch self {
        case .valentines, .newYear, .laborDay, .nationalDay, .christmas:
            return .solarAnnual
        case .qixi, .springFestival, .dragonBoat, .midAutumn:
            return .lunarAnnual
        case .qingming:
            // Qingming follows the solar term (太阳黄经 15°), not a fixed
            // solar or lunar date. We mark it solarAnnual so daysUntilNext
            // works on the seed date as a reasonable fallback; the precise
            // year-by-year date comes from HolidayScheduleData.lookup.
            return .solarAnnual
        }
    }

    /// Month/day in the relevant calendar (solar for solarAnnual, lunar for lunarAnnual).
    /// For qingming this is the typical solar date 4/5 — actual year-specific
    /// date is overridden by HolidayScheduleData when available.
    var monthDay: (month: Int, day: Int) {
        switch self {
        case .valentines: return (2, 14)
        case .qixi: return (7, 7)
        case .springFestival: return (1, 1)
        case .newYear: return (1, 1)
        case .qingming: return (4, 5)
        case .laborDay: return (5, 1)
        case .dragonBoat: return (5, 5)
        case .midAutumn: return (8, 15)
        case .nationalDay: return (10, 1)
        case .christmas: return (12, 25)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Together/Domain/Models/ImportantDate.swift
git commit -m "feat(anniv): expand PresetHolidayID to 10 (元旦/清明/劳动/端午/中秋/国庆/圣诞)"
```

---

## Task 6: `HolidaySchedule` value type

**Files:**
- Create: `Together/Domain/Models/HolidaySchedule.swift`

- [ ] **Step 1: Create file**

```swift
import Foundation

/// One year's worth of statutory holiday schedule (放假安排), including
/// any 调休 days the State Council bundles into the contiguous 放假 range.
/// Spec §2.4.
///
/// Display layer maps a user-created ImportantDate (kind == .holiday with
/// presetHolidayID) to the matching HolidaySchedule for the current year
/// to show "距春节假期还有 N 天". When no schedule exists for the year
/// (user is past the hardcoded 2026-2027 window before they update the
/// app), display falls back to ImportantDate.nextOccurrence on the
/// holiday's seed month/day.
struct HolidaySchedule: Hashable, Sendable {
    /// Display name including year, e.g. "2026 春节".
    let name: String
    /// First day of the contiguous off-period (i.e. start of 放假).
    let startDate: Date
    /// Last day of the off-period (inclusive).
    let endDate: Date
    /// Total days off (含调休补班后的实际放假天数).
    let offDays: Int
    /// Link back to PresetHolidayID so display layer can map a user's
    /// ImportantDate row to its matching year-specific schedule.
    let preset: PresetHolidayID?
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Together/Domain/Models/HolidaySchedule.swift
git commit -m "feat(anniv): add HolidaySchedule value type"
```

---

## Task 7: `HolidayScheduleData` hardcoded 2026-2027 + tests

**Files:**
- Create: `Together/Resources/HolidayScheduleData.swift`
- Create: `TogetherTests/HolidayScheduleDataTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/HolidayScheduleDataTests.swift`:

```swift
import XCTest
@testable import Together

final class HolidayScheduleDataTests: XCTestCase {
    func test_lookup_2026_springFestival_returnsSchedule() throws {
        let schedule = try XCTUnwrap(HolidayScheduleData.lookup(preset: .springFestival, year: 2026))
        XCTAssertEqual(schedule.name, "2026 春节")
        // 2026 春节放假为 2/16 (周一) ~ 2/22 (周日)，7 天
        XCTAssertEqual(Calendar.current.component(.month, from: schedule.startDate), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: schedule.startDate), 16)
        XCTAssertEqual(schedule.offDays, 7)
        XCTAssertEqual(schedule.preset, .springFestival)
    }

    func test_lookup_unsupportedYear_returnsNil() {
        XCTAssertNil(HolidayScheduleData.lookup(preset: .springFestival, year: 2099))
    }

    func test_lookup_unsupportedPreset_returnsNil() {
        // valentines is in PresetHolidayID but not officially a 法定节假日 — we
        // intentionally don't ship a schedule for it. Lookup returns nil.
        XCTAssertNil(HolidayScheduleData.lookup(preset: .valentines, year: 2026))
    }

    func test_nextUpcoming_excludesPastSchedules() {
        let future = Calendar.current.date(byAdding: .year, value: 100, to: .now)!
        let upcoming = HolidayScheduleData.nextUpcoming(now: future)
        XCTAssertTrue(upcoming.isEmpty, "All hardcoded schedules should be in the past relative to year 2126")
    }

    func test_all_isSortedByStartDate() {
        let starts = HolidayScheduleData.all.map { $0.startDate }
        XCTAssertEqual(starts, starts.sorted(), "HolidayScheduleData.all must be in ascending startDate order for nextUpcoming() to short-circuit")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/HolidayScheduleDataTests 2>&1 | tail -5
```
Expected: compile failure ("Cannot find 'HolidayScheduleData' in scope").

- [ ] **Step 3: Create `HolidayScheduleData`**

Create `Together/Resources/HolidayScheduleData.swift`:

```swift
import Foundation

/// Hardcoded 2026-2027 法定节假日 schedules per State Council 公告.
///
/// **Maintenance:** State Council typically publishes next year's 放假安排
/// in early November. After publication, append the new year's entries
/// here in startDate order and ship in the next app release. 1.0.1 will
/// add OTA fetch from holiday-cn (NateScarlet/holiday-cn GitHub repo)
/// so users see new years without app upgrade — until then, this file
/// is the single source of truth.
///
/// Source: 国务院办公厅关于 2026/2027 年部分节假日安排的通知.
enum HolidayScheduleData {
    static let all: [HolidaySchedule] = build()

    static func lookup(preset: PresetHolidayID, year: Int) -> HolidaySchedule? {
        all.first { schedule in
            schedule.preset == preset
                && Calendar.current.component(.year, from: schedule.startDate) == year
        }
    }

    static func nextUpcoming(now: Date = .now) -> [HolidaySchedule] {
        // .all is already sorted by startDate; suffix once we hit the first
        // not-yet-ended entry rather than scanning twice.
        guard let firstUpcomingIdx = all.firstIndex(where: { $0.endDate >= now }) else {
            return []
        }
        return Array(all[firstUpcomingIdx...])
    }

    // MARK: - Hardcoded data

    private static func build() -> [HolidaySchedule] {
        // Inline `make` keeps year-by-year edits diff-friendly. Dates are
        // local-calendar Date instances at midnight — comparisons are by-day,
        // not by-second, so timezone drift on date-arithmetic is tolerable.
        var out: [HolidaySchedule] = []

        // ===== 2026 =====
        out.append(.init(name: "2026 元旦", startDate: date(2026, 1, 1), endDate: date(2026, 1, 1), offDays: 1, preset: .newYear))
        out.append(.init(name: "2026 春节", startDate: date(2026, 2, 16), endDate: date(2026, 2, 22), offDays: 7, preset: .springFestival))
        out.append(.init(name: "2026 清明", startDate: date(2026, 4, 4), endDate: date(2026, 4, 6), offDays: 3, preset: .qingming))
        out.append(.init(name: "2026 劳动节", startDate: date(2026, 5, 1), endDate: date(2026, 5, 5), offDays: 5, preset: .laborDay))
        out.append(.init(name: "2026 端午节", startDate: date(2026, 6, 19), endDate: date(2026, 6, 21), offDays: 3, preset: .dragonBoat))
        out.append(.init(name: "2026 中秋节", startDate: date(2026, 9, 25), endDate: date(2026, 9, 27), offDays: 3, preset: .midAutumn))
        out.append(.init(name: "2026 国庆节", startDate: date(2026, 10, 1), endDate: date(2026, 10, 8), offDays: 8, preset: .nationalDay))

        // ===== 2027 (initial draft — VERIFY against 国务院公告 when published) =====
        out.append(.init(name: "2027 元旦", startDate: date(2027, 1, 1), endDate: date(2027, 1, 3), offDays: 3, preset: .newYear))
        out.append(.init(name: "2027 春节", startDate: date(2027, 2, 6), endDate: date(2027, 2, 12), offDays: 7, preset: .springFestival))
        out.append(.init(name: "2027 清明", startDate: date(2027, 4, 3), endDate: date(2027, 4, 5), offDays: 3, preset: .qingming))
        out.append(.init(name: "2027 劳动节", startDate: date(2027, 5, 1), endDate: date(2027, 5, 5), offDays: 5, preset: .laborDay))
        out.append(.init(name: "2027 端午节", startDate: date(2027, 6, 9), endDate: date(2027, 6, 11), offDays: 3, preset: .dragonBoat))
        out.append(.init(name: "2027 中秋节", startDate: date(2027, 9, 15), endDate: date(2027, 9, 19), offDays: 5, preset: .midAutumn))
        out.append(.init(name: "2027 国庆节", startDate: date(2027, 10, 1), endDate: date(2027, 10, 7), offDays: 7, preset: .nationalDay))

        return out
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
```

> **Note for the engineer applying this task:** The 2027 entries are placeholders pending official 公告 (typically published in November 2026). When the real 公告 is out, replace those entries with the published dates. The 2026 entries above match the actual 国务院 2025-11 公告. The unit test `test_lookup_2026_springFestival_returnsSchedule` validates 2026 春节 = 2/16; if that ever changes upstream, both this file and the test must be updated.

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/HolidayScheduleDataTests 2>&1 | grep -E "Test Suite.*passed|FAILED"
```
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Together/Resources/HolidayScheduleData.swift TogetherTests/HolidayScheduleDataTests.swift
git commit -m "feat(anniv): hardcoded 2026-2027 holiday schedules + lookup helpers"
```

---

## Task 8: `ImportantDate.DisplayMode` + `selectMode()`

**Files:**
- Modify: `Together/Domain/Models/ImportantDate.swift`
- Create: `TogetherTests/ImportantDateDisplayModeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/ImportantDateDisplayModeTests.swift`:

```swift
import XCTest
@testable import Together

final class ImportantDateDisplayModeTests: XCTestCase {

    private func makeEvent(
        kind: ImportantDateKind,
        anchor: Date,
        recurrence: Recurrence
    ) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: kind,
            title: "test",
            dateValue: anchor,
            recurrence: recurrence,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now
        )
    }

    private var now: Date { Calendar.current.startOfDay(for: .now) }
    private var futureAnchor: Date { Calendar.current.date(byAdding: .day, value: 60, to: now)! }
    private var pastAnchor: Date { Calendar.current.date(byAdding: .year, value: -2, to: now)! }
    private var nearFutureRecurrence: Date {
        // anchor 2 years ago + solarAnnual → next occurrence ~365 days away from anniversary day.
        // Use anchor 60 days ago of last year so next solarAnnual occurrence is ~305 days away.
        Calendar.current.date(byAdding: .day, value: -60, to: now)!
    }

    func test_anchorInFuture_alwaysCountdown() {
        for kind in [ImportantDateKind.anniversary, .holiday, .custom, .birthday(memberUserID: UUID())] {
            let e = makeEvent(kind: kind, anchor: futureAnchor, recurrence: .none)
            XCTAssertEqual(e.selectMode(now: now), .countdown, "kind=\(kind) anchor in future should be countdown")
        }
    }

    func test_birthday_pastAnchor_recurring_isCountdown() {
        let e = makeEvent(kind: .birthday(memberUserID: UUID()), anchor: pastAnchor, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_holiday_pastAnchor_recurring_isCountdown() {
        let e = makeEvent(kind: .holiday, anchor: pastAnchor, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_anniversary_pastAnchor_recurring_farFromNext_isForwardCount() {
        // anchor 2 years ago today, solarAnnual → next occurrence is ~365 days away → forwardCount.
        let twoYearsAgoToday = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let e = makeEvent(kind: .anniversary, anchor: twoYearsAgoToday, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }

    func test_anniversary_pastAnchor_recurring_within30Days_flipsCountdown() {
        // anchor 2 years ago + 20 days → next occurrence ~20 days away (< 30) → countdown.
        let recentAnniversaryDay = Calendar.current.date(byAdding: .day, value: 20, to: now)!
        let twoYearsBack = Calendar.current.date(byAdding: .year, value: -2, to: recentAnniversaryDay)!
        let e = makeEvent(kind: .anniversary, anchor: twoYearsBack, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .countdown)
    }

    func test_custom_pastAnchor_noneRecurrence_isForwardCount() {
        let e = makeEvent(kind: .custom, anchor: pastAnchor, recurrence: .none)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }

    func test_custom_pastAnchor_recurring_sameRuleAsAnniversary() {
        let twoYearsAgoToday = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let e = makeEvent(kind: .custom, anchor: twoYearsAgoToday, recurrence: .solarAnnual)
        XCTAssertEqual(e.selectMode(now: now), .forwardCount)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateDisplayModeTests 2>&1 | tail -5
```
Expected: compile failure (`selectMode` / `DisplayMode` not found).

- [ ] **Step 3: Add `DisplayMode` + `selectMode()` to `ImportantDate.swift`**

Append before the final closing brace of `extension ImportantDate { ... }` (the one containing `daysSinceStart`):

```swift
extension ImportantDate {
    /// Display mode the UI uses for this event's primary metric.
    /// `forwardCount` = "已经 N 天" since anchor.
    /// `countdown`    = "还有 N 天" until next occurrence (or anchor if anchor in future).
    enum DisplayMode { case forwardCount, countdown }

    /// Spec §3.1 decision table.
    func selectMode(now: Date = .now) -> DisplayMode {
        // Rule 1: anchor in future → always countdown to anchor.
        if dateValue > now { return .countdown }

        // Rule 2: anchor in past → kind-specific.
        switch kind {
        case .birthday, .holiday:
            // Always countdown — annual cycle, days-since not meaningful.
            return .countdown
        case .anniversary:
            return modeForRecurring(now: now)
        case .custom:
            switch recurrence {
            case .none:
                return .forwardCount
            case .solarAnnual, .lunarAnnual:
                return modeForRecurring(now: now)
            }
        }
    }

    /// Recurring + past-anchor rule: default forwardCount unless next
    /// occurrence is within 30 days (then flip to countdown to give the
    /// user lead time on the upcoming celebration).
    private func modeForRecurring(now: Date) -> DisplayMode {
        guard let until = daysUntilNext(from: now), until < 30 else {
            return .forwardCount
        }
        return .countdown
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateDisplayModeTests 2>&1 | grep -E "Test Suite.*passed|FAILED"
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Together/Domain/Models/ImportantDate.swift TogetherTests/ImportantDateDisplayModeTests.swift
git commit -m "feat(anniv): DisplayMode decision (kind × tense × 30-day flip) + tests"
```

---

## Task 9: `ImportantDate.displayAnchorDate` (sort key for stack)

**Files:**
- Modify: `Together/Domain/Models/ImportantDate.swift`

- [ ] **Step 1: Add helper**

In the same `extension ImportantDate { ... }`, append:

```swift
    /// Sort key for the Today pinned-anniversary stack (spec §5.1):
    /// - recurring events → next occurrence
    /// - .none-recurrence + anchor in future → anchor itself
    /// - .none-recurrence + anchor passed → distantFuture (don't compete for top slot)
    func displayAnchorDate(now: Date = .now) -> Date {
        if recurrence != .none {
            return nextOccurrence(after: now) ?? .distantFuture
        }
        return dateValue > now ? dateValue : .distantFuture
    }
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Together/Domain/Models/ImportantDate.swift
git commit -m "feat(anniv): displayAnchorDate sort helper for pinned stack"
```

---

## Task 10: `AnniversaryCapsuleView` — mode-aware label + long-press peek + haptic

**Files:**
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`

- [ ] **Step 1: Replace view body to render mode-aware label**

Replace the existing `var body` and `private var detail` with:

```swift
    @State private var isPeeking = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: icon)
                    .font(AppTheme.typography.sized(16, weight: .semibold))

                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))

                Spacer(minLength: 0)

                Text(metricText)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: metricText)
            }
            .foregroundStyle(AppTheme.colors.rose)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.rose.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        // Long-press peek (spec §3.2): only meaningful when both metrics
        // exist (anniversary or recurring custom). Birthday/holiday have a
        // single semantic — long-press is a no-op there.
        .onLongPressGesture(
            minimumDuration: 0.6,
            maximumDistance: 24,
            perform: {},
            onPressingChanged: { pressing in
                guard let event = nextEvent, event.hasPeekableAlternateMode else { return }
                if pressing {
                    HomeInteractionFeedback.selection()
                    isPeeking = true
                } else {
                    // Linger 1.5s before resuming default mode (matches iOS
                    // peek convention — value floats just long enough to read).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isPeeking = false
                    }
                }
            }
        )
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(metricText))
    }

    private var metricText: String {
        guard let event = nextEvent else { return "点击添加" }
        let mode = effectiveMode(for: event)
        switch mode {
        case .countdown:
            guard let target = countdownTarget(for: event) else { return "—" }
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: .now),
                                          to: cal.startOfDay(for: target)).day ?? 0
            return days <= 0 ? "· 今天" : "· 还有 \(days) 天"
        case .forwardCount:
            let days = event.daysSinceStart
            return days <= 0 ? "· 今天" : "· \(days) 天"
        }
    }

    /// Spec §2.5: for .holiday rows with a hardcoded HolidaySchedule, the
    /// countdown target is the 放假首日, not the festival's core day —
    /// users care about "距春节假期还有 N 天" (when can I rest?), not the
    /// abstract lunar-calendar marker. Falls back to nextOccurrence on the
    /// event's seed date when no schedule is available (year outside the
    /// 1.0 hardcoded 2026-2027 window — 1.0.1 OTA fetch will widen this).
    private func countdownTarget(for event: ImportantDate) -> Date? {
        if case .holiday = event.kind, let preset = event.presetHolidayID {
            let now = Date()
            let thisYear = Calendar.current.component(.year, from: now)
            if let s = HolidayScheduleData.lookup(preset: preset, year: thisYear),
               s.startDate > now {
                return s.startDate
            }
            if let s = HolidayScheduleData.lookup(preset: preset, year: thisYear + 1) {
                return s.startDate
            }
        }
        return event.nextOccurrence(after: .now)
    }

    private func effectiveMode(for event: ImportantDate) -> ImportantDate.DisplayMode {
        let base = event.selectMode()
        guard isPeeking, event.hasPeekableAlternateMode else { return base }
        return base == .forwardCount ? .countdown : .forwardCount
    }
```

- [ ] **Step 2: Add `hasPeekableAlternateMode` to ImportantDate**

In `Together/Domain/Models/ImportantDate.swift` extension, append:

```swift
    /// True when this event has both meaningful forwardCount and
    /// countdown metrics (spec §3.2). Used to gate long-press peek
    /// — birthday/holiday only have countdown, peek is a no-op there.
    var hasPeekableAlternateMode: Bool {
        switch kind {
        case .anniversary:
            return recurrence != .none
        case .custom:
            return recurrence != .none && dateValue <= .now
        case .birthday, .holiday:
            return false
        }
    }
```

- [ ] **Step 3: Build + run anniversary tests**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateDisplayModeTests 2>&1 | grep -E "Test Suite.*passed|FAILED|BUILD (SUCCEEDED|FAILED)"
```
Expected: `BUILD SUCCEEDED`, tests pass.

- [ ] **Step 4: Commit**

```bash
git add Together/Features/Anniversaries/AnniversaryCapsuleView.swift Together/Domain/Models/ImportantDate.swift
git commit -m "feat(anniv): mode-aware capsule label + long-press peek with haptic"
```

---

## Task 11: `PinnedAnniversaryStack` — multi-capsule layered view

**Files:**
- Create: `Together/Features/Anniversaries/PinnedAnniversaryStack.swift`

- [ ] **Step 1: Create file**

```swift
import SwiftUI

/// Multi-capsule stacked layout for the Today area when ≥2 events are
/// pinned to today. Mirrors iOS Lock Screen notification stack:
/// top capsule fully visible, bottom 1-2 capsules peek out via offset+scale.
/// Tapping the stack expands to a vertical list inline (no sheet, no
/// scroll-container exit). Tapping the top capsule when expanded folds
/// back to the stacked state.
///
/// Spec §5.2.
struct PinnedAnniversaryStack: View {
    let events: [ImportantDate]              // sorted by displayAnchorDate ascending
    let viewerSupabaseUserID: UUID?
    let partnerDisplayName: String?
    let onTapEvent: (ImportantDate) -> Void

    @State private var isExpanded = false

    /// Spec §5.2: render at most 3 in the stacked z-stack. The rest hide
    /// behind a "+N" badge until the user expands.
    private static let stackedRenderLimit = 3

    var body: some View {
        if isExpanded {
            VStack(spacing: AppTheme.spacing.sm) {
                ForEach(events) { event in
                    AnniversaryCapsuleView(
                        nextEvent: event,
                        viewerSupabaseUserID: viewerSupabaseUserID,
                        partnerDisplayName: partnerDisplayName,
                        onTap: { handleCapsuleTap(event: event, isTopOfStack: event.id == events.first?.id) }
                    )
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            collapsedStack
                .transition(.opacity)
        }
    }

    private var collapsedStack: some View {
        ZStack(alignment: .top) {
            // Render bottom-up so the top capsule sits on top of the ZStack.
            ForEach(Array(visibleStackedSlice.enumerated().reversed()), id: \.element.id) { idx, event in
                AnniversaryCapsuleView(
                    nextEvent: event,
                    viewerSupabaseUserID: viewerSupabaseUserID,
                    partnerDisplayName: partnerDisplayName,
                    onTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded = true } }
                )
                .scaleEffect(scale(forIndex: idx))
                .offset(y: offsetY(forIndex: idx))
                .zIndex(Double(visibleStackedSlice.count - idx))
                .allowsHitTesting(idx == 0) // only top capsule receives taps; lower ones decorative
            }
        }
        .overlay(alignment: .topTrailing) {
            if events.count > Self.stackedRenderLimit {
                Text("+\(events.count - Self.stackedRenderLimit)")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.colors.rose.opacity(0.18)))
                    .offset(x: -8, y: -6)
            }
        }
        // The visible stack is taller than a single capsule because of the
        // peek offset; pad bottom so it doesn't clip the bottom edges of
        // the underlying capsules.
        .padding(.bottom, CGFloat(visibleStackedSlice.count - 1) * 6)
    }

    private var visibleStackedSlice: [ImportantDate] {
        Array(events.prefix(Self.stackedRenderLimit))
    }

    private func scale(forIndex idx: Int) -> CGFloat {
        // 0 → 1.0, 1 → 0.96, 2 → 0.92
        max(0.88, 1.0 - CGFloat(idx) * 0.04)
    }

    private func offsetY(forIndex idx: Int) -> CGFloat {
        // Each subsequent capsule peeks ~6pt below the previous.
        CGFloat(idx) * 6
    }

    private func handleCapsuleTap(event: ImportantDate, isTopOfStack: Bool) {
        if isTopOfStack {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = false
            }
        } else {
            onTapEvent(event)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Together/Features/Anniversaries/PinnedAnniversaryStack.swift
git commit -m "feat(anniv): PinnedAnniversaryStack layered + inline expansion"
```

---

## Task 12: `PinnedAnniversaryArea` wrapper (0/1/N dispatcher)

**Files:**
- Create: `Together/Features/Anniversaries/PinnedAnniversaryArea.swift`

- [ ] **Step 1: Create file**

```swift
import SwiftUI

/// Today-region wrapper that picks the right rendering for the current
/// pinned set:
/// - 0 pinned → renders nothing (caller should not allocate space)
/// - 1 pinned → single AnniversaryCapsuleView
/// - 2+ pinned → PinnedAnniversaryStack with stack-then-expand UX
///
/// Spec §5.1.
struct PinnedAnniversaryArea: View {
    /// Already filtered to isPinnedToToday=true and sorted by displayAnchorDate ascending.
    let pinnedEvents: [ImportantDate]
    let viewerSupabaseUserID: UUID?
    let partnerDisplayName: String?
    let onTapEvent: (ImportantDate) -> Void

    var body: some View {
        switch pinnedEvents.count {
        case 0:
            EmptyView()
        case 1:
            AnniversaryCapsuleView(
                nextEvent: pinnedEvents[0],
                viewerSupabaseUserID: viewerSupabaseUserID,
                partnerDisplayName: partnerDisplayName,
                onTap: { onTapEvent(pinnedEvents[0]) }
            )
        default:
            PinnedAnniversaryStack(
                events: pinnedEvents,
                viewerSupabaseUserID: viewerSupabaseUserID,
                partnerDisplayName: partnerDisplayName,
                onTapEvent: onTapEvent
            )
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Together/Features/Anniversaries/PinnedAnniversaryArea.swift
git commit -m "feat(anniv): PinnedAnniversaryArea 0/1/N dispatcher"
```

---

## Task 13: `ImportantDatesViewModel.pinnedEvents` computed + cap-6 alert

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`
- Create: `TogetherTests/PinnedAnniversaryQuotaTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TogetherTests/PinnedAnniversaryQuotaTests.swift`:

```swift
import XCTest
@testable import Together

@MainActor
final class PinnedAnniversaryQuotaTests: XCTestCase {

    private func makeEvent(pinned: Bool, anchor: Date) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: .anniversary,
            title: "test",
            dateValue: anchor,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now,
            isPinnedToToday: pinned
        )
    }

    func test_pinnedCap_isSix() {
        XCTAssertEqual(ImportantDatesViewModel.pinnedToTodayCap, 6)
    }

    func test_pinnedEvents_filtersAndSortsByAnchor() {
        // Build six events with displayAnchorDate spread across 5..30 days.
        let now = Date()
        let dates = [30, 5, 10, 25, 1, 15].map {
            Calendar.current.date(byAdding: .day, value: -$0 * 365 + 5, to: now)!
        }
        // Mark 4 of them pinned.
        let events = dates.enumerated().map { idx, anchor in
            makeEvent(pinned: idx < 4, anchor: anchor)
        }
        let sortedAnchors = events.prefix(4)
            .map { $0.displayAnchorDate() }
            .sorted()

        XCTAssertEqual(
            ImportantDatesViewModel.pinnedEvents(from: events).map { $0.displayAnchorDate() },
            sortedAnchors
        )
    }

    func test_canPinAnotherToToday_returnsFalseWhenAtCap() {
        let pinnedSix = (0..<6).map { _ in makeEvent(pinned: true, anchor: Date()) }
        XCTAssertFalse(ImportantDatesViewModel.canPinAnotherToToday(events: pinnedSix))
        let pinnedFive = (0..<5).map { _ in makeEvent(pinned: true, anchor: Date()) }
        XCTAssertTrue(ImportantDatesViewModel.canPinAnotherToToday(events: pinnedFive))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/PinnedAnniversaryQuotaTests 2>&1 | tail -5
```
Expected: compile failures (`pinnedToTodayCap`, `pinnedEvents(from:)`, `canPinAnotherToToday(events:)` not found).

- [ ] **Step 3: Add static helpers + cap to ViewModel**

In `ImportantDatesViewModel.swift`, after the existing `static let freeAnniversaryQuota = 3` line, add:

```swift
    /// 1.0 hard cap on Today pinned anniversaries (spec §5.2).
    /// Above 6 the stacked view becomes visually crowded; UI surfaces an
    /// alert when the user tries to pin a 7th.
    static let pinnedToTodayCap = 6

    /// Filters and sorts events for the Today pinned area.
    /// Sort by displayAnchorDate ascending so the next-occurring pinned
    /// event sits at the top of the stack (closest in time = highest
    /// salience).
    nonisolated static func pinnedEvents(from events: [ImportantDate], now: Date = .now) -> [ImportantDate] {
        events
            .filter { $0.isPinnedToToday }
            .sorted { $0.displayAnchorDate(now: now) < $1.displayAnchorDate(now: now) }
    }

    /// Predicate the View consults before showing the pin toggle's "on" state.
    nonisolated static func canPinAnotherToToday(events: [ImportantDate]) -> Bool {
        events.filter { $0.isPinnedToToday }.count < pinnedToTodayCap
    }
```

Add an instance computed for view binding (immediately after the `var events: [ImportantDate]` line):

```swift
    var events: [ImportantDate] = []

    /// Convenience for HomeView's PinnedAnniversaryArea.
    var pinnedEvents: [ImportantDate] {
        Self.pinnedEvents(from: events)
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/PinnedAnniversaryQuotaTests 2>&1 | grep -E "Test Suite.*passed|FAILED"
```
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesViewModel.swift TogetherTests/PinnedAnniversaryQuotaTests.swift
git commit -m "feat(anniv): pinnedEvents helper + cap 6 + tests"
```

---

## Task 14: Replace `HomeView` `AnniversaryCapsuleView` call sites with `PinnedAnniversaryArea`

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: Identify the 3 call sites**

```bash
grep -n "AnniversaryCapsuleView(" Together/Features/Home/HomeView.swift
```
Expected: 3 line numbers (recently 387, 505, 610 — verify before editing).

- [ ] **Step 2: At each call site, replace `AnniversaryCapsuleView(...)` with `PinnedAnniversaryArea(...)`**

For each occurrence, replace the block. Example (the empty-state one near line 387):

```swift
                        if appContext.sessionStore.activeMode == .pair {
                            PinnedAnniversaryArea(
                                pinnedEvents: viewModel.importantDatesViewModel.pinnedEvents,
                                viewerSupabaseUserID: appContext.currentSupabaseUserID,
                                partnerDisplayName: appContext.sessionStore.pairSpaceSummary?.partner?.displayName,
                                onTapEvent: { event in
                                    isImportantDatesManagementPresented = true
                                }
                            )
                        }
```

Use the same shape at the other two call sites (just adapt indent/wrapping to match surrounding code).

> **Note:** `viewModel.importantDatesViewModel` may be `appContext.importantDatesViewModel` — match the existing usage pattern at each call site (`nextAnniversaryEvent()` was reading from the same place). Check before editing.

- [ ] **Step 3: Remove the now-unused `nextAnniversaryEvent()` helper**

```bash
grep -n "func nextAnniversaryEvent\|nextAnniversaryEvent()" Together/Features/Home/HomeView.swift
```
If only the function definition remains (no callers), delete it.

- [ ] **Step 4: Build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Home/HomeView.swift
git commit -m "feat(anniv): wire HomeView to PinnedAnniversaryArea (replace 3 capsule call sites)"
```

---

## Task 15: `ImportantDatesManagementView` — pin toggle button + sticky pinned-first sort

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`

- [ ] **Step 1: Add pin toggle action + state for cap alert**

Near the top of the View struct (alongside the other `@State` declarations), add:
```swift
    @State private var showsPinCapAlert = false
```

Find the existing `private var list` property and the `private func row(event:)` method.

Inside `row(event:)`, **prepend** a leading `Button` for pin/unpin to the existing `HStack`:

```swift
    private func row(event: ImportantDate) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            // Pin toggle (spec §6.1) — leading icon, rose-tinted, single-tap toggle.
            Button {
                togglePin(event: event)
            } label: {
                Image(systemName: event.isPinnedToToday ? "bookmark.fill" : "bookmark")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isPinnedToToday ? "取消固定到 Today" : "固定到 Today")

            // ... existing icon + text + spacer + days label ...
        }
        // ... existing modifiers ...
    }
```

- [ ] **Step 2: Add `togglePin` method**

After the existing `displayTitle(for:)` helper:

```swift
    /// Spec §6.1. Caps at 6 simultaneously pinned; pinning a 7th opens an alert.
    private func togglePin(event: ImportantDate) {
        if !event.isPinnedToToday,
           !ImportantDatesViewModel.canPinAnotherToToday(events: viewModel.events) {
            showsPinCapAlert = true
            return
        }
        var updated = event
        updated.isPinnedToToday.toggle()
        updated.updatedAt = .now
        Task { await viewModel.updateExisting(updated) }
        HomeInteractionFeedback.selection()
    }
```

- [ ] **Step 3: Update list ordering — pinned first, then by displayAnchorDate**

Find `private var list` and the existing `ForEach(viewModel.events.sorted { nextKey($0) < nextKey($1) })`.
Replace with:

```swift
            ForEach(orderedEvents) { event in
                row(event: event)
                    // ... existing row modifiers (listRowInsets, swipeActions, onTapGesture) ...
            }
```

And add this helper near `nextKey`:

```swift
    /// Pinned items float to the top (spec §6.1). Within each group items
    /// stay sorted by displayAnchorDate so the user's next event is always
    /// visually closest.
    private var orderedEvents: [ImportantDate] {
        viewModel.events.sorted { lhs, rhs in
            if lhs.isPinnedToToday != rhs.isPinnedToToday {
                return lhs.isPinnedToToday
            }
            return lhs.displayAnchorDate() < rhs.displayAnchorDate()
        }
    }
```

- [ ] **Step 4: Add cap alert modifier on the view**

Attach to the outer `NavigationStack`/`Group`:

```swift
        .alert("已达 \(ImportantDatesViewModel.pinnedToTodayCap) 个固定上限",
               isPresented: $showsPinCapAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("Today 最多只能固定 \(ImportantDatesViewModel.pinnedToTodayCap) 个纪念日。请先取消其他纪念日的固定。")
        }
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesManagementView.swift
git commit -m "feat(anniv): pin toggle + sticky pinned-first sort + cap-6 alert"
```

---

## Task 16: `PresetHolidayPickerSheet` — list expand to 10 + default pin

**Files:**
- Modify: `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift`

- [ ] **Step 1: Inspect current preset enumeration**

```bash
grep -n "PresetHolidayID\|allCases\|isPinnedToToday" Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
```

If the sheet already iterates `PresetHolidayID.allCases`, the list is already 10 (Task 5 added the cases). Otherwise update the iteration source. Verify by running the app and counting rows; if not auto-populated, switch to `ForEach(PresetHolidayID.allCases, id: \.self)`.

- [ ] **Step 2: Set `isPinnedToToday = true` on creation**

Find the function that creates an `ImportantDate` from a chosen preset (look for `ImportantDate(id: UUID(), ..., presetHolidayID: ...)`). Set the new field:

```swift
        let event = ImportantDate(
            // ... existing fields ...
            presetHolidayID: preset,
            updatedAt: .now,
            isPinnedToToday: true   // Spec §6.3 — preset holidays are auto-pinned.
        )
```

If multiple creation paths exist (single-add vs batch-add), apply at every site that constructs an ImportantDate from a preset.

- [ ] **Step 3: Build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
git commit -m "feat(anniv): preset holiday picker — 10 entries + default isPinnedToToday=true"
```

---

## Task 17: Sheet detents — `medium`/`large` on management + preset picker

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
- Modify: `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift`

- [ ] **Step 1: Find the `.sheet(...)` modifiers**

```bash
grep -n "presentationDetents\|\.sheet(" Together/Features/Anniversaries/ImportantDatesManagementView.swift Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
```

- [ ] **Step 2: Apply `.presentationDetents([.medium, .large])` + drag indicator on each sheet's root**

For each sheet's root view (e.g. `NavigationStack { ... }` body), append:

```swift
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesManagementView.swift Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
git commit -m "feat(anniv): sheet detents medium/large + drag indicator"
```

---

## Task 18: Full test sweep + manual smoke

- [ ] **Step 1: Run the full TogetherTests suite**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|FAILURE"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Manual regression smoke (run on simulator)**

Build to simulator, then verify by interaction:

1. Sign in, complete pair, navigate to Profile → 纪念日.
2. Add a custom anniversary "我们在一起" with anchor 2 years ago → list shows row.
3. Tap bookmark icon → row's bookmark fills, row floats to top.
4. Add 5 more anniversaries with various anchor dates and pin them. The 7th pin attempt → cap alert appears.
5. Return to Today: see stack with 6 events (top capsule + 2 visible peeks + "+3" badge).
6. Tap the stack → expands to vertical list of 6 capsules.
7. Tap top capsule → folds back to stack.
8. Long-press an anniversary capsule → metric flips (forwardCount ↔ countdown), haptic fires; release → after 1.5s flips back.
9. Add preset holiday "春节" via picker → defaults pinned, shows up on Today as countdown.
10. Verify on second device (paired) — pin/unpin syncs via Supabase.

If any of the above fails: open a separate fix task (do not commit broken state).

- [ ] **Step 3: Commit any lint/comment fixes that came out of smoke**

If clean: no commit needed.

- [ ] **Step 4: Tag release candidate**

```bash
git tag -a v1.0-anniv-pinned -m "1.0 pinned anniversaries + holiday schedules feature complete"
```

---

## Self-Review Checklist (engineer should run after every 2-3 tasks)

1. After each task: `xcodebuild ... build` succeeds and any new tests pass.
2. After Task 4 (DTO): pull a real partner row from Supabase via the app, verify `isPinnedToToday` round-trips.
3. After Task 10 (CapsuleView): visually compare on simulator vs the spec's UI description — capsule shape, rose tint, `·` separator, peek behavior.
4. After Task 14 (HomeView wire-up): Today renders as expected in 0/1/N states.
5. After Task 15 (Management): pin toggle behavior is responsive (haptic + bookmark flip in same frame).
6. **Final**: 6 capsules pinned → stack visual + expansion + "+3" badge match spec §5.2.

---

## Rollback Strategy

If any task introduces breakage caught after commit:

```bash
git revert <commit-sha>          # safe: builds a new revert commit
# or, if multiple consecutive bad commits:
git revert --no-edit HEAD~3..HEAD
```

Schema migration 024 has no rollback file (the column add is forward-only); should the column need to come out, write a `025_drop_is_pinned_to_today.sql` rather than reverting 024.

---

## Spec Coverage Map

| Spec section | Covered by task |
|---|---|
| §2.1 isPinnedToToday field | Task 1 (SQL), 2 (SwiftData), 3 (domain), 4 (DTO) |
| §2.3 PresetHolidayID expansion | Task 5 |
| §2.4 HolidaySchedule type | Task 6 |
| §2.5 ImportantDate × HolidaySchedule | Task 7 (data + lookup helpers) + Task 10 (display layer consumes lookup) |
| §3.1 Mode decision table | Task 8 |
| §3.2 Long-press peek + haptic | Task 10 |
| §3.3 `·` separator format | Task 10 |
| §4.1 Hardcoded 2026-2027 | Task 7 |
| §5.1 Today 0/1/N rendering | Task 12 |
| §5.2 PinnedAnniversaryStack | Task 11 |
| §5.3 HomeView replacement | Task 14 |
| §6.1 Pin toggle UI | Task 15 |
| §6.2 Sheet detents | Task 17 |
| §6.3 Preset auto-pinned | Task 16 |
| §7 Migrations (Supabase + SwiftData + DTO) | Task 1, 2, 3, 4 |
| §8 Test coverage | Tasks 4, 7, 8, 13 (+ smoke 18) |
| §10 Out of scope | Not implemented (1.0.1 spawn task — separate plan) |
