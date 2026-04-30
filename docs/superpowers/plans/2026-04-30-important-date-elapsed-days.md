# Important Date Elapsed Days Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-important-date preference that lets anniversary/custom rows show both `还有 N 天` and `已经 N 天`, and make the Today anniversary capsule obey the same preference.

**Architecture:** Keep the display preference on `ImportantDate` and sync it through SwiftData, Supabase DTOs, and the `important_dates` table. Domain and cloud use a non-optional Boolean; local SwiftData stores an optional Boolean to distinguish legacy local rows from a user explicitly turning the preference off.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Supabase Postgres migrations, existing `xcodebuild` iOS Simulator workflow.

---

## Current Context

Relevant spec:

- `docs/superpowers/specs/2026-04-30-important-date-elapsed-days-design.md`

Current code already has:

- `Together/Domain/Models/ImportantDate.swift`
  - `daysUntilNext(...)`
  - `daysSinceStart`
- `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`
  - local `AnniversaryCapsuleCountMode`
  - `@AppStorage("together.anniversaryCapsule.countMode")`
  - `.contentTransition(.numericText())`
  - long-press toggle currently limited to `.anniversary`
- `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
  - plain `List`
  - `row(event:)`
  - `daysLabel(for:)`
  - `viewModel.save(_:)` exists
- `Together/Persistence/Models/PersistentImportantDate.swift`
  - maps between SwiftData and `ImportantDate`
- `Together/Sync/SupabaseSyncService.swift`
  - `ImportantDateDTO`
  - `ImportantDateDTO.applyToLocal(context:)`
  - `ImportantDateDTO.init(from persistent:)`
- Existing tests:
  - `TogetherTests/ImportantDateSyncDTOTests.swift`
  - `TogetherTests/ImportantDatePushTests.swift`
  - `TogetherTests/ImportantDatePullTests.swift`
  - `TogetherTests/ImportantDateNextOccurrenceTests.swift`

Repository note:

- `supabase/migrations/038_archive_previous_pair_spaces_on_accept.sql` already exists in this workspace. Use migration number `039` for this feature.
- The worktree may contain unrelated dirty files. Do not revert or restage them.

---

## File Structure

- Modify: `Together/Domain/Models/ImportantDate.swift`
  - Add `showsElapsedDays`.
  - Add `supportsElapsedDaysDisplay`.
  - Add a shared default helper for legacy rows.
- Modify: `Together/Persistence/Models/PersistentImportantDate.swift`
  - Add optional `showsElapsedDays`.
  - Map optional local values into non-optional domain values.
- Modify: `Together/Sync/SupabaseSyncService.swift`
  - Add `showsElapsedDays` to `ImportantDateDTO`.
  - Add custom decode fallback for old JSON.
  - Map DTO to/from SwiftData.
- Modify: `Together/Sync/Solo/SupabaseSoloSyncService.swift`
  - No direct field changes are expected beyond compile compatibility because solo uses `ImportantDateDTO.applyToLocal`.
- Create: `supabase/migrations/039_add_elapsed_days_to_important_dates.sql`
  - Add `shows_elapsed_days`.
  - Backfill existing undeleted anniversary rows.
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
  - Add row-level Toggle for anniversary/custom.
  - Add elapsed label text.
  - Save only this field on Toggle changes.
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`
  - Gate elapsed mode by `event.supportsElapsedDaysDisplay && event.showsElapsedDays`.
  - Use `已经 N 天`.
  - Reset stored elapsed mode when current event does not allow elapsed display.
- Modify: tests listed above.

---

### Task 1: Domain and SwiftData Model

**Files:**
- Modify: `Together/Domain/Models/ImportantDate.swift`
- Modify: `Together/Persistence/Models/PersistentImportantDate.swift`
- Test: build only in this task

- [ ] **Step 1: Add domain field and helpers**

In `Together/Domain/Models/ImportantDate.swift`, update `ImportantDate`:

