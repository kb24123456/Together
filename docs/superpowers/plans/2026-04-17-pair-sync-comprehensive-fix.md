# Pair Sync Comprehensive Fix — Plan A (Data Correctness + Core Concurrency)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all P0/P1 sync bugs so that avatar, space name, and tasks (create / edit / complete / respond / archive / delete) reliably sync between the two paired devices without data loss, duplication, or stale overwrites.

**Architecture:** Supabase Postgres + Realtime remains authority for pair data; SwiftData holds local replica; a `PersistentSyncChange` queue mediates push. This plan closes 13 concrete breakages: DTO field gaps, `saveItem`/`deleteItem` not recording changes, hardcoded DTO fields destroying partner data, one-way unbind, tombstone-missing re-insert, concurrent push races, sending-state deadlock, memory-only `lastSyncedAt`, missing `updatedAt` conflict check, and Realtime echo.

**Tech Stack:** Swift 6 / SwiftData / Supabase Swift SDK 2.43 / Swift Testing (`@Test`, `#expect`) / Postgres migrations in `supabase/migrations/`.

**Out of scope (deferred to Plan B/C):** APNs JWT signing, avatar file upload to Supabase Storage, Anniversary repository implementation, nudge deep integration, invite code rate limiting, vector clock, lifecycle observers for background Realtime reconnection.

---

## File Structure

| File | Role |
|------|------|
| `supabase/migrations/003_sync_completeness.sql` | **New** — add missing columns to `tasks`, `project_subtasks`, `spaces`; enable RLS bits |
| `Together/Persistence/Models/PersistentItem.swift` | **Modify** — add `isLocallyDeleted` tombstone field + migration |
| `Together/Sync/SupabaseSyncService.swift` | **Modify** — extend TaskDTO, add conflict detection, push serialization, lastSyncedAt persistence, echo filter, startup recovery |
| `Together/Services/Items/LocalItemRepository.swift` | **Modify** — record sync change in `saveItem` and `deleteItem` |
| `Together/Services/Pairing/SupabaseInviteGateway.swift` | **Modify** — add `archiveSpace` method |
| `Together/Services/Pairing/CloudPairingService.swift` | **Modify** — call archiveSpace in `unbind`, pass real responder local ID via `space_members` |
| `Together/App/AppContext.swift` | **Modify** — call startup recovery on sync service |
| `TogetherTests/SyncInsertTests.swift` | **New** — DTO applyToLocal INSERT/UPDATE/tombstone tests |
| `TogetherTests/SyncConflictTests.swift` | **New** — updatedAt conflict detection tests |
| `TogetherTests/ItemRepositorySyncTests.swift` | **New** — saveItem/deleteItem recordLocalChange contract tests |

---

## Phase 1: Data Correctness (P0)

### Task 1: Supabase schema migration — add missing columns

**Files:**
- Create: `supabase/migrations/003_sync_completeness.sql`

**Background:** `tasks` table is missing `execution_role`, `response_history` (jsonb), `assignment_messages` (jsonb), `reminder_requested_at` (timestamptz), `location_text` (text). `project_subtasks` is missing `space_id` (required for RLS). `spaces` needs `archived_at` for soft-archive semantics.

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/003_sync_completeness.sql
-- Phase A — data correctness columns that pair sync requires

-- tasks: add local collaboration fields
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS execution_role text,
  ADD COLUMN IF NOT EXISTS response_history jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS assignment_messages jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reminder_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS location_text text,
  ADD COLUMN IF NOT EXISTS occurrence_completions jsonb;

-- spaces: support unbind semantics
ALTER TABLE spaces
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

-- project_subtasks: backfill space_id so RLS can filter
ALTER TABLE project_subtasks
  ADD COLUMN IF NOT EXISTS space_id uuid REFERENCES spaces ON DELETE CASCADE;

-- Backfill. Orphans (subtask without a project row) are deleted rather than blocking migration.
DELETE FROM project_subtasks WHERE project_id NOT IN (SELECT id FROM projects);

UPDATE project_subtasks s
SET space_id = p.space_id
FROM projects p
WHERE s.project_id = p.id AND s.space_id IS NULL;

ALTER TABLE project_subtasks ALTER COLUMN space_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_project_subtasks_space ON project_subtasks(space_id);

-- RLS tighten — subtasks enforce via space membership
DROP POLICY IF EXISTS "space members can read subtasks" ON project_subtasks;
CREATE POLICY "space members can read subtasks" ON project_subtasks
  FOR SELECT USING (is_space_member(space_id));

DROP POLICY IF EXISTS "space members can write subtasks" ON project_subtasks;
CREATE POLICY "space members can write subtasks" ON project_subtasks
  FOR ALL USING (is_space_member(space_id)) WITH CHECK (is_space_member(space_id));

-- space_members: let members exchange their local (app-side) UUID for partner identification
ALTER TABLE space_members
  ADD COLUMN IF NOT EXISTS local_user_id uuid;
