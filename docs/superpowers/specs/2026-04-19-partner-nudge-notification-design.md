# Partner Nudge Notification — Design Spec

**Date**: 2026-04-19
**Feature**: End-to-end "提醒" (formerly "催一下") notification flow
**Goal**: When a user taps "提醒" on a partner-assigned task, the partner receives an APNs push that is reliably delivered whether their app is foreground, background, locked, or killed, with an actionable "完成" button.

---

## §1 Scope & Non-goals

### In scope

- Rename UI-facing string "催一下" → "提醒"
- Client records a `task_messages(type='nudge')` INSERT on every "提醒" tap
- Supabase Database Webhook forwards INSERT events to existing `send-push-notification` Edge Function
- Edge Function implements real APNs delivery (JWT signing + HTTP/2 POST)
- APNs payload is actionable: category `TASK_NUDGE` with "完成" action
- Notification banner body tap deep-links the partner app into the task row
- Notification permission is proactively requested once after successful pair join
- Dual-write `tasks.reminder_requested_at` stays for foreground fallback (Route I)

### Explicitly NOT in scope

- Task comments, task emoji reactions, rock-paper-scissors game (same `task_messages` table, different `type` values — future work)
- iPad-side persistent storage of `task_messages` history (partner device does not persist nudge events; Realtime events land only as APNs on this path)
- APNs Production endpoint (MVP uses sandbox only; `aps-environment = development`)
- Custom cooldown policies (existing 30-second client cooldown stays)
- Anniversary feature
- Retry queues / durable delivery guarantees beyond what APNs natively provides

---

## §2 Data model

### Supabase schema

`task_messages` table already exists with sufficient columns:
- `id uuid NOT NULL`
- `task_id uuid NOT NULL` (FK → tasks.id — should verify)
- `sender_id uuid NOT NULL` (audit-only; local app UUID, not auth.uid)
- `type text NOT NULL` (values: `nudge` now; `comment`/`rps_result` reserved for future)
- `content text` (unused by nudge)
- `emoji text` (unused by nudge)
- `rps_result jsonb` (unused by nudge)
- `created_at timestamptz` (default now())

### Migration 009 — RLS INSERT policy

`task_messages.rowsecurity = true` but no policies exist, so all anon inserts are currently denied. Add one INSERT policy:

```sql
CREATE POLICY "space members can insert task messages" ON task_messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM tasks
      WHERE tasks.id = task_messages.task_id
        AND is_space_member(tasks.space_id)
    )
  );
```

No SELECT policy added — partner device does not pull task_messages in MVP.

### Client DTO

New write-only DTO in `SupabaseSyncService.swift`:

```swift
struct TaskMessagePushDTO: Encodable, Sendable {
    let id: UUID
    let taskId: UUID
    let senderId: UUID
    let type: String            // "nudge"
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type
        case taskId = "task_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}
```