```swift
struct ImportantDate: Identifiable, Hashable, Sendable {
    let id: UUID
    let spaceID: UUID
    let creatorID: UUID
    var kind: ImportantDateKind
    var title: String
    var dateValue: Date
    var recurrence: Recurrence
    var notifyDaysBefore: Int
    var notifyOnDay: Bool
    var icon: String?
    var presetHolidayID: PresetHolidayID?
    var showsElapsedDays: Bool = false
    var updatedAt: Date

    static let validNotifyDaysBefore: [Int] = [1, 3, 7, 15, 30]
}
```

Then add this inside `extension ImportantDate`:

```swift
    var supportsElapsedDaysDisplay: Bool {
        switch kind {
        case .anniversary, .custom:
            return true
        case .birthday, .holiday:
            return false
        }
    }

    static func defaultShowsElapsedDays(kindRawValue: String) -> Bool {
        kindRawValue == "anniversary"
    }
```

Why: the default helper is used only for legacy rows that have no stored value. New `ImportantDate(...)` calls use the property default `false`.

- [ ] **Step 2: Add optional SwiftData field**

In `Together/Persistence/Models/PersistentImportantDate.swift`, add a property after `presetHolidayIDRawValue`:

```swift
    var showsElapsedDays: Bool?
```

Update the initializer signature:

```swift
        isPresetHoliday: Bool = false,
        presetHolidayIDRawValue: String? = nil,
        showsElapsedDays: Bool? = nil,
        createdAt: Date = .now,
```

Set the property inside the initializer:

```swift
        self.showsElapsedDays = showsElapsedDays
```

Use optional storage because old local SwiftData rows will have `nil`. That lets existing anniversary rows default to `true`, while a user explicitly toggling the switch off can be stored as `false`.

- [ ] **Step 3: Map SwiftData to domain**

In `domainModel()`, add `showsElapsedDays` before `updatedAt`:

```swift
            icon: icon,
            presetHolidayID: presetHolidayIDRawValue.flatMap(PresetHolidayID.init(rawValue:)),
            showsElapsedDays: showsElapsedDays ?? ImportantDate.defaultShowsElapsedDays(kindRawValue: kindRawValue),
            updatedAt: updatedAt
```

- [ ] **Step 4: Map domain to SwiftData on insert/update**

In `PersistentImportantDate.make(from:)`, add:

```swift
            isPresetHoliday: event.presetHolidayID != nil,
            presetHolidayIDRawValue: event.presetHolidayID?.rawValue,
            showsElapsedDays: event.showsElapsedDays,
            updatedAt: event.updatedAt
```

In `apply(from:)`, add:

```swift
        self.isPresetHoliday = event.presetHolidayID != nil
        self.presetHolidayIDRawValue = event.presetHolidayID?.rawValue
        self.showsElapsedDays = event.showsElapsedDays
        self.updatedAt = event.updatedAt
```

- [ ] **Step 5: Run build to catch constructor drift**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected before later tasks: build may fail in `ImportantDateDTO` or test constructor call sites. Fix only constructor/compiler errors caused by the new field, not unrelated dirty-worktree issues.

- [ ] **Step 6: Commit Task 1**

```bash
git add Together/Domain/Models/ImportantDate.swift Together/Persistence/Models/PersistentImportantDate.swift
git commit -m "Add elapsed days field to important dates"
```

---

### Task 2: Supabase Schema and DTO Sync

**Files:**
- Create: `supabase/migrations/039_add_elapsed_days_to_important_dates.sql`
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Test: `TogetherTests/ImportantDateSyncDTOTests.swift`
- Test: `TogetherTests/ImportantDatePushTests.swift`
- Test: `TogetherTests/ImportantDatePullTests.swift`

- [ ] **Step 1: Write DTO tests first**

Extend `TogetherTests/ImportantDateSyncDTOTests.swift`.

In the existing `encodesSnakeCase()` DTO initializer, add:

```swift
            isPresetHoliday: false, presetHolidayId: nil,
            showsElapsedDays: true,
            createdAt: .now, updatedAt: .now,
```