```

- [ ] **Step 2: Apply the migration via Supabase MCP**

Run via Supabase MCP `apply_migration` with name `sync_completeness` and the SQL above.
Expected: success, 3 tables altered, 1 new policy.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/003_sync_completeness.sql
git commit -m "feat(supabase): add columns tasks/project_subtasks/spaces need for pair sync"
```

---

### Task 2: Add tombstone field to PersistentItem

**Files:**
- Modify: `Together/Persistence/Models/PersistentItem.swift`

**Background:** Current `deleteItem` hard-deletes the SwiftData record. After a delete, the next Realtime pull INSERTs the row again ("dead task walking"). Fix: introduce a local soft-delete flag that survives pull.

- [ ] **Step 1: Add the property and init parameter**

In `Together/Persistence/Models/PersistentItem.swift`:

At the bottom of the stored properties block (after `reminderRequestedAt`), add:

```swift
    var isLocallyDeleted: Bool = false
```

In the `init(...)` parameter list, after `reminderRequestedAt: Date? = nil`, add:

```swift
        isLocallyDeleted: Bool = false
```

In the init body, after `self.reminderRequestedAt = reminderRequestedAt`, add:

```swift
        self.isLocallyDeleted = isLocallyDeleted
```

- [ ] **Step 2: Update active-record fetch predicates**

In `Together/Services/Items/LocalItemRepository.swift`, find every `FetchDescriptor<PersistentItem>` used to populate user-visible lists. Grep for the helper:

```bash
grep -n "activeRecords\|fetchActiveItems\|archivedCompletedRecords" Together/Services/Items/LocalItemRepository.swift
```

For each predicate that today is like `$0.isArchived == false`, add `&& $0.isLocallyDeleted == false` so soft-deleted rows are never shown.

Example replacement inside `activeRecords(spaceID:context:)`:

```swift
let descriptor = FetchDescriptor<PersistentItem>(
    predicate: #Predicate<PersistentItem> {
        $0.spaceID == spaceID && $0.isArchived == false && $0.isLocallyDeleted == false
    },
    sortBy: [SortDescriptor(\PersistentItem.sortOrder, order: .forward)]
)
```

Do the same for archived/completed record predicates.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Together/Persistence/Models/PersistentItem.swift Together/Services/Items/LocalItemRepository.swift
git commit -m "feat(persistence): add isLocallyDeleted tombstone to PersistentItem"
```

---

### Task 3: Extend TaskDTO with missing fields

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

**Background:** DTO is missing 5 fields that exist in `PersistentItem` and 5 newly-added columns in Supabase. Also fixes hardcoded `isDeleted = false` and `occurrenceCompletions = nil` which destroy partner data on every push.

- [ ] **Step 1: Extend TaskDTO struct**

Find `struct TaskDTO: Codable, Sendable {` in `Together/Sync/SupabaseSyncService.swift`. Add these properties near their neighbors (keep alphabetical / logical grouping):

```swift
    var executionRole: String
    var responseHistory: String?   // jsonb text
    var assignmentMessages: String?
    var reminderRequestedAt: Date?
    var locationText: String?
```

Add the `CodingKeys` cases:

```swift
        case executionRole = "execution_role"
        case responseHistory = "response_history"
        case assignmentMessages = "assignment_messages"
        case reminderRequestedAt = "reminder_requested_at"
        case locationText = "location_text"
```

- [ ] **Step 2: Fix `init(from:spaceID:)` to populate them**

In `TaskDTO.init(from persistent:, spaceID:)`, replace the hardcoded `occurrenceCompletions = nil` line and append the new fields. The full updated init body (keep existing field assignments, just change the listed ones and add new):

```swift
        self.executionRole = persistent.executionRoleRawValue
        self.responseHistory = String(data: persistent.responseHistoryData, encoding: .utf8)
        self.assignmentMessages = String(data: persistent.assignmentMessagesData, encoding: .utf8)
        self.reminderRequestedAt = persistent.reminderRequestedAt
        self.locationText = persistent.locationText
        self.isDeleted = persistent.isLocallyDeleted       // was hardcoded false
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
        // Do NOT null-out occurrenceCompletions — preserve partner's progress.
        // PersistentItem has no direct storage; round-trip via repeatRuleData if needed.
        // For now: keep whatever is in Supabase untouched by NOT sending the field on upsert.
```

Now for `occurrenceCompletions`: because `PersistentItem` has no dedicated column, **remove the `occurrenceCompletions` line entirely from the init**. Instead, make the DTO property optional and never-set on write:

Change the struct property:

```swift
    var occurrenceCompletions: String?
```

And in the init, do not assign it (it stays nil). But nil will erase the column. Fix: use a custom `encode` that only encodes when `occurrenceCompletions != nil`:

Add at the bottom of the struct:

```swift
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spaceId, forKey: .spaceId)
        try c.encodeIfPresent(listId, forKey: .listId)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encode(creatorId, forKey: .creatorId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(assigneeMode, forKey: .assigneeMode)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(dueAt, forKey: .dueAt)
        try c.encode(hasExplicitTime, forKey: .hasExplicitTime)
        try c.encodeIfPresent(remindAt, forKey: .remindAt)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(isDraft, forKey: .isDraft)
        try c.encode(isReadByPartner, forKey: .isReadByPartner)
        try c.encodeIfPresent(readAt, forKey: .readAt)
        try c.encodeIfPresent(repeatRule, forKey: .repeatRule)
        // occurrenceCompletions intentionally skipped on encode to preserve server state
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(executionRole, forKey: .executionRole)
        try c.encodeIfPresent(responseHistory, forKey: .responseHistory)
        try c.encodeIfPresent(assignmentMessages, forKey: .assignmentMessages)
        try c.encodeIfPresent(reminderRequestedAt, forKey: .reminderRequestedAt)
        try c.encodeIfPresent(locationText, forKey: .locationText)
    }