No `PersistentTaskMessage` model needed (partner doesn't persist). No `applyToLocal` implementation needed (no pull path).

### `SyncEntityKind` extension

Add new case:
```swift
case taskMessage   // push-only; no Realtime subscription, no catchUp pull
```

Table mapping in `SupabaseSyncService.pushUpsert`:
```swift
case .taskMessage:
    let descriptor = FetchDescriptor<PersistentTaskMessage>(...)
    // ...  (see §3 for whether we persist locally or build inline)
```

### Preserved field: `tasks.reminder_requested_at`

Client writes `.now` to this field on every "提醒" tap (dual-write with `task_messages INSERT`). This field remains the data source for the foreground fallback UI indicator on the receiving device.

Semantics clarification:
- `task_messages(type='nudge')` row = authoritative event log + APNs trigger source
- `tasks.reminder_requested_at` = derived cache of "most recent nudge timestamp", useful for quick "has been nudged" queries without scanning message history

---

## §3 Client flow

### `DefaultTaskApplicationService.sendReminderToPartner` extended

```swift
func sendReminderToPartner(
    in spaceID: UUID,
    taskID: UUID,
    actorID: UUID
) async throws -> Item {
    var item = try await existingTask(in: spaceID, taskID: taskID)
    guard item.assigneeMode == .partner else { throw RepositoryError.notFound }

    // Existing 30s cooldown
    if let lastReminder = item.reminderRequestedAt,
       Date.now.timeIntervalSince(lastReminder) < 30 {
        return item
    }

    // Existing: bump reminder_requested_at (drives foreground fallback UI)
    item.reminderRequestedAt = .now
    item.updatedAt = .now
    let saved = try await itemRepository.saveItem(item)
    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .task, operation: .upsert, recordID: saved.id, spaceID: spaceID)
    )

    // NEW: insert a task_message row of type=nudge → triggers APNs via webhook
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

### `TaskMessageRepository` + `PersistentTaskMessage` (minimal, new)

Use the same Repository / Persistent / DTO triad as every other sync entity, so `pushUpsert(entityKind:.taskMessage, recordID:spaceID:context:)` can fetch and serialize by recordID the same way it does for `.task` / `.project` etc. — no one-off code path.

```swift
@Model
final class PersistentTaskMessage {
    var id: UUID
    var taskID: UUID
    var senderID: UUID
    var type: String
    var createdAt: Date

    init(id: UUID, taskID: UUID, senderID: UUID, type: String, createdAt: Date) { ... }
}
```

- Added to the 15-model `ModelContainer` schema list (all test containers too).
- No `isLocallyDeleted` needed (insert-only, no tombstone concept for events).
- `LocalTaskMessageRepository.insertNudge(messageID:taskID:senderID:createdAt:)` creates the row + saves.
- No fetch API (MVP). Future comments / history reader will add one.

### UI changes

1. `HomeView.swift:2487` button label `Text("催一下")` → `Text("提醒")`
2. Any accessibility label / tooltip containing "催" updated to "提醒"
3. `AppContext.swift:404` local notification body `"催你完成任务啦！"` → `"提醒你完成任务"`
4. `AppContext.swift:406` `"对方催你确认任务啦！"` → `"对方提醒你确认任务"`
5. Function names (`sendReminderToPartner`, `reminderRequestedAt`) stay — already English-neutral.

---

## §4 Server flow

### Supabase Database Webhook (one-time dashboard config)

User configures via Dashboard → Database → Webhooks → Create:
- Name: `task_messages_to_push_fn`
- Table: `public.task_messages`
- Events: `INSERT` only
- Type: Supabase Edge Functions → `send-push-notification`
- HTTP Method: POST
- Timeout: 5000 ms
- No filters (Edge Function already filters by `type` internally)

### Edge Function `send-push-notification` — real APNs implementation

File: `supabase/functions/send-push-notification/index.ts`

Replace the TODO `sendAPNs()` with a real implementation:

```typescript
import { importPKCS8, SignJWT } from "jsr:@panva/jose";

let cachedJWT: { token: string; exp: number } | null = null;

async function getApnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Reuse JWT if not expiring in next 5 minutes (APNs max validity is 60 min)
  if (cachedJWT && cachedJWT.exp > now + 300) return cachedJWT.token;

  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const privateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY")!;

  const privateKey = await importPKCS8(privateKeyPEM, "ES256");
  const jwt = await new SignJWT({ iss: teamId, iat: now })
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .sign(privateKey);

  cachedJWT = { token: jwt, exp: now + 3000 };  // 50 min cache
  return jwt;
}

