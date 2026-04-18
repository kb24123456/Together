# Partner Nudge Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the end-to-end "提醒" (formerly "催一下") APNs notification flow from the approved spec so a partner receives a banner in all 4 app states (foreground / background / locked / killed) with an actionable "完成" button.

**Architecture:** Dual-write model: client records `task_messages(type='nudge')` INSERT + bumps `tasks.reminder_requested_at` (fallback cache). Supabase Database Webhook forwards the INSERT to the existing `send-push-notification` Edge Function, which signs a JWT (ES256, `@panva/jose`) and HTTP/2 POSTs to `api.sandbox.push.apple.com`. APNs payload carries `category: TASK_NUDGE` + `task_id` for actionable responses. Permission prompted once on first successful pair join. 4xx/410 responses clean up stale device tokens; all other failures are silently tolerated with `reminder_requested_at`-driven in-UI fallback.

**Tech Stack:** Swift 6 / SwiftData / Supabase swift SDK / Deno Edge Functions / `@panva/jose` for JWT signing / APNs HTTP/2 API / Swift Testing for unit tests / MCP (`apply_migration`, `execute_sql`, `deploy_edge_function`).

**Spec:** `docs/superpowers/specs/2026-04-19-partner-nudge-notification-design.md`

---

## Pre-flight baseline

Work lands on `main` (repo working model). Create a feature branch:

```bash
cd /Users/papertiger/Desktop/Together
git checkout main
git pull --ff-only origin main
git checkout -b feat/partner-nudge-notification
```

All commits below land on this branch; merge ff + push at the end (Task 15).

---

## File map

### Modified
- `Together/Sync/SyncCoordinatorProtocol.swift` — add `.taskMessage` to `SyncEntityKind`
- `Together/Sync/SupabaseSyncService.swift` — add `TaskMessagePushDTO`, `pushUpsert` case, `supabaseTableName` mapping
- `Together/App/AppContext.swift` — handleNotificationResponse branch for `TASK_NUDGE`; remove `reloadAfterSync` nudge banner block; new `completeTaskFromNotification` + `openTaskFromNotification`; pending deep-link plumbing
- `Together/App/AppNotificationDelegate.swift` (current file fine) — no change; existing delegate routes to `AppContext.handleNotificationResponse`
- `Together/App/NotificationActionCatalog.swift` — add `TASK_NUDGE` category with `COMPLETE_NUDGE` action
- `Together/App/AppDelegate.swift` — read `launchOptions[.remoteNotification]` in `didFinishLaunchingWithOptions` and forward to bootstrapper / AppContext pending slot
- `Together/Services/Pairing/CloudPairingService.swift` — fire pair-join observer after `acceptInviteByCode` / `joinSpace` success
- `Together/Services/LocalServiceFactory.swift` — wire `PairJoinObserver` that requests notification authorization
- `Together/App/AppContext.swift` (again) — subscribe the pair-join observer to call `notificationService.requestAuthorization` when status `.notDetermined`
- `Together/Features/Home/HomeViewModel.swift` — button already wired to `sendReminderToPartner`; confirm emit path; rename visible copy
- `Together/Features/Home/HomeView.swift:2487` — `Text("催一下")` → `Text("提醒")`; add subtle row tint or 🔔 indicator when nudged
- `Together/Application/Tasks/DefaultTaskApplicationService.swift:429-456` — `sendReminderToPartner` extended to also insert `PersistentTaskMessage` + record `.taskMessage` change
- `Together/Application/Tasks/TaskApplicationServiceProtocol.swift` — no signature change if new work flows through existing method
- `Together/App/AppContainer.swift` — add `taskMessageRepository: TaskMessageRepositoryProtocol`
- `supabase/functions/send-push-notification/index.ts` — replace `sendAPNs` TODO with real JWT + HTTP/2; rename buildNotification nudge copy "催一下" → "提醒"

### Created
- `Together/Persistence/Models/PersistentTaskMessage.swift`
- `Together/Services/TaskMessages/LocalTaskMessageRepository.swift`
- `Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift`
- `Together/Domain/Models/TaskMessage.swift` (minimal domain struct: id, taskID, senderID, type, createdAt)
- `TogetherTests/TaskMessageRepositoryTests.swift` — insertNudge saves + returns
- `TogetherTests/SendReminderToPartnerTests.swift` — sendReminderToPartner records 2 SyncChanges (task.upsert + taskMessage.upsert)
- `TogetherTests/TaskMessagePushDTOTests.swift` — DTO encodes to correct JSON keys
- `supabase/migrations/009_add_rls_policy_task_messages_insert.sql`

### Unchanged (relevant references)
- `Together/Services/Push/DeviceTokenService.swift` — already writes to Supabase `device_tokens`
- `Together/App/AppDelegate.swift:25` — already calls `registerForRemoteNotifications()`
- `Together/Together.entitlements` — already has `aps-environment = development`
- Supabase Secrets — already set: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`
- `device_tokens` table — schema already correct, has 7 rows

### Manual (dashboard / non-code)
- Supabase Dashboard → Database → Webhooks — create one webhook pointing to `send-push-notification` (Task 10)
- No APNs credential work — already done earlier

---

## Conventions applied across all tasks

1. **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Mirror `TogetherTests/ItemRepositorySyncTests.swift` pattern.
2. **In-memory `ModelContainer` lists all 16 models** (the 15 existing + the new `PersistentTaskMessage`). Every new test file's `makeContainer()` must include `PersistentTaskMessage.self`.
3. **`SpyCoordinator`** already in `TogetherTests/ItemRepositorySyncTests.swift:8-35` — cross-file reference, do NOT redefine.
4. **`NoopReminderScheduler`** already in `TogetherTests/ProjectSubtaskRepositorySyncTests.swift:8-18` — cross-file reference, do NOT redefine.
5. **No `print` — use `os.Logger`** when needed (existing pattern: `Logger(subsystem: "com.pigdog.Together", category: "<feature>")`).
6. **No `// TODO`** or "后续完善" comments — if blocked, stop and ask.
7. **Default values on new `@Model` fields** (not applicable here since `PersistentTaskMessage` is brand new; but if later tasks add fields to existing models they need `= default`).
8. **Commit message format**: conventional (`feat(sync): ...`, `fix(...)`, `test(...)`, `chore(migrations): ...`), ending with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
9. Each Task has its own commit at the end.

---

## Task 1: Migration 009 — RLS INSERT policy on `task_messages`

**Files:**
- Create: `supabase/migrations/009_add_rls_policy_task_messages_insert.sql`

- [ ] **Step 1: Verify current state via MCP**

Run via Supabase MCP `execute_sql`:
```sql
SELECT policyname, cmd FROM pg_policies WHERE tablename='task_messages';
```
Expected: empty result (no policies currently).

```sql
SELECT rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename='task_messages';
```
Expected: `t` (RLS enabled, no policies → all anon access denied).