```

- [ ] **Step 3: Update `applyToLocal` to persist the new fields**

In `TaskDTO.applyToLocal(context:)`, inside the `if let existing` UPDATE branch add **before** `if isDeleted { context.delete(existing) }`:

```swift
            existing.executionRoleRawValue = executionRole
            if let h = responseHistory, let d = h.data(using: .utf8) { existing.responseHistoryData = d }
            if let m = assignmentMessages, let d = m.data(using: .utf8) { existing.assignmentMessagesData = d }
            existing.reminderRequestedAt = reminderRequestedAt
            existing.locationText = locationText
            // Soft-delete semantics: mark local tombstone instead of hard delete
            if isDeleted {
                existing.isLocallyDeleted = true
            }
```

Replace `if isDeleted { context.delete(existing) }` with a no-op (we now just set the tombstone above).

In the `else if !isDeleted` INSERT branch, change hardcoded `executionRoleRawValue`, `assignmentStateRawValue`, `responseHistoryData`, `assignmentMessagesData`, and `locationText` to use DTO-provided values:

```swift
            let item = PersistentItem(
                id: id,
                spaceID: spaceId,
                listID: listId,
                projectID: projectId,
                creatorID: creatorId,
                title: title,
                notes: notes,
                locationText: locationText,
                executionRoleRawValue: executionRole,
                assigneeModeRawValue: assigneeMode,
                dueAt: dueAt,
                hasExplicitTime: hasExplicitTime,
                remindAt: remindAt,
                statusRawValue: status,
                assignmentStateRawValue: ItemStatus(rawValue: status)?.assignmentState.rawValue
                    ?? TaskAssignmentState.active.rawValue,
                latestResponseData: nil,
                responseHistoryData: responseHistory?.data(using: .utf8) ?? Data(),
                assignmentMessagesData: assignmentMessages?.data(using: .utf8) ?? Data(),
                lastActionByUserID: nil,
                lastActionAt: nil,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
                isPinned: isPinned,
                isDraft: isDraft,
                isArchived: isArchived,
                archivedAt: archivedAt,
                repeatRuleData: repeatRule?.data(using: .utf8),
                reminderRequestedAt: reminderRequestedAt,
                isLocallyDeleted: false
            )
            context.insert(item)
```

- [ ] **Step 4: Build and fix signatures**

Run: `xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:" | head -10`
Expected: zero errors. If `PersistentItem.init` signature fails, ensure `reminderRequestedAt:` and `isLocallyDeleted:` are listed and defaulted.

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "feat(sync): TaskDTO carries executionRole, responseHistory, messages, nudge, location"
```

---

### Task 4: Write DTO INSERT/UPDATE tombstone tests

**Files:**
- Create: `TogetherTests/SyncInsertTests.swift`

**Background:** Lock in behavior so we never regress the three-branch applyToLocal.

- [ ] **Step 1: Create the test file**

```swift
// TogetherTests/SyncInsertTests.swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SyncInsertTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PersistentItem.self, PersistentTaskList.self, PersistentProject.self, PersistentProjectSubtask.self, PersistentPeriodicTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func taskDTO_inserts_new_item_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let dto = makeTaskDTO(id: taskID, spaceID: spaceID, title: "买牛奶")
        dto.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "买牛奶")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func taskDTO_updates_existing_item() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let firstDTO = makeTaskDTO(id: taskID, spaceID: spaceID, title: "买牛奶")
        firstDTO.applyToLocal(context: context)
        try context.save()

        let secondDTO = makeTaskDTO(id: taskID, spaceID: spaceID, title: "买豆浆")
        secondDTO.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "买豆浆")
    }

    @Test func taskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let dto = makeTaskDTO(id: taskID, spaceID: spaceID, title: "买牛奶")
        dto.applyToLocal(context: context)
        try context.save()

        let deleteDTO = makeTaskDTO(id: taskID, spaceID: spaceID, title: "买牛奶", isDeleted: true)
        deleteDTO.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }

    @Test func taskDTO_does_not_reinsert_after_tombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        // simulate: partner created, local tombstoned, partner re-pushed the same record
        let dto = makeTaskDTO(id: taskID, spaceID: spaceID, title: "幽灵")
        dto.applyToLocal(context: context)
        try context.save()

        let tomb = makeTaskDTO(id: taskID, spaceID: spaceID, title: "幽灵", isDeleted: true)
        tomb.applyToLocal(context: context)
        try context.save()

        // Now partner re-sends as not-deleted (stale message). We must NOT resurrect.
        let revival = makeTaskDTO(id: taskID, spaceID: spaceID, title: "幽灵", isDeleted: false)
        revival.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true, "tombstoned item must stay tombstoned")
    }

    private func makeTaskDTO(
        id: UUID,
        spaceID: UUID,
        title: String,
        isDeleted: Bool = false
    ) -> TaskDTO {
        TaskDTO(
            id: id,
            spaceId: spaceID,
            listId: nil,
            projectId: nil,
            creatorId: UUID(),
            title: title,
            notes: nil,
            assigneeMode: "self",
            status: "inProgress",
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            isPinned: false,
            isDraft: false,
            isReadByPartner: false,
            readAt: nil,
            repeatRule: nil,
            occurrenceCompletions: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isArchived: false,
            archivedAt: nil,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? .now : nil,
            executionRole: "initiator",
            responseHistory: nil,
            assignmentMessages: nil,
            reminderRequestedAt: nil,
            locationText: nil
        )
    }
}
```

- [ ] **Step 2: Extend TaskDTO.applyToLocal to protect tombstone on stale inserts**

In `Together/Sync/SupabaseSyncService.swift`, `TaskDTO.applyToLocal(context:)`, the UPDATE branch already handles tombstone via `existing.isLocallyDeleted = true` when `isDeleted == true`. We need the INSERT branch to also not resurrect a tombstone, but by definition the record is absent there. The tombstone-protection is sufficient because if the record is tombstoned it IS present and takes the UPDATE branch. Verify by running the test.

- [ ] **Step 3: Run the tests**

Run: `xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/SyncInsertTests 2>&1 | tail -20`
Expected: 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add TogetherTests/SyncInsertTests.swift
git commit -m "test(sync): lock applyToLocal insert/update/tombstone contract"
```