Then add this assertion:

```swift
        #expect(json?["shows_elapsed_days"] as? Bool == true)
```

In the `roundTrip()` initializer, add:

```swift
            isPresetHoliday: false, presetHolidayId: nil,
            showsElapsedDays: true,
            createdAt: .now, updatedAt: .now,
```

Then add:

```swift
        #expect(decoded.showsElapsedDays == true)
```

In the `presetHoliday()` initializer, add:

```swift
            isPresetHoliday: true, presetHolidayId: "qixi",
            showsElapsedDays: false,
            createdAt: .now, updatedAt: .now,
```

Add a new test:

```swift
    @Test("old JSON missing shows_elapsed_days defaults anniversary to true and custom to false")
    func decodesMissingElapsedDaysWithKindDefaults() throws {
        let anniversaryJSON = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "space_id":"00000000-0000-0000-0000-000000000002",
          "creator_id":"00000000-0000-0000-0000-000000000003",
          "kind":"anniversary",
          "title":"我们在一起的日子",
          "date_value":"2025-04-16T00:00:00Z",
          "is_recurring":true,
          "recurrence_rule":"solar_annual",
          "notify_days_before":7,
          "notify_on_day":true,
          "icon":"heart.fill",
          "member_user_id":null,
          "is_preset_holiday":false,
          "preset_holiday_id":null,
          "created_at":"2025-04-16T00:00:00Z",
          "updated_at":"2025-04-16T00:00:00Z",
          "is_deleted":false,
          "deleted_at":null
        }
        """.data(using: .utf8)!

        let customJSON = anniversaryJSON
            .replacingOccurrences(of: "\"kind\":\"anniversary\"", with: "\"kind\":\"custom\"")
            .replacingOccurrences(of: "\"title\":\"我们在一起的日子\"", with: "\"title\":\"第一次旅行\"")
            .data(using: .utf8)!

        let decoder = JSONDecoder()
        let anniversary = try decoder.decode(ImportantDateDTO.self, from: anniversaryJSON)
        let custom = try decoder.decode(ImportantDateDTO.self, from: customJSON)

        #expect(anniversary.showsElapsedDays == true)
        #expect(custom.showsElapsedDays == false)
    }
```

- [ ] **Step 2: Run DTO test and verify it fails**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateSyncDTOTests 2>&1 | tail -30
```

Expected: compile failure because `ImportantDateDTO` has no `showsElapsedDays` field yet.

- [ ] **Step 3: Add migration**

Create `supabase/migrations/039_add_elapsed_days_to_important_dates.sql`:

```sql
-- Migration 039: per-important-date elapsed-days display preference.
--
-- Existing anniversary rows keep the behavior users already expect from the
-- "我们在一起的日子" capsule. Custom rows and all new rows default off.

alter table public.important_dates
add column if not exists shows_elapsed_days boolean not null default false;

update public.important_dates
set shows_elapsed_days = true
where kind = 'anniversary'
  and is_deleted = false;
```

- [ ] **Step 4: Add DTO field with legacy decode fallback**

In `Together/Sync/SupabaseSyncService.swift`, add property:

```swift
    var showsElapsedDays: Bool
```

Add coding key:

```swift
        case showsElapsedDays = "shows_elapsed_days"