- [ ] **Step 2: Apply migration via MCP `apply_migration`**

```
apply_migration(
  project_id="nxielmwdoiwiwhzczrmt",
  name="add_rls_policy_task_messages_insert",
  query="CREATE POLICY \"space members can insert task messages\" ON task_messages
         FOR INSERT WITH CHECK (
           EXISTS (
             SELECT 1 FROM tasks
             WHERE tasks.id = task_messages.task_id
               AND is_space_member(tasks.space_id)
           )
         );"
)
```
Expected: `{success: true}`.

- [ ] **Step 3: Verify via MCP**

```sql
SELECT policyname, cmd FROM pg_policies WHERE tablename='task_messages';
```
Expected: one row, `policyname='space members can insert task messages'`, `cmd='INSERT'`.

- [ ] **Step 4: Write SQL file for git**

Create `supabase/migrations/009_add_rls_policy_task_messages_insert.sql`:

```sql
-- =============================================================
-- Migration 009: add_rls_policy_task_messages_insert
--
-- task_messages has RLS enabled but zero policies (deny-all for anon).
-- Partner nudge feature needs clients to INSERT rows of type='nudge'.
-- Add an INSERT policy gated on the actor being a member of the
-- parent task's space (via tasks.space_id).
--
-- No SELECT policy added — partner device does not pull task_messages
-- in MVP (APNs is the delivery channel).
-- =============================================================

CREATE POLICY "space members can insert task messages" ON task_messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM tasks
      WHERE tasks.id = task_messages.task_id
        AND is_space_member(tasks.space_id)
    )
  );
```

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/009_add_rls_policy_task_messages_insert.sql
git commit -m "$(cat <<'EOF'
chore(migrations): add RLS INSERT policy on task_messages

Partner nudge feature requires clients to INSERT task_messages rows of
type='nudge'. Table had rowsecurity=true but zero policies → all anon
writes denied. Policy allows INSERT when the actor is a space member
of the parent task (via tasks.space_id → is_space_member). No SELECT
policy in MVP — partner device does not pull task_messages history.

Already applied to prod via MCP apply_migration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Domain model + persistent schema for `TaskMessage`

**Files:**
- Create: `Together/Domain/Models/TaskMessage.swift`
- Create: `Together/Persistence/Models/PersistentTaskMessage.swift`
- Modify: wherever the 15-model schema list is registered (`PersistenceController`). Add `PersistentTaskMessage.self`.

- [ ] **Step 1: Find the ModelContainer schema registration site**

```bash
grep -rn "PersistentPeriodicTask.self\|ModelContainer(for:" Together --include="*.swift" | grep -v Tests
```
Expected: a file like `Together/Persistence/PersistenceController.swift` listing all 15 Persistent* models.

- [ ] **Step 2: Create `TaskMessage` domain struct**

Create `Together/Domain/Models/TaskMessage.swift`:

```swift
import Foundation

struct TaskMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID
    let senderID: UUID
    let type: String  // "nudge" for now; "comment" / "rps_result" reserved
    let createdAt: Date
}
```

- [ ] **Step 3: Create `PersistentTaskMessage` model**

Create `Together/Persistence/Models/PersistentTaskMessage.swift`:

```swift
import Foundation
import SwiftData

@Model
final class PersistentTaskMessage {
    var id: UUID
    var taskID: UUID
    var senderID: UUID
    var type: String
    var createdAt: Date

    init(
        id: UUID,
        taskID: UUID,
        senderID: UUID,
        type: String,
        createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.senderID = senderID
        self.type = type
        self.createdAt = createdAt
    }
}

extension PersistentTaskMessage {
    convenience init(message: TaskMessage) {
        self.init(
            id: message.id,
            taskID: message.taskID,
            senderID: message.senderID,
            type: message.type,
            createdAt: message.createdAt
        )
    }

    func domainModel() -> TaskMessage {
        TaskMessage(
            id: id,
            taskID: taskID,
            senderID: senderID,
            type: type,
            createdAt: createdAt
        )
    }
}
```

- [ ] **Step 4: Register `PersistentTaskMessage.self` in schema**

Find the `ModelContainer(for:` list in `PersistenceController.swift` (or wherever Step 1 located it). Add `PersistentTaskMessage.self` to the comma-separated list. The schema now has 16 models.

- [ ] **Step 5: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Together/Domain/Models/TaskMessage.swift \
        Together/Persistence/Models/PersistentTaskMessage.swift \
        Together/Persistence/PersistenceController.swift
git commit -m "$(cat <<'EOF'
feat(persistence): add TaskMessage domain + PersistentTaskMessage model

Event-log entity backing the partner nudge feature. Insert-only in MVP
(no tombstone, no update). Registered in ModelContainer schema list
alongside the existing 15 Persistent* models.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `TaskMessageRepositoryProtocol` + `LocalTaskMessageRepository` + test

**Files:**
- Create: `Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift`
- Create: `Together/Services/TaskMessages/LocalTaskMessageRepository.swift`
- Create: `TogetherTests/TaskMessageRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/TaskMessageRepositoryTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct TaskMessageRepositoryTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            configurations: config
        )
    }

    @Test func insertNudge_persistsRowWithTypeNudge() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)

        let messageID = UUID()
        let taskID = UUID()
        let senderID = UUID()
        let createdAt = Date()

        try await repo.insertNudge(
            messageID: messageID,
            taskID: taskID,
            senderID: senderID,
            createdAt: createdAt
        )

        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == messageID)
        #expect(fetched.first?.taskID == taskID)
        #expect(fetched.first?.senderID == senderID)
        #expect(fetched.first?.type == "nudge")
    }

    @Test func fetchMessage_returnsInsertedRow() async throws {
        let container = try makeContainer()
        let repo = LocalTaskMessageRepository(container: container)

        let messageID = UUID()
        try await repo.insertNudge(
            messageID: messageID,
            taskID: UUID(),
            senderID: UUID(),
            createdAt: Date()
        )

        let fetched = try await repo.fetchMessage(messageID: messageID)
        #expect(fetched?.id == messageID)
        #expect(fetched?.type == "nudge")
    }
}
```

