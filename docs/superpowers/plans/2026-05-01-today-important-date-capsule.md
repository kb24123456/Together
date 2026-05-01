# Today Important Date Capsule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Today important-date capsule so pair mode defaults to the anniversary anchor, only includes other dates within 7 days, supports single-layer paging, and switches elapsed/countdown by tapping the visible count text.

**Architecture:** Keep backend schema and the `ImportantDate` core model unchanged. Add a repository projection that carries `createdAt`, a UI-layer planner that computes capsule candidates, and a SwiftUI pager component that owns UI preferences through `AppStorage`.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, `@AppStorage`, existing Together theme and haptic helpers.

---

## File Structure

- Create: `Together/Domain/Models/ImportantDateStoredRecord.swift`
  - Repository projection containing `event: ImportantDate` and `createdAt: Date`.
- Modify: `Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift`
  - Add `fetchAllStoredRecords(spaceID:)` while keeping `fetchAll(spaceID:)`.
- Modify: `Together/Services/ImportantDates/LocalImportantDateRepository.swift`
  - Return `PersistentImportantDate.createdAt` without changing Supabase or domain schema.
- Modify: `Together/Services/ImportantDates/MockImportantDateRepository.swift`
  - Store deterministic created dates for tests and previews.
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePlanner.swift`
  - Pure UI planning: anchor detection, 7-day window, today handling, sorting.
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePreferences.swift`
  - JSON encode/decode helpers for per-date count mode and selected ID strings.
- Modify: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`
  - Load stored records and expose capsule candidates.
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`
  - Convert from one event + long press to one page + semantic count tap.
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePagerView.swift`
  - Single-layer horizontal pager, light page dots, selection persistence.
- Modify: `Together/Features/Home/HomeView.swift`
  - Replace `nextAnniversaryEvent()` usage with the pager.
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
  - Set new anniversary seed `showsElapsedDays: true`.
- Create: `TogetherTests/ImportantDateCapsulePlannerTests.swift`
  - Planner coverage for anchor, 7-day filter, latest-created ordering, today handling.
- Create: `TogetherTests/ImportantDateCapsulePreferencesTests.swift`
  - Preference JSON resilience and per-date count mode tests.

## Task 1: Repository Projection For `createdAt`

**Files:**
- Create: `Together/Domain/Models/ImportantDateStoredRecord.swift`
- Modify: `Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift`
- Modify: `Together/Services/ImportantDates/LocalImportantDateRepository.swift`
- Modify: `Together/Services/ImportantDates/MockImportantDateRepository.swift`

- [ ] **Step 1: Add the stored record projection**

Create `Together/Domain/Models/ImportantDateStoredRecord.swift`:

```swift
import Foundation

struct ImportantDateStoredRecord: Identifiable, Hashable, Sendable {
    var id: UUID { event.id }
    let event: ImportantDate
    let createdAt: Date
}
```

- [ ] **Step 2: Extend the repository protocol without removing existing API**

In `Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift`, replace the protocol body with:

```swift
import Foundation

protocol ImportantDateRepositoryProtocol: Sendable {
    func fetchAll(spaceID: UUID) async throws -> [ImportantDate]
    func fetchAllStoredRecords(spaceID: UUID) async throws -> [ImportantDateStoredRecord]
    func fetch(id: UUID) async throws -> ImportantDate?
    func save(_ event: ImportantDate) async throws
    func delete(id: UUID) async throws
    func hardDelete(id: UUID) async throws
}
```

- [ ] **Step 3: Implement local repository projection**

In `Together/Services/ImportantDates/LocalImportantDateRepository.swift`, replace `fetchAll(spaceID:)` with:

```swift
func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
    let records = try await fetchAllStoredRecords(spaceID: spaceID)
    return records.map(\.event)
}