```

Replace synthesized Codable with explicit `init(from:)` and `encode(to:)` inside `ImportantDateDTO`:

```swift
    init(
        id: UUID,
        spaceId: UUID,
        creatorId: UUID,
        kind: String,
        title: String,
        dateValue: Date,
        isRecurring: Bool,
        recurrenceRule: String?,
        notifyDaysBefore: Int,
        notifyOnDay: Bool,
        icon: String?,
        memberUserId: UUID?,
        isPresetHoliday: Bool,
        presetHolidayId: String?,
        showsElapsedDays: Bool,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool,
        deletedAt: Date?
    ) {
        self.id = id
        self.spaceId = spaceId
        self.creatorId = creatorId
        self.kind = kind
        self.title = title
        self.dateValue = dateValue
        self.isRecurring = isRecurring
        self.recurrenceRule = recurrenceRule
        self.notifyDaysBefore = notifyDaysBefore
        self.notifyOnDay = notifyOnDay
        self.icon = icon
        self.memberUserId = memberUserId
        self.isPresetHoliday = isPresetHoliday
        self.presetHolidayId = presetHolidayId
        self.showsElapsedDays = showsElapsedDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceId = try container.decode(UUID.self, forKey: .spaceId)
        creatorId = try container.decode(UUID.self, forKey: .creatorId)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        dateValue = try container.decode(Date.self, forKey: .dateValue)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule)
        notifyDaysBefore = try container.decode(Int.self, forKey: .notifyDaysBefore)
        notifyOnDay = try container.decode(Bool.self, forKey: .notifyOnDay)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        memberUserId = try container.decodeIfPresent(UUID.self, forKey: .memberUserId)
        isPresetHoliday = try container.decode(Bool.self, forKey: .isPresetHoliday)
        presetHolidayId = try container.decodeIfPresent(String.self, forKey: .presetHolidayId)
        showsElapsedDays = try container.decodeIfPresent(Bool.self, forKey: .showsElapsedDays)
            ?? ImportantDate.defaultShowsElapsedDays(kindRawValue: kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(spaceId, forKey: .spaceId)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(dateValue, forKey: .dateValue)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(notifyDaysBefore, forKey: .notifyDaysBefore)
        try container.encode(notifyOnDay, forKey: .notifyOnDay)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(memberUserId, forKey: .memberUserId)
        try container.encode(isPresetHoliday, forKey: .isPresetHoliday)
        try container.encodeIfPresent(presetHolidayId, forKey: .presetHolidayId)
        try container.encode(showsElapsedDays, forKey: .showsElapsedDays)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
```

- [ ] **Step 5: Map DTO to SwiftData**

In `ImportantDateDTO.applyToLocal(context:)`, update existing rows:

```swift
            existing.isPresetHoliday = isPresetHoliday
            existing.presetHolidayIDRawValue = presetHolidayId
            existing.showsElapsedDays = showsElapsedDays
            existing.updatedAt = updatedAt
```

In the new `PersistentImportantDate(...)` initializer call, add:

```swift
                isPresetHoliday: isPresetHoliday,
                presetHolidayIDRawValue: presetHolidayId,
                showsElapsedDays: showsElapsedDays,
                createdAt: createdAt,
```

In `ImportantDateDTO.init(from persistent:)`, add:

```swift
        self.showsElapsedDays = persistent.showsElapsedDays
            ?? ImportantDate.defaultShowsElapsedDays(kindRawValue: persistent.kindRawValue)
```

- [ ] **Step 6: Update test helper DTO constructors**

Add `showsElapsedDays:` to every `ImportantDateDTO(...)` initializer in:

- `TogetherTests/ImportantDateSyncDTOTests.swift`
- `TogetherTests/ImportantDatePullTests.swift`
- `TogetherTests/SupabaseSoloSyncServiceTests.swift`

Default rule for test fixtures:

```swift
showsElapsedDays: kind == "anniversary"
```

For explicit custom rows, use:

```swift
showsElapsedDays: false
```

- [ ] **Step 7: Extend push/pull assertions**

In `TogetherTests/ImportantDatePushTests.swift`, update `seedImportantDate(...)` to accept:

```swift
    showsElapsedDays: Bool = false
```

Pass it into `PersistentImportantDate(...)`:

```swift
        showsElapsedDays: showsElapsedDays,
```

In `pushUpsertCallsWriter()`, call:

```swift
try seedImportantDate(
    in: container,
    id: recordID,
    spaceID: spaceID,
    title: "妈生日",
    showsElapsedDays: true
)
```

Add assertion:

```swift
#expect(dto?.showsElapsedDays == true)
```

In `TogetherTests/ImportantDatePullTests.swift`, extend `makeDTO(...)` with:

```swift
    showsElapsedDays: Bool = false,
```

Pass it into `ImportantDateDTO(...)`.

Add a test:

```swift
    @Test("pull persists elapsed days display preference")
    func pullPersistsElapsedDaysPreference() async throws {
        let h = try await ImportantDatePullHarness()
        let id = UUID()
        h.reader.setRows([makeDTO(
            id: id,
            spaceID: h.spaceID,
            title: "第一次旅行",
            showsElapsedDays: true
        )])

        try await h.sut.pullImportantDatesForTesting(spaceID: h.spaceID)

        let rows = try h.localRows()
        #expect(rows.count == 1)
        #expect(rows.first?.showsElapsedDays == true)
    }
```

- [ ] **Step 8: Run sync tests**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateSyncDTOTests -only-testing:TogetherTests/ImportantDatePushTests -only-testing:TogetherTests/ImportantDatePullTests 2>&1 | tail -40
```

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 2**

```bash
git add supabase/migrations/039_add_elapsed_days_to_important_dates.sql Together/Sync/SupabaseSyncService.swift TogetherTests/ImportantDateSyncDTOTests.swift TogetherTests/ImportantDatePushTests.swift TogetherTests/ImportantDatePullTests.swift TogetherTests/SupabaseSoloSyncServiceTests.swift
git commit -m "Sync important date elapsed days preference"
```

---

### Task 3: Management Sheet Row Toggle

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`

- [ ] **Step 1: Add display helpers**

In `ImportantDatesManagementView`, replace `daysLabel(for:)` with next/elapsed helpers:

```swift
    private func nextDaysLabel(for event: ImportantDate) -> String {
        guard let days = event.daysUntilNext() else { return "-" }
        return days == 0 ? "今天" : "还有 \(days) 天"
    }

    private func elapsedDaysLabel(for event: ImportantDate) -> String {
        "已经 \(max(0, event.daysSinceStart)) 天"
    }
```

Update references from `daysLabel(for:)` to `nextDaysLabel(for:)`.

- [ ] **Step 2: Replace row layout**

Replace `row(event:)` with:

```swift
    private func row(event: ImportantDate) -> some View {
        Button {
            showEdit = event
        } label: {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(displayTitle(for: event))
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    Text(dateLabel(for: event))
                        .font(AppTheme.typography.textStyle(.caption1))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.spacing.sm)

                HStack(spacing: AppTheme.spacing.sm) {
                    VStack(alignment: .trailing, spacing: AppTheme.spacing.xxs) {
                        Text(nextDaysLabel(for: event))
                            .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if event.supportsElapsedDaysDisplay && event.showsElapsedDays {
                            Text(elapsedDaysLabel(for: event))
                                .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.rose.opacity(0.82))
                                .contentTransition(.numericText())
                        }
                    }
                    .multilineTextAlignment(.trailing)

                    if event.supportsElapsedDaysDisplay {
                        Toggle(
                            "同时展示累计天数",
                            isOn: elapsedDaysBinding(for: event)
                        )
                        .labelsHidden()
                        .tint(AppTheme.colors.rose)
                        .fixedSize()
                        .accessibilityLabel("同时展示累计天数")
                        .accessibilityValue(event.showsElapsedDays ? "已开启" : "已关闭")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayTitle(for: event)))
        .accessibilityValue(Text(accessibilityValue(for: event)))
        .accessibilityHint(Text(event.supportsElapsedDaysDisplay ? "轻点编辑，使用开关控制是否显示累计天数" : "轻点编辑这个纪念日"))
    }