- [ ] **Step 2: Run test — expected FAIL (Repository doesn't exist yet)**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/TaskMessageRepositoryTests 2>&1 | grep -E "error:|Test case" | tail -5
```
Expected: build error "cannot find LocalTaskMessageRepository" (or similar).

- [ ] **Step 3: Create the protocol**

Create `Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift`:

```swift
import Foundation

protocol TaskMessageRepositoryProtocol: Sendable {
    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws

    func fetchMessage(messageID: UUID) async throws -> TaskMessage?
}
```

- [ ] **Step 4: Create `LocalTaskMessageRepository`**

Create `Together/Services/TaskMessages/LocalTaskMessageRepository.swift`:

```swift
import Foundation
import SwiftData

actor LocalTaskMessageRepository: TaskMessageRepositoryProtocol {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws {
        let context = ModelContext(container)
        context.insert(
            PersistentTaskMessage(
                id: messageID,
                taskID: taskID,
                senderID: senderID,
                type: "nudge",
                createdAt: createdAt
            )
        )
        try context.save()
    }

    func fetchMessage(messageID: UUID) async throws -> TaskMessage? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate<PersistentTaskMessage> { $0.id == messageID }
        )
        return try context.fetch(descriptor).first?.domainModel()
    }
}
```

- [ ] **Step 5: Run tests — expected PASS (2 tests)**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/TaskMessageRepositoryTests 2>&1 | grep -E "Test case|TEST SUCC|TEST FAIL" | tail -5
```
Expected: 2 passed, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift \
        Together/Services/TaskMessages/LocalTaskMessageRepository.swift \
        TogetherTests/TaskMessageRepositoryTests.swift
git commit -m "$(cat <<'EOF'
feat(repo): LocalTaskMessageRepository with insertNudge + fetchMessage

Insert-only repository for the nudge event log. 2 passing tests verify
PersistentTaskMessage row is created with type='nudge' and fetchable by
messageID.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `SyncEntityKind.taskMessage` + Supabase table name mapping

**Files:**
- Modify: `Together/Sync/SyncCoordinatorProtocol.swift` (add `.taskMessage` case + CKRecord type mapping OR N/A)
- Modify: `Together/Sync/SupabaseSyncService.swift:665-678` (`supabaseTableName` extension)

- [ ] **Step 1: Add `.taskMessage` to `SyncEntityKind`**

Edit `Together/Sync/SyncCoordinatorProtocol.swift:3-12` to add `.taskMessage`:

```swift
enum SyncEntityKind: String, Codable, Hashable, Sendable {
    case task
    case taskList
    case project
    case projectSubtask
    case periodicTask
    case space
    case memberProfile
    case avatarAsset
    case taskMessage   // New — push-only event log entity
    // ...
```

And in `ckRecordType` computed property:
```swift
case .taskMessage: return "TaskMessage"  // inert; no CloudKit codec planned
```

And in `init?(ckRecordType:)` — add a mapping case to keep the round-trip symmetric even though we don't route taskMessage through CKSyncEngine:
```swift
case "TaskMessage":
    self = .taskMessage
```

- [ ] **Step 2: Add `taskMessage` table name**

Edit `Together/Sync/SupabaseSyncService.swift:665-678` extension:

```swift
extension SyncEntityKind {
    nonisolated var supabaseTableName: String {
        switch self {
        case .task: return "tasks"
        case .taskList: return "task_lists"
        case .project: return "projects"
        case .projectSubtask: return "project_subtasks"
        case .periodicTask: return "periodic_tasks"
        case .space: return "spaces"
        case .memberProfile: return "space_members"
        case .avatarAsset: return "avatars"
        case .taskMessage: return "task_messages"
        }
    }
}
```

- [ ] **Step 3: Build — expect compile errors where switch over `SyncEntityKind` is now non-exhaustive**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:" | head -10
```
Expected: errors on switch statements that miss `.taskMessage`. Common sites:
- `SupabaseSyncService.swift` `pushUpsert` switch (around line 311-377) — will need explicit `.taskMessage` case in Task 5
- CKSyncEngine routing code may need a `.taskMessage: return .ignored` equivalent

- [ ] **Step 4: Add minimal "ignored by CloudKit" handling**

For any `SyncEntityKind` switch in CloudKit-related code (SyncEngineCoordinator, CKSync codecs), add:
```swift
case .taskMessage:
    break  // Not synced via CloudKit solo zone; Supabase-only event log
```

Grep for non-exhaustive sites:
```bash
grep -rn "switch.*entityKind\|switch.*kind:.*SyncEntityKind" Together --include="*.swift" | head -10
```

Fix each by adding a `.taskMessage: break` or `.taskMessage: fatalError("...not routed via ...")` as semantically appropriate.

- [ ] **Step 5: pushUpsert placeholder case (will be filled in Task 5)**

In `SupabaseSyncService.swift` pushUpsert, add for now:
```swift
case .taskMessage:
    break   // Real implementation in Task 5
```

- [ ] **Step 6: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Together/Sync/SyncCoordinatorProtocol.swift \
        Together/Sync/SupabaseSyncService.swift \
        Together/Sync/*.swift
git commit -m "$(cat <<'EOF'
feat(sync): add SyncEntityKind.taskMessage case + table mapping

Opens the new routing slot for partner-nudge events without wiring
the actual push payload yet (follows in next commit). Also updates
any non-exhaustive switches to explicitly ignore .taskMessage in
CloudKit paths (taskMessage is Supabase-only).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `TaskMessagePushDTO` + `pushUpsert` case `.taskMessage` + test

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift` (add DTO struct + pushUpsert case)
- Create: `TogetherTests/TaskMessagePushDTOTests.swift`

- [ ] **Step 1: Write the DTO encoding test**

Create `TogetherTests/TaskMessagePushDTOTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@MainActor
struct TaskMessagePushDTOTests {
    @Test func encode_producesSnakeCaseKeys() throws {
        let dto = TaskMessagePushDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            taskId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            senderId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            type: "nudge",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"id\":\"11111111-1111-1111-1111-111111111111\""))
        #expect(json.contains("\"task_id\":\"22222222-2222-2222-2222-222222222222\""))
        #expect(json.contains("\"sender_id\":\"33333333-3333-3333-3333-333333333333\""))
        #expect(json.contains("\"type\":\"nudge\""))
        #expect(json.contains("\"created_at\":"))
    }
}
```

- [ ] **Step 2: Run — expected FAIL (TaskMessagePushDTO doesn't exist)**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/TaskMessagePushDTOTests 2>&1 | grep -E "error:" | head -3
```
Expected: "cannot find 'TaskMessagePushDTO' in scope".

- [ ] **Step 3: Add the DTO struct to `SupabaseSyncService.swift`**

At the end of `Together/Sync/SupabaseSyncService.swift` before the `// MARK: - SyncEntityKind Supabase 扩展` section (around line 663), add:

```swift
// MARK: - TaskMessage DTO (write-only)

/// Nudge / comment event pushed to the task_messages table.
/// Write-only for MVP — partner device does not pull this table; APNs is
/// the delivery channel. Keep Encodable-only to make that intent explicit.
struct TaskMessagePushDTO: Encodable, Sendable {
    let id: UUID
    let taskId: UUID
    let senderId: UUID
    let type: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type
        case taskId = "task_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }

    nonisolated init(from persistent: PersistentTaskMessage) {
        self.id = persistent.id
        self.taskId = persistent.taskID
        self.senderId = persistent.senderID
        self.type = persistent.type
        self.createdAt = persistent.createdAt
    }

    nonisolated init(id: UUID, taskId: UUID, senderId: UUID, type: String, createdAt: Date) {
        self.id = id
        self.taskId = taskId
        self.senderId = senderId
        self.type = type
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Replace the placeholder `case .taskMessage` in `pushUpsert`**

In `SupabaseSyncService.swift` `pushUpsert` (around the block that handles `.periodicTask` at line 346), add/replace the `.taskMessage` case:

```swift
case .taskMessage:
    let descriptor = FetchDescriptor<PersistentTaskMessage>(
        predicate: #Predicate { $0.id == recordID }
    )
    guard let message = try? context.fetch(descriptor).first else { return }
    let dto = TaskMessagePushDTO(from: message)
    try await client.from(tableName).insert(dto).execute()
```

Note: **insert, not upsert** — task_messages is an event log, each row has a unique id; we never re-insert the same event.

- [ ] **Step 5: Run tests + build**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/TaskMessagePushDTOTests 2>&1 | grep -E "Test case|TEST SUCC" | tail -3
```
Expected: 1 passed.

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift \
        TogetherTests/TaskMessagePushDTOTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): TaskMessagePushDTO + pushUpsert case .taskMessage (insert, not upsert)

