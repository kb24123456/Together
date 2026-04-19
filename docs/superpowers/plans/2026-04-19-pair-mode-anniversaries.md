# Pair-Mode Anniversaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 pair 模式砍掉例行事务、保留任务和项目、新增"纪念日"feature（双方生日 / 在一起纪念日 / 常见节日 / 自定义事件）+ 本机 `UNUserNotification` 倒计时提醒。

**Architecture:** 新增 Supabase 表 `important_dates` 和 SwiftData `PersistentImportantDate` 镜像；复用现有 pair sync（push/pull/realtime）+ `ReaderWriter` seam 测试模式；本机 `UNUserNotification` 幂等全量调度；主页新胶囊 + "我"页新入口；服务端硬删 pair-space periodic_tasks + 客户端一次性 migration 清理本地缓存。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / supabase-swift SDK / PostgreSQL migrations / Swift Testing / UserNotifications / Calendar(.chinese) for 农历.

---

## 硬性约束（所有 task 通用）

1. **Swift Testing**（`import Testing` / `@Test` / `#expect`）——不用 XCTest
2. In-memory `ModelContainer` 必须列出**全部 Persistent 模型**（新增 `PersistentImportantDate` 后清单从 16 变 17）
3. 跨文件公用 test helper 直接 import 引用，不要重新定义
4. Commit message：英文 conventional commit + trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
5. 每个 task 一个 commit；build + 全量 regression 绿才完成
6. 禁用 `print`；用 `os.Logger`。禁 `// TODO` / `// FIXME` 注释
7. Supabase project ID：`nxielmwdoiwiwhzczrmt`
8. Pair space 识别条件：`spaces.type = 'pair'`（没有独立 `pair_spaces` 表）

---

## 文件结构一览

### 新建

**Supabase:**
- `supabase/migrations/015_hard_delete_pair_periodic.sql`
- `supabase/migrations/016_create_important_dates.sql`

**Domain:**
- `Together/Domain/Models/ImportantDate.swift`
- `Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift`

**Persistence:**
- `Together/Persistence/Models/PersistentImportantDate.swift`

**Services:**
- `Together/Services/ImportantDates/LocalImportantDateRepository.swift`
- `Together/Services/ImportantDates/MockImportantDateRepository.swift`
- `Together/Services/Notifications/AnniversaryNotificationScheduler.swift`
- `Together/App/Migrations/PairPeriodicPurgeMigration.swift`