---

### Task 5: `LocalItemRepository.saveItem` must record sync change

**Files:**
- Modify: `Together/Services/Items/LocalItemRepository.swift`
- Create: `TogetherTests/ItemRepositorySyncTests.swift`

**Background:** `saveItem` today just writes to SwiftData. Any code path not going through `HomeViewModel.emitSharedTaskMutation` silently fails to sync. Make the repository the single source of truth for "this task mutated, record it."

- [ ] **Step 0: Verify `SyncCoordinatorProtocol` shape**

Open `Together/Sync/LocalSyncCoordinator.swift` (or wherever the protocol lives — grep `protocol SyncCoordinatorProtocol`). The `SpyCoordinator` stub below implements the 5 methods we know about; **if the real protocol has additional methods**, add no-op implementations to the spy so it conforms. Common additions that may need stubs: `setOnChangeRecorded`, `setOnSharedChangeRecorded`.

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/ItemRepositorySyncTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

actor SpyCoordinator: SyncCoordinatorProtocol {
    var recorded: [SyncChange] = []
    func recordLocalChange(_ change: SyncChange) async { recorded.append(change) }
    func mutationLog(for spaceID: UUID) async -> [SyncMutationSnapshot] { [] }
    func syncState(for spaceID: UUID) async -> SyncState? { nil }
    func markConfirmed(recordIDs: [UUID]) async {}
    func markFailed(recordIDs: [UUID], error: String) async {}
}

@MainActor
struct ItemRepositorySyncTests {
    @Test func saveItem_records_upsert() async throws {
        let schema = Schema([PersistentItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        let item = Item(
            id: UUID(),
            spaceID: UUID(),
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: "测试",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .active,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil
        )
        _ = try await repo.saveItem(item)

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .task)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == item.id)
    }