Write-only Encodable DTO carrying id/task_id/sender_id/type/created_at
to task_messages table. pushUpsert routes .taskMessage to .insert()
rather than .upsert() because each row is an immutable event log
entry keyed by its own UUID; no re-insert semantics.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire `LocalTaskMessageRepository` into `AppContainer` + factory

**Files:**
- Modify: `Together/App/AppContainer.swift` — add `taskMessageRepository` property
- Modify: `Together/Services/LocalServiceFactory.swift` — inject the new repo

- [ ] **Step 1: Check current AppContainer signature**

```bash
grep -n "itemRepository\|taskTemplateRepository" Together/App/AppContainer.swift | head -5
```
Expected: lines showing how existing repos are declared (stored properties + init params).

- [ ] **Step 2: Add `taskMessageRepository` property**

Find where `itemRepository` is declared in `AppContainer.swift`. Add alongside:
```swift
let taskMessageRepository: TaskMessageRepositoryProtocol
```

Update the designated init params similarly.

- [ ] **Step 3: Inject in `LocalServiceFactory.swift`**

In `Together/Services/LocalServiceFactory.swift`, find where `itemRepository` is created, and add:
```swift
let taskMessageRepository = LocalTaskMessageRepository(container: modelContainer)
```

Pass it to `AppContainer(...)` init.

- [ ] **Step 4: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Together/App/AppContainer.swift Together/Services/LocalServiceFactory.swift
git commit -m "$(cat <<'EOF'
chore(di): wire LocalTaskMessageRepository into AppContainer

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Extend `sendReminderToPartner` to insert nudge + record 2 SyncChanges

**Files:**
- Modify: `Together/Application/Tasks/DefaultTaskApplicationService.swift:429-456`
- Modify: constructor to accept `taskMessageRepository`
- Create: `TogetherTests/SendReminderToPartnerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TogetherTests/SendReminderToPartnerTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct SendReminderToPartnerTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self,
            configurations: config
        )
    }

    private func makePartnerItem(spaceID: UUID, actorID: UUID) -> Item {
        Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "倒垃圾",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .partner,   // ← key: partner-mode task
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .inProgress,
            assignmentState: .pendingAcceptance,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil,
            occurrenceCompletions: [],
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRule: nil,
            reminderRequestedAt: nil
        )
    }

    @Test func sendReminder_recordsTaskUpsertAndTaskMessageUpsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let itemRepo = LocalItemRepository(container: container, syncCoordinator: spy)
        let messageRepo = LocalTaskMessageRepository(container: container)
        let scheduler = NoopReminderScheduler()
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepo,
            taskMessageRepository: messageRepo,
            syncCoordinator: spy,
            reminderScheduler: scheduler
        )

        let spaceID = UUID()
        let actorID = UUID()
        let item = makePartnerItem(spaceID: spaceID, actorID: actorID)
        _ = try await itemRepo.saveItem(item)

        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)

        let recorded = await spy.recorded
        let taskUpserts = recorded.filter { $0.entityKind == .task && $0.operation == .upsert && $0.recordID == item.id }
        let nudgeRecords = recorded.filter { $0.entityKind == .taskMessage && $0.operation == .upsert && $0.spaceID == spaceID }

        #expect(taskUpserts.count >= 1, "saveItem bumps reminder_requested_at → task .upsert recorded")
        #expect(nudgeRecords.count == 1, "exactly one task_message .upsert recorded")
    }

    @Test func sendReminder_withinCooldown_doesNotInsertSecondMessage() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let itemRepo = LocalItemRepository(container: container, syncCoordinator: spy)
        let messageRepo = LocalTaskMessageRepository(container: container)
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepo,
            taskMessageRepository: messageRepo,
            syncCoordinator: spy,
            reminderScheduler: NoopReminderScheduler()
        )

        let spaceID = UUID()
        let actorID = UUID()
        let item = makePartnerItem(spaceID: spaceID, actorID: actorID)
        _ = try await itemRepo.saveItem(item)

        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)
        _ = try await service.sendReminderToPartner(in: spaceID, taskID: item.id, actorID: actorID)

        let context = ModelContext(container)
        let messages = try context.fetch(FetchDescriptor<PersistentTaskMessage>())
        #expect(messages.count == 1, "second tap within 30s cooldown is a no-op")
    }
}
```

- [ ] **Step 2: Run — expected FAIL (DefaultTaskApplicationService signature mismatch)**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/SendReminderToPartnerTests 2>&1 | grep -E "error:" | head -5
```
Expected: compile error about unknown param `taskMessageRepository`.

- [ ] **Step 3: Add `taskMessageRepository` param to `DefaultTaskApplicationService`**

Edit `Together/Application/Tasks/DefaultTaskApplicationService.swift`:

```swift
actor DefaultTaskApplicationService: TaskApplicationServiceProtocol {
    private let itemRepository: ItemRepositoryProtocol
    private let taskMessageRepository: TaskMessageRepositoryProtocol  // new
    private let syncCoordinator: SyncCoordinatorProtocol
    private let reminderScheduler: ReminderSchedulerProtocol

    init(
        itemRepository: ItemRepositoryProtocol,
        taskMessageRepository: TaskMessageRepositoryProtocol,
        syncCoordinator: SyncCoordinatorProtocol,
        reminderScheduler: ReminderSchedulerProtocol
    ) {
        self.itemRepository = itemRepository
        self.taskMessageRepository = taskMessageRepository
        self.syncCoordinator = syncCoordinator
        self.reminderScheduler = reminderScheduler
    }
    // ... rest unchanged
```

- [ ] **Step 4: Extend `sendReminderToPartner`**

Replace lines 429-456 with:

```swift
func sendReminderToPartner(
    in spaceID: UUID,
    taskID: UUID,
    actorID: UUID
) async throws -> Item {
    var item = try await existingTask(in: spaceID, taskID: taskID)
    guard item.assigneeMode == .partner else { throw RepositoryError.notFound }

    // 30 秒冷却
    if let lastReminder = item.reminderRequestedAt,
       Date.now.timeIntervalSince(lastReminder) < 30 {
        return item
    }

    item.reminderRequestedAt = .now
    item.updatedAt = .now

    let saved = try await itemRepository.saveItem(item)
    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .task, operation: .upsert, recordID: saved.id, spaceID: spaceID)
    )

    // 新增：插入 task_messages 事件（push 触发 APNs）
    let messageID = UUID()
    try await taskMessageRepository.insertNudge(
        messageID: messageID,
        taskID: taskID,
        senderID: actorID,
        createdAt: Date.now
    )
    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .taskMessage, operation: .upsert, recordID: messageID, spaceID: spaceID)
    )

    return saved
}
```

- [ ] **Step 5: Update `LocalServiceFactory.swift` injection**

Find where `DefaultTaskApplicationService(...)` is constructed and add `taskMessageRepository: taskMessageRepository,` to the init call.

- [ ] **Step 6: Run tests — expected PASS (2)**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/SendReminderToPartnerTests 2>&1 | grep -E "Test case|TEST SUCC" | tail -3
```
Expected: 2 passed.