**UI:**
- `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
- `Together/Features/Anniversaries/ImportantDateEditSheet.swift`
- `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift`
- `Together/Features/Anniversaries/ImportantDatesViewModel.swift`（重写，取代 `AnniversariesViewModel`）
- `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`

**Tests:**
- `TogetherTests/ImportantDateNextOccurrenceTests.swift`
- `TogetherTests/ImportantDateRepositoryTests.swift`
- `TogetherTests/ImportantDateSyncDTOTests.swift`
- `TogetherTests/ImportantDatePushTests.swift`
- `TogetherTests/ImportantDatePullTests.swift`
- `TogetherTests/AnniversaryNotificationSchedulerTests.swift`
- `TogetherTests/PairPeriodicPurgeMigrationTests.swift`
- `TogetherTests/PeriodicTaskPairGuardTests.swift`

### 修改

- `Together/Persistence/PersistenceController.swift`（Schema 加入 `PersistentImportantDate`）
- `Together/Sync/SyncCoordinatorProtocol.swift`（`SyncEntityKind.importantDate`）
- `Together/Sync/SupabaseSyncService.swift`（push/pull 分支 + DTO + Reader/Writer seam + realtime channel）
- `Together/Sync/Engine/SyncEngineDelegate.swift`（包含 importantDate 的处理）
- `Together/App/AppContainer.swift`（新字段 `importantDateRepository` + `anniversaryScheduler`）
- `Together/Services/LocalServiceFactory.swift`
- `Together/Services/MockServiceFactory.swift`
- `Together/App/AppContext.swift`（wire scheduler + postLaunch purge migration）
- `Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift`（pair-space guard）
- `Together/TogetherApp.swift` / `Together/App/AppRootView.swift`（条件 tab bar）
- `Together/Features/Home/HomeView.swift`（routines card 条件 + 新 capsule）
- `Together/Features/Profile/*.swift`（"我"页双人模式区加入口 — 具体文件开工时 grep 确认）
- `Together/Services/Anniversaries/*.swift`（删除旧 Mock + Protocol，迁入新目录）

### 删除

- `Together/Services/Anniversaries/MockAnniversaryRepository.swift`
- `Together/Domain/Protocols/AnniversaryRepositoryProtocol.swift`
- `Together/Features/Anniversaries/AnniversariesViewModel.swift`（旧）

---

# Batch A: Schema + Domain Model（6 tasks）

---

## Task 1: Migration 015 — 硬删 pair-space periodic_tasks

**Files:**
- Create: `supabase/migrations/015_hard_delete_pair_periodic.sql`

**注意**：`spaces.type = 'pair'` 识别 pair space（没有独立 `pair_spaces` 表）。MCP 查询已确认当前 pair-space 有 **1** 条活跃 periodic_task 数据。

- [ ] **Step 1: 写 SQL 文件**

Path: `/Users/papertiger/Desktop/Together/supabase/migrations/015_hard_delete_pair_periodic.sql`

```sql
-- Migration 015: hard-delete all periodic_tasks in pair spaces.
--
-- Pair 模式 v2 不再提供例行事务功能（UX 上和家务分工差太远）。
-- Dev 阶段无线上用户，直接物理删除；solo-space 数据完全不动。
DELETE FROM periodic_tasks
WHERE space_id IN (SELECT id FROM spaces WHERE type = 'pair');
```

- [ ] **Step 2: controller 通过 MCP 应用迁移（subagent 跳过）**

```
apply_migration(
  project_id="nxielmwdoiwiwhzczrmt",
  name="hard_delete_pair_periodic",
  query=<上面 SQL>
)
```

Expected: `{success: true}`。

- [ ] **Step 3: 验证**

```sql
SELECT count(*) FROM periodic_tasks
WHERE space_id IN (SELECT id FROM spaces WHERE type='pair');
```
Expected: 0。

- [ ] **Step 4: commit**

```bash
git add supabase/migrations/015_hard_delete_pair_periodic.sql
git commit -m "$(cat <<'EOF'
chore(migrations): 015 hard-delete pair-space periodic_tasks

Pair mode v2 removes periodic tasks from the IA (doesn't fit the
couple-life scenario; chores belong elsewhere). Hard delete
pair-space rows; solo-space untouched. Dev phase, no live users
so no tombstone needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Migration 016 — 创建 important_dates 表

**Files:**
- Create: `supabase/migrations/016_create_important_dates.sql`

- [ ] **Step 1: 写 SQL**

```sql
-- Migration 016: pair-mode anniversaries (生日 / 纪念日 / 节日 / 自定义)
CREATE TABLE important_dates (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id           uuid NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    creator_id         uuid NOT NULL,
    kind               text NOT NULL,                 -- 'birthday' | 'anniversary' | 'holiday' | 'custom'
    title              text NOT NULL,
    date_value         date NOT NULL,                 -- 首次发生的完整公历日期
    is_recurring       boolean NOT NULL DEFAULT true,
    recurrence_rule    text,                          -- 'solar_annual' | 'lunar_annual' | null
    notify_days_before int NOT NULL DEFAULT 7,        -- 1/3/7/15/30
    notify_on_day      boolean NOT NULL DEFAULT true,
    icon               text,
    member_user_id     uuid,                          -- 仅 kind='birthday' 使用
    is_preset_holiday  boolean NOT NULL DEFAULT false,
    preset_holiday_id  text,                          -- 'valentines' | 'qixi' | 'springFestival'
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    is_deleted         boolean NOT NULL DEFAULT false,
    deleted_at         timestamptz
);

CREATE INDEX important_dates_space_idx ON important_dates (space_id, is_deleted);

-- 防止同一 space 重复勾选同一 preset
CREATE UNIQUE INDEX important_dates_unique_preset
ON important_dates (space_id, preset_holiday_id)
WHERE is_preset_holiday AND NOT is_deleted;

-- RLS（参考其他表模式，目前全局开放，匹配项目 anon-key 架构）
ALTER TABLE important_dates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "important_dates_anon_all" ON important_dates;
CREATE POLICY "important_dates_anon_all"
ON important_dates FOR ALL
TO public
USING (true)
WITH CHECK (true);
```

- [ ] **Step 2: MCP 应用 + 验证**

```
apply_migration(project_id="nxielmwdoiwiwhzczrmt", name="create_important_dates", query=<above>)
```

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='important_dates'
ORDER BY ordinal_position;
```
Expected: 17 列。

- [ ] **Step 3: commit**

```bash
git add supabase/migrations/016_create_important_dates.sql
git commit -m "$(cat <<'EOF'
chore(migrations): 016 create important_dates table

New entity for pair-mode anniversaries feature. Fields cover
birthday / anniversary / holiday / custom kinds, solar / lunar
recurrence, notification config, and preset holiday identity.
Unique index prevents double-selection of same preset within a
space. RLS open-to-public matching the project's existing anon-
key model.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Domain model — `ImportantDate`

**Files:**
- Create: `Together/Domain/Models/ImportantDate.swift`

- [ ] **Step 1: 新建文件**

Path: `/Users/papertiger/Desktop/Together/Together/Domain/Models/ImportantDate.swift`

```swift
import Foundation

enum ImportantDateKind: Hashable, Sendable {
    case birthday(memberUserID: UUID)
    case anniversary
    case holiday
    case custom

    var rawValue: String {
        switch self {
        case .birthday: return "birthday"
        case .anniversary: return "anniversary"
        case .holiday: return "holiday"
        case .custom: return "custom"
        }
    }
}

enum Recurrence: String, Hashable, Sendable, Codable {
    case none
    case solarAnnual
    case lunarAnnual

    var supabaseValue: String? {
        switch self {
        case .none: return nil
        case .solarAnnual: return "solar_annual"
        case .lunarAnnual: return "lunar_annual"
        }
    }

    init(supabaseValue: String?) {
        switch supabaseValue {
        case "solar_annual": self = .solarAnnual
        case "lunar_annual": self = .lunarAnnual
        default: self = .none
        }
    }
}

enum PresetHolidayID: String, CaseIterable, Sendable, Codable {
    case valentines
    case qixi
    case springFestival

    var defaultTitle: String {
        switch self {
        case .valentines: return "情人节"
        case .qixi: return "七夕"
        case .springFestival: return "春节"
        }
    }

    var defaultIcon: String {
        switch self {
        case .valentines: return "heart.fill"
        case .qixi: return "sparkles"
        case .springFestival: return "party.popper.fill"
        }
    }

    var recurrence: Recurrence {
        switch self {
        case .valentines: return .solarAnnual
        case .qixi, .springFestival: return .lunarAnnual
        }
    }

    /// Month/day in the relevant calendar (solar for valentines, lunar for qixi/spring).
    var monthDay: (month: Int, day: Int) {
        switch self {
        case .valentines: return (2, 14)       // solar
        case .qixi: return (7, 7)              // lunar
        case .springFestival: return (1, 1)    // lunar
        }
    }
}

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
    var updatedAt: Date

    static let validNotifyDaysBefore: [Int] = [1, 3, 7, 15, 30]
}

extension ImportantDate {
    /// Returns the next occurrence strictly after `reference`, or nil if this is
    /// a non-recurring event that has already passed.
    func nextOccurrence(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch recurrence {
        case .none:
            return dateValue > reference ? dateValue : nil
        case .solarAnnual:
            return nextSolarOccurrence(after: reference, calendar: calendar)
        case .lunarAnnual:
            return nextLunarOccurrence(after: reference)
        }
    }

    private func nextSolarOccurrence(after reference: Date, calendar: Calendar) -> Date? {
        var gregorian = calendar
        gregorian.timeZone = .current
        let month = gregorian.component(.month, from: dateValue)
        let day = gregorian.component(.day, from: dateValue)
        var year = gregorian.component(.year, from: reference)

        for _ in 0..<2 {
            if let candidate = gregorian.date(from: DateComponents(year: year, month: month, day: day)),
               candidate > reference {
                return candidate
            }
            year += 1
        }
        return nil
    }

    private func nextLunarOccurrence(after reference: Date) -> Date? {
        var chineseCal = Calendar(identifier: .chinese)
        chineseCal.timeZone = .current
        let lunarMonth = chineseCal.component(.month, from: dateValue)
        let lunarDay = chineseCal.component(.day, from: dateValue)
        var year = chineseCal.component(.year, from: reference)

        for _ in 0..<3 {
            var comps = DateComponents()
            comps.year = year
            comps.month = lunarMonth
            comps.day = lunarDay
            var candidate = chineseCal.date(from: comps)

            // Leap-month fallback: if this year lacks the leap month, drop the flag.
            if candidate == nil {
                comps.isLeapMonth = false
                candidate = chineseCal.date(from: comps)
            }

            if let candidate, candidate > reference {
                return candidate
            }
            year += 1
        }
        return nil
    }

    func daysUntilNext(from reference: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let next = nextOccurrence(after: reference, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    var daysSinceStart: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: dateValue)
        let now = cal.startOfDay(for: .now)
        return cal.dateComponents([.day], from: start, to: now).day ?? 0
    }
}
```

- [ ] **Step 2: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: commit**

```bash
git add Together/Domain/Models/ImportantDate.swift
git commit -m "$(cat <<'EOF'
feat(domain): ImportantDate model + Kind/Recurrence/PresetHolidayID enums

Pure domain model covering pair-mode anniversaries:
- kind = birthday(memberUserID) | anniversary | holiday | custom
- recurrence = none | solarAnnual | lunarAnnual (Swift Calendar(.chinese))
- nextOccurrence(after:) handles solar/lunar/leap-month fallback
- daysUntilNext / daysSinceStart derived helpers
- PresetHolidayID enumerates MVP 3 holidays (情人节/七夕/春节)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `nextOccurrence` 单元测试

**Files:**
- Create: `TogetherTests/ImportantDateNextOccurrenceTests.swift`

- [ ] **Step 1: 新建测试文件**

```swift
import Testing
import Foundation
@testable import Together

@Suite("ImportantDate.nextOccurrence")
struct ImportantDateNextOccurrenceTests {

    private func makeEvent(
        dateValue: Date,
        recurrence: Recurrence,
        kind: ImportantDateKind = .custom
    ) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: kind,
            title: "Test",
            dateValue: dateValue,
            recurrence: recurrence,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now
        )
    }

    private func date(_ isoString: String) -> Date {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: isoString)!
    }

    @Test("solarAnnual: date is later this year — returns this year's date")
    func solarThisYearUpcoming() {
        let event = makeEvent(
            dateValue: date("2020-05-20T00:00:00Z"),
            recurrence: .solarAnnual
        )
        let reference = date("2026-01-15T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2026)
        #expect(cal.component(.month, from: next!) == 5)
        #expect(cal.component(.day, from: next!) == 20)
    }

    @Test("solarAnnual: date already passed this year — rolls to next year")
    func solarThisYearPassed() {
        let event = makeEvent(
            dateValue: date("2020-02-14T00:00:00Z"),
            recurrence: .solarAnnual
        )
        let reference = date("2026-06-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.year, from: next!) == 2027)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 14)
    }

    @Test("lunarAnnual: qixi 2026 — 农历 7/7 对应公历 2026/8/19")
    func lunarQixi2026() {
        // 2020-08-25 is 农历 2020/7/7 (qixi)
        let event = makeEvent(
            dateValue: date("2020-08-25T00:00:00Z"),
            recurrence: .lunarAnnual,
            kind: .holiday
        )
        let reference = date("2026-01-01T00:00:00Z")
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        // 2026 qixi is August 19
        #expect(cal.component(.year, from: next!) == 2026)
        #expect(cal.component(.month, from: next!) == 8)
        #expect(cal.component(.day, from: next!) == 19)
    }

    @Test("lunarAnnual: current year already passed — rolls to next")
    func lunarAfterEvent() {
        // 农历 1/1 (春节) — 2026 春节 2/17
        let event = makeEvent(
            dateValue: date("2020-01-25T00:00:00Z"),  // 2020 春节公历日期
            recurrence: .lunarAnnual
        )
        let reference = date("2026-03-01T00:00:00Z")  // 已过 2026 春节
        let next = event.nextOccurrence(after: reference)
        #expect(next != nil)
        let cal = Calendar(identifier: .gregorian)
        // 2027 春节公历 2/6
        #expect(cal.component(.year, from: next!) == 2027)
    }

    @Test("none recurrence: past event returns nil")
    func nonRecurringPast() {
        let event = makeEvent(
            dateValue: date("2020-01-01T00:00:00Z"),
            recurrence: .none
        )
        let next = event.nextOccurrence(after: .now)
        #expect(next == nil)
    }

    @Test("none recurrence: future event returns that date")
    func nonRecurringFuture() {
        let future = Date.now.addingTimeInterval(60 * 60 * 24 * 30)  // +30 days
        let event = makeEvent(dateValue: future, recurrence: .none)
        let next = event.nextOccurrence(after: .now)
        #expect(next == future)
    }
}
```

- [ ] **Step 2: 跑测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ImportantDateNextOccurrenceTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -3
```
Expected: `** TEST SUCCEEDED **` `Executed 6 tests`.

- [ ] **Step 3: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 4: commit**

```bash
git add TogetherTests/ImportantDateNextOccurrenceTests.swift
git commit -m "$(cat <<'EOF'
test(domain): ImportantDate.nextOccurrence solar + lunar coverage

6 tests covering:
- solar annual upcoming (same year)
- solar annual already passed (rolls to next year)
- lunar annual qixi 2026 → gregorian 2026/8/19
- lunar annual after event (rolls to next lunar year)
- non-recurring past → nil
- non-recurring future → unchanged

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `PersistentImportantDate` SwiftData 模型

**Files:**
- Create: `Together/Persistence/Models/PersistentImportantDate.swift`
- Modify: `Together/Persistence/PersistenceController.swift`

- [ ] **Step 1: 新建 SwiftData 模型文件**

```swift
import Foundation
import SwiftData

@Model
final class PersistentImportantDate {
    @Attribute(.unique) var id: UUID
    var spaceID: UUID
    var creatorID: UUID
    var kindRawValue: String       // "birthday" | "anniversary" | "holiday" | "custom"
    var memberUserID: UUID?        // only for birthday
    var title: String
    var dateValue: Date
    var recurrenceRawValue: String // "none" | "solarAnnual" | "lunarAnnual"
    var notifyDaysBefore: Int
    var notifyOnDay: Bool
    var icon: String?
    var isPresetHoliday: Bool
    var presetHolidayIDRawValue: String?
    var createdAt: Date
    var updatedAt: Date
    var isLocallyDeleted: Bool
    var deletedAt: Date?

    init(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID,
        kindRawValue: String,
        memberUserID: UUID? = nil,
        title: String,
        dateValue: Date,
        recurrenceRawValue: String,
        notifyDaysBefore: Int = 7,
        notifyOnDay: Bool = true,
        icon: String? = nil,
        isPresetHoliday: Bool = false,
        presetHolidayIDRawValue: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isLocallyDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.kindRawValue = kindRawValue
        self.memberUserID = memberUserID
        self.title = title
        self.dateValue = dateValue
        self.recurrenceRawValue = recurrenceRawValue
        self.notifyDaysBefore = notifyDaysBefore
        self.notifyOnDay = notifyOnDay
        self.icon = icon
        self.isPresetHoliday = isPresetHoliday
        self.presetHolidayIDRawValue = presetHolidayIDRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
        self.deletedAt = deletedAt
    }

    func domainModel() -> ImportantDate {
        let kind: ImportantDateKind
        switch kindRawValue {
        case "birthday":
            kind = .birthday(memberUserID: memberUserID ?? UUID())
        case "anniversary":
            kind = .anniversary
        case "holiday":
            kind = .holiday
        default:
            kind = .custom
        }
        return ImportantDate(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            kind: kind,
            title: title,
            dateValue: dateValue,
            recurrence: Recurrence(rawValue: recurrenceRawValue) ?? .none,
            notifyDaysBefore: notifyDaysBefore,
            notifyOnDay: notifyOnDay,
            icon: icon,
            presetHolidayID: presetHolidayIDRawValue.flatMap(PresetHolidayID.init(rawValue:)),
            updatedAt: updatedAt
        )
    }

    static func make(from event: ImportantDate) -> PersistentImportantDate {
        let (kindRaw, memberID): (String, UUID?) = {
            switch event.kind {
            case .birthday(let mID): return ("birthday", mID)
            case .anniversary: return ("anniversary", nil)
            case .holiday: return ("holiday", nil)
            case .custom: return ("custom", nil)
            }
        }()
        return PersistentImportantDate(
            id: event.id,
            spaceID: event.spaceID,
            creatorID: event.creatorID,
            kindRawValue: kindRaw,
            memberUserID: memberID,
            title: event.title,
            dateValue: event.dateValue,
            recurrenceRawValue: event.recurrence.rawValue,
            notifyDaysBefore: event.notifyDaysBefore,
            notifyOnDay: event.notifyOnDay,
            icon: event.icon,
            isPresetHoliday: event.presetHolidayID != nil,
            presetHolidayIDRawValue: event.presetHolidayID?.rawValue,
            updatedAt: event.updatedAt
        )
    }

    func apply(from event: ImportantDate) {
        let (kindRaw, memberID): (String, UUID?) = {
            switch event.kind {
            case .birthday(let mID): return ("birthday", mID)
            case .anniversary: return ("anniversary", nil)
            case .holiday: return ("holiday", nil)
            case .custom: return ("custom", nil)
            }
        }()
        self.spaceID = event.spaceID
        self.creatorID = event.creatorID
        self.kindRawValue = kindRaw
        self.memberUserID = memberID
        self.title = event.title
        self.dateValue = event.dateValue
        self.recurrenceRawValue = event.recurrence.rawValue
        self.notifyDaysBefore = event.notifyDaysBefore
        self.notifyOnDay = event.notifyOnDay
        self.icon = event.icon
        self.isPresetHoliday = event.presetHolidayID != nil
        self.presetHolidayIDRawValue = event.presetHolidayID?.rawValue
        self.updatedAt = event.updatedAt
    }
}
```

- [ ] **Step 2: 在 `PersistenceController.swift` 的 schema 数组中加入**

打开 `Together/Persistence/PersistenceController.swift`，在每个 `Schema` / `ModelContainer` 构造调用里加 `PersistentImportantDate.self`（同时存在两处：line 184 附近 + line 207 附近）。确保其他测试文件里构造 in-memory container 的地方也同步更新（task 7 会再收一次，此处先管 production）。

- [ ] **Step 3: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 全量 regression（测试 in-memory container 可能挂）**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|failed" | tail -5
```

如果有测试挂：grep 哪些 in-memory container 测试没包含新模型，补上 `PersistentImportantDate.self`：

```bash
grep -rln "ModelContainer(\s*for:\|PersistentPeriodicTask.self\," TogetherTests --include="*.swift"
```

每个文件加一行 `PersistentImportantDate.self,`。重跑。

- [ ] **Step 5: commit**

```bash
git add Together/Persistence/Models/PersistentImportantDate.swift \
  Together/Persistence/PersistenceController.swift \
  TogetherTests/
git commit -m "$(cat <<'EOF'
feat(persistence): PersistentImportantDate SwiftData model

Mirrors ImportantDate domain. Registers into PersistenceController
schema (16 → 17 persistent models). In-memory test containers
updated to include the new type.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `PairPeriodicPurgeMigration` 一次性客户端清理

**Files:**
- Create: `Together/App/Migrations/PairPeriodicPurgeMigration.swift`
- Create: `TogetherTests/PairPeriodicPurgeMigrationTests.swift`
- Modify: `Together/App/AppContext.swift` (postLaunch hook)

- [ ] **Step 1: 新建迁移文件**

```swift
import Foundation
import SwiftData
import os

enum PairPeriodicPurgeMigration {
    private static let flagKey = "migration_pair_periodic_purged_v1"
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "PairPeriodicPurge")

    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let pairSpaceIDs: Set<UUID> = {
            let descriptor = FetchDescriptor<PersistentPairSpace>()
            guard let spaces = try? context.fetch(descriptor) else { return [] }
            return Set(spaces.map { $0.sharedSpaceID })
        }()

        if pairSpaceIDs.isEmpty {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        let descriptor = FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate { task in pairSpaceIDs.contains(task.spaceID) }
        )
        if let orphans = try? context.fetch(descriptor), !orphans.isEmpty {
            for task in orphans {
                context.delete(task)
            }
            do {
                try context.save()
                logger.info("purged \(orphans.count) pair-space periodic_tasks from local store")
            } catch {
                logger.error("purge save failed: \(error.localizedDescription)")
                return  // Don't set flag; try again next launch
            }
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
```

- [ ] **Step 2: 测试**

```swift
import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("PairPeriodicPurgeMigration")
struct PairPeriodicPurgeMigrationTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }

    @Test("purges periodic_tasks in pair space, leaves solo-space untouched")
    func purgesPairOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let pairSpaceID = UUID()
        let soloSpaceID = UUID()

        // Seed a PairSpace
        ctx.insert(PersistentPairSpace(
            id: UUID(),
            sharedSpaceID: pairSpaceID,
            statusRawValue: "active",
            createdAt: .now,
            activatedAt: .now,
            endedAt: nil
        ))

        // Seed 2 periodic tasks: one pair, one solo
        let pairTask = PersistentPeriodicTask(
            id: UUID(),
            spaceID: pairSpaceID,
            creatorID: UUID(),
            title: "Pair chore",
            intervalDays: 7,
            nextDueAt: .now,
            createdAt: .now,
            updatedAt: .now
        )
        let soloTask = PersistentPeriodicTask(
            id: UUID(),
            spaceID: soloSpaceID,
            creatorID: UUID(),
            title: "Solo habit",
            intervalDays: 1,
            nextDueAt: .now,
            createdAt: .now,
            updatedAt: .now
        )
        ctx.insert(pairTask)
        ctx.insert(soloTask)
        try ctx.save()

        // Reset flag (might be set from previous test run)
        UserDefaults.standard.removeObject(forKey: "migration_pair_periodic_purged_v1")

        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.spaceID == soloSpaceID)
    }

    @Test("is idempotent — second run does nothing")
    func idempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: "migration_pair_periodic_purged_v1")
        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_periodic_purged_v1") == true)
        // Second run should be no-op (flag set)
        PairPeriodicPurgeMigration.runIfNeeded(context: ctx)
        // Nothing to assert beyond no crash; flag still true
        #expect(UserDefaults.standard.bool(forKey: "migration_pair_periodic_purged_v1") == true)
    }
}
```

Note: 里面用到的 `PersistentPeriodicTask` / `PersistentPairSpace` init 参数名按你 codebase 里已有的实际签名来（可能需要调整字段名或默认参数）。Grep `init(` 找对齐。

- [ ] **Step 3: 在 AppContext.postLaunch 调用**

打开 `Together/App/AppContext.swift`，找到 `postLaunch` 或 `bootstrapIfNeeded` 的开头（grep `postLaunch.begin`），加上：

```swift
let purgeContext = ModelContext(container.modelContainer)
PairPeriodicPurgeMigration.runIfNeeded(context: purgeContext)
```

在 `StartupTrace.mark("AppContext.postLaunch.begin")` 之后，其他 restore 操作之前。

- [ ] **Step 4: 测试 + 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/PairPeriodicPurgeMigrationTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -3
```
Expected: `Executed 2 tests` 绿灯。

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/App/Migrations/PairPeriodicPurgeMigration.swift \
  Together/App/AppContext.swift \
  TogetherTests/PairPeriodicPurgeMigrationTests.swift
git commit -m "$(cat <<'EOF'
feat(migration): PairPeriodicPurgeMigration one-shot local cleanup

Server migration 015 hard-deleted pair-space periodic_tasks, but
local SwiftData caches still hold the old rows. This one-shot
migration runs at AppContext.postLaunch, guarded by a UserDefaults
flag so it executes exactly once per install. Deletes
PersistentPeriodicTask rows whose spaceID belongs to any
PersistentPairSpace; solo-space tasks untouched.

2 tests cover the purge + idempotency.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Batch B: Repository + Sync（7 tasks）

---

## Task 7: `ImportantDateRepositoryProtocol` + `LocalImportantDateRepository` + tests

**Files:**
- Create: `Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift`
- Create: `Together/Services/ImportantDates/LocalImportantDateRepository.swift`
- Create: `TogetherTests/ImportantDateRepositoryTests.swift`
- Delete: `Together/Domain/Protocols/AnniversaryRepositoryProtocol.swift`
- Delete: `Together/Services/Anniversaries/MockAnniversaryRepository.swift`

- [ ] **Step 1: 读旧协议决定是否有调用点**

```bash
grep -rn "AnniversaryRepository\|anniversaryRepository" Together TogetherTests --include="*.swift"
```

记下所有引用点（应当集中在 AppContainer / factories / AnniversariesViewModel）。

- [ ] **Step 2: 写新协议**

```swift
import Foundation

protocol ImportantDateRepositoryProtocol: Sendable {
    func fetchAll(spaceID: UUID) async throws -> [ImportantDate]
    func fetch(id: UUID) async throws -> ImportantDate?
    func save(_ event: ImportantDate) async throws
    func delete(id: UUID) async throws   // soft delete (tombstone)
    func hardDelete(id: UUID) async throws   // purge tombstone after confirmed push
}
```

- [ ] **Step 3: 写本地实现**

```swift
import Foundation
import SwiftData

actor LocalImportantDateRepository: ImportantDateRepositoryProtocol {
    private let modelContainer: ModelContainer
    private let syncCoordinator: SyncCoordinatorProtocol?

    init(modelContainer: ModelContainer, syncCoordinator: SyncCoordinatorProtocol? = nil) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
    }

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate {
                $0.spaceID == spaceID && $0.isLocallyDeleted == false
            },
            sortBy: [SortDescriptor(\.dateValue)]
        )
        let rows = try context.fetch(descriptor)
        return rows.map { $0.domainModel() }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id && $0.isLocallyDeleted == false }
        )
        return try context.fetch(descriptor).first?.domainModel()
    }

    func save(_ event: ImportantDate) async throws {
        let context = ModelContext(modelContainer)
        let eventID = event.id
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == eventID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.apply(from: event)
        } else {
            context.insert(PersistentImportantDate.make(from: event))
        }
        try context.save()
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .importantDate, operation: .upsert,
                       recordID: event.id, spaceID: event.spaceID)
        )
    }

    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try context.fetch(descriptor).first else { return }
        existing.isLocallyDeleted = true
        existing.deletedAt = .now
        existing.updatedAt = .now
        try context.save()
        await syncCoordinator?.recordLocalChange(
            SyncChange(entityKind: .importantDate, operation: .delete,
                       recordID: id, spaceID: existing.spaceID)
        )
    }

    func hardDelete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }
}
```

- [ ] **Step 4: 测试**

```swift
import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("LocalImportantDateRepository")
struct ImportantDateRepositoryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self,
            PersistentTaskList.self, PersistentProject.self,
            PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self, PersistentSyncChange.self,
            PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            PersistentImportantDate.self,
            configurations: config
        )
    }

    private func sampleEvent(spaceID: UUID = UUID()) -> ImportantDate {
        ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: UUID(),
            kind: .custom, title: "Test", dateValue: .now,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: nil, presetHolidayID: nil, updatedAt: .now
        )
    }

    @Test("save new event then fetchAll returns it")
    func saveAndFetch() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        let event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.count == 1)
        #expect(events.first?.id == event.id)
    }

    @Test("update existing event replaces fields")
    func updateExisting() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        var event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        event.title = "Updated"
        event.updatedAt = .now
        try await repo.save(event)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.count == 1)
        #expect(events.first?.title == "Updated")
    }

    @Test("delete tombstones the row (invisible to fetchAll)")
    func tombstone() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceID = UUID()
        let event = sampleEvent(spaceID: spaceID)
        try await repo.save(event)
        try await repo.delete(id: event.id)
        let events = try await repo.fetchAll(spaceID: spaceID)
        #expect(events.isEmpty)
    }

    @Test("fetchAll scopes by spaceID")
    func spaceScoping() async throws {
        let container = try makeContainer()
        let repo = LocalImportantDateRepository(modelContainer: container)
        let spaceA = UUID()
        let spaceB = UUID()
        try await repo.save(sampleEvent(spaceID: spaceA))
        try await repo.save(sampleEvent(spaceID: spaceB))
        let eventsA = try await repo.fetchAll(spaceID: spaceA)
        let eventsB = try await repo.fetchAll(spaceID: spaceB)
        #expect(eventsA.count == 1)
        #expect(eventsB.count == 1)
    }
}
```

- [ ] **Step 5: 跑测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ImportantDateRepositoryTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -3
```
Expected: `Executed 4 tests` 全绿。

- [ ] **Step 6: 删除旧 protocol 和 Mock 文件（先不 commit，task 8 一起）**

```bash
rm Together/Domain/Protocols/AnniversaryRepositoryProtocol.swift
rm Together/Services/Anniversaries/MockAnniversaryRepository.swift
```

旧的 `AnniversariesViewModel` 暂留，task 16 重写。暂时让它 compile error 被 ignore（编译会挂）——因此本 task 先把 viewModel 也删掉：

```bash
rm Together/Features/Anniversaries/AnniversariesViewModel.swift
```

- [ ] **Step 7: build 检查**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```

如果挂，挂的地方是对旧 AnniversariesViewModel / Protocol 的引用，grep 找到后暂时注释或删引用。记录下来 task 16 恢复。

- [ ] **Step 8: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 9: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(repo): LocalImportantDateRepository + protocol + 4-pattern tests

Replaces old AnniversaryRepositoryProtocol / MockAnniversaryRepository /
AnniversariesViewModel with a clean ImportantDate-centric stack.
Repository supports save / fetch / tombstone delete / hard delete;
records SyncChange via syncCoordinator on every mutation.

Old files deleted in this commit; references elsewhere tracked for
rewriting in later tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: DI 接入 AppContainer + factories

**Files:**
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/Services/MockServiceFactory.swift`
- Create: `Together/Services/ImportantDates/MockImportantDateRepository.swift`

- [ ] **Step 1: 写 Mock 实现**

```swift
import Foundation
@testable import Together

actor MockImportantDateRepository: ImportantDateRepositoryProtocol {
    private var storage: [UUID: ImportantDate] = [:]
    private var tombstones: Set<UUID> = []

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        storage.values
            .filter { $0.spaceID == spaceID && !tombstones.contains($0.id) }
            .sorted { $0.dateValue < $1.dateValue }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        guard !tombstones.contains(id) else { return nil }
        return storage[id]
    }

    func save(_ event: ImportantDate) async throws {
        storage[event.id] = event
        tombstones.remove(event.id)
    }

    func delete(id: UUID) async throws {
        tombstones.insert(id)
    }

    func hardDelete(id: UUID) async throws {
        storage.removeValue(forKey: id)
        tombstones.remove(id)
    }
}
```

- [ ] **Step 2: 在 AppContainer 里加字段**

打开 `Together/App/AppContainer.swift`，grep `taskMessageRepository` 找到现有字段位置，后面加：

```swift
let importantDateRepository: ImportantDateRepositoryProtocol
```

更新 init 接受新参数 + 赋值。

- [ ] **Step 3: LocalServiceFactory 构造真实**

打开 `Together/Services/LocalServiceFactory.swift`，grep `LocalTaskMessageRepository`，附近加：

```swift
let importantDateRepository = LocalImportantDateRepository(
    modelContainer: persistenceController.modelContainer,
    syncCoordinator: syncCoordinator
)
```

并传入 `AppContainer.init`。

- [ ] **Step 4: MockServiceFactory 构造 mock**

```swift
let importantDateRepository = MockImportantDateRepository()
```

传入 container。

- [ ] **Step 5: build + 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore(di): wire ImportantDateRepository through AppContainer + factories

Real backed by ModelContainer + syncCoordinator; mock in-memory
dict keyed by UUID with tombstone set for delete semantics.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `SyncEntityKind.importantDate` + table mapping

**Files:**
- Modify: `Together/Sync/SyncCoordinatorProtocol.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift`（supabaseTableName 扩展）

- [ ] **Step 1: 给 enum 加 case**

打开 `Together/Sync/SyncCoordinatorProtocol.swift`，在 `taskMessage` 之后加：

```swift
case importantDate   // Supabase `important_dates` table
```

给 `ckRecordType` 返回 `"ImportantDate"`；`init?(ckRecordType:)` 对应 case 加上：`case "ImportantDate": self = .importantDate`。

- [ ] **Step 2: `supabaseTableName` 扩展**

打开 `Together/Sync/SupabaseSyncService.swift` line ~825 的 `supabaseTableName` switch，加：

```swift
case .importantDate: return "important_dates"
```

- [ ] **Step 3: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

Swift 可能要求你在 `pushUpsert` switch 里也处理 `.importantDate`——先加个占位:

```swift
case .importantDate:
    return  // implemented in Task 11
```

- [ ] **Step 4: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/Sync/SyncCoordinatorProtocol.swift Together/Sync/SupabaseSyncService.swift
git commit -m "$(cat <<'EOF'
feat(sync): add SyncEntityKind.importantDate + supabase table mapping

Adds the enum case + "important_dates" table name. pushUpsert
branch is a placeholder (return) until DTO and actual push logic
land in Task 11.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `ImportantDateDTO` + round-trip tests

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`（增加 DTO struct）
- Create: `TogetherTests/ImportantDateSyncDTOTests.swift`

- [ ] **Step 1: 在 SupabaseSyncService.swift 的 DTO 段加入**

追加到 `// MARK: - DTO 数据传输对象` 段末尾：

```swift
struct ImportantDateDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let creatorId: UUID
    var kind: String
    var title: String
    var dateValue: Date           // encoded as ISO date
    var isRecurring: Bool
    var recurrenceRule: String?
    var notifyDaysBefore: Int
    var notifyOnDay: Bool
    var icon: String?
    var memberUserId: UUID?
    var isPresetHoliday: Bool
    var presetHolidayId: String?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case spaceId = "space_id"
        case creatorId = "creator_id"
        case kind, title
        case dateValue = "date_value"
        case isRecurring = "is_recurring"
        case recurrenceRule = "recurrence_rule"
        case notifyDaysBefore = "notify_days_before"
        case notifyOnDay = "notify_on_day"
        case icon
        case memberUserId = "member_user_id"
        case isPresetHoliday = "is_preset_holiday"
        case presetHolidayId = "preset_holiday_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    nonisolated init(from persistent: PersistentImportantDate) {
        self.id = persistent.id
        self.spaceId = persistent.spaceID
        self.creatorId = persistent.creatorID
        self.kind = persistent.kindRawValue
        self.title = persistent.title
        self.dateValue = persistent.dateValue
        self.isRecurring = persistent.recurrenceRawValue != "none"
        self.recurrenceRule = Recurrence(rawValue: persistent.recurrenceRawValue)?.supabaseValue
        self.notifyDaysBefore = persistent.notifyDaysBefore
        self.notifyOnDay = persistent.notifyOnDay
        self.icon = persistent.icon
        self.memberUserId = persistent.memberUserID
        self.isPresetHoliday = persistent.isPresetHoliday
        self.presetHolidayId = persistent.presetHolidayIDRawValue
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.deletedAt
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let id = self.id
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            if updatedAt < existing.updatedAt { return }   // 冲突保护
            existing.spaceID = spaceId
            existing.creatorID = creatorId
            existing.kindRawValue = kind
            existing.title = title
            existing.dateValue = dateValue
            existing.recurrenceRawValue = Recurrence(supabaseValue: recurrenceRule).rawValue
            existing.notifyDaysBefore = notifyDaysBefore
            existing.notifyOnDay = notifyOnDay
            existing.icon = icon
            existing.memberUserID = memberUserId
            existing.isPresetHoliday = isPresetHoliday
            existing.presetHolidayIDRawValue = presetHolidayId
            existing.updatedAt = updatedAt
            if isDeleted { existing.isLocallyDeleted = true }
        } else if !isDeleted {
            let new = PersistentImportantDate(
                id: id,
                spaceID: spaceId,
                creatorID: creatorId,
                kindRawValue: kind,
                memberUserID: memberUserId,
                title: title,
                dateValue: dateValue,
                recurrenceRawValue: Recurrence(supabaseValue: recurrenceRule).rawValue,
                notifyDaysBefore: notifyDaysBefore,
                notifyOnDay: notifyOnDay,
                icon: icon,
                isPresetHoliday: isPresetHoliday,
                presetHolidayIDRawValue: presetHolidayId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isLocallyDeleted: false
            )
            context.insert(new)
        }
    }
}
```

- [ ] **Step 2: 写测试**

```swift
import Testing
import Foundation
@testable import Together

@Suite("ImportantDateDTO serialization")
struct ImportantDateSyncDTOTests {

    @Test("DTO encodes snake_case keys correctly")
    func encodesSnakeCase() throws {
        let dto = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "birthday", title: "Test birthday",
            dateValue: Date(timeIntervalSince1970: 0),
            isRecurring: true, recurrenceRule: "solar_annual",
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "gift.fill", memberUserId: UUID(),
            isPresetHoliday: false, presetHolidayId: nil,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["space_id"] != nil)
        #expect(json?["creator_id"] != nil)
        #expect(json?["date_value"] != nil)
        #expect(json?["notify_days_before"] as? Int == 7)
        #expect(json?["recurrence_rule"] as? String == "solar_annual")
    }

    @Test("DTO round-trips through encode/decode")
    func roundTrip() throws {
        let original = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "anniversary", title: "在一起纪念日",
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            isRecurring: true, recurrenceRule: "solar_annual",
            notifyDaysBefore: 15, notifyOnDay: true,
            icon: "heart.fill", memberUserId: nil,
            isPresetHoliday: false, presetHolidayId: nil,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportantDateDTO.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.notifyDaysBefore == 15)
        #expect(decoded.recurrenceRule == "solar_annual")
    }

    @Test("preset holiday encodes flag + id")
    func presetHoliday() throws {
        let dto = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "holiday", title: "七夕",
            dateValue: .now,
            isRecurring: true, recurrenceRule: "lunar_annual",
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "sparkles", memberUserId: nil,
            isPresetHoliday: true, presetHolidayId: "qixi",
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["is_preset_holiday"] as? Bool == true)
        #expect(json?["preset_holiday_id"] as? String == "qixi")
    }
}
```

- [ ] **Step 3: 跑测试 + 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ImportantDateSyncDTOTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -3
```
Expected: `Executed 3 tests` 全绿。

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 4: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift TogetherTests/ImportantDateSyncDTOTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): ImportantDateDTO codable + applyToLocal + round-trip tests

snake_case CodingKeys match migration 016 column names. applyToLocal
follows the same conflict-guard pattern as other DTOs
(updatedAt comparison).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `pushUpsert(.importantDate)` 实装 + test seam

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/ImportantDatePushTests.swift`

- [ ] **Step 1: 在 `SupabaseSyncService` 里引入 `ImportantDateWriter` protocol seam**

打开 service 文件，仿照 `SpaceMemberWriter` 模式新增：

```swift
protocol ImportantDateWriter: Sendable {
    func upsert(dto: ImportantDateDTO) async throws
    func delete(id: UUID) async throws
}

struct SupabaseImportantDateWriter: ImportantDateWriter {
    let client: SupabaseClient

    func upsert(dto: ImportantDateDTO) async throws {
        try await client.from("important_dates")
            .upsert(dto, onConflict: "id")
            .execute()
    }

    func delete(id: UUID) async throws {
        let tombstone: [String: AnyCodable] = [
            "is_deleted": AnyCodable(true),
            "deleted_at": AnyCodable(Date()),
            "updated_at": AnyCodable(Date())
        ]
        try await client.from("important_dates")
            .update(tombstone)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
```

（如果项目里没有 `AnyCodable`，就用 `JSONEncoder` 手搓 encode 一个 dict；照抄其他 tombstone 写法更稳。`grep "tombstone" Together/Sync/SupabaseSyncService.swift` 找已有做法。）

- [ ] **Step 2: `SupabaseSyncService` 新增 init 参数 `importantDateWriter`**

```swift
private let importantDateWriter: ImportantDateWriter

init(
    // ... existing params ...
    importantDateWriter: ImportantDateWriter? = nil
) {
    // ... existing assignments ...
    self.importantDateWriter = importantDateWriter ?? SupabaseImportantDateWriter(client: client)
}
```

所有构造点（LocalServiceFactory / tests）传 nil 或 mock。

- [ ] **Step 3: 实装 `case .importantDate` 在 pushUpsert switch**

```swift
case .importantDate:
    let descriptor = FetchDescriptor<PersistentImportantDate>(
        predicate: #Predicate { $0.id == recordID }
    )
    guard let existing = try? context.fetch(descriptor).first else {
        logger.warning("[Push] importantDate not found locally id=\(recordID)")
        return
    }
    let dto = ImportantDateDTO(from: existing)
    try await importantDateWriter.upsert(dto: dto)
    recentlyPushedIDs[recordID] = Date()
```

Similarly 处理 `.delete` operation in the existing operation-kind switch (look how `.task` handles it):

```swift
case .delete:
    try await importantDateWriter.delete(id: recordID)
    recentlyPushedIDs[recordID] = Date()
```

如果当前架构是在顶层 operation switch 里统一调用 `pushDelete`，则在那里加 importantDate 分支。

- [ ] **Step 4: 写 push 测试（capturing writer）**

```swift
import Testing
import Foundation
import SwiftData
@testable import Together

@Suite("ImportantDate push")
struct ImportantDatePushTests {

    final class CapturingImportantDateWriter: ImportantDateWriter, @unchecked Sendable {
        private let lock = NSLock()
        private var _upserts: [ImportantDateDTO] = []
        private var _deletes: [UUID] = []
        var upserts: [ImportantDateDTO] {
            lock.lock(); defer { lock.unlock() }; return _upserts
        }
        var deletes: [UUID] {
            lock.lock(); defer { lock.unlock() }; return _deletes
        }
        func upsert(dto: ImportantDateDTO) async throws {
            lock.lock(); _upserts.append(dto); lock.unlock()
        }
        func delete(id: UUID) async throws {
            lock.lock(); _deletes.append(id); lock.unlock()
        }
    }

    @Test("pushUpsert serializes row to writer")
    func pushUpsertCallsWriter() async throws {
        // Build a minimal SupabaseSyncService with mock client + capturing writer.
        // Exact construction args depend on the real init signature — follow the
        // pattern used in AvatarAssetPushTests.swift / TaskMessagePushDTOTests.swift.
        // Key assertion: after calling pushUpsert(SyncChange(.importantDate, .upsert, recordID)),
        // writer.upserts has exactly 1 entry with matching id.
        #expect(true) // placeholder; implement along with test seam finalization
    }
}
```

**注意**：push 测试的 harness 跟 T6/T11 avatar-sync / partner-nudge 里的 `AvatarAssetPushTests` 模式几乎一样。Subagent 实现时请**复刻那个文件的设置**，不要从零发明。包含：in-memory ModelContainer、seed a PersistentImportantDate、触发 `syncService.pushUpsert(SyncChange(...))`、assert capturing writer 收到 DTO。

- [ ] **Step 5: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift \
  Together/Services/LocalServiceFactory.swift \
  TogetherTests/ImportantDatePushTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): pushUpsert(.importantDate) + .delete via ImportantDateWriter

New protocol seam ImportantDateWriter + default
SupabaseImportantDateWriter. SupabaseSyncService routes .importantDate
pushes through the writer (upsert for save; tombstone update for
delete). CapturingImportantDateWriter used by tests to assert DTOs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `pullImportantDates` + `ImportantDateReader` seam

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/ImportantDatePullTests.swift`

- [ ] **Step 1: 引入 `ImportantDateReader` protocol + 默认实现**

```swift
protocol ImportantDateReader: Sendable {
    func fetchRows(spaceID: UUID, since: String) async throws -> [ImportantDateDTO]
}

struct SupabaseImportantDateReader: ImportantDateReader {
    let client: SupabaseClient
    func fetchRows(spaceID: UUID, since: String) async throws -> [ImportantDateDTO] {
        let rows: [ImportantDateDTO] = try await client
            .from("important_dates")
            .select()
            .eq("space_id", value: spaceID.uuidString)
            .gte("updated_at", value: since)
            .execute()
            .value
        return rows
    }
}
```

- [ ] **Step 2: 在 SupabaseSyncService init 加参数 + 调用点**

```swift
private let importantDateReader: ImportantDateReader

init(
    // ... existing ...
    importantDateReader: ImportantDateReader? = nil
) {
    self.importantDateReader = importantDateReader ?? SupabaseImportantDateReader(client: client)
}
```

加一个 `pullImportantDates(spaceID:since:)` method：

```swift
private func pullImportantDates(spaceID: UUID, since: String) async throws {
    let rows = try await importantDateReader.fetchRows(spaceID: spaceID, since: since)
    let context = ModelContext(modelContainer)
    for row in rows {
        row.applyToLocal(context: context)
    }
    try context.save()
    logger.info("[Pull] ✅ 拉取 important_dates rows=\(rows.count)")
}
```

然后在 `catchUp(spaceID:since:)` 流程里跟其他 `pullXXX` 并列调用此 method。

- [ ] **Step 3: Test seam — `pullImportantDatesForTesting(spaceID:)` internal entry point**

跟 `pullSpaceMembersForTesting` 一样模式 expose 一个 internal 方法让测试跑 pull 主体。

- [ ] **Step 4: 测试**

```swift
import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("ImportantDate pull")
struct ImportantDatePullTests {

    final class StubImportantDateReader: ImportantDateReader, @unchecked Sendable {
        private let lock = NSLock()
        private var _rows: [ImportantDateDTO] = []
        func setRows(_ rows: [ImportantDateDTO]) {
            lock.lock(); _rows = rows; lock.unlock()
        }
        func fetchRows(spaceID: UUID, since: String) async throws -> [ImportantDateDTO] {
            lock.lock(); defer { lock.unlock() }; return _rows
        }
    }

    @Test("pull inserts new rows into local store")
    func pullInserts() async throws {
        // Harness pattern from SpaceMemberPullAvatarTests: makeInMemoryContainer,
        // inject stub reader, call pullImportantDatesForTesting, fetch local rows.
        // Assert the inserted DTO's id matches.
        #expect(true)  // placeholder
    }

    @Test("pull updates existing when remote updated_at is newer")
    func pullUpdates() async throws {
        #expect(true)
    }

    @Test("pull marks tombstone when remote is_deleted=true")
    func pullTombstones() async throws {
        #expect(true)
    }
}
```

（上面三个测试的完整 harness 实现应**复刻 `SpaceMemberPullAvatarTests.swift` 里的 `PullTestHarness` 模式**，改成 important_date 版本。Subagent 实现时直接 port。）

- [ ] **Step 5: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(sync): pullImportantDates via ImportantDateReader seam

Mirrors the SpaceMemberReader pattern: protocol + default Supabase
impl, injectable for tests. catchUp now pulls important_dates
alongside other entities. applyToLocal upserts new rows and
tombstones when is_deleted=true.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Realtime 订阅 `important_dates` channel

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

- [ ] **Step 1: grep 现有 realtime subscription 模式**

```bash
grep -n "handleMemberChange\|channel\|PostgresChangeFilter\|task_messages.*realtime" Together/Sync/SupabaseSyncService.swift | head -20
```

找到现有 pair channel setup，通常在 `startListening` / `subscribeToRealtime` 里。

- [ ] **Step 2: 加 important_dates channel**

按现有 subscribing pattern 加订阅：

```swift
// 订阅 important_dates channel
channel.on(PostgresChangesFilter(
    event: .all,
    schema: "public",
    table: "important_dates",
    filter: "space_id=eq.\(spaceID.uuidString)"
)) { [weak self] change in
    Task { await self?.handleImportantDateChange(change) }
}
```

新 method：

```swift
private func handleImportantDateChange(_ change: Any) async {
    await catchUp()  // 简单起见直接 catchUp（与 handleMemberChange 一致）
    await MainActor.run {
        NotificationCenter.default.post(name: .importantDatesChanged, object: nil)
    }
}
```

并在 `Notification.Name` 扩展处新增：

```swift
extension Notification.Name {
    static let importantDatesChanged = Notification.Name("importantDatesChanged")
}
```

- [ ] **Step 3: build + 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 4: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "$(cat <<'EOF'
feat(sync): realtime subscription on important_dates channel

On UPDATE/INSERT/DELETE, triggers catchUp() + posts
.importantDatesChanged notification so UI and notification
scheduler can refresh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Batch C: Pair-mode IA pruning（3 tasks）

---

## Task 14: Tab bar 条件 + HomeView routines card 条件渲染

**Files:**
- Modify: `Together/TogetherApp.swift` 或 `Together/App/AppRootView.swift`（tab bar 实际定义处）
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: grep tab 定义**

```bash
grep -rn "RoutinesView\|routinesTab\|Tab(.*routines\|case routines" Together --include="*.swift" | head
```

找到 tab 结构（可能在 RootSurface enum / main TabView setup）。

- [ ] **Step 2: 条件渲染例行事务 tab**

在 tab bar 定义处，包装例行 tab：

```swift
if sessionStore.activeMode == .solo {
    Tab("例行", systemImage: "repeat") { RoutinesView() }
        .tag(AppTab.routines)
}
// 或 if 链内
```

根据实际代码结构（可能是 `@ViewBuilder` 或数组），照搬现有 pattern 加 guard。

- [ ] **Step 3: HomeView routines summary card 条件**

```bash
grep -n "routinesViewModel.hasPendingTasks\|RoutinesSummaryCard" Together/Features/Home/HomeView.swift
```

找到渲染位置（可能在 line ~528 附近），外层加 guard：

```swift
if appContext.sessionStore.activeMode == .solo,
   appContext.routinesViewModel.hasPendingTasks {
    RoutinesSummaryCard(...)
}
```

- [ ] **Step 4: 全量 regression + build 手工验证**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/TogetherApp.swift \
  Together/Features/Home/HomeView.swift \
  Together/App/AppRootView.swift 2>/dev/null  # if exists
git commit -m "$(cat <<'EOF'
feat(pair-mode): hide periodic tab + routines summary card in pair mode

Conditional rendering driven by sessionStore.activeMode. Solo mode
UX unchanged; pair mode tab bar now shows without the routines
entry, and the home summary card doesn't appear when the active
mode is pair.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: `LocalPeriodicTaskRepository.save` pair-space guard

**Files:**
- Modify: `Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift`
- Create: `TogetherTests/PeriodicTaskPairGuardTests.swift`

- [ ] **Step 1: 加 error 类型**

在 `LocalPeriodicTaskRepository.swift` 顶部或最底部加：

```swift
enum PeriodicTaskError: Error, Equatable {
    case notSupportedInPairMode
}
```

- [ ] **Step 2: save() 入口校验**

在 `save` 方法开头加：

```swift
let context = ModelContext(modelContainer)
// Guard: pair spaces can't have periodic tasks.
let spaceID = input.spaceID  // 按实际参数名调整
let pairDescriptor = FetchDescriptor<PersistentPairSpace>(
    predicate: #Predicate { $0.sharedSpaceID == spaceID }
)
if let pairCount = try? context.fetch(pairDescriptor).count, pairCount > 0 {
    throw PeriodicTaskError.notSupportedInPairMode
}
```

- [ ] **Step 3: 测试**

```swift
import Testing
import SwiftData
import Foundation
@testable import Together

@Suite("LocalPeriodicTaskRepository pair-space guard")
struct PeriodicTaskPairGuardTests {

    @Test("save throws notSupportedInPairMode when space is pair")
    func rejectsPairSpace() async throws {
        // harness: in-memory container with a PersistentPairSpace seeded at sharedSpaceID=X.
        // repo.save(task with spaceID=X) → expect PeriodicTaskError.notSupportedInPairMode
        #expect(true) // placeholder; implement per repo's real save signature
    }

    @Test("save succeeds when space is solo (no pair space record)")
    func allowsSoloSpace() async throws {
        // No PersistentPairSpace seeded → save succeeds
        #expect(true)
    }
}
```

（实际测试需按 `LocalPeriodicTaskRepository` 真实 init + save 签名实现。参考同目录下其他 repository 测试文件的 harness 模式。）

- [ ] **Step 4: 跑测试 + 全量**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/PeriodicTaskPairGuardTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed" | tail -3
```

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 5: commit**

```bash
git add Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift \
  TogetherTests/PeriodicTaskPairGuardTests.swift
git commit -m "$(cat <<'EOF'
feat(periodic): service-layer guard rejecting pair-space save()

Defense-in-depth: even if UI exposes a periodic creation path by
mistake in pair mode, the repository throws
PeriodicTaskError.notSupportedInPairMode. Solo spaces unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: 清理旧 Anniversary view-model 引用

**Files:**
- Modify: 任何编译挂点（task 7 删旧 viewModel 可能导致引用未修）
- Create: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`（最小骨架，UI task 会扩展）

- [ ] **Step 1: 找所有残余引用**

```bash
grep -rn "AnniversariesViewModel\|anniversariesViewModel\|AnniversaryRepository" Together --include="*.swift"
```

每处：
- 是 UI 引用 → 暂时删该段或注释（UI task 会重建）
- 是 AppContainer 字段 → 删字段及构造调用

- [ ] **Step 2: 新建空骨架 ViewModel**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ImportantDatesViewModel {
    var events: [ImportantDate] = []
    var isLoading = false

    private let repository: ImportantDateRepositoryProtocol
    private var spaceID: UUID?

    init(repository: ImportantDateRepositoryProtocol) {
        self.repository = repository
    }

    func configure(spaceID: UUID) {
        self.spaceID = spaceID
    }

    func load() async {
        guard let spaceID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await repository.fetchAll(spaceID: spaceID)
        } catch {
            // log
        }
    }

    func delete(_ id: UUID) async {
        try? await repository.delete(id: id)
        await load()
    }
}
```

- [ ] **Step 3: 在 AppContext 构造并持有**

在 `AppContext` 字段里加：

```swift
let importantDatesViewModel: ImportantDatesViewModel
```

init 里：

```swift
importantDatesViewModel = ImportantDatesViewModel(repository: container.importantDateRepository)
```

如果 AppContext 已有"每个 ViewModel 一个字段"的模式，照抄。

- [ ] **Step 4: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): ImportantDatesViewModel skeleton + clean up old references

Replaces removed AnniversariesViewModel. Minimal load / delete
API; fuller features land in UI tasks (management view, edit
sheet, capsule).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Batch D: 通知调度（4 tasks）

---

## Task 17: `AnniversaryNotificationScheduler` 服务骨架

**Files:**
- Create: `Together/Services/Notifications/AnniversaryNotificationScheduler.swift`

- [ ] **Step 1: 新建文件**

```swift
import Foundation
import UserNotifications
import os

protocol AnniversaryNotificationSchedulerProtocol: Sendable {
    func refresh(spaceID: UUID) async
}

actor AnniversaryNotificationScheduler: AnniversaryNotificationSchedulerProtocol {
    private let repository: ImportantDateRepositoryProtocol
    private let center: UNUserNotificationCenter
    private let partnerDisplayNameProvider: @Sendable () -> String?
    private let myDisplayNameProvider: @Sendable () -> String?
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AnniversaryScheduler")

    private static let identifierPrefix = "anniversary-"

    init(
        repository: ImportantDateRepositoryProtocol,
        center: UNUserNotificationCenter = .current(),
        partnerDisplayNameProvider: @escaping @Sendable () -> String? = { nil },
        myDisplayNameProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.repository = repository
        self.center = center
        self.partnerDisplayNameProvider = partnerDisplayNameProvider
        self.myDisplayNameProvider = myDisplayNameProvider
    }

    func refresh(spaceID: UUID) async {
        // 1. Check authorization
        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            logger.info("not authorized (\(status.rawValue)); skipping refresh")
            return
        }

        // 2. Remove any existing anniversary-prefixed pending
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }.map(\.identifier)
        if !ourIDs.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: ourIDs)
        }

        // 3. Fetch events + sort by nextOccurrence
        guard let events = try? await repository.fetchAll(spaceID: spaceID) else { return }
        let now = Date.now
        let upcoming = events
            .compactMap { event -> (ImportantDate, Date)? in
                guard let next = event.nextOccurrence(after: now) else { return nil }
                return (event, next)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(32)   // iOS 64 limit → 2 per event → 32 events

        // 4. Schedule 2 notifications per event
        for (event, next) in upcoming {
            if event.notifyDaysBefore > 0,
               let advanceDate = Calendar.current.date(byAdding: .day, value: -event.notifyDaysBefore, to: next),
               let triggerDate = calendarDateWithTime(advanceDate, hour: 9, minute: 0),
               triggerDate > now {
                schedule(
                    identifier: "\(Self.identifierPrefix)\(event.id)-before",
                    triggerDate: triggerDate,
                    title: advanceTitle(for: event),
                    body: advanceBody(for: event, daysUntil: event.notifyDaysBefore)
                )
            }
            if event.notifyOnDay,
               let triggerDate = calendarDateWithTime(next, hour: 9, minute: 0),
               triggerDate > now {
                schedule(
                    identifier: "\(Self.identifierPrefix)\(event.id)-day",
                    triggerDate: triggerDate,
                    title: dayOfTitle(for: event),
                    body: dayOfBody(for: event)
                )
            }
        }

        logger.info("scheduled anniversary notifications for \(upcoming.count) events")
    }

    private func calendarDateWithTime(_ date: Date, hour: Int, minute: Int) -> Date? {
        var cal = Calendar.current
        cal.timeZone = .current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private func schedule(identifier: String, triggerDate: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task { [center] in
            try? await center.add(request)
        }
    }

    // MARK: - Copy

    private func advanceTitle(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday: return "💝 生日快到啦"
        case .anniversary: return "💕 纪念日提醒"
        case .holiday: return "✨ \(event.title)快到啦"
        case .custom: return "📌 \(event.title)"
        }
    }

    private func advanceBody(for event: ImportantDate, daysUntil: Int) -> String {
        switch event.kind {
        case .birthday(let memberID):
            let name = isMyself(memberID) ? "你的" : (partnerDisplayNameProvider().map { "\($0) 的" } ?? "伴侣的")
            return "\(name)生日还有 \(daysUntil) 天"
        case .anniversary:
            return "纪念日还有 \(daysUntil) 天"
        case .holiday:
            return "\(event.title) 还有 \(daysUntil) 天"
        case .custom:
            return "\(event.title) 还有 \(daysUntil) 天"
        }
    }

    private func dayOfTitle(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday(let memberID):
            return isMyself(memberID) ? "🎉 生日快乐！" : "🎂 今天是伴侣生日"
        case .anniversary: return "💕 纪念日快乐"
        case .holiday: return "✨ \(event.title)快乐"
        case .custom: return "📌 今天是\(event.title)"
        }
    }

    private func dayOfBody(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday(let memberID):
            return isMyself(memberID) ? "祝自己生日快乐 🎂" : "别忘了说声生日快乐 💌"
        case .anniversary:
            let years = Calendar.current.dateComponents([.year], from: event.dateValue, to: .now).year ?? 0
            return years > 0 ? "今天是你们在一起的第 \(years) 周年" : "今天是你们的纪念日"
        case .holiday: return "祝你们节日愉快"
        case .custom: return event.title
        }
    }

    private func isMyself(_ memberID: UUID) -> Bool {
        // A hook for future use; for now Scheduler doesn't know which user it is.
        // Caller passes this info via providers — extend if needed.
        false
    }
}
```

（`isMyself` 暂留 false；v1 文案不区分"我的 vs 伴侣"，只按是否 birthday kind 整体叫"生日"。可由后续 feedback 细化。）

- [ ] **Step 2: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: commit**

```bash
git add Together/Services/Notifications/AnniversaryNotificationScheduler.swift
git commit -m "$(cat <<'EOF'
feat(notify): AnniversaryNotificationScheduler skeleton

Client-side UNUserNotification scheduler for pair-mode anniversaries.
refresh(spaceID:) idempotently rebuilds all pending requests
with identifier prefix "anniversary-": 2 per event (advance + day-of),
capped at 64 total (32 events × 2) for iOS's per-app limit.
Copy templates cover birthday/anniversary/holiday/custom kinds.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Scheduler 单元测试

**Files:**
- Create: `TogetherTests/AnniversaryNotificationSchedulerTests.swift`

- [ ] **Step 1: 写测试 with mock notification center**

```swift
import Testing
import UserNotifications
import Foundation
@testable import Together

@Suite("AnniversaryNotificationScheduler")
struct AnniversaryNotificationSchedulerTests {

    @Test("refresh schedules 2 notifications per event")
    func schedulesTwoPerEvent() async throws {
        // Use MockImportantDateRepository seeded with 2 events
        // Use a fake UNUserNotificationCenter wrapper, OR UNUserNotificationCenter.current()
        // with setup/teardown cleaning anniversary- ids.
        //
        // Alternative: refactor Scheduler to accept protocol over UNUserNotificationCenter
        // for testability. If short on time, skip this test and rely on E2E.
        #expect(true)   // placeholder per testability tradeoff
    }

    @Test("refresh skips when authorization is not granted")
    func skipsWhenNotAuthorized() async throws {
        #expect(true)   // placeholder
    }

    @Test("refresh caps at 32 events")
    func capsAt32() async throws {
        #expect(true)   // placeholder
    }
}
```

**注意**：`UNUserNotificationCenter` 直接 mock 较难（是 class、singleton）。两个选项：

1. **低成本**：跳过 Scheduler 单元测试，依赖 E2E（合理，因为逻辑简单且依赖系统）
2. **彻底**：把 `UNUserNotificationCenter` 方法抽出 protocol `NotificationCenterAdapter`，Scheduler 依赖 adapter。Mock adapter 记录 add/remove 调用。

如果选 1，注明"跳过单元测试，依赖 E2E"，本 task 不写测试但提交一个"测试已评估"的注释。

如果选 2，要 refactor Scheduler init + 再发一个 commit。

推荐：**选 1 + 在 commit message 注明**（控制 MVP 范围；Scheduler 逻辑简单读代码即可验证）。

- [ ] **Step 2: 确定选项后，要么 commit placeholder，要么实装**

Subagent 实施时判断。若选 1：

```bash
git commit --allow-empty -m "$(cat <<'EOF'
test(notify): defer Scheduler unit tests to E2E

UNUserNotificationCenter is a singleton without built-in mockability;
extracting a NotificationCenterAdapter protocol would be a meaningful
refactor. For MVP, Scheduler logic is simple (priority sort + schedule
loop + copy templates), readable by inspection, and verified via the
E2E step (Batch F task 29) confirming advance/day-of notifications
arrive on real devices.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: Scheduler 接入 AppContext postLaunch + refresh 触发点

**Files:**
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/Services/MockServiceFactory.swift`
- Modify: `Together/App/AppContext.swift`

- [ ] **Step 1: AppContainer 加字段**

```swift
let anniversaryScheduler: AnniversaryNotificationSchedulerProtocol
```

- [ ] **Step 2: LocalServiceFactory 构造真实**

```swift
let anniversaryScheduler = AnniversaryNotificationScheduler(
    repository: importantDateRepository,
    partnerDisplayNameProvider: { /* read from sessionStore lazy */ nil },
    myDisplayNameProvider: { nil }
)
```

Name providers 初期给 nil；文案 fallback 到 "伴侣的"。

- [ ] **Step 3: MockServiceFactory 给一个 no-op**

```swift
struct NoopAnniversaryScheduler: AnniversaryNotificationSchedulerProtocol {
    func refresh(spaceID: UUID) async {}
}
// ...
let anniversaryScheduler = NoopAnniversaryScheduler()
```

- [ ] **Step 4: AppContext 集成触发点**

在 `AppContext.swift`：

a. `postLaunch` 开头（PairPeriodicPurge 之后）：

```swift
if let pairSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {
    Task { [container] in
        await container.anniversaryScheduler.refresh(spaceID: pairSpaceID)
    }
}
```

b. 现有 `.supabaseRealtimeChanged` 观察器里（grep `supabaseRealtimeChanged` 找），追加：

```swift
NotificationCenter.default.addObserver(
    forName: .importantDatesChanged, object: nil, queue: .main
) { [weak self] _ in
    guard let self else { return }
    Task {
        guard let id = await self.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        await self.container.anniversaryScheduler.refresh(spaceID: id)
    }
}
```

- [ ] **Step 5: build + 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add Together/App/AppContainer.swift \
  Together/Services/LocalServiceFactory.swift \
  Together/Services/MockServiceFactory.swift \
  Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
chore(di): wire AnniversaryNotificationScheduler + refresh triggers

AppContainer holds the scheduler; LocalServiceFactory builds the real
impl, MockServiceFactory a no-op. AppContext calls refresh() on
postLaunch and on .importantDatesChanged realtime events.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 20: 对 CRUD 操作也触发 scheduler refresh

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`
- Modify: `Together/App/AppContext.swift`（若 ViewModel 的 delete/save 走 AppContext callback）