func fetchAllStoredRecords(spaceID: UUID) async throws -> [ImportantDateStoredRecord] {
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<PersistentImportantDate>(
        predicate: #Predicate {
            $0.spaceID == spaceID && $0.isLocallyDeleted == false
        },
        sortBy: [
            SortDescriptor(\.dateValue),
            SortDescriptor(\.createdAt, order: .reverse)
        ]
    )
    let rows = try context.fetch(descriptor)
    return rows.map {
        ImportantDateStoredRecord(event: $0.domainModel(), createdAt: $0.createdAt)
    }
}
```

- [ ] **Step 4: Implement mock repository projection**

In `Together/Services/ImportantDates/MockImportantDateRepository.swift`, replace the stored properties and `fetchAll` / `save` with:

```swift
private var storage: [UUID: ImportantDateStoredRecord] = [:]
private var tombstones: Set<UUID> = []

func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
    let records = try await fetchAllStoredRecords(spaceID: spaceID)
    return records.map(\.event)
}

func fetchAllStoredRecords(spaceID: UUID) async throws -> [ImportantDateStoredRecord] {
    storage.values
        .filter { $0.event.spaceID == spaceID && !tombstones.contains($0.id) }
        .sorted {
            if $0.event.dateValue == $1.event.dateValue {
                return $0.createdAt > $1.createdAt
            }
            return $0.event.dateValue < $1.event.dateValue
        }
}

func fetch(id: UUID) async throws -> ImportantDate? {
    guard !tombstones.contains(id) else { return nil }
    return storage[id]?.event
}

func save(_ event: ImportantDate) async throws {
    let createdAt = storage[event.id]?.createdAt ?? Date()
    storage[event.id] = ImportantDateStoredRecord(event: event, createdAt: createdAt)
    tombstones.remove(event.id)
}
```

Keep the existing `delete` and `hardDelete` behavior, changing `hardDelete` to remove from `storage` by key if needed.

- [ ] **Step 5: Compile to catch protocol conformers**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -80
```

Expected: build may fail only if another repository conformer needs `fetchAllStoredRecords(spaceID:)`. Add the same simple projection there if one exists; do not change Supabase migrations or `ImportantDate`.

- [ ] **Step 6: Commit**

```bash
git add Together/Domain/Models/ImportantDateStoredRecord.swift \
        Together/Domain/Protocols/ImportantDateRepositoryProtocol.swift \
        Together/Services/ImportantDates/LocalImportantDateRepository.swift \
        Together/Services/ImportantDates/MockImportantDateRepository.swift
git commit -m "Add important date stored record projection"
```

## Task 2: Pure Capsule Planner

**Files:**
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePlanner.swift`
- Create: `TogetherTests/ImportantDateCapsulePlannerTests.swift`

- [ ] **Step 1: Write failing planner tests**

Create `TogetherTests/ImportantDateCapsulePlannerTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("ImportantDateCapsulePlanner")
struct ImportantDateCapsulePlannerTests {
    private let spaceID = UUID()
    private let creatorID = UUID()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func record(
        id: UUID = UUID(),
        kind: ImportantDateKind,
        title: String,
        dateValue: Date,
        recurrence: Recurrence = .solarAnnual,
        createdAt: Date,
        showsElapsedDays: Bool = false
    ) -> ImportantDateStoredRecord {
        ImportantDateStoredRecord(
            event: ImportantDate(
                id: id,
                spaceID: spaceID,
                creatorID: creatorID,
                kind: kind,
                title: title,
                dateValue: dateValue,
                recurrence: recurrence,
                notifyDaysBefore: 7,
                notifyOnDay: true,
                icon: nil,
                presetHolidayID: nil,
                showsElapsedDays: showsElapsedDays,
                updatedAt: createdAt
            ),
            createdAt: createdAt
        )
    }