- [ ] **Step 7: Full regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Together/Application/Tasks/DefaultTaskApplicationService.swift \
        Together/Services/LocalServiceFactory.swift \
        TogetherTests/SendReminderToPartnerTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): sendReminderToPartner dual-writes task_messages + tasks

Partner nudge feature entry point. Insert a task_messages(type='nudge')
event row (APNs trigger source) while also bumping reminder_requested_at
on the parent task (foreground-fallback cache). Both SyncChanges queued
in one call; 30s cooldown prevents duplicate messages.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: UI copy rename "催一下" → "提醒" + remove duplicate banner path

**Files:**
- Modify: `Together/Features/Home/HomeView.swift:2487`
- Modify: `Together/App/AppContext.swift:399-408` (remove the schedule block)
- Grep and update: any remaining occurrences of "催一下" / "催你" / "对方催" visible to users

- [ ] **Step 1: Grep all occurrences**

```bash
grep -rn "催一下\|催你\|对方催" Together --include="*.swift"
```
Expected: a list (roughly 5-10 hits across HomeView + AppContext + any toasts).

- [ ] **Step 2: Edit HomeView button**

In `Together/Features/Home/HomeView.swift:2487`:
```swift
// Before
Text("催一下")
// After
Text("提醒")
```

- [ ] **Step 3: Edit AppContext local notification text + remove the block**

Edit `Together/App/AppContext.swift`. Replace lines 399-408 (the `for item in allItems { ... scheduleReminderNotification ... }` block):

```swift
// Remove the whole block — APNs now handles nudge banners. The
// foreground fallback uses in-UI indicators driven directly by
// item.reminderRequestedAt in HomeView (Task 14).
```

(Effectively: delete lines 399-408 inclusive.)

Keep `scheduleReminderNotification` method at line 412 — it may still be used by other code paths (due-date reminders, etc). Grep to confirm no other callers.

```bash
grep -n "scheduleReminderNotification" Together/App/AppContext.swift
```
If no other callers remain → also delete the method body. If present → leave it.

- [ ] **Step 4: Update any remaining "催" strings**

For each hit from Step 1 not yet addressed, replace:
- "催一下" → "提醒"
- "催你完成任务啦！" → N/A (the block was deleted)
- "对方催你确认任务啦！" → N/A (the block was deleted)
- Any accessibility label containing 催 → "提醒"

- [ ] **Step 5: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Together/Features/Home/HomeView.swift Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(ui): rename "催一下" → "提醒"; remove duplicate local-notification path

HomeView button and any accessibility copy now read "提醒". The
AppContext.reloadAfterSync loop that scheduled local notifications for
every new reminder_requested_at change is removed — APNs now owns the
banner path in all 4 app states. Foreground fallback becomes in-UI
row tint (implemented in Task 14).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `TASK_NUDGE` notification category + action registration

**Files:**
- Modify: `Together/App/NotificationActionCatalog.swift:13-45`

- [ ] **Step 1: Add `TASK_NUDGE` identifiers**

Edit `NotificationActionCatalog.swift`. At the top of the enum:

```swift
enum NotificationActionCatalog {
    static let taskCategoryIdentifier = "together.notification.task"
    static let genericCategoryIdentifier = "together.notification.generic"
    static let taskNudgeCategoryIdentifier = "TASK_NUDGE"   // new, matches APNs category
    static let completeActionIdentifier = "together.notification.complete"
    static let completeNudgeActionIdentifier = "COMPLETE_NUDGE"  // new, matches APNs action

    static let snoozeFiveMinutesIdentifier = "together.notification.snooze.5m"
    // ... existing ...
```

- [ ] **Step 2: Register the new category in `categories`**

In the `static var categories: Set<UNNotificationCategory>` block, append the new category:

```swift
UNNotificationCategory(
    identifier: taskNudgeCategoryIdentifier,
    actions: [
        UNNotificationAction(
            identifier: completeNudgeActionIdentifier,
            title: "完成",
            options: []
        )
    ],
    intentIdentifiers: [],
    options: [.customDismissAction]
)
```

- [ ] **Step 3: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Together/App/NotificationActionCatalog.swift
git commit -m "$(cat <<'EOF'
feat(notifications): register TASK_NUDGE category with COMPLETE_NUDGE action

Matches the APNs payload category / actionIdentifier sent by the
send-push-notification Edge Function. Categories are registered at
app launch by AppNotificationDelegate.configure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Edge Function — real APNs via JWT + HTTP/2 + Supabase webhook config

**Files:**
- Modify: `supabase/functions/send-push-notification/index.ts`
- Deploy via MCP `deploy_edge_function`
- Create (in dashboard): Database Webhook `task_messages_to_push_fn`

- [ ] **Step 1: Rewrite `sendAPNs` + related helpers**

Replace the full contents of `supabase/functions/send-push-notification/index.ts` with:

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "jsr:@panva/jose";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apnsKeyId = Deno.env.get("APNS_KEY_ID") || "";
const apnsTeamId = Deno.env.get("APNS_TEAM_ID") || "";
const apnsPrivateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY") || "";
const appBundleId = "com.pigdog.Together";

const supabase = createClient(supabaseUrl, serviceRoleKey);

// JWT cached per instance; APNs token is valid for up to 60 minutes.
let cachedJWT: { token: string; exp: number } | null = null;

async function getApnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && cachedJWT.exp > now + 300) return cachedJWT.token;

  const privateKey = await importPKCS8(apnsPrivateKeyPEM, "ES256");
  const jwt = await new SignJWT({ iss: apnsTeamId, iat: now })
    .setProtectedHeader({ alg: "ES256", kid: apnsKeyId })
    .sign(privateKey);

  cachedJWT = { token: jwt, exp: now + 3000 };  // 50 min
  return jwt;
}