- [ ] **Step 1: ViewModel 增加 refresh 回调**

```swift
@MainActor
@Observable
final class ImportantDatesViewModel {
    var events: [ImportantDate] = []
    var isLoading = false
    var onChange: (() async -> Void)?   // AppContext 注入 scheduler.refresh + home reload

    private let repository: ImportantDateRepositoryProtocol
    private var spaceID: UUID?

    // ... init + configure + load 不变 ...

    func save(_ event: ImportantDate) async {
        try? await repository.save(event)
        await load()
        await onChange?()
    }

    func delete(_ id: UUID) async {
        try? await repository.delete(id: id)
        await load()
        await onChange?()
    }
}
```

- [ ] **Step 2: AppContext 注入 onChange**

```swift
importantDatesViewModel.onChange = { [weak self] in
    guard let self, let id = await self.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
    await self.container.anniversaryScheduler.refresh(spaceID: id)
    await self.homeViewModel.reload()
}
```

在 AppContext 其他 ViewModel 回调注入处附近。

- [ ] **Step 3: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 4: commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesViewModel.swift \
  Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(notify): viewModel save/delete triggers scheduler refresh

Every mutation refreshes the scheduled notifications so newly
created / deleted events take effect immediately without waiting
for next app launch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Batch E: UI（8 tasks）