async function sendAPNs(
  deviceToken: string,
  notification: { title: string; body: string },
  taskId?: string
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
      "apns-topic": "com.pigdog.Together",
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  return {
    ok: res.ok,
    status: res.status,
    deleteToken: res.status === 410,  // Unregistered
  };
}
```

### Payload dispatch loop

Existing code in `Deno.serve` handler:
- Parse webhook payload
- Extract `sender_id`, look up `space_id` via `tasks.id = record.task_id`
- Find partner's `user_id` in `space_members` (exclude sender)
- Query `device_tokens` for all partner devices
- Build notification via `buildNotification(table='task_messages', type='INSERT', record, actorName)` → existing code already handles `type === 'nudge'` and returns `{title: '提醒', body: '${actorName} 提醒你完成任务'}` (rename from "催一下")
- For each token, call `sendAPNs(token, notification, record.task_id)`:
  - If returned `deleteToken: true` (410 Unregistered) → `DELETE FROM device_tokens WHERE token = ?`
  - If `!ok` otherwise → `console.error`, continue
- Return `{ sent: N }` with HTTP 200 (always 200 so the webhook doesn't auto-retry and cause duplicate pushes)

### Edge Function `buildNotification` string rename

In `buildNotification`, update `type === 'nudge'` branch:
```typescript
if (record.type === "nudge") {
  return { title: "提醒", body: `${actorName} 提醒你完成任务` };
}
```

---

## §5 Delivery in 4 app states

| App state | Delivery path |
|---|---|
| **Foreground** | APNs arrives → `UNUserNotificationCenterDelegate.willPresent` returns `[.banner, .sound]` → banner shows in-app. `AppContext.reloadAfterSync` path NO longer schedules a local notification for nudges: **delete the entire `if let reminderAt = item.reminderRequestedAt ... scheduleReminderNotification ...` block at `AppContext.swift:399-408`** (both branches of the inner if/else-if). The "对方催你确认" branch was inadvertently self-firing on the sender's own device anyway; APNs subsumes the legitimate use case. Foreground fallback on APNs failure = in-UI visual indicator (§7). |
| **Background** | APNs delivered natively by iOS (banner in notification center / lock screen). Taps invoke app delegate. |
| **Locked screen** | Same as background. |
| **Killed** | APNs delivered, banner shown. Tapping launches app cold. Payload stored by iOS and provided to app via launch options / `UNNotificationResponse`. |

---

## §6 Actionable notification + deep-link

### Category registration

Extend `NotificationActionCatalog` (already wired in `TogetherApp.swift:54-55`):

```swift
let taskNudgeCategory = UNNotificationCategory(
    identifier: "TASK_NUDGE",
    actions: [
        UNNotificationAction(
            identifier: "COMPLETE_NUDGE",
            title: "完成",
            options: []   // not destructive, not auth-required
        )
    ],
    intentIdentifiers: [],
    options: [.customDismissAction]
)
```

Register alongside existing categories.

### `UNUserNotificationCenterDelegate.didReceive` handler

In `AppNotificationDelegate.swift`, extend `didReceive`:

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let userInfo = response.notification.request.content.userInfo
    guard let taskIDString = userInfo["task_id"] as? String,
          let taskID = UUID(uuidString: taskIDString) else {
        return
    }
    switch response.actionIdentifier {
    case "COMPLETE_NUDGE":
        await appContext?.completeTaskFromNotification(taskID: taskID)
    case UNNotificationDefaultActionIdentifier:
        // Banner body tap → deep-link
        await appContext?.openTaskFromNotification(taskID: taskID)
    default:
        break
    }
}
```

### AppContext handlers

Two new public async methods on `AppContext`:

1. `completeTaskFromNotification(taskID: UUID) async`
   - Resolve current `actorID` from `sessionStore.currentUser?.id`; fall back to stored actor if none
   - Call `taskApplicationService.markCompleted(itemID: taskID, actorID: actorID, referenceDate: .now)`
   - This goes through `LocalItemRepository.markCompleted` → records `.complete` SyncChange → push
   - If app is just launching from killed state, wait for `AppBootstrapper.phase == .ready` before executing (store pending action, consume on `postLaunch`)

2. `openTaskFromNotification(taskID: UUID) async`
   - If bootstrap not ready: store `pendingTaskIDForDeepLink = taskID`, consume on `postLaunch`
   - When ready: switch to Home tab via `router.activeTab = .home`; post `NotificationCenter` event `.openTaskFromNudge` with `taskID`; `HomeView` (or its sub-component) subscribes and scrolls the list + highlights the row for ~2 seconds

Both handlers run on `@MainActor` (AppContext is already `@MainActor`).

### Cold launch deep-link plumbing

- `AppDelegate.didFinishLaunchingWithOptions` reads `launchOptions[.remoteNotification]` if set; if present, extract `task_id` and pre-populate `AppContext.pendingTaskIDForDeepLink` (or similar) before `AppContext.postLaunch` runs.
- Existing `AppDelegate` calls `registerForRemoteNotifications()` already; no change to that.

---

## §7 Failure & fallback (Q6 A+C)

### APNs send failure (Q6 A — silent tolerance)

- **410 Unregistered** from Apple's servers → Edge Function does `DELETE FROM device_tokens WHERE token = ?`. The offending token won't waste attempts on future nudges.
- **5xx / network / 4xx other than 410** → `console.error`; drop the event; continue to next token.
- Return HTTP 200 from Edge Function regardless of internal failures, so Supabase doesn't auto-retry and cause duplicate pushes on the partner side.
- User retry model: 30-second client cooldown on "提醒" button means user can tap again after cooldown. Re-tap inserts a fresh `task_messages` row with a new `id`, new `created_at`, triggering a new webhook event and new APNs attempt.

### Foreground fallback (Q6 C — in-app visual indicator)

- `tasks.reminder_requested_at` continues to be updated by the sender as part of the dual-write.
- Receiving device's catchUp pulls the updated task row. `AppContext.reloadAfterSync` detects `reminderRequestedAt` has changed.
- **Remove** `reloadAfterSync`'s current `scheduleReminderNotification` calls (lines 403-407 of `AppContext.swift`) so we don't double-banner in foreground.
- Replace with in-UI visual: HomeView's row for this task shows a small 🔔 badge (or subtle row tint) while `reminderRequestedAt > (item.lastActionAt ?? item.createdAt)` and auto-clears once the user interacts with the row (response, complete, or view detail).
- MVP note: the UI badge can ship as a minimal row tint. Visual polish is a separate concern.