async function sendAPNs(
  deviceToken: string,
  notification: { title: string; body: string },
  taskId: string | undefined,
): Promise<{ ok: boolean; status: number; deleteToken: boolean }> {
  const jwt = await getApnsJWT();
  const payload = {
    aps: {
      alert: { title: notification.title, body: notification.body },
      sound: "default",
      badge: 1,
      category: "TASK_NUDGE",
    },
    task_id: taskId,
  };
  const url = `https://api.sandbox.push.apple.com/3/device/${deviceToken}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": appBundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  return { ok: res.ok, status: res.status, deleteToken: res.status === 410 };
}

function buildNotification(
  table: string,
  type: string,
  record: Record<string, unknown>,
  actorName: string,
): { title: string; body: string } | null {
  if (table === "tasks" && type === "INSERT") {
    if (record.assignee_mode === "partner") {
      return { title: "新任务", body: `${actorName} 给你分配了「${record.title}」` };
    }
    return null;
  }
  if (table === "tasks" && type === "UPDATE") {
    if (record.status === "completed") {
      return { title: "任务完成", body: `${actorName} 完成了「${record.title}」` };
    }
    return null;
  }
  if (table === "task_messages") {
    if (record.type === "nudge") {
      return { title: "提醒", body: `${actorName} 提醒你完成任务` };
    }
    if (record.type === "comment") {
      return { title: "留言", body: `${actorName} 给你留了言` };
    }
    if (record.type === "rps_result") {
      return { title: "✊✌️✋", body: `${actorName} 发起了石头剪刀布！` };
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const { type, table, record } = payload;

    const actorId = record?.creator_id || record?.sender_id;
    if (!actorId) return new Response("No actor", { status: 200 });

    // Look up space_id — either on record directly, or via tasks join for task_messages.
    let spaceId = record?.space_id;
    if (!spaceId && table === "task_messages") {
      const { data: task } = await supabase
        .from("tasks")
        .select("space_id")
        .eq("id", record.task_id)
        .single();
      spaceId = task?.space_id;
    }
    if (!spaceId) return new Response("No space", { status: 200 });

    // Find partner (everyone else in space).
    const { data: members } = await supabase
      .from("space_members")
      .select("user_id")
      .eq("space_id", spaceId)
      .neq("user_id", actorId);

    if (!members || members.length === 0) return new Response("No partner", { status: 200 });
    const partnerId = members[0].user_id;

    // Partner's device tokens.
    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", partnerId);

    if (!tokens || tokens.length === 0) return new Response("No tokens", { status: 200 });

    // Actor display name.
    const { data: actor } = await supabase
      .from("space_members")
      .select("display_name")
      .eq("space_id", spaceId)
      .eq("user_id", actorId)
      .single();

    const actorName = actor?.display_name || "伴侣";

    const notification = buildNotification(table, type, record, actorName);
    if (!notification) return new Response("Skip", { status: 200 });

    const taskId: string | undefined =
      table === "task_messages" ? (record.task_id as string | undefined) : (record.id as string | undefined);

    let sentCount = 0;
    for (const { token } of tokens) {
      try {
        const result = await sendAPNs(token, notification, taskId);
        if (result.ok) {
          sentCount++;
        } else if (result.deleteToken) {
          await supabase.from("device_tokens").delete().eq("token", token);
          console.warn(`[APNs] 410 Unregistered — deleted token ${token.substring(0, 8)}...`);
        } else {
          console.error(`[APNs] ${result.status} for ${token.substring(0, 8)}...`);
        }
      } catch (e) {
        console.error(`[APNs] exception: ${e}`);
      }
    }

    return new Response(JSON.stringify({ sent: sentCount }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(`[Push] Error: ${error}`);
    // Always return 200 so Supabase webhook doesn't auto-retry and double-push.
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Deploy Edge Function via MCP**

```
deploy_edge_function(
  project_id="nxielmwdoiwiwhzczrmt",
  name="send-push-notification",
  files=[{name:"index.ts", content:<contents of the file above>}]
)
```
Expected: `{success: true, version: N}` (version increments from previous).

- [ ] **Step 3: Configure Database Webhook (manual — user must do this once)**

User-facing instructions to print / display:

> Open https://supabase.com/dashboard/project/nxielmwdoiwiwhzczrmt/database/hooks → **Create a new hook**
>
> - Name: `task_messages_to_push_fn`
> - Table: `public.task_messages`
> - Events: ☑ INSERT, ☐ UPDATE, ☐ DELETE
> - Type: **Supabase Edge Functions**
> - Edge Function: `send-push-notification`
> - HTTP Method: POST
> - Timeout: 5000 ms
>
> Save. Test by asking user to run an INSERT from MCP (next step).

- [ ] **Step 4: Verify webhook fires via MCP logs**

Have user insert a synthetic test row (or wait for first client-side nudge). Then check function logs:

```
get_logs(project_id="nxielmwdoiwiwhzczrmt", service="edge-function")
```
Expected: log lines like `Deno.serve invoked`, either `No tokens` (if user has 0 device tokens for partner) or APNs `200`/`410`/etc responses.

- [ ] **Step 5: Commit Edge Function source**

```bash
git add supabase/functions/send-push-notification/index.ts
git commit -m "$(cat <<'EOF'
feat(edge-fn): real APNs delivery via JWT + HTTP/2

Replaces the TODO stub in sendAPNs with a real implementation:
- ES256 JWT signed with APNs Auth Key (.p8 in APNS_PRIVATE_KEY secret)
- Token cached 50 min per Edge Function instance
- POST to api.sandbox.push.apple.com/3/device/<token> with the standard
  APNs headers (apns-topic, apns-push-type=alert, apns-priority=10)
- 410 Unregistered → delete the stale row from device_tokens
- Other non-OK statuses logged and swallowed
- Webhook always returns 200 to avoid Supabase retry loops

Also renames buildNotification nudge copy "催一下" → "提醒" to match UI.
Deploy via MCP deploy_edge_function. Database Webhook must be configured
once manually in the Supabase dashboard (one-time setup per project).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Cold-launch deep-link plumbing in `AppDelegate` + pending slot on `AppContext`

**Files:**
- Modify: `Together/App/AppDelegate.swift`
- Modify: `Together/App/AppContext.swift` (add pending slot + consume hook)

- [ ] **Step 1: Store pending task ID on AppDelegate**

Extend `AppDelegate.swift`:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var bootstrapper: AppBootstrapper?
    private(set) var pendingShareMetadata: CKShare.Metadata?
    private(set) var pendingTaskIDFromNotification: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()

        // Cold-launch from APNs payload with task_id
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let taskIDString = remote["task_id"] as? String,
           let taskID = UUID(uuidString: taskIDString) {
            pendingTaskIDFromNotification = taskID
        }
        return true
    }

    func consumePendingTaskIDFromNotification() -> UUID? {
        let id = pendingTaskIDFromNotification
        pendingTaskIDFromNotification = nil
        return id
    }
    // ... existing methods unchanged ...
}
```

- [ ] **Step 2: Add pending slot on AppContext + consume on postLaunch**

In `Together/App/AppContext.swift`, add near top:

```swift
private var pendingDeepLinkTaskID: UUID?