```

- [ ] **Step 3: Add binding and save helpers**

Add:

```swift
    private func elapsedDaysBinding(for event: ImportantDate) -> Binding<Bool> {
        Binding(
            get: { event.showsElapsedDays },
            set: { newValue in
                updateElapsedDaysPreference(for: event, showsElapsedDays: newValue)
            }
        )
    }

    private func updateElapsedDaysPreference(for event: ImportantDate, showsElapsedDays: Bool) {
        guard event.supportsElapsedDaysDisplay else { return }
        var updated = event
        updated.showsElapsedDays = showsElapsedDays
        updated.updatedAt = .now
        HomeInteractionFeedback.selection()
        Task {
            await viewModel.save(updated)
        }
    }

    private func accessibilityValue(for event: ImportantDate) -> String {
        if event.supportsElapsedDaysDisplay && event.showsElapsedDays {
            return "\(dateLabel(for: event))，\(nextDaysLabel(for: event))，\(elapsedDaysLabel(for: event))"
        }
        return "\(dateLabel(for: event))，\(nextDaysLabel(for: event))"
    }
```

Why: the Toggle binding writes through `viewModel.save(_:)`. Because the Toggle consumes its own tap target, row editing still works through the surrounding Button.

- [ ] **Step 4: Set create defaults explicitly**

In `createBirthday(myself:)`, add:

```swift
            icon: "gift.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