---

## §8 Permission request timing (Q7 — B)

### Current state
`ProfileViewModel.swift:416` calls `notificationService.requestAuthorization()` when user toggles notifications in settings.

### Addition: prompt once after pair join

In `CloudPairingService.finalizeAcceptance` and `CloudPairingService.joinSpace` success paths, after the pair space is fully set up:

```swift
// Defer to application layer so Service doesn't depend on UI
await pairJoinObserver?.onSuccessfulPairJoin()
```

Where the observer (wired in `LocalServiceFactory` or `AppContext.configureSyncCallbacks`):
```swift
func onSuccessfulPairJoin() async {
    let status = await notificationService.authorizationStatus()
    guard status == .notDetermined else { return }   // Only prompt if never asked
    _ = try? await notificationService.requestAuthorization()
}
```

System will show the permission dialog exactly once in the app's lifetime (iOS limitation), so this is safe to trigger here.

If user declines → 提醒 push still delivered but silently dropped by iOS (as designed). User can enable later in Profile settings or iOS Settings.

---

## Architecture diagram (text)

```
iPhone (sender)                        Supabase                       iPad (partner)
---------------                        --------                       --------------
User taps "提醒"
  │
  └─▶ sendReminderToPartner
        │
        ├─▶ saveItem (reminder_requested_at = now)
        │     └─▶ SyncChange(.task, .upsert)
        │
        └─▶ taskMessageRepository.insertNudge
              └─▶ SyncChange(.taskMessage, .upsert)
                    │
                    ▼
              push() → pushUpsert (tasks + task_messages)
                    │
                    │  (HTTPS)
                    ▼
                                      tasks UPDATE
                                      task_messages INSERT
                                              │
                                              │ (DB Webhook on INSERT)
                                              ▼
                                      Edge Function send-push-notification
                                              │
                                              ├─▶ lookup partner user_id via space_members
                                              ├─▶ query device_tokens for partner
                                              └─▶ for each token: HTTPS POST api.sandbox.push.apple.com/3/device/<token>
                                                                                        │
                                                                                        │ (APNs)
                                                                                        ▼
                                                                              iPad receives banner
                                                                              (foreground/bg/locked/killed)
                                                                                        │
                                                                                        ├─▶ tap "完成" action
                                                                                        │     └─▶ markCompleted
                                                                                        │           └─▶ syncs back
                                                                                        │
                                                                                        └─▶ tap banner body
                                                                                              └─▶ openTask deep-link
```

---

## Open decisions the plan can make

Decisions deferred to planning that don't affect the architecture:

1. Exact visual design of the in-UI "nudged" indicator (§7) — row tint / badge icon / both; plan picks whichever is cheapest to ship with the existing `HomeView` row component.
2. Add `supabase/migrations/009` + `010` to client repo AND apply via MCP `apply_migration` (precedent: we do both — prod is applied via MCP, SQL file checked in for reproducibility).

---

## Testing strategy

### Unit tests
- `DefaultTaskApplicationService.sendReminderToPartnerRecordsBothChanges` — spy SyncCoordinator, assert 2 SyncChanges (.task + .taskMessage) with correct entity kinds.
- `TaskMessagePushDTOEncodesCorrectKeys` — encode and assert JSON keys match Supabase column names.

### Integration tests
- RLS: execute SQL as anon → INSERT task_messages for a task in a space the user is NOT member of → assert fails. INSERT for a task in a joined space → succeeds.
- Edge Function: mock fetch, simulate 410 response → assert DELETE FROM device_tokens called.

### E2E (manual, dual device)
- Tap 提醒 on iPhone → iPad receives banner within 3 seconds (background + locked + killed scenarios).
- Tap 完成 action from banner → iPhone sees task completed within 10 seconds.
- Tap banner body → iPad app opens, lands on Home tab, highlights the task row.
- Deny notification permission on iPad → tap 提醒 → iPad no banner but opening app shows UI indicator.

---

## Rollback plan

If APNs delivery creates problems in production:
1. Disable the database webhook from Supabase Dashboard → Database → Webhooks → disable `task_messages_to_push_fn`. Nudges still record `task_messages` rows and still bump `reminder_requested_at` so foreground UI indicator still works.
2. If that's insufficient, client can feature-flag the `task_messages` insert (revert to `reminder_requested_at`-only) by commenting out the insert call. Zero schema rollback.