func rememberDeepLinkTaskID(_ id: UUID) {
    pendingDeepLinkTaskID = id
}

func consumeDeepLinkTaskIDIfAny() async {
    guard let id = pendingDeepLinkTaskID else { return }
    pendingDeepLinkTaskID = nil
    await openTaskFromNotification(taskID: id)
}
```

Find where `postLaunch` (or equivalent bootstrapper completion) calls into AppContext; add a `await consumeDeepLinkTaskIDIfAny()` after app is ready.

In the bootstrapper wiring (probably `TogetherApp.swift` or `AppBootstrapper.swift`), when bootstrapping completes, read `appDelegate.consumePendingTaskIDFromNotification()` and pass to `appContext.rememberDeepLinkTaskID(...)` before calling `consumeDeepLinkTaskIDIfAny`.

- [ ] **Step 3: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` (still missing `openTaskFromNotification` impl — placeholder stub for now is fine):

```swift
func openTaskFromNotification(taskID: UUID) async {
    // Full implementation in Task 12. For now, no-op.
}

func completeTaskFromNotification(taskID: UUID) async {
    // Full implementation in Task 12. For now, no-op.
}
```

- [ ] **Step 4: Commit**

```bash
git add Together/App/AppDelegate.swift Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(deep-link): cold-launch task_id plumbing from APNs userInfo

AppDelegate reads launchOptions[.remoteNotification].task_id and stores
it. AppContext gains a pending-slot + consume hook. Placeholders for
openTaskFromNotification / completeTaskFromNotification added; real
implementations in next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Implement `completeTaskFromNotification` + `openTaskFromNotification` + handleNotificationResponse for TASK_NUDGE

**Files:**
- Modify: `Together/App/AppContext.swift` — real bodies for the two methods; new branch in `handleNotificationResponse`

- [ ] **Step 1: Implement `completeTaskFromNotification`**

Replace placeholder in `AppContext.swift`:

```swift
func completeTaskFromNotification(taskID: UUID) async {
    await bootstrapIfNeeded()

    guard
        let spaceID = sessionStore.currentSpace?.id,
        let actorID = sessionStore.currentUser?.id
    else { return }

    do {
        _ = try await container.taskApplicationService.completeTask(
            in: spaceID, taskID: taskID, actorID: actorID
        )
        await flushRecordedSharedMutation(
            SyncChange(entityKind: .task, operation: .complete, recordID: taskID, spaceID: spaceID)
        )
        await homeViewModel.reload()
    } catch {
        appContextLogger.error("[Nudge] complete failed: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Implement `openTaskFromNotification`**

```swift
func openTaskFromNotification(taskID: UUID) async {
    await bootstrapIfNeeded()
    router.activeTab = .home
    await MainActor.run {
        NotificationCenter.default.post(
            name: .openTaskFromNudge,
            object: nil,
            userInfo: ["task_id": taskID]
        )
    }
}
```

And declare the Notification.Name in `AppContext.swift`:

```swift
extension Notification.Name {
    static let openTaskFromNudge = Notification.Name("openTaskFromNudge")
}
```

- [ ] **Step 3: Extend `handleNotificationResponse` for TASK_NUDGE category**

At the top of `handleNotificationResponse(_:)` (currently at line 674), before the existing `AppNotification.parseIdentifier` block, add:

```swift
// APNs-originated TASK_NUDGE: userInfo carries task_id directly;
// identifier is server-generated and does not follow AppNotification format.
if let taskIDString = response.notification.request.content.userInfo["task_id"] as? String,
   let taskID = UUID(uuidString: taskIDString),
   response.notification.request.content.categoryIdentifier == NotificationActionCatalog.taskNudgeCategoryIdentifier {
    await bootstrapIfNeeded()
    switch response.actionIdentifier {
    case NotificationActionCatalog.completeNudgeActionIdentifier:
        await completeTaskFromNotification(taskID: taskID)
    case UNNotificationDefaultActionIdentifier:
        await openTaskFromNotification(taskID: taskID)
    default:
        break
    }
    return
}
```

- [ ] **Step 4: Build + existing tests**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(nudge): actionable TASK_NUDGE response handler + deep-link

handleNotificationResponse branches on categoryIdentifier == TASK_NUDGE:
- COMPLETE_NUDGE action → taskApplicationService.completeTask → flush push → home reload
- default (banner body tap) → openTaskFromNotification → home tab + NotificationCenter
  post for HomeView to scroll/highlight (Task 13 wires the listener)

Both paths tolerate cold-launch: bootstrapIfNeeded ensures session/context
are ready before acting.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: HomeView listens to `.openTaskFromNudge` + scrolls + highlights

**Files:**
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: Add onReceive + scroll state**

In `HomeView` (SwiftUI view), add:

```swift
@State private var highlightedTaskID: UUID?
```

And at the top of the view hierarchy (e.g. inside the main `VStack` or `List`), add a `ScrollViewReader` wrapper if not already present, then:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openTaskFromNudge)) { notif in
    guard let id = notif.userInfo?["task_id"] as? UUID else { return }
    highlightedTaskID = id
    withAnimation {
        proxy.scrollTo(id, anchor: .center)
    }
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        highlightedTaskID = nil
    }
}
```

And the row rendering for each task:

```swift
.background(
    highlightedTaskID == task.id
        ? AppTheme.colors.coral.opacity(0.18)
        : Color.clear
)
```

- [ ] **Step 2: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Together/Features/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat(nudge): HomeView scrolls + highlights task on deep-link

Subscribes to .openTaskFromNudge via NotificationCenter; when received,
scrolls the list to the task row and tints it briefly to signal to the
partner which task was just nudged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: In-UI visual "nudged" indicator (foreground fallback)

**Files:**
- Modify: `Together/Features/Home/HomeView.swift` — add bell/tint on rows where `reminderRequestedAt > lastActionAt`

- [ ] **Step 1: Find the task row rendering**

```bash
grep -n "struct.*Row\|func.*Row\|@ViewBuilder" Together/Features/Home/HomeView.swift | head -10
```
Identify the view / function that renders a single item row.

- [ ] **Step 2: Add a computed helper to determine nudged state**

Add to HomeView or its row model:

```swift
private func isNudged(_ item: Item) -> Bool {
    guard let reminderAt = item.reminderRequestedAt else { return false }
    guard let lastAction = item.lastActionAt else { return true }
    return reminderAt > lastAction
}
```

- [ ] **Step 3: Apply tint or icon**

In the row rendering view, add a small 🔔 SF Symbol overlay + subtle row background tint:

```swift
HStack {
    // ... existing row content ...
    if isNudged(task) {
        Image(systemName: "bell.badge.fill")
            .foregroundStyle(AppTheme.colors.coral)
            .font(.caption)
    }
}
.background(
    isNudged(task) ? AppTheme.colors.coral.opacity(0.08) : Color.clear
)
```

- [ ] **Step 4: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Home/HomeView.swift
git commit -m "$(cat <<'EOF'
feat(nudge): in-UI bell indicator as foreground fallback

Row shows a small bell icon + subtle coral tint while
reminderRequestedAt > lastActionAt. Clears once the partner interacts
with the task (any action updates lastActionAt via
LocalItemRepository.updateItemStatus / markCompleted / markIncomplete —
already fixed in batch 1 hotfix).

This is the Q6 C fallback: if APNs delivery fails silently, the
partner opening the app still sees which task was nudged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Prompt for notification permission once on first pair success

**Files:**
- Modify: `Together/Services/Pairing/CloudPairingService.swift`
- Modify: `Together/App/AppContext.swift` (observer wiring)

- [ ] **Step 1: Add observer protocol**

In `CloudPairingService.swift` near the top:

```swift
protocol PairJoinObserver: AnyObject, Sendable {
    func onSuccessfulPairJoin() async
}
```

And a weak property:
```swift
private weak var pairJoinObserver: PairJoinObserver?