```

In `createAnniversary()`, add:

```swift
            icon: "heart.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
```

In `createCustom()`, add:

```swift
            icon: "star.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
```

This is redundant with the domain default, but makes the product rule visible at creation sites.

- [ ] **Step 5: Update preset holiday creation sites**

In `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift`, add `showsElapsedDays: false` to both `ImportantDate(...)` calls.

- [ ] **Step 6: Run build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: build succeeds. If SwiftUI complains about `Binding` in a non-mutating helper, qualify the return type as `SwiftUI.Binding<Bool>`.

- [ ] **Step 7: Commit Task 3**

```bash
git add Together/Features/Anniversaries/ImportantDatesManagementView.swift Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
git commit -m "Add elapsed days toggle to important dates sheet"
```

---

### Task 4: Today Anniversary Capsule Gate

**Files:**
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`

- [ ] **Step 1: Update label text and eligibility**

In `detail`, replace:

```swift
        if countMode == .elapsed, isAnniversary(event) {
            return "已 \(max(0, event.daysSinceStart)) 天"
        }
```

with:

```swift
        if countMode == .elapsed, canShowElapsedDays(for: event) {
            return "已经 \(max(0, event.daysSinceStart)) 天"
        }
```

Replace `canToggleCountMode`:

```swift
    private var canToggleCountMode: Bool {
        guard let nextEvent else { return false }
        return canShowElapsedDays(for: nextEvent)
    }
```

Add:

```swift
    private func canShowElapsedDays(for event: ImportantDate) -> Bool {
        event.supportsElapsedDaysDisplay && event.showsElapsedDays
    }
```

- [ ] **Step 2: Reset stale stored elapsed mode**

Add this modifier to `body` after `.onLongPressGesture(...)`:

```swift
        .onChange(of: nextEvent?.id) { _, _ in
            normalizeCountModeIfNeeded()
        }
        .onChange(of: nextEvent?.showsElapsedDays) { _, _ in
            normalizeCountModeIfNeeded()
        }
        .task {
            normalizeCountModeIfNeeded()
        }
```

Add helper:

```swift
    private func normalizeCountModeIfNeeded() {
        guard countMode == .elapsed, canToggleCountMode == false else { return }
        countModeRawValue = AnniversaryCapsuleCountMode.next.rawValue
    }
```

Why: the stored `@AppStorage` mode is global. If it says elapsed but the next event does not allow elapsed display, the capsule must immediately fall back to next.

- [ ] **Step 3: Remove old anniversary-only helper**

Delete:

```swift
    private func isAnniversary(_ event: ImportantDate) -> Bool {
        if case .anniversary = event.kind { return true }
        return false
    }
```

No behavior should depend on kind alone anymore.

- [ ] **Step 4: Run build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: build succeeds.

- [ ] **Step 5: Commit Task 4**