    @Test func deleteItem_records_delete() async throws {
        let schema = Schema([PersistentItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let spy = SpyCoordinator()
        let repo = LocalItemRepository(container: container, syncCoordinator: spy)

        // seed one item
        let item = Item(
            id: UUID(), spaceID: UUID(), listID: nil, projectID: nil,
            creatorID: UUID(), title: "t", notes: nil, locationText: nil,
            executionRole: .initiator, assigneeMode: .self,
            dueAt: nil, hasExplicitTime: false, remindAt: nil,
            status: .inProgress, assignmentState: .active,
            latestResponse: nil, responseHistory: [], assignmentMessages: [],
            lastActionByUserID: nil, lastActionAt: nil,
            createdAt: .now, updatedAt: .now, completedAt: nil,
            isPinned: false, isDraft: false, isArchived: false, archivedAt: nil,
            repeatRule: nil
        )
        _ = try await repo.saveItem(item)
        try await repo.deleteItem(itemID: item.id)

        let recorded = await spy.recorded
        let deletes = recorded.filter { $0.operation == .delete }
        #expect(deletes.count == 1)
        #expect(deletes.first?.recordID == item.id)
    }
}
```

- [ ] **Step 2: Run the test to verify failure**

Run: `xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ItemRepositorySyncTests 2>&1 | tail -15`
Expected: FAIL — `#expect(recorded.count == 1)` should fail with 0 because `saveItem` never records.

- [ ] **Step 3: Add recordLocalChange to `saveItem`**

In `Together/Services/Items/LocalItemRepository.swift`, replace the `saveItem(_:)` body ending with:

```swift
        try context.save()
        if let record = try fetchRecord(itemID: item.id, context: context) {
            let hydrated = try hydratedItem(from: record, context: context)
            if let sid = record.spaceID {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .task, operation: .upsert, recordID: item.id, spaceID: sid)
                )
            }
            return hydrated
        }
        return savedItem
```

- [ ] **Step 4: Add recordLocalChange to `deleteItem`**

Replace `deleteItem(itemID:)` with:

```swift
    func deleteItem(itemID: UUID) async throws {
        let context = ModelContext(container)
        guard let record = try fetchRecord(itemID: itemID, context: context) else {
            throw RepositoryError.notFound
        }
        let spaceID = record.spaceID
        let occurrenceRecords = try fetchOccurrenceRecords(itemIDs: [itemID], context: context)
        for occurrenceRecord in occurrenceRecords {
            context.delete(occurrenceRecord)
        }
        record.isLocallyDeleted = true      // tombstone rather than hard delete so pull cannot resurrect
        record.updatedAt = .now
        try context.save()

        if let spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .task, operation: .delete, recordID: itemID, spaceID: spaceID)
            )
        }
    }
```

- [ ] **Step 5: Run the tests**

Run: `xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ItemRepositorySyncTests 2>&1 | tail -15`
Expected: 2 tests pass.

- [ ] **Step 6: Verify no double-recording path**

`HomeViewModel.emitSharedTaskMutation` still fires via `onSharedMutationRecorded`. Our `flushRecordedSharedMutation` now does `recordLocalChange + push`. Since the repository already recorded, the second call is a duplicate. Open `Together/App/AppContext.swift` and change `flushRecordedSharedMutation` to only trigger push (not re-record):

```swift
    func flushRecordedSharedMutation(_ change: SyncChange) async {
        // Repository already queued the change; we just ensure push is attempted.
        await supabaseSyncService?.push()
        await refreshSharedSyncStatusAsync()
    }
```

Note: `submitSharedMutation` (used for profile/avatar mutations that don't flow through repository) retains its `recordLocalChange + push` body.

- [ ] **Step 7: Build and commit**

Run: `xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

```bash
git add Together/Services/Items/LocalItemRepository.swift TogetherTests/ItemRepositorySyncTests.swift Together/App/AppContext.swift
git commit -m "fix(sync): saveItem/deleteItem record SyncChange; remove duplicate push path"
```

---

### Task 6: Filter out tombstoned items from all UI queries

**Files:**
- Modify: `Together/Services/Items/LocalItemRepository.swift`

**Background:** Step 2 of Task 2 only updated the *active* records helper. We must also exclude tombstones from archived/completed queries so the user doesn't see rows that came back because a stale DTO was applied before tombstone handling.

- [ ] **Step 1: Grep remaining predicates**

```bash
grep -n "FetchDescriptor<PersistentItem>" Together/Services/Items/LocalItemRepository.swift
```

- [ ] **Step 2: For every predicate not yet updated, append `&& $0.isLocallyDeleted == false`**

Locations to update: `archivedCompletedRecords`, `completedRecords`, pinned descriptors used in `saveItem` (pinned sort), any occurrence fetch.

For archivedCompletedRecords the predicate becomes:

```swift
#Predicate<PersistentItem> {
    $0.spaceID == spaceID && $0.isArchived == true && $0.isLocallyDeleted == false
}
```

- [ ] **Step 3: Build**

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Together/Services/Items/LocalItemRepository.swift
git commit -m "fix(repo): exclude tombstoned items from all fetch predicates"
```

---

### Task 7: `CloudPairingService.unbind` archives Supabase space

**Files:**
- Modify: `Together/Services/Pairing/SupabaseInviteGateway.swift`
- Modify: `Together/Services/Pairing/CloudPairingService.swift`

**Background:** Today `unbind` is local-only, leaving an active space on Supabase that partner still syncs to. Close the loop.

- [ ] **Step 1: Add `archiveSpace` and `leaveSpace` to gateway**

Append to `SupabaseInviteGateway.swift` before the closing brace:

```swift
    /// 将 space 归档（解绑时调用）
    func archiveSpace(spaceID: UUID) async throws {
        struct Body: Encodable {
            let status: String
            let archivedAt: String
            enum CodingKeys: String, CodingKey {
                case status
                case archivedAt = "archived_at"
            }
        }
        try await client.from("spaces")
            .update(Body(status: "archived", archivedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: spaceID.uuidString)
            .execute()
    }

    /// 从 space_members 删除自己（解绑另一端时触发 Realtime DELETE 事件）
    func leaveSpace(spaceID: UUID, userID: UUID) async throws {
        try await client.from("space_members")
            .delete()
            .eq("space_id", value: spaceID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }
```

- [ ] **Step 2: Wire into CloudPairingService.unbind**

Replace the existing `unbind` method in `CloudPairingService.swift`:

```swift
    func unbind(pairSpaceID: UUID, actorID: UUID) async throws -> PairingContext {
        // 1. Find the Supabase space UUID BEFORE local teardown destroys it
        let ctx = await localPairing.currentPairingContext(for: actorID)
        let supabaseSpaceID: UUID? = {
            guard let zone = ctx.pairSpaceSummary?.pairSpace.cloudKitZoneName else { return nil }
            return UUID(uuidString: zone)
        }()

        // 2. Tear down Supabase sync (stops realtime, flushes queues)
        await onPairSyncTeardown?(pairSpaceID)

        // 3. Archive space + leave, if we have the remote UUID and a logged-in user
        if let supabaseSpaceID, let myID = await supabaseAuth.currentUserID {
            do {
                try await inviteGateway.leaveSpace(spaceID: supabaseSpaceID, userID: myID)
                try await inviteGateway.archiveSpace(spaceID: supabaseSpaceID)
            } catch {
                // best-effort: local unbind still proceeds
            }
        }

        // 4. Local teardown (deletes shared data & pair membership)
        return try await localPairing.unbind(pairSpaceID: pairSpaceID, actorID: actorID)
    }
```

- [ ] **Step 3: Build**

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Together/Services/Pairing/SupabaseInviteGateway.swift Together/Services/Pairing/CloudPairingService.swift
git commit -m "fix(pairing): unbind archives Supabase space and leaves space_members"
```

---

## Phase 2: Concurrency & Stability (P1)

### Task 8: Serialize `push()` to prevent duplicate upserts

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

**Background:** `push()` is async-actor-isolated but suspends at every `await`, which lets a second caller read the same pending rows and double-upsert. Guard with an `isPushing` flag.

- [ ] **Step 1: Add the lock field**

In the private vars block of `SupabaseSyncService`:

```swift
    private var isPushing = false
    private var pushRequestedDuringFlight = false
```

- [ ] **Step 2: Wrap `push()`**

Replace the very first lines of `push()` with:

```swift
    func push() async {
        guard let spaceID else { return }

        // Serialization: only one push in flight; coalesce concurrent requests into one follow-up run
        if isPushing {
            pushRequestedDuringFlight = true
            return
        }
        isPushing = true
        defer {
            isPushing = false
            if pushRequestedDuringFlight {
                pushRequestedDuringFlight = false
                Task { [weak self] in await self?.push() }
            }
        }

        // ... rest of body unchanged ...
```

- [ ] **Step 3: Reset on teardown**

In `teardown()`:

```swift
        isPushing = false
        pushRequestedDuringFlight = false
```

- [ ] **Step 4: Build**

Expected: BUILD SUCCEEDED. Swift warns about `defer` capturing mutable state — reword if needed using explicit cleanup instead of defer:

```swift
        // If your Swift version complains about defer, inline the cleanup at each return point.
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "fix(sync): serialize push() via isPushing flag; coalesce concurrent requests"
```

---

### Task 9: Revive `sending`-state changes on startup

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Modify: `Together/App/AppContext.swift`

**Background:** If a push is interrupted mid-flight (process killed), affected `PersistentSyncChange` rows stay in `sending` forever. `push()` only picks up pending/failed. Add a one-shot recovery that re-queues stale sending rows.

- [ ] **Step 1: Add `resurrectStuckChanges` to SupabaseSyncService**

Add a new method on `SupabaseSyncService` above `push()`:

```swift
    /// Move any PersistentSyncChange left in .sending (from a previous process) back to .pending.
    func resurrectStuckChanges() async {
        guard let spaceID else { return }
        let sendingRaw = SyncMutationLifecycleState.sending.rawValue
        let pendingRaw = SyncMutationLifecycleState.pending.rawValue
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate {
                $0.spaceID == spaceID && $0.lifecycleStateRawValue == sendingRaw
            }
        )
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for change in stuck { change.lifecycleStateRawValue = pendingRaw }
        try? context.save()
        logger.info("[Recovery] Revived \(stuck.count) stuck sending changes")
    }
```

- [ ] **Step 2: Call it from startListening before catchUp**

In `startListening()`, right after `isListening = true`:

```swift
        await resurrectStuckChanges()
        await push()     // attempt once before catchUp for low-latency recovery
```

- [ ] **Step 3: Build and commit**

Expected: BUILD SUCCEEDED

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "fix(sync): resurrect stuck sending changes on startup"
```

---

### Task 10: Persist `lastSyncedAt` per space

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

**Background:** Currently in-memory only. Restarts pull from `distantPast`, wasting 15–30s per startup and risking stale overwrite.

- [ ] **Step 1: Replace the stored `lastSyncedAt` with UserDefaults-backed accessor**

Replace `private var lastSyncedAt: Date?` with computed accessors:

```swift
    private var lastSyncedAt: Date? {
        get {
            guard let spaceID else { return nil }
            return UserDefaults.standard.object(forKey: lastSyncedKey(spaceID)) as? Date
        }
        set {
            guard let spaceID else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lastSyncedKey(spaceID))
            } else {
                UserDefaults.standard.removeObject(forKey: lastSyncedKey(spaceID))
            }
        }
    }

    private func lastSyncedKey(_ spaceID: UUID) -> String {
        "together.supabase.lastSyncedAt.\(spaceID.uuidString)"
    }
```

- [ ] **Step 2: Remove the `lastSyncedAt = nil` line in teardown**

`lastSyncedAt` is now persistent; we keep it across teardown so re-pair same space is incremental. Remove that line.

- [ ] **Step 3: Build and commit**

Expected: BUILD SUCCEEDED

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "fix(sync): persist lastSyncedAt per space in UserDefaults"
```

---

### Task 11: `updatedAt` conflict detection in applyToLocal

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/SyncConflictTests.swift`

**Background:** applyToLocal blindly overwrites even if incoming DTO is older than local record. Not full LWW — but we can at least honor incoming only if `updatedAt >= existing.updatedAt`.

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/SyncConflictTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SyncConflictTests {
    @Test func older_dto_does_not_overwrite_newer_local() throws {
        let schema = Schema([PersistentItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let taskID = UUID()
        let spaceID = UUID()
        let now = Date()
        let earlier = now.addingTimeInterval(-60)

        // seed local with "newer"
        let newerDTO = makeDTO(id: taskID, spaceID: spaceID, title: "newer", updatedAt: now)
        newerDTO.applyToLocal(context: context)
        try context.save()

        // attempt to apply an older DTO for the same row
        let olderDTO = makeDTO(id: taskID, spaceID: spaceID, title: "older", updatedAt: earlier)
        olderDTO.applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(fetched.first?.title == "newer")
    }

    private func makeDTO(id: UUID, spaceID: UUID, title: String, updatedAt: Date) -> TaskDTO {
        TaskDTO(
            id: id, spaceId: spaceID, listId: nil, projectId: nil,
            creatorId: UUID(), title: title, notes: nil,
            assigneeMode: "self", status: "inProgress",
            dueAt: nil, hasExplicitTime: false, remindAt: nil,
            isPinned: false, isDraft: false, isReadByPartner: false, readAt: nil,
            repeatRule: nil, occurrenceCompletions: nil,
            createdAt: updatedAt, updatedAt: updatedAt,
            completedAt: nil, isArchived: false, archivedAt: nil,
            isDeleted: false, deletedAt: nil,
            executionRole: "initiator", responseHistory: nil,
            assignmentMessages: nil, reminderRequestedAt: nil, locationText: nil
        )
    }
}
```

- [ ] **Step 2: Run — expected to fail**

Run: `xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/SyncConflictTests 2>&1 | tail -10`
Expected: FAIL — title becomes "older".

- [ ] **Step 3: Guard the UPDATE branch in TaskDTO**

In TaskDTO.applyToLocal, the UPDATE branch becomes:

```swift
        if let existing = try? context.fetch(descriptor).first {
            // Conflict guard: only apply if incoming is at least as fresh as local.
            if updatedAt < existing.updatedAt {
                return
            }
            // ... rest of UPDATE body unchanged ...
```

- [ ] **Step 3a: Apply the exact same guard to TaskListDTO.applyToLocal**

First line inside `if let existing`:

```swift
            if updatedAt < existing.updatedAt { return }
```

- [ ] **Step 3b: Apply the same guard to ProjectDTO.applyToLocal**

Same pattern — insert `if updatedAt < existing.updatedAt { return }` as the first line inside the `if let existing` branch.

- [ ] **Step 3c: Apply the same guard to ProjectSubtaskDTO.applyToLocal**

Same pattern.

- [ ] **Step 3d: Apply the same guard to PeriodicTaskDTO.applyToLocal**

Same pattern.

- [ ] **Step 4: Rerun tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift TogetherTests/SyncConflictTests.swift
git commit -m "fix(sync): applyToLocal refuses stale updates via updatedAt guard"
```

---

### Task 12: Realtime echo filter

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

**Background:** A's own push round-trips through Realtime and triggers a catchUp that wastes bandwidth and can race with local pending changes.

- [ ] **Step 1: Track recently-pushed record IDs**

Add to the private state:

```swift
    private var recentlyPushedIDs: [UUID: Date] = [:]
    private let echoWindow: TimeInterval = 10
```

- [ ] **Step 2: Record on successful push**

In `push()`, right after `change.confirmedAt = Date()` and the successful save:

```swift
                recentlyPushedIDs[change.recordID] = Date()
```

Also add a cleanup helper and call it at the end of push:

```swift
    private func pruneEchoWindow() {
        let cutoff = Date().addingTimeInterval(-echoWindow)
        recentlyPushedIDs = recentlyPushedIDs.filter { $0.value > cutoff }
    }
```

Call `pruneEchoWindow()` at end of push.

- [ ] **Step 3: Short-circuit echo in handleRealtimeChange**

Rewrite:

```swift
    private func handleRealtimeChange(_ change: AnyAction, table: String) async {
        // Extract record id from payload if possible; if we recently pushed it, skip catchUp.
        let recordID: UUID? = extractRecordID(from: change)
        if let id = recordID, let pushedAt = recentlyPushedIDs[id],
           Date().timeIntervalSince(pushedAt) < echoWindow {
            return
        }
        await catchUp()
        lastSyncedAt = Date()
        await MainActor.run {
            NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
        }
    }

    private func extractRecordID(from change: AnyAction) -> UUID? {
        switch change {
        case .insert(let action):
            return (action.record["id"]?.stringValue).flatMap(UUID.init)
        case .update(let action):
            return (action.record["id"]?.stringValue).flatMap(UUID.init)
        case .delete(let action):
            return (action.oldRecord["id"]?.stringValue).flatMap(UUID.init)
        }
    }
```

If the Supabase SDK's `AnyAction` associated payload type differs (e.g. `AnyJSON`), adapt the accessor to match the SDK. Verify with:

```bash
grep -r "struct InsertAction\|struct UpdateAction" ~/Library/Developer/Xcode/DerivedData -path "*supabase-swift*" | head -5
```

- [ ] **Step 4: Build and commit**

Expected: BUILD SUCCEEDED

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "feat(sync): filter self-originated Realtime events via recentlyPushedIDs"
```

---

## Phase 3: Verification

### Task 13: Manual end-to-end verification checklist

**Files:** none — runbook only.

- [ ] **Step 1: Prepare clean state**

Uninstall Together from both devices (iPhone + iPad). Launch fresh; sign in with SIWA on each.

- [ ] **Step 2: Pair**

On iPhone generate invite → on iPad accept → confirm pair flow completes. Note the Supabase space UUID from log `[Realtime] ✅ 已订阅 space: XXXXX`.

- [ ] **Step 3: Task lifecycle matrix**

Execute on iPhone, confirm on iPad:

| Action (iPhone) | Expected on iPad |
|---|---|
| Create "买牛奶" | Task appears within ~3s |
| Edit title to "买豆浆" | Title updates |
| Set dueAt to tomorrow | Due date changes |
| Mark completed | Moves to completed list |
| Un-complete | Returns to active |
| Archive | Moves to archived |
| Delete (swipe) | Disappears |

Reverse direction (iPad → iPhone) with a fresh task — confirm symmetric behavior.

- [ ] **Step 4: Collaboration matrix**

| Action | Expected |
|---|---|
| iPhone assigns task to partner (assigneeMode = partner) | iPad sees it with correct role |
| iPad responds "willing" | iPhone sees status flip to inProgress + response recorded |
| iPad writes a message | iPhone sees message |

- [ ] **Step 5: Space/profile**

| Action | Expected |
|---|---|
| iPhone renames space to "我们的窝" | iPad shows new name |
| iPhone changes nickname | iPad shows new nickname |

- [ ] **Step 6: Unbind**

On iPhone → Settings → Unbind. Verify:
- iPhone returns to single-trial state
- Supabase console: `spaces.status = archived`, iPhone's `space_members` row deleted
- iPad within ~5s receives DELETE event and transitions out of pair state (this may require Plan C lifecycle observers for full reliability; acceptable if iPad shows stale pair until manual refresh — log for Plan C follow-up)

- [ ] **Step 7: Concurrency probe**

On both devices simultaneously:
1. Tap same task, edit title to different values, save within 1 second of each other
2. Verify LWW by updatedAt: the later save wins on both devices after sync

- [ ] **Step 8: Kill-restart probe**

On iPhone: create a task → immediately force-quit app → relaunch.
Expected: `[Recovery] Revived N stuck sending changes` appears, task eventually arrives on iPad.

- [ ] **Step 9: Document any failures**

If any matrix row fails, open an issue titled `pair-sync regression: <row>` and attach iPhone + iPad logs; do not proceed to Plan B until all rows pass.

- [ ] **Step 10: Final commit marker**

```bash
git commit --allow-empty -m "chore: Plan A pair-sync comprehensive fix — manual verification passed"
```

---

## Verification

**Automated:**
- `xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/SyncInsertTests -only-testing:TogetherTests/SyncConflictTests -only-testing:TogetherTests/ItemRepositorySyncTests`
- Expected: all green.

**Manual:** Task 13 checklist above, executed on two physical devices (or two simulators in separate SIWA sessions).

**Schema:** After migration 003 applies, query Supabase dashboard:
- `\d tasks` shows execution_role, response_history, assignment_messages, reminder_requested_at, location_text, occurrence_completions columns.
- `\d project_subtasks` shows space_id NOT NULL with index.
- `\d spaces` shows archived_at.

---

## Follow-up plans required

- **Plan B — missing features**: Anniversary repository (replace MockAnniversaryRepository), APNs JWT signing in `send-push-notification` Edge Function, Supabase Storage upload for avatar files (currently only URL string syncs), task_messages push/pull wiring, invite code rate limiting + 8-digit or signed-URL format.
- **Plan C — robustness**: vector clock / device-id tiebreaker for LWW, `UIScene` foreground/background observers to unsub/resub Realtime, `NWPathMonitor` to auto-retry push on connection restore, partner's real local UUID exchange via `space_members.local_user_id` column (schema added in Task 1, wiring deferred).