func setPairJoinObserver(_ observer: PairJoinObserver?) {
    self.pairJoinObserver = observer
}
```

- [ ] **Step 2: Fire observer at success sites**

After the final successful `joinSpace` / `finalizeAcceptance` in `acceptInviteByCode` and any other pair-success return paths, add:

```swift
await pairJoinObserver?.onSuccessfulPairJoin()
```

- [ ] **Step 3: Implement observer on AppContext**

In `Together/App/AppContext.swift`, extend AppContext to conform:

```swift
extension AppContext: PairJoinObserver {
    func onSuccessfulPairJoin() async {
        let status = await container.notificationService.authorizationStatus()
        guard status == .notDetermined else { return }
        _ = try? await container.notificationService.requestAuthorization()
    }
}
```

Wire in `LocalServiceFactory.swift` or `AppContext.configureSyncCallbacks`:

```swift
await container.pairingService.setPairJoinObserver(self)
```

(Dispatch from @MainActor appropriately — `pairingService` is an actor.)

- [ ] **Step 4: Build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Pairing/CloudPairingService.swift Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(permissions): prompt for notifications once on first pair success

CloudPairingService fires a PairJoinObserver callback on every
successful joinSpace / acceptInviteByCode. AppContext implements the
observer by requesting notification authorization iff current status
is .notDetermined (so it's a one-time lifetime prompt, per iOS rules).
If already decided, no-op.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Full regression + E2E smoke + merge to main + push

**Files:** none

- [ ] **Step 1: Full test regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL" | tail -3
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Device E2E (manual, dual-device)**

1. iPhone + iPad both rebuild + launch
2. Confirm APNs permission prompt fired on first pair join (or verify `authorizationStatus` is `.authorized` in iOS Settings → Notifications → Together)
3. iPhone: create `assigneeMode = .partner` task → iPad accepts → iPhone sees accepted state
4. iPhone: tap "提醒" on accepted partner task
5. iPad expectations (one per test):
   - **foreground**: banner pops in-app with "提醒 / {actor} 提醒你完成任务"
   - **background**: swipe iPad up to background, repeat step 4, banner appears in notification center
   - **locked**: lock iPad, repeat step 4, banner appears on lock screen
   - **killed**: swipe-kill Together on iPad, repeat step 4, banner appears; tapping banner launches app to Home tab with that task highlighted
6. Tap "完成" action from banner on iPad (any state) → iPhone sees task marked completed within 10s
7. Tap banner body → iPad app opens, scrolls to task row, brief coral tint
8. Verify `get_logs(service="edge-function")` shows one successful POST per nudge (status 200)

- [ ] **Step 3: Verify Supabase data**

```sql
SELECT count(*) FROM task_messages;
```
Expected: one row per nudge tapped during E2E.

```sql
SELECT count(*) FROM device_tokens;
```
Expected: unchanged unless some devices hit 410 (then decreases).

- [ ] **Step 4: Merge + push**

```bash
git checkout main
git merge --ff-only feat/partner-nudge-notification
git push origin main
```

- [ ] **Step 5: Append implementation log to plan**

Open this file (`docs/superpowers/plans/2026-04-19-partner-nudge-notification.md`), append a `## 实施日志` section with:
- Commit SHAs (ordered)
- Any unexpected findings
- Any deviations from spec

Commit separately:
```bash
git add docs/superpowers/plans/2026-04-19-partner-nudge-notification.md
git commit -m "docs(plan): partner nudge implementation log"
git push origin main
```

---

## Verification checklist

Before Task 16 Step 4 (merge + push), confirm every spec requirement has landed:

```
□ §1 Scope
  □ "提醒" rename visible in UI (Task 8)
  □ task_messages(type='nudge') INSERT on every tap (Task 7)
  □ APNs delivered in 4 states (Tasks 9-12 + E2E)
  □ Actionable "完成" button (Tasks 9, 12)
  □ Banner body → deep-link (Tasks 11-13)
  □ APNs failure silent + foreground fallback (Tasks 10, 14)

□ §2 Data model
  □ Migration 009 applied (Task 1)
  □ PersistentTaskMessage + domain + protocol + repo (Tasks 2-3)
  □ .taskMessage enum case (Task 4)
  □ TaskMessagePushDTO + pushUpsert case (Task 5)
  □ tasks.reminder_requested_at preserved (Task 7 — unchanged dual-write)

□ §3 Client flow
  □ sendReminderToPartner dual-writes + 2 SyncChanges (Task 7)
  □ 30s cooldown preserved (Task 7)
  □ UI rename (Task 8)

□ §4 Server flow
  □ Edge Function JWT + HTTP/2 real APNs (Task 10)
  □ 410 → delete token (Task 10)
  □ webhook always 200 (Task 10)
  □ Database Webhook configured (Task 10 Step 3 — manual)

□ §5 4-state delivery
  □ Foreground willPresent returns banner (existing AppNotificationDelegate; no change)
  □ reloadAfterSync nudge banner block removed (Task 8)
  □ Background/locked/killed verified via E2E (Task 16)

□ §6 Actionable notification
  □ TASK_NUDGE category + COMPLETE_NUDGE action (Task 9)
  □ handleNotificationResponse branch (Task 12)
  □ Cold-launch plumbing (Task 11)
  □ HomeView scrolls + highlights (Task 13)

□ §7 Failure + fallback
  □ 410 token cleanup (Task 10)
  □ Bell indicator for foreground fallback (Task 14)

□ §8 Permission
  □ Auto-prompt on pair success if notDetermined (Task 15)
```

---

## 实施日志

（开工后追加）