```bash
git add Together/Features/Anniversaries/AnniversaryCapsuleView.swift
git commit -m "Gate anniversary capsule elapsed days display"
```

---

### Task 5: Count Logic Tests and Final Verification

**Files:**
- Modify: `TogetherTests/ImportantDateNextOccurrenceTests.swift`
- Modify: `TogetherTests/ImportantDatesViewModelQuotaTests.swift` if constructor compile fixes are still needed
- Modify: any remaining `ImportantDate(...)` / `PersistentImportantDate(...)` test constructors that fail to compile

- [ ] **Step 1: Add domain behavior tests**

In `TogetherTests/ImportantDateNextOccurrenceTests.swift`, add:

```swift
    @Test("elapsed days support is limited to anniversary and custom")
    func elapsedDaysSupportByKind() {
        let anniversary = makeEvent(
            dateValue: date("2025-04-16T00:00:00Z"),
            recurrence: .solarAnnual,
            kind: .anniversary
        )
        let custom = makeEvent(
            dateValue: date("2025-04-16T00:00:00Z"),
            recurrence: .solarAnnual,
            kind: .custom
        )
        let birthday = makeEvent(
            dateValue: date("2025-04-16T00:00:00Z"),
            recurrence: .solarAnnual,
            kind: .birthday(memberUserID: UUID())
        )
        let holiday = makeEvent(
            dateValue: date("2025-04-16T00:00:00Z"),
            recurrence: .solarAnnual,
            kind: .holiday
        )

        #expect(anniversary.supportsElapsedDaysDisplay == true)
        #expect(custom.supportsElapsedDaysDisplay == true)
        #expect(birthday.supportsElapsedDaysDisplay == false)
        #expect(holiday.supportsElapsedDaysDisplay == false)
    }

    @Test("legacy elapsed days default is true only for anniversary raw kind")
    func legacyElapsedDaysDefaultByRawKind() {
        #expect(ImportantDate.defaultShowsElapsedDays(kindRawValue: "anniversary") == true)
        #expect(ImportantDate.defaultShowsElapsedDays(kindRawValue: "custom") == false)
        #expect(ImportantDate.defaultShowsElapsedDays(kindRawValue: "birthday") == false)
        #expect(ImportantDate.defaultShowsElapsedDays(kindRawValue: "holiday") == false)
    }
```

- [ ] **Step 2: Run focused tests**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateNextOccurrenceTests -only-testing:TogetherTests/ImportantDateSyncDTOTests -only-testing:TogetherTests/ImportantDatePushTests -only-testing:TogetherTests/ImportantDatePullTests 2>&1 | tail -60
```

Expected: all focused tests pass.

- [ ] **Step 3: Run diff check**

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Run full build**

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Optional full test pass**

Run this if time allows or if any shared sync/model code changed beyond this plan:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|Executed [0-9]+ tests|error:"
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit Task 5**

```bash
git add TogetherTests/ImportantDateNextOccurrenceTests.swift TogetherTests/ImportantDatesViewModelQuotaTests.swift TogetherTests
git commit -m "Test important date elapsed days preference"
```

Only include test files actually modified by this task. Do not use broad `git add TogetherTests` if unrelated test files are dirty.

---

## Self-Review Checklist

- Spec coverage:
  - Per-date preference: Task 1 and Task 2.
  - Supabase migration and sync: Task 2.
  - Sheet row toggle: Task 3.
  - Homepage capsule gate and `.numericText()`: Task 4 keeps existing numeric transition and gates elapsed mode.
  - Tests and verification: Task 5.
- Placeholder scan:
  - No `TBD`, `TODO`, or unspecified test steps.
- Type consistency:
  - Domain property: `showsElapsedDays`.
  - DB/JSON key: `shows_elapsed_days`.
  - Support helper: `supportsElapsedDaysDisplay`.
  - Legacy helper: `ImportantDate.defaultShowsElapsedDays(kindRawValue:)`.
- Scope check:
  - This is one feature across persistence/sync/UI; tasks are ordered so each produces a testable increment.