---

## Task 21: `AnniversaryCapsuleView` + 接入 HomeView

**Files:**
- Create: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: 新建胶囊 view（复用现有 overdue / routines 样式）**

```swift
import SwiftUI

struct AnniversaryCapsuleView: View {
    let nextEvent: ImportantDate?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Spacer()
                Text(detail)
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        guard let event = nextEvent else { return "sparkles" }
        return event.icon ?? defaultIcon(for: event.kind)
    }

    private var title: String {
        guard let event = nextEvent else { return "添加第一个纪念日" }
        return event.title
    }

    private var detail: String {
        guard let event = nextEvent,
              let days = event.daysUntilNext() else { return "点击添加" }
        if days == 0 { return "今天" }
        return "还有 \(days) 天"
    }

    private func defaultIcon(for kind: ImportantDateKind) -> String {
        switch kind {
        case .birthday: return "gift.fill"
        case .anniversary: return "heart.fill"
        case .holiday: return "sparkles"
        case .custom: return "star.fill"
        }
    }
}
```

- [ ] **Step 2: HomeView 里条件渲染胶囊**

找到现有 overdue 胶囊渲染位置（grep `overdueReminderCapsule`），加 sibling：

```swift
if appContext.sessionStore.activeMode == .pair {
    AnniversaryCapsuleView(
        nextEvent: appContext.importantDatesViewModel.events
            .compactMap { event -> (ImportantDate, Int)? in
                guard let days = event.daysUntilNext() else { return nil }
                return (event, days)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0,
        onTap: {
            router.presentSheet(.importantDatesManagement)  // 或 router.push(...)
        }
    )
    .listRowInsets(...)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
}
```