    @Test("anniversary is anchor even when title is not literal 在一起的日子")
    func anniversaryAnchorUsesKindNotTitle() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let birthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-03T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [birthday, anniversary],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id, birthday.event.id])
        #expect(candidates.first?.isAnchor == true)
    }

    @Test("dates outside seven days do not enter the pool")
    func sevenDayWindowExcludesFarDates() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let farBirthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-20T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, farBirthday],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(candidates.map(\.event.id) == [anniversary.event.id])
    }

    @Test("latest eligible created date is second after anchor")
    func latestEligibleCreatedDateIsSecond() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-05-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let soonerOlder = record(
            kind: .custom,
            title: "第一次旅行",
            dateValue: date("2025-05-02T00:00:00Z"),
            createdAt: date("2026-04-01T00:00:00Z")
        )
        let laterNewer = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-06T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [soonerOlder, laterNewer, anniversary],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(candidates.map(\.event.id) == [
            anniversary.event.id,
            laterNewer.event.id,
            soonerOlder.event.id
        ])
    }

    @Test("annual event on current day remains in pool and reports today")
    func annualEventTodayIsIncluded() {
        let anniversary = record(
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: date("2025-01-01T00:00:00Z"),
            createdAt: date("2026-01-01T00:00:00Z"),
            showsElapsedDays: true
        )
        let birthday = record(
            kind: .birthday(memberUserID: UUID()),
            title: "我的生日",
            dateValue: date("1990-05-01T00:00:00Z"),
            createdAt: date("2026-04-30T00:00:00Z")
        )

        let candidates = ImportantDateCapsulePlanner.candidates(
            from: [anniversary, birthday],
            referenceDate: date("2026-05-01T12:00:00Z"),
            calendar: Calendar(identifier: .gregorian)
        )

        let birthdayCandidate = candidates.first { $0.event.id == birthday.event.id }
        #expect(birthdayCandidate?.daysUntilOrToday == 0)
        #expect(birthdayCandidate?.isToday == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateCapsulePlannerTests 2>&1 | tail -80
```

Expected: fail to compile because `ImportantDateCapsulePlanner` and `ImportantDateCapsuleCandidate` do not exist.

- [ ] **Step 3: Add planner implementation**

Create `Together/Features/Anniversaries/ImportantDateCapsulePlanner.swift`:

```swift
import Foundation

struct ImportantDateCapsuleCandidate: Identifiable, Hashable, Sendable {
    var id: UUID { event.id }
    let event: ImportantDate
    let createdAt: Date
    let daysUntilOrToday: Int
    let isToday: Bool
    let isAnchor: Bool
}

enum ImportantDateCapsulePlanner {
    static let visibilityWindowDays = 7

    static func candidates(
        from records: [ImportantDateStoredRecord],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [ImportantDateCapsuleCandidate] {
        let anchor = records
            .filter { isAnchor($0.event) }
            .sorted { $0.createdAt < $1.createdAt }
            .first

        let nonAnchorCandidates = records
            .filter { !isAnchor($0.event) }
            .compactMap { candidate(from: $0, referenceDate: referenceDate, calendar: calendar) }
            .filter { $0.daysUntilOrToday <= visibilityWindowDays }

        let latestEligibleID = nonAnchorCandidates
            .max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.event.updatedAt < rhs.event.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }?
            .id

        let latest = nonAnchorCandidates.filter { $0.id == latestEligibleID }
        let remaining = nonAnchorCandidates
            .filter { $0.id != latestEligibleID }
            .sorted { lhs, rhs in
                if lhs.daysUntilOrToday == rhs.daysUntilOrToday {
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.event.updatedAt > rhs.event.updatedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.daysUntilOrToday < rhs.daysUntilOrToday
            }

        var result: [ImportantDateCapsuleCandidate] = []
        if let anchor {
            result.append(anchorCandidate(from: anchor, referenceDate: referenceDate, calendar: calendar))
        }
        result.append(contentsOf: latest)
        result.append(contentsOf: remaining)
        return result
    }

    static func isAnchor(_ event: ImportantDate) -> Bool {
        if case .anniversary = event.kind { return true }
        return false
    }

    private static func anchorCandidate(
        from record: ImportantDateStoredRecord,
        referenceDate: Date,
        calendar: Calendar
    ) -> ImportantDateCapsuleCandidate {
        let days = daysUntilOrToday(for: record.event, referenceDate: referenceDate, calendar: calendar) ?? 0
        return ImportantDateCapsuleCandidate(
            event: record.event,
            createdAt: record.createdAt,
            daysUntilOrToday: max(0, days),
            isToday: days == 0,
            isAnchor: true
        )
    }

    private static func candidate(
        from record: ImportantDateStoredRecord,
        referenceDate: Date,
        calendar: Calendar
    ) -> ImportantDateCapsuleCandidate? {
        guard let days = daysUntilOrToday(for: record.event, referenceDate: referenceDate, calendar: calendar) else {
            return nil
        }
        return ImportantDateCapsuleCandidate(
            event: record.event,
            createdAt: record.createdAt,
            daysUntilOrToday: days,
            isToday: days == 0,
            isAnchor: false
        )
    }

    private static func daysUntilOrToday(
        for event: ImportantDate,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        let today = calendar.startOfDay(for: referenceDate)
        let target: Date?

        switch event.recurrence {
        case .none:
            target = calendar.startOfDay(for: event.dateValue)
        case .solarAnnual, .lunarAnnual:
            let previousDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            target = event.nextOccurrence(after: previousDay, calendar: calendar).map {
                calendar.startOfDay(for: $0)
            }
        }

        guard let target else { return nil }
        let delta = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return delta >= 0 ? delta : nil
    }
}
```

- [ ] **Step 4: Run planner tests**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateCapsulePlannerTests 2>&1 | tail -80
```

Expected: `ImportantDateCapsulePlannerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDateCapsulePlanner.swift \
        TogetherTests/ImportantDateCapsulePlannerTests.swift
git commit -m "Add important date capsule planner"
```

## Task 3: ViewModel Records And Anniversary Seed

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`
- Modify: `Together/Features/Anniversaries/ImportantDatesManagementView.swift`
- Create: `TogetherTests/ImportantDatesViewModelCapsuleTests.swift`

- [ ] **Step 1: Write failing ViewModel tests**

Create `TogetherTests/ImportantDatesViewModelCapsuleTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

private actor CapsuleRecordRepository: ImportantDateRepositoryProtocol {
    var records: [ImportantDateStoredRecord] = []

    func setRecords(_ records: [ImportantDateStoredRecord]) {
        self.records = records
    }

    func fetchAll(spaceID: UUID) async throws -> [ImportantDate] {
        records.filter { $0.event.spaceID == spaceID }.map(\.event)
    }

    func fetchAllStoredRecords(spaceID: UUID) async throws -> [ImportantDateStoredRecord] {
        records.filter { $0.event.spaceID == spaceID }
    }

    func fetch(id: UUID) async throws -> ImportantDate? {
        records.first { $0.event.id == id }?.event
    }

    func save(_ event: ImportantDate) async throws {
        records.removeAll { $0.event.id == event.id }
        records.append(ImportantDateStoredRecord(event: event, createdAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func delete(id: UUID) async throws {
        records.removeAll { $0.event.id == id }
    }

    func hardDelete(id: UUID) async throws {
        records.removeAll { $0.event.id == id }
    }
}

@Suite("ImportantDatesViewModel capsule records")
@MainActor
struct ImportantDatesViewModelCapsuleTests {
    private func makeEvent(spaceID: UUID, kind: ImportantDateKind, title: String) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: spaceID,
            creatorID: UUID(),
            kind: kind,
            title: title,
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            recurrence: .solarAnnual,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("load stores records and preserves public events array")
    func loadStoresRecords() async throws {
        let spaceID = UUID()
        let repository = CapsuleRecordRepository()
        let event = makeEvent(spaceID: spaceID, kind: .anniversary, title: "我们的纪念日")
        await repository.setRecords([
            ImportantDateStoredRecord(event: event, createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        ])
        let date = SystemDateProvider()
        let viewModel = ImportantDatesViewModel(
            sessionStore: SessionStore(),
            premiumGate: PremiumGate(
                rcClient: StubRCClient(),
                grantsLoader: StubGrantsLoader(),
                cache: PremiumStatusCache(
                    defaults: UserDefaults(suiteName: UUID().uuidString)!,
                    dateProvider: date
                ),
                dateProvider: date
            ),
            repository: repository
        )

        viewModel.configure(spaceID: spaceID)
        await viewModel.load()

        #expect(viewModel.events.map(\.id) == [event.id])
        #expect(viewModel.storedRecords.map(\.id) == [event.id])
        #expect(viewModel.storedRecords.first?.createdAt == Date(timeIntervalSince1970: 1_700_000_100))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDatesViewModelCapsuleTests 2>&1 | tail -80
```

Expected: fail because `storedRecords` does not exist.

- [ ] **Step 3: Store records in ViewModel**

In `Together/Features/Anniversaries/ImportantDatesViewModel.swift`, add after `var events: [ImportantDate] = []`:

```swift
private(set) var storedRecords: [ImportantDateStoredRecord] = []
```

Replace the successful load assignment inside `load()` with:

```swift
let records = try await repository.fetchAllStoredRecords(spaceID: spaceID)
storedRecords = records
events = records.map(\.event)
```

- [ ] **Step 4: Default new anniversary to elapsed-days capable**

In `Together/Features/Anniversaries/ImportantDatesManagementView.swift`, inside `createAnniversary()`, change:

```swift
showsElapsedDays: false,
```

to:

```swift
showsElapsedDays: true,
```

- [ ] **Step 5: Run ViewModel test**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDatesViewModelCapsuleTests 2>&1 | tail -80
```

Expected: test passes.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesViewModel.swift \
        Together/Features/Anniversaries/ImportantDatesManagementView.swift \
        TogetherTests/ImportantDatesViewModelCapsuleTests.swift
git commit -m "Expose important date capsule records"
```

## Task 4: Preference Encoding

**Files:**
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePreferences.swift`
- Create: `TogetherTests/ImportantDateCapsulePreferencesTests.swift`

- [ ] **Step 1: Write failing preference tests**

Create `TogetherTests/ImportantDateCapsulePreferencesTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("ImportantDateCapsulePreferences")
struct ImportantDateCapsulePreferencesTests {
    @Test("selected ID round trips through string storage")
    func selectedIDRoundTrip() {
        let id = UUID()
        #expect(ImportantDateCapsulePreferences.selectedID(from: id.uuidString) == id)
        #expect(ImportantDateCapsulePreferences.selectedID(from: "bad") == nil)
        #expect(ImportantDateCapsulePreferences.storageString(for: id) == id.uuidString)
        #expect(ImportantDateCapsulePreferences.storageString(for: nil) == "")
    }

    @Test("count modes round trip and ignore invalid data")
    func countModesRoundTrip() {
        let first = UUID()
        let second = UUID()
        let encoded = ImportantDateCapsulePreferences.encodeCountModes([
            first: .elapsed,
            second: .next
        ])
        let decoded = ImportantDateCapsulePreferences.decodeCountModes(encoded)

        #expect(decoded[first] == .elapsed)
        #expect(decoded[second] == .next)
        #expect(ImportantDateCapsulePreferences.decodeCountModes("{").isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateCapsulePreferencesTests 2>&1 | tail -80
```

Expected: fail to compile because preferences type and public count mode do not exist.

- [ ] **Step 3: Add preference helpers**

Create `Together/Features/Anniversaries/ImportantDateCapsulePreferences.swift`:

```swift
import Foundation

enum ImportantDateCapsuleCountMode: String, Codable, Hashable, Sendable {
    case next
    case elapsed
}

enum ImportantDateCapsulePreferences {
    static func selectedID(from rawValue: String) -> UUID? {
        UUID(uuidString: rawValue)
    }

    static func storageString(for id: UUID?) -> String {
        id?.uuidString ?? ""
    }

    static func decodeCountModes(_ rawValue: String) -> [UUID: ImportantDateCapsuleCountMode] {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ImportantDateCapsuleCountMode].self, from: data) else {
            return [:]
        }
        return decoded.reduce(into: [UUID: ImportantDateCapsuleCountMode]()) { result, pair in
            guard let id = UUID(uuidString: pair.key) else { return }
            result[id] = pair.value
        }
    }

    static func encodeCountModes(_ modes: [UUID: ImportantDateCapsuleCountMode]) -> String {
        let encoded = modes.reduce(into: [String: ImportantDateCapsuleCountMode]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        guard let data = try? JSONEncoder().encode(encoded),
              let rawValue = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return rawValue
    }
}
```

- [ ] **Step 4: Run preference tests**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TogetherTests/ImportantDateCapsulePreferencesTests 2>&1 | tail -80
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDateCapsulePreferences.swift \
        TogetherTests/ImportantDateCapsulePreferencesTests.swift
git commit -m "Add important date capsule preferences"
```

## Task 5: Single Page Capsule Refactor

**Files:**
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`

- [ ] **Step 1: Replace private count mode with shared count mode**

Remove the private `AnniversaryCapsuleCountMode` enum at the top of `AnniversaryCapsuleView.swift`. Update the view properties to:

```swift
struct AnniversaryCapsuleView: View {
    let event: ImportantDate?
    let countMode: ImportantDateCapsuleCountMode
    let isToday: Bool
    var viewerSupabaseUserID: UUID? = nil
    var partnerDisplayName: String? = nil
    let onPrimaryTap: () -> Void
    let onCountTap: () -> Void
```

- [ ] **Step 2: Replace gesture-driven body with semantic buttons**

Replace `body` and `content` with:

```swift
var body: some View {
    content
        .accessibilityElement(children: .contain)
}

private var content: some View {
    HStack(spacing: AppTheme.spacing.sm) {
        Button(action: onPrimaryTap) {
            HStack(spacing: AppTheme.spacing.sm) {
                Image(systemName: icon)
                    .font(AppTheme.typography.sized(16, weight: .semibold))

                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("打开纪念日管理"))

        if showsCountButton {
            Button(action: onCountTap) {
                AnniversaryCapsuleDetailText(display: detailDisplay)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, AppTheme.spacing.xs)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(detailAccessibilityLabel))
            .accessibilityHint(Text("切换计数方式"))
        } else {
            AnniversaryCapsuleDetailText(display: detailDisplay)
                .font(AppTheme.typography.sized(12, weight: .semibold))
                .foregroundStyle(AppTheme.colors.rose.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, AppTheme.spacing.xs)
                .padding(.vertical, AppTheme.spacing.sm)
        }
    }
    .foregroundStyle(AppTheme.colors.rose)
    .padding(.leading, AppTheme.spacing.md)
    .padding(.trailing, AppTheme.spacing.sm)
    .padding(.vertical, AppTheme.spacing.sm)
    .background(
        Capsule(style: .continuous)
            .fill(AppTheme.colors.rose.opacity(0.12))
    )
}
```

- [ ] **Step 3: Update helpers**

Replace references to `nextEvent` with `event`. Replace `detailDisplay`, `canToggleCountMode`, and count switch helpers with:

```swift
private var detailDisplay: AnniversaryCapsuleDetailDisplay {
    guard let event else { return .staticText("点击添加") }
    if countMode == .elapsed, canShowElapsedDays(for: event) {
        return .numeric(prefix: "已经", value: max(0, event.daysSinceStart))
    }
    if isToday { return .staticText("今天") }
    guard let days = event.daysUntilNext() else { return .staticText("今天") }
    return .numeric(prefix: "还有", value: max(0, days))
}

private var showsCountButton: Bool {
    guard let event else { return false }
    return canShowElapsedDays(for: event)
}

private var detailAccessibilityLabel: String {
    switch detailDisplay {
    case let .numeric(prefix, value):
        return "\(prefix) \(value) 天"
    case let .staticText(text):
        return text
    }
}

private func canShowElapsedDays(for event: ImportantDate) -> Bool {
    event.supportsElapsedDaysDisplay && event.showsElapsedDays
}
```

Keep `icon`, `title`, `defaultIcon(for:)`, and `AnniversaryCapsuleDetailText`, updating `guard let event = event` where needed.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -80
```

Expected: build fails at old `AnniversaryCapsuleView(...)` call sites in `HomeView`, because the pager has not replaced them yet.

- [ ] **Step 5: Commit after Task 6 instead of here**

Do not commit this task alone if the app does not build. Continue directly to Task 6 and commit both together.

## Task 6: Pager View And Home Integration

**Files:**
- Create: `Together/Features/Anniversaries/ImportantDateCapsulePagerView.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/Features/Anniversaries/AnniversaryCapsuleView.swift`

- [ ] **Step 1: Create pager view**

Create `Together/Features/Anniversaries/ImportantDateCapsulePagerView.swift`:

```swift
import SwiftUI

struct ImportantDateCapsulePagerView: View {
    let records: [ImportantDateStoredRecord]
    var viewerSupabaseUserID: UUID? = nil
    var partnerDisplayName: String? = nil
    let onPrimaryTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("together.importantDateCapsule.selectedID") private var selectedIDRawValue = ""
    @AppStorage("together.importantDateCapsule.countModesByDateID") private var countModesRawValue = "{}"

    private var candidates: [ImportantDateCapsuleCandidate] {
        ImportantDateCapsulePlanner.candidates(from: records)
    }

    private var selectedID: UUID? {
        ImportantDateCapsulePreferences.selectedID(from: selectedIDRawValue)
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing.xs) {
            if candidates.isEmpty {
                AnniversaryCapsuleView(
                    event: nil,
                    countMode: .next,
                    isToday: false,
                    viewerSupabaseUserID: viewerSupabaseUserID,
                    partnerDisplayName: partnerDisplayName,
                    onPrimaryTap: onPrimaryTap,
                    onCountTap: {}
                )
            } else if candidates.count == 1, let candidate = candidates.first {
                page(for: candidate)
            } else {
                TabView(selection: selectionBinding) {
                    ForEach(candidates) { candidate in
                        page(for: candidate)
                            .tag(candidate.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(minHeight: 48)
                .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: selectedIDRawValue)

                pageDots
            }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: candidates.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private var selectionBinding: Binding<UUID> {
        Binding(
            get: {
                normalizedSelectedID() ?? candidates.first?.id ?? UUID()
            },
            set: { newValue in
                selectedIDRawValue = ImportantDateCapsulePreferences.storageString(for: newValue)
            }
        )
    }

    private func page(for candidate: ImportantDateCapsuleCandidate) -> some View {
        AnniversaryCapsuleView(
            event: candidate.event,
            countMode: countMode(for: candidate.event),
            isToday: candidate.isToday,
            viewerSupabaseUserID: viewerSupabaseUserID,
            partnerDisplayName: partnerDisplayName,
            onPrimaryTap: onPrimaryTap,
            onCountTap: { toggleCountMode(for: candidate.event) }
        )
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(candidates) { candidate in
                Circle()
                    .fill(candidate.id == normalizedSelectedID() ? AppTheme.colors.rose.opacity(0.58) : AppTheme.colors.rose.opacity(0.18))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedSelectedID() -> UUID? {
        if let selectedID, candidates.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return candidates.first?.id
    }

    private func normalizeSelection() {
        let normalized = normalizedSelectedID()
        selectedIDRawValue = ImportantDateCapsulePreferences.storageString(for: normalized)
    }

    private func countMode(for event: ImportantDate) -> ImportantDateCapsuleCountMode {
        let modes = ImportantDateCapsulePreferences.decodeCountModes(countModesRawValue)
        let stored = modes[event.id] ?? .next
        if stored == .elapsed, event.supportsElapsedDaysDisplay, event.showsElapsedDays {
            return .elapsed
        }
        return .next
    }

    private func toggleCountMode(for event: ImportantDate) {
        guard event.supportsElapsedDaysDisplay, event.showsElapsedDays else { return }
        HomeInteractionFeedback.selection()
        var modes = ImportantDateCapsulePreferences.decodeCountModes(countModesRawValue)
        modes[event.id] = countMode(for: event) == .next ? .elapsed : .next
        countModesRawValue = ImportantDateCapsulePreferences.encodeCountModes(modes)
    }
}
```

- [ ] **Step 2: Replace HomeView helper**

In `Together/Features/Home/HomeView.swift`, delete `nextAnniversaryEvent()` and add:

```swift
private var importantDateRecords: [ImportantDateStoredRecord] {
    appContext.importantDatesViewModel.storedRecords
}
```

- [ ] **Step 3: Replace each `AnniversaryCapsuleView` call site**

Replace each of the three existing `AnniversaryCapsuleView(...)` blocks in `HomeView` with:

```swift
ImportantDateCapsulePagerView(
    records: importantDateRecords,
    viewerSupabaseUserID: appContext.currentSupabaseUserID,
    partnerDisplayName: appContext.sessionStore.pairSpaceSummary?.partner?.displayName,
    onPrimaryTap: { isImportantDatesManagementPresented = true }
)
```

Keep the existing `if appContext.sessionStore.activeMode == .pair` guards and list row insets.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -100
```

Expected: build succeeds. If `TabView(selection:)` complains about optional selection, keep the binding as `Binding<UUID>` exactly as shown above.

- [ ] **Step 5: Commit Task 5 and Task 6 together**

```bash
git add Together/Features/Anniversaries/AnniversaryCapsuleView.swift \
        Together/Features/Anniversaries/ImportantDateCapsulePagerView.swift \
        Together/Features/Home/HomeView.swift
git commit -m "Add important date capsule pager"
```

## Task 7: Verification Pass

**Files:**
- Verify only unless tests expose defects.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:TogetherTests/ImportantDateCapsulePlannerTests \
  -only-testing:TogetherTests/ImportantDateCapsulePreferencesTests \
  -only-testing:TogetherTests/ImportantDatesViewModelCapsuleTests \
  -only-testing:TogetherTests/ImportantDateNextOccurrenceTests \
  -only-testing:TogetherTests/ImportantDatePullTests \
  -only-testing:TogetherTests/ImportantDatePushTests \
  -only-testing:TogetherTests/ImportantDateSyncDTOTests \
  2>&1 | tail -120
```

Expected: all selected tests pass.

- [ ] **Step 2: Run simulator build**

Run:

```bash
xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -120
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual simulator check**

Run the app on simulator, pair mode fixture or a real paired account, then verify:

- With only anniversary: one capsule, no page dots.
- Add birthday 8+ days away: capsule remains anniversary only.
- Add birthday within 7 days: dots appear and horizontal swipe reaches birthday.
- Birthday today: detail reads “今天”.
- Tap count text on anniversary: switches between “还有 N 天” and “已经 N 天”.
- Tap capsule title/icon/body: opens `ImportantDatesManagementSheet`.
- Dynamic Type large: count text remains readable and tappable; title truncates before count overlaps.

- [ ] **Step 4: Run diff hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors. Status includes only intended source and test files.

- [ ] **Step 5: Final commit if verification required fixes**

If Task 7 required fixes, commit them:

```bash
git add Together TogetherTests
git commit -m "Verify important date capsule behavior"
```

If no fixes were required, do not create an empty commit.

## Self-Review

- Spec coverage:
  - Stable anniversary anchor: Task 2 planner tests and implementation.
  - 7-day pool and latest-added ordering: Task 2.
  - No backend schema change and no `ImportantDate` core field change: Task 1 uses projection, Task 7 verifies DTO tests.
  - Single-layer pager and light dots: Task 6.
  - Count text tap instead of long press: Task 5.
  - Adaptive touch region: Task 5 uses semantic buttons, padding, content shape, layout priority, and scaling.
  - Today handling despite strictly-after recurrence: Task 2 uses previous-day anchor and tests day-zero behavior.
- Placeholder scan: no placeholder markers remain.
- Type consistency:
  - `ImportantDateCapsuleCountMode` is introduced in Task 4 and consumed in Tasks 5-6.
  - `ImportantDateStoredRecord` is introduced in Task 1 and consumed in Tasks 2-6.
  - `ImportantDateCapsuleCandidate` is introduced in Task 2 and consumed in Task 6.