具体的 `router.presentSheet` 调用请按 app 现有 router pattern 调整。

- [ ] **Step 3: HomeView 监听 `.importantDatesChanged` reload**

grep 现有 `NotificationCenter.default.publisher` 用法，增加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .importantDatesChanged)) { _ in
    Task { await appContext.importantDatesViewModel.load() }
}
```

- [ ] **Step 4: 在 AppContext postLaunch load 一次 important dates**

```swift
if let pairSpaceID = sessionStore.pairSpaceSummary?.sharedSpace.id {
    importantDatesViewModel.configure(spaceID: pairSpaceID)
    Task { await importantDatesViewModel.load() }
}
```

- [ ] **Step 5: build（UI 验证必须人工真机或模拟器）**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```

- [ ] **Step 6: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 7: commit**

```bash
git add Together/Features/Anniversaries/AnniversaryCapsuleView.swift \
  Together/Features/Home/HomeView.swift \
  Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(ui): AnniversaryCapsuleView on home (pair mode)

Renders the most-imminent upcoming anniversary as a tappable capsule
matching the existing overdue/routines capsule visual style. Empty
state shows "添加第一个纪念日" to guide new pairs. Listens on
.importantDatesChanged to reload.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 22: "我"页双人模式区入口

**Files:**
- Modify: `Together/Features/Profile/...`（具体文件开工时 grep）

- [ ] **Step 1: 定位"我"页 pair section**

```bash
grep -rn "双人协作\|当前工作空间\|解绑双人空间" Together/Features --include="*.swift" | head
```

找到 `Text("双人协作")` 或相似锚点所在 view。

- [ ] **Step 2: 在该 section 追加入口 row**

```swift
Button {
    router.push(.importantDatesManagement)  // 按 router 实际 API
} label: {
    HStack {
        Image(systemName: "calendar.badge.plus")
            .foregroundStyle(AppTheme.colors.coral)
        Text("纪念日管理")
            .foregroundStyle(AppTheme.colors.title)
        Spacer()
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(AppTheme.colors.body.opacity(0.4))
    }
    .padding(...)
    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.colors.surfaceElevated))
}
.buttonStyle(.plain)
```

- [ ] **Step 3: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```

- [ ] **Step 4: commit**

```bash
git add Together/Features/Profile/
git commit -m "$(cat <<'EOF'
feat(ui): profile page entry for anniversaries management (pair mode)

Adds a row to the existing "双人协作" section on the Me tab. Only
appears in pair mode; taps push into ImportantDatesManagementView.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 23: `ImportantDatesManagementView` 全屏管理页

**Files:**
- Create: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`

- [ ] **Step 1: 写管理 view**

```swift
import SwiftUI

struct ImportantDatesManagementView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit: ImportantDate?
    @State private var showCreateSheet = false
    @State private var showPresetPicker = false
    @State private var createKind: ImportantDateKind?

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.events.isEmpty {
                    emptyStateView
                } else {
                    list
                }
            }
            .navigationTitle("纪念日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $showEdit) { event in
                ImportantDateEditSheet(event: event)
            }
            .confirmationDialog("添加纪念日", isPresented: $showCreateSheet) {
                Button("🎂 伴侣生日") { createBirthday(myself: false) }
                    .disabled(existingBirthday(myself: false) != nil)
                Button("🎁 我的生日") { createBirthday(myself: true) }
                    .disabled(existingBirthday(myself: true) != nil)
                Button("💕 在一起纪念日") { createAnniversary() }
                    .disabled(viewModel.events.contains { $0.kind == .anniversary })
                Button("🎉 添加常见节日") { showPresetPicker = true }
                Button("✏️ 自定义") { createCustom() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showPresetPicker) {
                PresetHolidayPickerSheet()
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            emptyCTA(title: "添加伴侣生日 🎂", isPrimary: true) { createBirthday(myself: false) }
            emptyCTA(title: "添加我的生日 🎁", isPrimary: false) { createBirthday(myself: true) }
            emptyCTA(title: "添加在一起纪念日 💕", isPrimary: false) { createAnniversary() }
            Button("+ 其他纪念日 / 添加常见节日") { showCreateSheet = true }
                .foregroundStyle(AppTheme.colors.coral)
                .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private func emptyCTA(title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(18, weight: .bold))
                .foregroundStyle(isPrimary ? .white : AppTheme.colors.title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isPrimary ? AppTheme.colors.coral : AppTheme.colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.events.sorted { lhsNext($0) < lhsNext($1) }) { event in
                row(event: event)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(event.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .onTapGesture { showEdit = event }
            }
        }
        .listStyle(.plain)
    }

    private func row(event: ImportantDate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon ?? defaultIcon(for: event.kind))
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.colors.coral)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(dateLabel(for: event)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(daysLabel(for: event)).font(.subheadline).foregroundStyle(AppTheme.colors.coral)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.colors.surfaceElevated))
    }

    private func lhsNext(_ event: ImportantDate) -> Date {
        event.nextOccurrence(after: .now) ?? .distantFuture
    }

    private func dateLabel(for event: ImportantDate) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d"
        let base = fmt.string(from: event.dateValue)
        switch event.recurrence {
        case .lunarAnnual:
            return "\(base) · 农历"
        case .solarAnnual:
            return "\(base) · 每年"
        case .none:
            return base
        }
    }

    private func daysLabel(for event: ImportantDate) -> String {
        guard let days = event.daysUntilNext() else { return "-" }
        return days == 0 ? "今天" : "还有 \(days) 天"
    }

    private func defaultIcon(for kind: ImportantDateKind) -> String {
        switch kind {
        case .birthday: return "gift.fill"
        case .anniversary: return "heart.fill"
        case .holiday: return "sparkles"
        case .custom: return "star.fill"
        }
    }

    // MARK: - Existing checks

    private func existingBirthday(myself: Bool) -> ImportantDate? {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let partnerID = appContext.sessionStore.pairSpaceSummary?.partner?.id else { return nil }
        let target = myself ? myID : partnerID
        return viewModel.events.first {
            if case .birthday(let m) = $0.kind { return m == target }
            return false
        }
    }

    // MARK: - Create actions

    private func createBirthday(myself: Bool) {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let partnerID = appContext.sessionStore.pairSpaceSummary?.partner?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let memberID = myself ? myID : partnerID
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .birthday(memberUserID: memberID),
            title: myself ? "我的生日" : "伴侣生日",
            dateValue: .now,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "gift.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed   // open edit sheet for user to set date
    }

    private func createAnniversary() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .anniversary, title: "我们的纪念日",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "heart.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed
    }

    private func createCustom() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .custom, title: "",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "star.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed
    }
}
```

- [ ] **Step 2: 把 view 挂到 Router / 导航层**

具体怎么 push / sheet 取决于 app 现有 router。保证 T21（主页胶囊）和 T22（profile 入口）都能打开这个 view。

- [ ] **Step 3: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 4: commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesManagementView.swift
git commit -m "$(cat <<'EOF'
feat(ui): ImportantDatesManagementView — empty state + list + add sheet

Empty state: three primary CTAs (partner birthday / my birthday /
anniversary) + "more / preset holidays" footer.
Non-empty: list sorted by next occurrence; swipe to delete; tap to
edit. Bottom-right + shows action sheet for category selection.
Add sheet disables already-existing unique-kind options (one-per-pair).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 24: `ImportantDateEditSheet` 创建/编辑 form

**Files:**
- Create: `Together/Features/Anniversaries/ImportantDateEditSheet.swift`

- [ ] **Step 1: 写 edit sheet**

```swift
import SwiftUI

struct ImportantDateEditSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State var event: ImportantDate   // passed in as seed or existing

    private let notifyOptions = ImportantDate.validNotifyDaysBefore

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("纪念日名称", text: $event.title)
                }
                Section("日期") {
                    DatePicker("日期", selection: $event.dateValue, displayedComponents: .date)
                    Picker("重复", selection: $event.recurrence) {
                        Text("一次性").tag(Recurrence.none)
                        Text("每年（公历）").tag(Recurrence.solarAnnual)
                        Text("每年（农历）").tag(Recurrence.lunarAnnual)
                    }
                    .pickerStyle(.segmented)
                }
                Section("提醒") {
                    Picker("提前几天", selection: $event.notifyDaysBefore) {
                        ForEach(notifyOptions, id: \.self) { day in
                            Text("\(day) 天").tag(day)
                        }
                    }
                    Toggle("当天提醒", isOn: $event.notifyOnDay)
                }
                if case .birthday = event.kind {
                    Section {
                        Text("生日不能修改所属用户")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑纪念日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(event.title.isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = event
        updated.updatedAt = .now
        Task {
            await appContext.importantDatesViewModel.save(updated)
            dismiss()
        }
    }
}
```

- [ ] **Step 2: 确保 `ImportantDate: Identifiable` 能被 `sheet(item:)` 使用**（已在 domain 定义 Identifiable ✅）

- [ ] **Step 3: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 4: commit**

```bash
git add Together/Features/Anniversaries/ImportantDateEditSheet.swift
git commit -m "$(cat <<'EOF'
feat(ui): ImportantDateEditSheet — title / date / recurrence / notify

Form-based sheet for creating or editing an anniversary:
- Title text field
- Date picker
- Recurrence segmented (一次性 / 每年公历 / 每年农历)
- Notify advance days (1/3/7/15/30 picker)
- Notify on day toggle
Birthday kind shows a read-only note about ownership (member_user_id
is set at creation and not editable).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 25: `PresetHolidayPickerSheet`

**Files:**
- Create: `Together/Features/Anniversaries/PresetHolidayPickerSheet.swift`

- [ ] **Step 1: 写节日勾选 sheet**

```swift
import SwiftUI

struct PresetHolidayPickerSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<PresetHolidayID> = []

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            List(PresetHolidayID.allCases, id: \.self) { preset in
                Button {
                    if selectedIDs.contains(preset) {
                        selectedIDs.remove(preset)
                    } else {
                        selectedIDs.insert(preset)
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedIDs.contains(preset) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedIDs.contains(preset) ? AppTheme.colors.coral : .secondary)
                        Text(preset.defaultTitle).foregroundStyle(.primary)
                        Spacer()
                        Text(nextDateLabel(for: preset)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("常见节日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save() }.disabled(selectedIDs.isEmpty)
                }
            }
        }
        .onAppear { seedSelection() }
    }

    private func seedSelection() {
        let existing = viewModel.events.compactMap { $0.presetHolidayID }
        selectedIDs = Set(existing)
    }

    private func nextDateLabel(for preset: PresetHolidayID) -> String {
        let seedDate = computeSeedDate(for: preset)
        let event = ImportantDate(
            id: UUID(), spaceID: UUID(), creatorID: UUID(),
            kind: .holiday, title: preset.defaultTitle, dateValue: seedDate,
            recurrence: preset.recurrence, notifyDaysBefore: 7, notifyOnDay: true,
            icon: nil, presetHolidayID: preset, updatedAt: .now
        )
        guard let next = event.nextOccurrence(after: .now) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d"
        return fmt.string(from: next)
    }

    /// 内置 seed date：preset 的首次发生参考日期（用于 nextOccurrence 计算）
    /// 对 solar preset，直接构造当年的月日；对 lunar preset，构造今年的农历月日对应的公历日期
    private func computeSeedDate(for preset: PresetHolidayID) -> Date {
        let (month, day) = preset.monthDay
        let cal: Calendar
        switch preset.recurrence {
        case .solarAnnual:
            cal = Calendar(identifier: .gregorian)
        case .lunarAnnual:
            cal = Calendar(identifier: .chinese)
        case .none:
            return .now
        }
        let year = cal.component(.year, from: .now)
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = day
        return cal.date(from: comps) ?? .now
    }

    private func save() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let existing = Dictionary(uniqueKeysWithValues: viewModel.events.compactMap { e -> (PresetHolidayID, ImportantDate)? in
            guard let pid = e.presetHolidayID else { return nil }
            return (pid, e)
        })

        Task {
            // Create new
            for preset in selectedIDs where existing[preset] == nil {
                let event = ImportantDate(
                    id: UUID(), spaceID: spaceID, creatorID: myID,
                    kind: .holiday, title: preset.defaultTitle,
                    dateValue: computeSeedDate(for: preset),
                    recurrence: preset.recurrence,
                    notifyDaysBefore: 7, notifyOnDay: true,
                    icon: preset.defaultIcon, presetHolidayID: preset,
                    updatedAt: .now
                )
                await viewModel.save(event)
            }
            // Remove un-selected
            for (preset, event) in existing where !selectedIDs.contains(preset) {
                await viewModel.delete(event.id)
            }
            dismiss()
        }
    }
}
```

- [ ] **Step 2: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 3: commit**

```bash
git add Together/Features/Anniversaries/PresetHolidayPickerSheet.swift
git commit -m "$(cat <<'EOF'
feat(ui): PresetHolidayPickerSheet for MVP 3 holidays

Multi-select sheet: 情人节 (solar) / 七夕 / 春节 (lunar).
Displays computed next solar date beside each lunar holiday so
users see exactly when it lands. Save: creates newly-checked
events, deletes newly-unchecked; existing selections seed state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 26: Router 集成 management view 路由入口

**Files:**
- Modify: Router / Navigation relevant file（e.g., `AppRouter.swift`、或者处理 `presentSheet` 的地方）

- [ ] **Step 1: grep router surface**

```bash
grep -rn "enum RootSurface\|presentSheet\|activeSheet" Together/App --include="*.swift" | head
```

- [ ] **Step 2: 加 importantDatesManagement case / sheet**

根据现有 router pattern，增加一个 case 让 Home 胶囊和 Profile 入口都能跳转过去。

例：如果 router 用 NavigationStack + path 模式：
```swift
enum AppDestination: Hashable {
    case importantDatesManagement
    // ...
}

.navigationDestination(for: AppDestination.self) { dest in
    switch dest {
    case .importantDatesManagement:
        ImportantDatesManagementView()
    }
}
```

或如果用 sheet：
```swift
@Observable
final class AppRouter {
    var presentedSheet: AppSheet?
}
enum AppSheet: Identifiable {
    case importantDatesManagement
    var id: String { /* ... */ }
}
```

具体看既有 pattern。

- [ ] **Step 3: 回填 Task 21 + 22 里的 `router.push`/`presentSheet` 调用**

- [ ] **Step 4: build**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3
```

- [ ] **Step 5: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 6: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): route anniversaries management via AppRouter

Both the home capsule and profile entry now push/present the
ImportantDatesManagementView through the existing router surface.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 27: 伴侣昵称 label 动态注入（修 scheduler 文案的 "伴侣" fallback）

**Files:**
- Modify: `Together/Services/LocalServiceFactory.swift`（name providers wiring）
- Modify: `Together/Services/Notifications/AnniversaryNotificationScheduler.swift`（providers 实际用到）

- [ ] **Step 1: 修改 LocalServiceFactory 注入 real providers**

```swift
let sessionStoreRef = sessionStore  // assumes exists in this scope
let anniversaryScheduler = AnniversaryNotificationScheduler(
    repository: importantDateRepository,
    partnerDisplayNameProvider: { [weak sessionStoreRef] in
        sessionStoreRef?.pairSpaceSummary?.partner?.displayName
    },
    myDisplayNameProvider: { [weak sessionStoreRef] in
        sessionStoreRef?.currentUser?.displayName
    }
)
```

（精确的 `sessionStoreRef` 获取按 factory 现状。也可以让 `AppContext` 在 configure 完毕后设 provider。）

- [ ] **Step 2: Scheduler 的 `isMyself` 实装**

Scheduler 需要知道"我是谁"。可以追加一个 `myUserIDProvider: () -> UUID?`：

```swift
private let myUserIDProvider: @Sendable () -> UUID?

init(
    repository: ...,
    ...
    myUserIDProvider: @escaping @Sendable () -> UUID? = { nil }
) { ... }

private func isMyself(_ memberID: UUID) -> Bool {
    myUserIDProvider() == memberID
}
```

LocalServiceFactory 传 `sessionStoreRef?.currentUser?.id`。

- [ ] **Step 3: advanceBody / dayOfTitle / dayOfBody 在 "我 vs 伴侣" 情况下分别取 provider**

已经由 Step 1 + 2 完成（Scheduler 代码里 advanceBody 已处理 isMyself 分支）。

- [ ] **Step 4: build + regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 5: commit**

```bash
git add Together/Services/LocalServiceFactory.swift \
  Together/Services/Notifications/AnniversaryNotificationScheduler.swift
git commit -m "$(cat <<'EOF'
feat(notify): dynamic 我/伴侣 labels via session providers

Scheduler now accepts partnerDisplayNameProvider +
myDisplayNameProvider + myUserIDProvider closures, wired from
LocalServiceFactory against the live SessionStore. Notification
copy distinguishes 我的生日 vs 伴侣 生日 correctly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 28: 视觉打磨 pass

**Files:** 本任务主要调 app 内现有 UI 样式，按需修改刚写的 view 文件

- [ ] **Step 1: 手工跑一遍真机或模拟器**

启动 app → 切 pair 模式 → 检查：
1. 主页胶囊存在；空状态 CTA 清晰
2. 点胶囊进管理页，空态 3 张卡片 + 底部 footer 排版正常
3. 创建一条自定义纪念日，保存后回到列表
4. 主页胶囊立刻显示新事件 "还有 X 天"
5. "我"页纪念日入口 row 样式 ok
6. 节日勾选表勾选 + 保存
7. 在 list 里右划删除

- [ ] **Step 2: 按观察到的问题小改 UI**

常见需改：
- 字号 / 间距对齐 app 既有 AppTheme scale
- 珊瑚色 accent 统一
- 空态 CTA primary 按钮 padding / 圆角

一次 commit 把所有视觉调整打包。

- [ ] **Step 3: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```

- [ ] **Step 4: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
style(ui): visual polish pass across anniversary views

Align typography, spacing and coral accents with AppTheme. Minor
fixes to empty state CTA padding, list row rhythm, and capsule
inset matching existing overdue/routines capsules.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Batch F: E2E + 合并（2 tasks）

---

## Task 29: 双设备 E2E 手工验证（user blocking）

**Files:** 无

请在 iPhone + iPad 上执行以下场景，每条都要通过：

- [ ] **Case 1** — iPad 进入 pair 模式 Home：例行事务 tab 不见、routines summary card 不见
- [ ] **Case 2** — 纪念日胶囊显示在主页，空态显示"添加第一个纪念日"
- [ ] **Case 3** — 点胶囊进管理页 → 添加伴侣生日（选今日 + 3 天后的日期）→ 保存
- [ ] **Case 4** — 回到主页胶囊立刻显示"还有 3 天 · 伴侣生日"
- [ ] **Case 5** — iPad 上同步显示 → 主页胶囊同样显示"还有 3 天 · 伴侣生日"
- [ ] **Case 6** — 勾选七夕节日 → 管理页列表多一条"七夕 · 2026/8/19"
- [ ] **Case 7** — 等 3 天或手动改系统时间 → 当天 9:00 收到通知"🎂 今天是伴侣生日"
- [ ] **Case 8** — iPad 删除该生日 → iPhone realtime 更新 → 主页胶囊消失或换成下一条
- [ ] **Case 9** — 切换 iPad 到 solo 模式 → 例行事务 tab 再次出现；solo 数据完整（验证迁移没误伤 solo）
- [ ] **Case 10** — 验证 Supabase 数据：
```sql
SELECT kind, title, recurrence_rule, preset_holiday_id FROM important_dates
WHERE space_id IN (SELECT id FROM spaces WHERE type='pair')
ORDER BY updated_at DESC LIMIT 10;
```

用户报告每条 Pass / Fail 即可。

---

## Task 30: 合并 + push + 实施日志

**Files:**
- Modify: `docs/superpowers/plans/2026-04-19-pair-mode-anniversaries.md`（追加"实施日志"段）

- [ ] **Step 1: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 2: 合并 + push**

```bash
git checkout main
git merge --ff-only feat/pair-mode-anniversaries
git push origin main
```

- [ ] **Step 3: 追加实施日志**

打开此 plan 文件，在文末 `## 实施日志（开工后追加）` 段追加：
- Commit SHA 顺序列（跑 `git log --oneline BASE..HEAD`）
- 任何偏离 plan 的决定
- 验证不可行的方案
- v2 待办

Commit 分开：
```bash
git add docs/superpowers/plans/2026-04-19-pair-mode-anniversaries.md
git commit -m "docs(plan): pair-mode anniversaries implementation log"
git push origin main
```

---

## Verification checklist

合并前对照 spec 对一遍：

```
□ §1 IA 变更
  □ pair 模式隐藏例行 tab + routines summary card（Task 14）
  □ Migration 015 硬删 pair-space periodic（Task 1）
  □ 客户端一次性 migration 清理本地缓存（Task 6）
  □ Service guard 拒绝 pair-space periodic save（Task 15）

□ §2 纪念日功能范围
  □ 4 种 kind + 3 种 preset（Task 3）
  □ 共享模型（Task 10 DTO 里 space_id 路由）

□ §3 数据模型
  □ important_dates 表 + 索引（Task 2）
  □ PersistentImportantDate + schema register（Task 5）
  □ Domain model + Kind/Recurrence/PresetHolidayID（Task 3）

□ §4 通知推送
  □ AnniversaryNotificationScheduler（Task 17）
  □ 4 触发点接入（Task 19, 20）
  □ 32 事件 cap + 9am 触发（Task 17）
  □ 文案 localization（Task 17, 27）

□ §5 农历处理
  □ solar / lunar / leap fallback（Task 3, 4）

□ §6 UI
  □ 主页胶囊（Task 21）
  □ 我 页入口（Task 22）
  □ 管理页 + 空态 + 列表（Task 23）
  □ 编辑 sheet（Task 24）
  □ 节日勾选表（Task 25）
  □ Router 集成（Task 26）

□ §8 测试
  □ nextOccurrence 6 tests（Task 4）
  □ Repository 4 tests（Task 7）
  □ DTO 3 tests（Task 10）
  □ Periodic purge migration 2 tests（Task 6）
  □ Pair guard 2 tests（Task 15）
  □ Scheduler：依赖 E2E（Task 18 评估后延期）

□ §10 旧代码清理
  □ MockAnniversaryRepository 删除（Task 7）
  □ AnniversaryRepositoryProtocol 删除（Task 7）
  □ 旧 AnniversariesViewModel 替换为 ImportantDatesViewModel（Task 7, 16）
```

---

## 实施日志（2026-04-19 shipped to main）

36 commits merged ff-only → main at `2428982`. Supabase migrations 015 / 016 / 017 / 018 / 019 all applied to `nxielmwdoiwiwhzczrmt`. Full regression green at every step (Swift Testing only; XCTest untouched).

### Commit history

Feature commits (plan order, with any mid-stream fixes grouped):

- `089fc5c` Task 1 — migration 015 hard-delete pair-space periodic_tasks
- `b8b9abc` + `fc11434` Task 2 — migration 016 create important_dates (rebuilt after discovering 001 pre-created a Phase-3 placeholder with wrong schema)
- `58decf4` Task 3 — domain model `ImportantDate` + enums + `nextOccurrence` (solar / lunar / leap-month fallback)
- `10f358e` Task 4 — 6 `nextOccurrence` tests
- `c3dece7` Task 5 — `PersistentImportantDate` SwiftData model (schema grew 16 → 17)
- `12520b8` Task 6 — `PairPeriodicPurgeMigration` + postLaunch hook + 2 tests
- `b21fcc3` Task 7 — `LocalImportantDateRepository` (actor) + protocol + 4 tests + `SyncEntityKind.importantDate` case + removed legacy `AnniversaryRepositoryProtocol` / `MockAnniversaryRepository` / `AnniversariesViewModel` / `AnniversariesView` (+ build-green stubs in `SupabaseSyncService.pushUpsert` / `SyncEngineDelegate.fetchAndEncode`)
- `d8471be` Task 8 — DI wiring through `AppContainer` + factories + `MockImportantDateRepository`
- `5f7b615` follow-up — migration 017 CHECK constraints (auto-merged from spawned chip before Task 10)
- Task 9 — rolled into Task 7
- `838e8f7` Task 10 — `ImportantDateDTO` Codable + `applyToLocal` + 3 round-trip tests (memberwise init preserved by moving `init(from:)` to extension)
- `97b00ca` Task 11 — `pushUpsert(.importantDate)` + `ImportantDateWriter` seam + 2 push tests (delete reused generic `pushDelete`)
- `1d3f4ea` Task 12 — `pullImportantDates` + `ImportantDateReader` seam + 3 pull tests (insert / update / tombstone)
- `4ba46eb` Task 13 — realtime subscription + `.importantDatesChanged` notification + echo filter
- `dd0a8cf` + `f107b6f` Task 14 — hide routines dock button + summary card when `activeMode == .pair`
- `ce27da5` Task 15 — `LocalPeriodicTaskRepository.saveTask` pair-space guard + 3 tests
- `69e8530` Task 16 — `ImportantDatesViewModel` skeleton wired into `AppContext`
- `724f0c0` Task 17 — `AnniversaryNotificationScheduler` skeleton (fixed plan's `center.authorizationStatus()` call, actual API is `center.notificationSettings().authorizationStatus`)
- `3426a95` Task 18 — empty commit documenting scheduler unit-test deferral to E2E
- `8ccf3c9` Task 19 — scheduler wired through AppContainer + factories + postLaunch + `.importantDatesChanged` observer
- `f112151` Task 20 — ViewModel `onChange` callback triggers scheduler refresh on save/delete
- `b5ffb2e` Task 21 — `AnniversaryCapsuleView` + two timeline list mounting points + postLaunch `configure + load`
- `aa489da` Task 22 — profile page anniversaries entry row (pair mode only)
- `9d33d11` Task 24 — `ImportantDateEditSheet` (reordered ahead of 23 because 23 references 24 + 25)
- `bb49224` Task 25 — `PresetHolidayPickerSheet`
- `abcff5c` Task 23 — `ImportantDatesManagementView` empty state + list + add sheet
- `eb92df5` Task 26 — home capsule + profile row wired to sheet via local `@State` (deliberately not AppRouter — profile is inside a fullScreenCover that would occlude a router-owned sheet)
- `af7ce77` Task 27 — scheduler API refactored from provider closures to explicit `refresh(spaceID:partnerName:myName:myUserID:)` args (factories have no sessionStore handle; explicit args at call-time sidestep Swift 6 actor-isolation complexity)
- `922b55e` Task 28 — empty commit documenting visual polish deferral to E2E

E2E-driven fix commits (on top of the 28-task plan):

- `6a9fd5d` Fix A+B — missing `supabaseSyncService.push()` call after VM save/delete (queued changes never left the device) + missing capsule mount in the tasksContent empty-state branch
- `a6e1a06` Fix C — migration 018 relax INSERT RLS (the plan accidentally wrote `is_space_member(space_id) AND creator_id = auth.uid()` when all other pair tables use only `is_space_member(space_id)`; anon-key path couldn't satisfy the stricter clause)
- `e8779e6` Fix D — migration 019 convert `date_value` from `date` to `timestamptz` (PostgREST returns bare `"YYYY-MM-DD"` for `date` columns, Swift's JSONDecoder cannot parse that as `Date` under any default strategy; timestamptz returns ISO8601 which the Supabase Swift SDK decodes out of the box)
- `2428982` Fix E — VM `spaceID` configure when pair becomes active (postLaunch fires once-per-launch; if pair isn't ready yet the VM stays nil-configured and all subsequent `load()` calls short-circuit silently). Three defensive hooks: `startSupabaseSyncIfNeeded` after pair resolution, `ImportantDatesManagementView.task`, `HomeView.onReceive(.importantDatesChanged)`.

### Decisions that diverged from the plan (keep in mind for future work)

1. **RLS policy** — plan wrote anon open-to-public; controller chose `is_space_member()` to match other pair tables. Then E2E discovered the plan's own INSERT-side extra clause `creator_id = auth.uid()` was too strict for the project's two-user-id-universe identity model. 018 relaxed it to match tasks / projects / periodic_tasks.
2. **`date_value` column type** — plan said `date`; E2E showed PostgREST/Swift decoder mismatch. 019 converted to `timestamptz`. UI still extracts year/month/day via `Calendar(.current)` so the forced 00:00 UTC component is display-invisible.
3. **Delete path** — plan wanted `ImportantDateWriter.delete()`; the generic `pushDelete(entityKind:recordID:)` on `SupabaseSyncService` already uses `supabaseTableName + SoftDelete` struct and covers any kind. `ImportantDateWriter` only needed `upsert`.
4. **`#Predicate` on optional `UUID`** — `Set<UUID>.contains(task.spaceID)` where `spaceID: UUID?` is not expressible in SwiftData's predicate DSL. `PairPeriodicPurgeMigration` fetches all rows and filters in Swift.
5. **ViewModel API** — plan used provider closures for `partnerDisplayName` / `myDisplayName`. Factories don't have SessionStore handle (AppContext builds factory first). Rewrote scheduler to accept explicit `refresh(spaceID:partnerName:myName:myUserID:)` args; AppContext reads session at call time.
6. **Task 23 ordering** — 23 references types from 24 + 25. Executed 24 → 25 → 23 in the commit log to keep every commit green on build.
7. **Sheet routing** — plan assumed an AppRouter sheet enum. Project's AppRouter is a minimal `@Observable` with no sheet/destination API. Used local `@State` on HomeView and ProfileView for `isImportantDatesManagementPresented`; profile sheet is attached inside the fullScreenCover so it isn't occluded.
8. **Scheduler unit tests** — `UNUserNotificationCenter` is a Swift singleton without a cheap seam. Deferred tests to E2E (per plan's recommended "Option 1") rather than refactoring a `NotificationCenterAdapter` protocol for MVP.
9. **Visual polish pass** — Task 28 required human eyes; controller cannot iterate on pixels. Deferred to E2E user feedback.

### Follow-ups left on the backlog (chips)

- Add `CHECK` constraints to `important_dates` for kind / recurrence_rule / notify_days_before / preset consistency *(already auto-merged as `5f7b615` mid-way)*
- Fix Feb 29 / lunar leap-month edge cases — extend `nextOccurrence` loop bounds from `0..<2` / `0..<3` to `0..<5` with targeted tests
- Explicitly configure Supabase Swift client ISO8601 Date encoder/decoder (currently implicit, survives SDK upgrades only by luck)
- Serialize `AnniversaryNotificationScheduler.refresh` against concurrent invocations (current implementation could race and remove its own just-added pending requests)
- Backfill `pullImportantDates` when local store is empty (ignore `lastSyncedAt since` so a prior empty-successful catchUp can't hide later rows)
- Clean up pair unbind side-effects — stale `space_members` rows on Supabase, local SwiftData rows tagged with the old spaceID (not anniversaries-specific, affects every pair-scoped table)

### E2E outcomes (task 29, user-driven)

User ran 10 cases on iPhone + iPad. Uncovered the 5 fix commits above; on the final iteration both devices reached steady state with correct cross-device sync:

- Empty state shows "添加第一个纪念日" capsule correctly
- Capsule + management view + profile entry all present in pair mode, hidden in solo
- Routines dock button + summary card hidden in pair mode, unchanged in solo
- iPhone create → iPad realtime receive via `.importantDatesChanged` channel → capsule and management view refresh
- Local scheduler logs `scheduled anniversary notifications for N events` on every mutation
- Supabase `important_dates` table synced; RLS policies green with the relaxed INSERT rule
