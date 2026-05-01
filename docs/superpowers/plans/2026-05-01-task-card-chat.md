# Task Card Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add task-scoped chat to pair task cards, backed by `task_messages`, with single-line card previews, morph chat panel UI, comment push/pull, and local unread state.

**Architecture:** Use `task_messages` as the canonical task chat event stream and keep `assignmentMessages` as read-only legacy fallback. Keep chat state out of `PairTimelineCard`; add a repository/service/ViewModel boundary and a dedicated overlay panel. Extend Supabase constraints and sync so comments are durable across APNs, foreground catch-up, reinstall, and offline retry.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Supabase PostgREST/Realtime, Supabase SQL migrations, existing `SyncCoordinatorProtocol` outbox.

---

## File Structure

**Backend / Supabase**
- Create: `supabase/migrations/040_task_message_comments_constraints.sql`
- Modify: `supabase/functions/send-push-notification/index.ts` only if tests show `comment` payload needs extra fields; default push text stays privacy-preserving.

**Domain and persistence**
- Modify: `Together/Domain/Models/TaskMessage.swift`
- Modify: `Together/Persistence/Models/PersistentTaskMessage.swift`
- Create: `Together/Persistence/Models/PersistentTaskChatReadState.swift`
- Modify: `Together/Persistence/PersistenceController.swift`
- Modify: test `ModelContainer` builders that list all models.

**Repository and application service**
- Modify: `Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift`
- Modify: `Together/Services/TaskMessages/LocalTaskMessageRepository.swift`
- Modify: `Together/Services/TaskMessages/MockTaskMessageRepository.swift`
- Modify: `Together/Application/Tasks/TaskApplicationServiceProtocol.swift`
- Modify: `Together/Application/Tasks/DefaultTaskApplicationService.swift`
- Modify: `Together/Services/Items/LocalItemRepository.swift`
- Modify: `Together/Services/Items/MockItemRepository.swift`

**Sync**
- Modify: `Together/Sync/SyncCoordinatorProtocol.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Modify: `TogetherTests/TaskMessagePushDTOTests.swift`
- Add focused sync tests in `TogetherTests/TaskMessageSyncTests.swift` if current seams are enough; otherwise extend `SupabaseSoloSyncServiceTests.swift` only with small helper tests.

**Home / chat UI**
- Create: `Together/Features/Home/TaskChatTimelineEntry.swift`
- Create: `Together/Features/Home/TaskChatViewModel.swift`
- Create: `Together/Features/Home/TaskChatPanelView.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify or extend preview fixtures in `Together/PreviewContent/MockDataFactory.swift`

**Tests**
- Modify: `TogetherTests/TaskMessageRepositoryTests.swift`
- Modify: `TogetherTests/SendReminderToPartnerTests.swift`
- Modify: `TogetherTests/TogetherTests.swift`
- Add: `TogetherTests/TaskChatViewModelTests.swift`

---

## Task 1: Supabase Comment Constraints

**Files:**
- Create: `supabase/migrations/040_task_message_comments_constraints.sql`
- Verify: `supabase/migrations/036_add_core_check_constraints.sql`
- Verify: `supabase/functions/send-push-notification/index.ts`

- [ ] **Step 1: Add migration for comment content and completed-task guard**

Create `supabase/migrations/040_task_message_comments_constraints.sql`:

```sql
-- Migration 040: task message comment constraints
--
-- Chat comments now use task_messages(type='comment', content=...).
-- The app enforces these checks client-side too, but the database remains
-- the final guard against empty comments, oversized comments, and comments on
-- completed/deleted tasks.

ALTER TABLE public.task_messages
  DROP CONSTRAINT IF EXISTS ck_task_messages_comment_content;

ALTER TABLE public.task_messages
  ADD CONSTRAINT ck_task_messages_comment_content CHECK (
    type <> 'comment'
    OR (
      content IS NOT NULL
      AND length(btrim(content)) BETWEEN 1 AND 500
    )
  ) NOT VALID;

ALTER TABLE public.task_messages
  VALIDATE CONSTRAINT ck_task_messages_comment_content;

DROP POLICY IF EXISTS "space members can insert task messages" ON public.task_messages;

CREATE POLICY "space members can insert task messages" ON public.task_messages
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.tasks
      WHERE tasks.id = task_messages.task_id
        AND is_space_member(tasks.space_id)
        AND (
          task_messages.type <> 'comment'
          OR (
            tasks.status <> 'completed'
            AND coalesce(tasks.is_deleted, false) = false
          )
        )
    )
  );
```

- [ ] **Step 2: Review push function privacy behavior**

Check `supabase/functions/send-push-notification/index.ts` keeps comment notification content generic:

```ts
if (record.type === "comment") {
  return { title: "留言", body: "伴侣给你留了言", eventType: "task_comment" };
}
```

Expected: no message body content is exposed in APNs.

- [ ] **Step 3: Commit backend constraint**

Run:

```bash
git diff --check
git add supabase/migrations/040_task_message_comments_constraints.sql
git commit -m "chore: constrain task message comments"
```

Expected: commit succeeds with only the migration file staged.

---

## Task 2: Domain Models and SwiftData Schema

**Files:**
- Modify: `Together/Domain/Models/TaskMessage.swift`
- Modify: `Together/Persistence/Models/PersistentTaskMessage.swift`
- Create: `Together/Persistence/Models/PersistentTaskChatReadState.swift`
- Modify: `Together/Persistence/PersistenceController.swift`
- Modify: `Together/Services/MockServiceFactory.swift`
- Modify: every test `ModelContainer` builder that currently includes `PersistentTaskMessage.self`
- Test: `TogetherTests/TaskMessageRepositoryTests.swift`

- [ ] **Step 1: Write failing model tests**

Append to `TogetherTests/TaskMessageRepositoryTests.swift`:

```swift
@Test func insertComment_persistsContentAndType() async throws {
    let container = try makeContainer()
    let repo = LocalTaskMessageRepository(container: container)

    let messageID = UUID()
    let taskID = UUID()
    let senderID = UUID()
    let createdAt = Date()

    try await repo.insertComment(
        messageID: messageID,
        taskID: taskID,
        senderID: senderID,
        content: "买低脂牛奶",
        createdAt: createdAt
    )

    let context = ModelContext(container)
    let fetched = try #require(try context.fetch(FetchDescriptor<PersistentTaskMessage>()).first)
    #expect(fetched.id == messageID)
    #expect(fetched.taskID == taskID)
    #expect(fetched.senderID == senderID)
    #expect(fetched.type == TaskMessageType.comment.rawValue)
    #expect(fetched.content == "买低脂牛奶")
}

@Test func readState_persistsLastReadCreatedAt() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let taskID = UUID()
    let readAt = Date()

    context.insert(PersistentTaskChatReadState(taskID: taskID, lastReadMessageCreatedAt: readAt, updatedAt: readAt))
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<PersistentTaskChatReadState>()).first)
    #expect(fetched.taskID == taskID)
    #expect(fetched.lastReadMessageCreatedAt == readAt)
}
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests
```

Expected: FAIL because `insertComment`, `TaskMessageType`, `content`, and `PersistentTaskChatReadState` do not exist.

- [ ] **Step 3: Extend domain model**

Replace `Together/Domain/Models/TaskMessage.swift` with:

```swift
import Foundation

enum TaskMessageType: String, Codable, Hashable, Sendable {
    case comment
    case nudge
    case rpsResult = "rps_result"
}

struct TaskMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID
    let senderID: UUID
    let type: TaskMessageType
    let content: String?
    let createdAt: Date
}

struct TaskChatReadState: Hashable, Sendable {
    let taskID: UUID
    let lastReadMessageCreatedAt: Date
    let updatedAt: Date
}
```

- [ ] **Step 4: Extend persistent message model**

Update `Together/Persistence/Models/PersistentTaskMessage.swift`:

```swift
@Model
final class PersistentTaskMessage {
    var id: UUID
    var taskID: UUID
    var senderID: UUID
    var type: String
    var content: String?
    var createdAt: Date

    init(
        id: UUID,
        taskID: UUID,
        senderID: UUID,
        type: String,
        content: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.senderID = senderID
        self.type = type
        self.content = content
        self.createdAt = createdAt
    }
}
```

Update the conversion extension:

```swift
extension PersistentTaskMessage {
    convenience init(message: TaskMessage) {
        self.init(
            id: message.id,
            taskID: message.taskID,
            senderID: message.senderID,
            type: message.type.rawValue,
            content: message.content,
            createdAt: message.createdAt
        )
    }

    func domainModel() -> TaskMessage {
        TaskMessage(
            id: id,
            taskID: taskID,
            senderID: senderID,
            type: TaskMessageType(rawValue: type) ?? .comment,
            content: content,
            createdAt: createdAt
        )
    }
}
```

- [ ] **Step 5: Add read-state model**

Create `Together/Persistence/Models/PersistentTaskChatReadState.swift`:

```swift
import Foundation
import SwiftData

@Model
final class PersistentTaskChatReadState {
    var taskID: UUID
    var lastReadMessageCreatedAt: Date
    var updatedAt: Date

    init(taskID: UUID, lastReadMessageCreatedAt: Date, updatedAt: Date) {
        self.taskID = taskID
        self.lastReadMessageCreatedAt = lastReadMessageCreatedAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 6: Register read-state model everywhere**

Add `PersistentTaskChatReadState.self` immediately after `PersistentTaskMessage.self` in:

```swift
PersistentTaskMessage.self,
PersistentTaskChatReadState.self,
PersistentImportantDate.self,
```

Apply this to:
- `Together/Persistence/PersistenceController.swift`
- `Together/Services/MockServiceFactory.swift`
- `TogetherTests/TaskMessageRepositoryTests.swift`
- `TogetherTests/SendReminderToPartnerTests.swift`
- every test helper found with:

```bash
rg -n "PersistentTaskMessage.self" TogetherTests Together/Services Together/Persistence
```

- [ ] **Step 7: Run model tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests
```

Expected: tests still fail only because repository protocol does not yet expose `insertComment`.

- [ ] **Step 8: Commit model changes after Task 3 passes**

Do not commit yet if protocol compile errors remain. Commit together with Task 3 repository changes.

---

## Task 3: TaskMessageRepository API

**Files:**
- Modify: `Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift`
- Modify: `Together/Services/TaskMessages/LocalTaskMessageRepository.swift`
- Modify: `Together/Services/TaskMessages/MockTaskMessageRepository.swift`
- Test: `TogetherTests/TaskMessageRepositoryTests.swift`

- [ ] **Step 1: Extend repository protocol**

Replace `TaskMessageRepositoryProtocol` with:

```swift
import Foundation

protocol TaskMessageRepositoryProtocol: Sendable {
    func insertComment(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        content: String,
        createdAt: Date
    ) async throws

    func insertNudge(
        messageID: UUID,
        taskID: UUID,
        senderID: UUID,
        createdAt: Date
    ) async throws

    func fetchMessages(taskID: UUID, limit: Int, before: Date?) async throws -> [TaskMessage]
    func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage]
    func fetchMessage(messageID: UUID) async throws -> TaskMessage?
    func markRead(taskID: UUID, through createdAt: Date) async throws
    func fetchReadState(taskID: UUID) async throws -> TaskChatReadState?
}
```

- [ ] **Step 2: Implement local repository**

Add methods to `LocalTaskMessageRepository`:

```swift
func insertComment(
    messageID: UUID,
    taskID: UUID,
    senderID: UUID,
    content: String,
    createdAt: Date
) async throws {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }
    let context = ModelContext(container)
    context.insert(
        PersistentTaskMessage(
            id: messageID,
            taskID: taskID,
            senderID: senderID,
            type: TaskMessageType.comment.rawValue,
            content: trimmed,
            createdAt: createdAt
        )
    )
    try context.save()
}

func fetchMessages(taskID: UUID, limit: Int, before: Date?) async throws -> [TaskMessage] {
    let context = ModelContext(container)
    let effectiveLimit = max(1, min(limit, 100))
    let descriptor: FetchDescriptor<PersistentTaskMessage>
    if let before {
        descriptor = FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate<PersistentTaskMessage> { message in
                message.taskID == taskID && message.createdAt < before
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    } else {
        descriptor = FetchDescriptor<PersistentTaskMessage>(
            predicate: #Predicate<PersistentTaskMessage> { message in
                message.taskID == taskID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
    var limited = descriptor
    limited.fetchLimit = effectiveLimit
    return try context.fetch(limited)
        .map { $0.domainModel() }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
}

func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage] {
    guard taskIDs.isEmpty == false else { return [:] }
    let taskIDSet = Set(taskIDs)
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PersistentTaskMessage>(
        predicate: #Predicate<PersistentTaskMessage> { message in
            taskIDSet.contains(message.taskID) && message.type == TaskMessageType.comment.rawValue
        },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    var result: [UUID: TaskMessage] = [:]
    for message in try context.fetch(descriptor) where result[message.taskID] == nil {
        result[message.taskID] = message.domainModel()
    }
    return result
}

func markRead(taskID: UUID, through createdAt: Date) async throws {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PersistentTaskChatReadState>(
        predicate: #Predicate<PersistentTaskChatReadState> { $0.taskID == taskID }
    )
    if let existing = try context.fetch(descriptor).first {
        existing.lastReadMessageCreatedAt = max(existing.lastReadMessageCreatedAt, createdAt)
        existing.updatedAt = Date()
    } else {
        context.insert(PersistentTaskChatReadState(taskID: taskID, lastReadMessageCreatedAt: createdAt, updatedAt: Date()))
    }
    try context.save()
}

func fetchReadState(taskID: UUID) async throws -> TaskChatReadState? {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PersistentTaskChatReadState>(
        predicate: #Predicate<PersistentTaskChatReadState> { $0.taskID == taskID }
    )
    return try context.fetch(descriptor).first.map {
        TaskChatReadState(
            taskID: $0.taskID,
            lastReadMessageCreatedAt: $0.lastReadMessageCreatedAt,
            updatedAt: $0.updatedAt
        )
    }
}
```

- [ ] **Step 3: Update nudge insertion to use enum**

Change existing nudge insertion:

```swift
type: TaskMessageType.nudge.rawValue,
content: nil,
createdAt: createdAt
```

- [ ] **Step 4: Update mock repository**

Replace `MockTaskMessageRepository` with a minimal in-memory actor:

```swift
actor MockTaskMessageRepository: TaskMessageRepositoryProtocol {
    private var messages: [TaskMessage] = []
    private var readStates: [UUID: TaskChatReadState] = [:]

    func insertComment(messageID: UUID, taskID: UUID, senderID: UUID, content: String, createdAt: Date) async throws {
        messages.append(TaskMessage(id: messageID, taskID: taskID, senderID: senderID, type: .comment, content: content, createdAt: createdAt))
    }

    func insertNudge(messageID: UUID, taskID: UUID, senderID: UUID, createdAt: Date) async throws {
        messages.append(TaskMessage(id: messageID, taskID: taskID, senderID: senderID, type: .nudge, content: nil, createdAt: createdAt))
    }

    func fetchMessages(taskID: UUID, limit: Int, before: Date?) async throws -> [TaskMessage] {
        messages
            .filter { message in
                message.taskID == taskID && (before.map { cutoff in message.createdAt < cutoff } ?? true)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(limit)
    }

    func fetchLatestComments(taskIDs: [UUID]) async throws -> [UUID: TaskMessage] {
        let taskIDSet = Set(taskIDs)
        return Dictionary(
            grouping: messages.filter { taskIDSet.contains($0.taskID) && $0.type == .comment },
            by: \.taskID
        ).compactMapValues { $0.sorted { $0.createdAt < $1.createdAt }.last }
    }

    func fetchMessage(messageID: UUID) async throws -> TaskMessage? {
        messages.first { $0.id == messageID }
    }

    func markRead(taskID: UUID, through createdAt: Date) async throws {
        readStates[taskID] = TaskChatReadState(taskID: taskID, lastReadMessageCreatedAt: createdAt, updatedAt: Date())
    }

    func fetchReadState(taskID: UUID) async throws -> TaskChatReadState? {
        readStates[taskID]
    }
}
```

- [ ] **Step 5: Run repository tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests
```

Expected: PASS.

- [ ] **Step 6: Commit models and repository**

Run:

```bash
git diff --check
git add Together/Domain/Models/TaskMessage.swift Together/Persistence/Models/PersistentTaskMessage.swift Together/Persistence/Models/PersistentTaskChatReadState.swift Together/Persistence/PersistenceController.swift Together/Services/MockServiceFactory.swift Together/Domain/Protocols/TaskMessageRepositoryProtocol.swift Together/Services/TaskMessages/LocalTaskMessageRepository.swift Together/Services/TaskMessages/MockTaskMessageRepository.swift TogetherTests
git commit -m "feat: add task message comment storage"
```

Expected: commit succeeds.

---

## Task 4: Application Service Comment Writes

**Files:**
- Modify: `Together/Application/Tasks/TaskApplicationServiceProtocol.swift`
- Modify: `Together/Application/Tasks/DefaultTaskApplicationService.swift`
- Modify: `Together/Services/Items/LocalItemRepository.swift`
- Modify: `Together/Services/Items/MockItemRepository.swift`
- Test: `TogetherTests/TogetherTests.swift`
- Test: `TogetherTests/SendReminderToPartnerTests.swift`

- [ ] **Step 1: Add failing application service tests**

Add tests near existing assignment message tests in `TogetherTests/TogetherTests.swift`:

```swift
@Test func createPartnerTask_assignmentNoteWritesCommentNotAssignmentMessages() async throws {
    let persistence = try PersistenceController(inMemory: true)
    let spy = SpyCoordinator()
    let itemRepository = LocalItemRepository(container: persistence.container, syncCoordinator: spy)
    let messageRepository = LocalTaskMessageRepository(container: persistence.container)
    let service = DefaultTaskApplicationService(
        itemRepository: itemRepository,
        taskMessageRepository: messageRepository,
        syncCoordinator: spy,
        reminderScheduler: NoopReminderScheduler()
    )
    let spaceID = UUID()
    let actorID = UUID()
    var draft = TaskDraft(title: "买牛奶")
    draft.assigneeMode = .partner
    draft.assignmentNote = "买低脂的"

    let item = try await service.createTask(in: spaceID, actorID: actorID, draft: draft)
    #expect(item.assignmentMessages.isEmpty)

    let comments = try await messageRepository.fetchMessages(taskID: item.id, limit: 20, before: nil)
    #expect(comments.count == 1)
    #expect(comments.first?.type == .comment)
    #expect(comments.first?.content == "买低脂的")
}

@Test func sendTaskComment_completedTaskThrows() async throws {
    let persistence = try PersistenceController(inMemory: true)
    let spy = SpyCoordinator()
    let itemRepository = LocalItemRepository(container: persistence.container, syncCoordinator: spy)
    let messageRepository = LocalTaskMessageRepository(container: persistence.container)
    let service = DefaultTaskApplicationService(
        itemRepository: itemRepository,
        taskMessageRepository: messageRepository,
        syncCoordinator: spy,
        reminderScheduler: NoopReminderScheduler()
    )
    let spaceID = UUID()
    let actorID = UUID()
    let completed = Item(
        id: UUID(), spaceID: spaceID, listID: nil, projectID: nil, creatorID: actorID,
        title: "完成的任务", notes: nil, locationText: nil, executionRole: .collaborator,
        assigneeMode: .both, dueAt: nil, hasExplicitTime: false, remindAt: nil,
        status: .completed, assignmentState: .completed, latestResponse: nil,
        responseHistory: [], assignmentMessages: [], lastActionByUserID: actorID,
        lastActionAt: Date(), createdAt: Date(), updatedAt: Date(), completedAt: Date(),
        isPinned: false, isDraft: false
    )
    _ = try await itemRepository.saveItem(completed)

    await #expect(throws: RepositoryError.notFound) {
        _ = try await service.sendTaskComment(in: spaceID, taskID: completed.id, actorID: actorID, content: "还要聊")
    }
}
```

- [ ] **Step 2: Extend protocol**

Add to `TaskApplicationServiceProtocol`:

```swift
func sendTaskComment(
    in spaceID: UUID,
    taskID: UUID,
    actorID: UUID,
    content: String
) async throws -> TaskMessage?
```

- [ ] **Step 3: Implement comment write helper**

Add to `DefaultTaskApplicationService`:

```swift
@discardableResult
func sendTaskComment(
    in spaceID: UUID,
    taskID: UUID,
    actorID: UUID,
    content: String
) async throws -> TaskMessage? {
    let item = try await existingTask(in: spaceID, taskID: taskID)
    guard item.assigneeMode == .partner || item.assigneeMode == .both else { throw RepositoryError.notFound }
    guard item.status != .completed, item.assignmentState != .completed, item.isArchived == false else {
        throw RepositoryError.notFound
    }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    guard trimmed.count <= 500 else { throw RepositoryError.notFound }

    let messageID = UUID()
    let createdAt = Date.now
    try await taskMessageRepository.insertComment(
        messageID: messageID,
        taskID: taskID,
        senderID: actorID,
        content: trimmed,
        createdAt: createdAt
    )
    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .taskMessage, operation: .upsert, recordID: messageID, spaceID: spaceID)
    )
    return TaskMessage(id: messageID, taskID: taskID, senderID: actorID, type: .comment, content: trimmed, createdAt: createdAt)
}
```

Use a domain-specific error later if the app already has a better validation error; keep this first implementation aligned with existing repository error style.

- [ ] **Step 4: Move create-task assignment note into task_messages**

In `createTask`, set `assignmentMessages: []` when building `Item`. After `saveItem`, insert the note:

```swift
let saved = try await itemRepository.saveItem(item)
await syncCoordinator.recordLocalChange(SyncChange(entityKind: .task, operation: .upsert, recordID: saved.id, spaceID: spaceID))

if draft.assigneeMode == .partner,
   let note = draft.assignmentNote?.trimmingCharacters(in: .whitespacesAndNewlines),
   note.isEmpty == false {
    _ = try await sendTaskComment(in: spaceID, taskID: saved.id, actorID: actorID, content: note)
}

await reminderScheduler.syncTaskReminder(for: saved)
return saved
```

- [ ] **Step 5: Move update-task assignment note into task_messages**

In `updateTask`, remove the append to `item.assignmentMessages`. After saving and recording task upsert:

```swift
if draft.assigneeMode == .partner,
   let note = draft.assignmentNote?.trimmingCharacters(in: .whitespacesAndNewlines),
   note.isEmpty == false {
    _ = try await sendTaskComment(in: spaceID, taskID: saved.id, actorID: actorID, content: note)
}
```

- [ ] **Step 6: Move response messages into task_messages**

In `LocalItemRepository.updateItemStatus` and `MockItemRepository.updateItemStatus`, stop appending `TaskAssignmentMessage` when response message is present. Keep `ItemResponse.message` in `responseHistory`.

In `DefaultTaskApplicationService.respondToTask`, after the task upsert:

```swift
if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
   message.isEmpty == false {
    _ = try await sendTaskComment(in: spaceID, taskID: item.id, actorID: actorID, content: message)
}
```

- [ ] **Step 7: Keep quick-message compatibility**

Change `appendAssignmentMessage` implementation to call `sendTaskComment` and return the current task:

```swift
func appendAssignmentMessage(in spaceID: UUID, taskID: UUID, actorID: UUID, message: String) async throws -> Item {
    _ = try await sendTaskComment(in: spaceID, taskID: taskID, actorID: actorID, content: message)
    return try await existingTask(in: spaceID, taskID: taskID)
}
```

- [ ] **Step 8: Run application tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TogetherTests -only-testing:TogetherTests/SendReminderToPartnerTests
```

Expected: PASS or only unrelated tests fail. Any assignment-message expectation that assumes new writes go to `assignmentMessages` must be updated to expect `task_messages`.

- [ ] **Step 9: Commit application service changes**

Run:

```bash
git diff --check
git add Together/Application/Tasks Together/Services/Items TogetherTests
git commit -m "feat: write pair task comments to task messages"
```

Expected: commit succeeds.

---

## Task 5: Supabase TaskMessage Push/Pull

**Files:**
- Modify: `Together/Sync/SyncCoordinatorProtocol.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Modify: `TogetherTests/TaskMessagePushDTOTests.swift`
- Create: `TogetherTests/TaskMessageSyncTests.swift`

- [ ] **Step 1: Write DTO encoding test for content**

Extend `TaskMessagePushDTOTests`:

```swift
@Test func encode_commentIncludesContentAndSupabaseSender() throws {
    let dto = TaskMessagePushDTO(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        taskId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        senderId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        senderSupabaseUserID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        type: TaskMessageType.comment.rawValue,
        content: "买低脂牛奶",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = try #require(String(data: try encoder.encode(dto), encoding: .utf8))

    #expect(json.contains("\"type\":\"comment\""))
    #expect(json.contains("\"content\":\"买低脂牛奶\""))
    #expect(json.contains("\"sender_supabase_user_id\":\"44444444-4444-4444-4444-444444444444\""))
}
```

- [ ] **Step 2: Extend push DTO**

Modify `TaskMessagePushDTO`:

```swift
struct TaskMessagePushDTO: Encodable, Sendable {
    let id: UUID
    let taskId: UUID
    let senderId: UUID
    let senderSupabaseUserID: UUID?
    let type: String
    let content: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case taskId = "task_id"
        case senderId = "sender_id"
        case senderSupabaseUserID = "sender_supabase_user_id"
        case createdAt = "created_at"
    }

    nonisolated init(from persistent: PersistentTaskMessage, supabaseUserID: UUID? = nil) {
        self.id = persistent.id
        self.taskId = persistent.taskID
        self.senderId = persistent.senderID
        self.senderSupabaseUserID = supabaseUserID
        self.type = persistent.type
        self.content = persistent.content
        self.createdAt = persistent.createdAt
    }
}
```

Update the manual initializer to include `content: String? = nil`.

- [ ] **Step 3: Rename push-only comments**

In `SyncCoordinatorProtocol`, change the task message comment:

```swift
case taskMessage   // Supabase task_messages event stream: comments, nudges, future task-scoped events
```

In `SupabaseSyncService`, update the DTO comment to remove “write-only”.

- [ ] **Step 4: Add pull DTO**

Add below `TaskMessagePushDTO`:

```swift
struct TaskMessagePullDTO: Decodable, Sendable {
    let id: UUID
    let taskId: UUID
    let senderId: UUID
    let senderSupabaseUserID: UUID?
    let type: String
    let content: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case taskId = "task_id"
        case senderId = "sender_id"
        case senderSupabaseUserID = "sender_supabase_user_id"
        case createdAt = "created_at"
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentTaskMessage>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.taskID = taskId
            existing.senderID = senderId
            existing.type = type
            existing.content = content
            existing.createdAt = createdAt
        } else {
            context.insert(PersistentTaskMessage(
                id: id,
                taskID: taskId,
                senderID: senderId,
                type: type,
                content: content,
                createdAt: createdAt
            ))
        }
    }
}
```

- [ ] **Step 5: Add pullTaskMessages method**

In `SupabaseSyncService`, add:

```swift
private func pullTaskMessages(spaceID: UUID, since: String) async throws {
    let overlapSince = ISO8601DateFormatter().date(from: since)
        .flatMap { Calendar.current.date(byAdding: .minute, value: -10, to: $0) }
        .map { ISO8601DateFormatter().string(from: $0) } ?? since

    let rows: [TaskMessagePullDTO] = try await client.from("task_messages")
        .select("id, task_id, sender_id, sender_supabase_user_id, type, content, created_at, tasks!inner(space_id)")
        .eq("tasks.space_id", value: spaceID.uuidString)
        .gte("created_at", value: overlapSince)
        .order("created_at", ascending: true)
        .execute()
        .value

    let context = ModelContext(modelContainer)
    for row in rows {
        row.applyToLocal(context: context)
    }
    try context.save()
}
```

- [ ] **Step 6: Wire catch-up and realtime**

In `catchUp`, call after `pullTasks`:

```swift
try await pullTaskMessages(spaceID: spaceID, since: sinceISO)
```

In Realtime setup, add task messages stream:

```swift
let messagesStream = await channel.postgresChange(
    AnyAction.self,
    schema: "public",
    table: "task_messages"
)
```

Append listener:

```swift
listeningTasks.append(Task { [weak self] in
    for await change in messagesStream {
        await self?.handleRealtimeChange(change, table: "task_messages")
    }
})
```

- [ ] **Step 7: Preserve FK retry**

In `push()` or outbox drain logic, verify failed `.taskMessage` push is not deleted when Supabase rejects due to missing parent `task_id`. If current code deletes on any thrown error, change it so thrown errors keep the sync change for retry.

Expected behavior:

```swift
do {
    try await pushUpsert(...)
    deleteOutboxRow()
} catch {
    keepOutboxRowAndMarkFailed()
}
```

- [ ] **Step 8: Run sync tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessagePushDTOTests
```

Expected: PASS.

- [ ] **Step 9: Commit sync work**

Run:

```bash
git diff --check
git add Together/Sync TogetherTests/TaskMessagePushDTOTests.swift TogetherTests/TaskMessageSyncTests.swift
git commit -m "feat: sync task message comments"
```

Expected: commit succeeds.

---

## Task 6: Chat Timeline ViewModel

**Files:**
- Create: `Together/Features/Home/TaskChatTimelineEntry.swift`
- Create: `Together/Features/Home/TaskChatViewModel.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Test: `TogetherTests/TaskChatViewModelTests.swift`

- [ ] **Step 1: Add timeline entry model**

Create `Together/Features/Home/TaskChatTimelineEntry.swift`:

```swift
import Foundation

enum TaskChatTimelineEntry: Identifiable, Hashable, Sendable {
    case system(key: String, text: String, createdAt: Date)
    case nudge(TaskMessage)
    case comment(TaskMessage)

    var id: String {
        switch self {
        case .system(let key, _, _): "system-\(key)"
        case .nudge(let message): "nudge-\(message.id.uuidString)"
        case .comment(let message): "comment-\(message.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case .system(_, _, let createdAt): createdAt
        case .nudge(let message): message.createdAt
        case .comment(let message): message.createdAt
        }
    }
}

enum TaskChatTimelineBuilder {
    static func build(task: Item, messages: [TaskMessage]) -> [TaskChatTimelineEntry] {
        var result: [TaskChatTimelineEntry] = [
            .system(key: "\(task.id.uuidString)-assigned", text: "任务已指派", createdAt: task.createdAt)
        ]
        for response in task.responseHistory {
            let text = response.kind == .willing ? "已接受任务" : "已拒绝任务"
            result.append(.system(
                key: "\(task.id.uuidString)-response-\(response.respondedAt.timeIntervalSince1970)",
                text: text,
                createdAt: response.respondedAt
            ))
        }
        if let completedAt = task.completedAt {
            result.append(.system(key: "\(task.id.uuidString)-completed", text: "任务已完成", createdAt: completedAt))
        }
        for message in messages {
            switch message.type {
            case .comment:
                result.append(.comment(message))
            case .nudge:
                result.append(.nudge(message))
            case .rpsResult:
                break
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return sortRank(lhs) < sortRank(rhs)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func sortRank(_ entry: TaskChatTimelineEntry) -> Int {
        switch entry {
        case .system: return 0
        case .nudge: return 1
        case .comment: return 2
        }
    }
}
```

- [ ] **Step 2: Add ViewModel skeleton**

Create `Together/Features/Home/TaskChatViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TaskChatViewModel {
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let taskMessageRepository: TaskMessageRepositoryProtocol
    private let sessionStore: SessionStore

    private(set) var task: Item
    private(set) var entries: [TaskChatTimelineEntry] = []
    var draftText = ""
    var isSending = false
    var errorText: String?

    var canSend: Bool {
        task.status != .completed && task.assignmentState != .completed
    }

    init(
        task: Item,
        taskApplicationService: TaskApplicationServiceProtocol,
        taskMessageRepository: TaskMessageRepositoryProtocol,
        sessionStore: SessionStore
    ) {
        self.task = task
        self.taskApplicationService = taskApplicationService
        self.taskMessageRepository = taskMessageRepository
        self.sessionStore = sessionStore
    }
}
```

- [ ] **Step 3: Implement load and send**

Add:

```swift
func load() async {
    do {
        let messages = try await taskMessageRepository.fetchMessages(taskID: task.id, limit: 50, before: nil)
        entries = TaskChatTimelineBuilder.build(task: task, messages: messages)
        if let last = messages.last {
            try await taskMessageRepository.markRead(taskID: task.id, through: last.createdAt)
        }
    } catch {
        errorText = "消息暂时无法加载"
    }
}

func send() async {
    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }
    guard trimmed.count <= 500 else {
        errorText = "留言最多 500 字"
        return
    }
    guard canSend else { return }
    guard let spaceID = sessionStore.currentSpace?.id, let actorID = sessionStore.currentUser?.id else { return }

    isSending = true
    defer { isSending = false }
    do {
        if let message = try await taskApplicationService.sendTaskComment(in: spaceID, taskID: task.id, actorID: actorID, content: trimmed) {
            entries.append(.comment(message))
            draftText = ""
            try await taskMessageRepository.markRead(taskID: task.id, through: message.createdAt)
        }
    } catch {
        errorText = "发送失败，请重试"
    }
}
```

- [ ] **Step 4: Add ViewModel tests**

Create `TogetherTests/TaskChatViewModelTests.swift` with tests:

```swift
import Foundation
import Testing
@testable import Together

@MainActor
struct TaskChatViewModelTests {
    @Test func timeline_sortsSystemNudgeThenCommentAtSameTimestamp() {
        let taskID = UUID()
        let actorID = UUID()
        let now = Date()
        let task = Item(
            id: taskID,
            spaceID: UUID(),
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "买牛奶",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            assigneeMode: .partner,
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            status: .pendingConfirmation,
            assignmentState: .pendingResponse,
            latestResponse: nil,
            responseHistory: [],
            assignmentMessages: [],
            lastActionByUserID: actorID,
            lastActionAt: now,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            isPinned: false,
            isDraft: false
        )
        let nudge = TaskMessage(
            id: UUID(),
            taskID: taskID,
            senderID: actorID,
            type: .nudge,
            content: nil,
            createdAt: now
        )
        let comment = TaskMessage(
            id: UUID(),
            taskID: taskID,
            senderID: actorID,
            type: .comment,
            content: "买低脂的",
            createdAt: now
        )

        let entries = TaskChatTimelineBuilder.build(task: task, messages: [comment, nudge])

        #expect(entries.count == 3)
        if case .system = entries[0] {} else { Issue.record("first entry should be system") }
        if case .nudge = entries[1] {} else { Issue.record("second entry should be nudge") }
        if case .comment = entries[2] {} else { Issue.record("third entry should be comment") }
    }
}
```

- [ ] **Step 5: Run ViewModel tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskChatViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit ViewModel**

Run:

```bash
git diff --check
git add Together/Features/Home/TaskChatTimelineEntry.swift Together/Features/Home/TaskChatViewModel.swift TogetherTests/TaskChatViewModelTests.swift
git commit -m "feat: add task chat view model"
```

Expected: commit succeeds.

---

## Task 7: Home Latest Comment Preview

**Files:**
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `Together/Features/Home/HomeView.swift`
- Modify: `Together/PreviewContent/MockDataFactory.swift`

- [ ] **Step 0: Inject task message repository into HomeViewModel**

Update `HomeViewModel` initializer:

```swift
private let taskMessageRepository: TaskMessageRepositoryProtocol

init(
    sessionStore: SessionStore,
    taskApplicationService: TaskApplicationServiceProtocol,
    itemRepository: ItemRepositoryProtocol,
    taskTemplateRepository: TaskTemplateRepositoryProtocol,
    taskMessageRepository: TaskMessageRepositoryProtocol
) {
    self.sessionStore = sessionStore
    self.taskApplicationService = taskApplicationService
    self.itemRepository = itemRepository
    self.taskTemplateRepository = taskTemplateRepository
    self.taskMessageRepository = taskMessageRepository
}
```

Update all `HomeViewModel(...)` call sites to pass the same `taskMessageRepository` already present in `AppContainer` / `LocalServiceFactory`.

- [ ] **Step 1: Extend `HomeTimelineEntry`**

Add fields:

```swift
let latestComment: TaskMessage?
let hasUnreadComment: Bool
```

Keep `messagePreview` temporarily for legacy fallback.

- [ ] **Step 2: Add latest comment cache to HomeViewModel**

Add:

```swift
private var latestCommentsByTaskID: [UUID: TaskMessage] = [:]
private var chatReadStatesByTaskID: [UUID: TaskChatReadState] = [:]
```

After loading visible Today items, call:

```swift
private func refreshLatestComments(for items: [Item]) async {
    let taskIDs = items
        .filter { isPairModeActive && ($0.assigneeMode == .partner || $0.assigneeMode == .both) }
        .map(\.id)
    do {
        latestCommentsByTaskID = try await taskMessageRepository.fetchLatestComments(taskIDs: taskIDs)
    } catch {
        latestCommentsByTaskID = [:]
    }
}
```

If `HomeViewModel` does not currently hold `taskMessageRepository`, inject it through its initializer from `AppContext` / service factory.

- [ ] **Step 3: Update entry creation**

In `makeTimelineEntry`, derive:

```swift
let latestComment = latestCommentsByTaskID[item.id]
let fallbackPreview = item.assignmentMessages.last?.body
let latestPreview = latestComment?.content ?? fallbackPreview
let latestAuthorName = latestComment.map { latestCommentAuthorName(for: $0) } ?? latestMessageAuthorName(for: item)
```

Set:

```swift
messagePreview: isPairMode ? latestPreview : nil,
latestComment: latestComment,
latestMessageAuthorName: latestAuthorName,
hasUnreadComment: hasUnread(latestComment, taskID: item.id)
```

Add helper:

```swift
private func hasUnread(_ message: TaskMessage?, taskID: UUID) -> Bool {
    guard let message else { return false }
    guard message.senderID != sessionStore.currentUser?.id else { return false }
    guard let readAt = chatReadStatesByTaskID[taskID]?.lastReadMessageCreatedAt else { return true }
    return message.createdAt > readAt
}
```

Add task lookup and chat ViewModel factory:

```swift
func item(for itemID: UUID) -> Item? {
    items.first { $0.id == itemID }
}

func makeTaskChatViewModel(for item: Item) -> TaskChatViewModel {
    TaskChatViewModel(
        task: item,
        taskApplicationService: taskApplicationService,
        taskMessageRepository: taskMessageRepository,
        sessionStore: sessionStore
    )
}
```

- [ ] **Step 4: Make message zone tappable**

Add a closure to `PairTimelineCard`:

```swift
let onOpenChat: () -> Void
```

Wrap `messageIdentityRow` message zone in a Button or make the entire identity row a button only when chat is available:

```swift
Button(action: onOpenChat) {
    messageIdentityRow
        .frame(minHeight: 44, alignment: .center)
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
.accessibilityLabel(chatAccessibilityLabel)
```

Do not include the reminder/completion button inside this Button.

Add the computed label inside `PairTimelineCard`:

```swift
private var chatAccessibilityLabel: String {
    if let messagePreview {
        return "任务留言，最后一条 \(messagePreview)，点按打开聊天"
    }
    return "任务留言，点按打开聊天"
}
```

- [ ] **Step 5: Run build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit preview integration**

Run:

```bash
git diff --check
git add Together/Features/Home/HomeViewModel.swift Together/Features/Home/HomeView.swift Together/PreviewContent/MockDataFactory.swift
git commit -m "feat: show latest task chat preview"
```

Expected: commit succeeds.

---

## Task 8: TaskChatPanelView and Morph Overlay

**Files:**
- Create: `Together/Features/Home/TaskChatPanelView.swift`
- Modify: `Together/Features/Home/HomeView.swift`

- [ ] **Step 1: Create chat panel view**

Create `TaskChatPanelView.swift`:

```swift
import SwiftUI

struct TaskChatPanelView: View {
    @Bindable var viewModel: TaskChatViewModel
    let currentUserID: UUID?
    let partnerAvatar: HomeAvatar?
    let currentUserAvatar: HomeAvatar?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: AppTheme.spacing.sm) {
                    ForEach(viewModel.entries) { entry in
                        row(for: entry)
                    }
                }
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.md)
            }
            composer
        }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: AppTheme.radius.xxl, style: .continuous))
        .task { await viewModel.load() }
    }
}
```

Add `header`, `row(for:)`, and `composer` in the same file. Use existing `UserAvatarView` or `PairTimelineAvatarStrip` components for avatars; do not create a separate image loading system.

- [ ] **Step 2: Implement message rows**

Use this structure for comments:

```swift
@ViewBuilder
private func commentRow(_ message: TaskMessage) -> some View {
    let isMe = message.senderID == currentUserID
    HStack(alignment: .bottom, spacing: AppTheme.spacing.sm) {
        if isMe { Spacer(minLength: 44) } else { avatar(for: message.senderID) }
        Text(message.content ?? "")
            .font(AppTheme.typography.sized(15, weight: .medium))
            .foregroundStyle(AppTheme.colors.body)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.sm)
            .background(isMe ? AppTheme.colors.coral.opacity(0.14) : AppTheme.colors.sky.opacity(0.14), in: .rect(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 260, alignment: isMe ? .trailing : .leading)
        if isMe { avatar(for: message.senderID) } else { Spacer(minLength: 44) }
    }
}
```

Ensure text can wrap inside the panel; only the card preview is single-line.

Add an avatar helper in the same view:

```swift
@ViewBuilder
private func avatar(for userID: UUID) -> some View {
    let avatar = userID == currentUserID ? currentUserAvatar : partnerAvatar
    if let avatar {
        UserAvatarView(
            avatarAsset: avatar.avatarAsset,
            displayName: avatar.displayName,
            size: 32,
            fillColor: AppTheme.colors.surfaceElevated,
            symbolColor: AppTheme.colors.textTertiary,
            symbolFont: AppTheme.typography.sized(13, weight: .semibold),
            overrideImage: avatar.overrideImage
        )
    } else {
        Circle()
            .fill(AppTheme.colors.surfaceElevated)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "person.fill")
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
            }
    }
}
```

- [ ] **Step 3: Implement composer**

Use `TextField(axis: .vertical)`:

```swift
private var composer: some View {
    HStack(alignment: .bottom, spacing: AppTheme.spacing.sm) {
        TextField(viewModel.canSend ? "写一句回复..." : "任务已完成，不能继续留言", text: $viewModel.draftText, axis: .vertical)
            .lineLimit(1...4)
            .disabled(viewModel.canSend == false || viewModel.isSending)
        Button {
            Task { await viewModel.send() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30, weight: .semibold))
        }
        .disabled(viewModel.canSend == false || viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(AppTheme.spacing.md)
    .background(.bar)
}
```

- [ ] **Step 4: Add overlay state to HomeView**

In `HomeView`, add state:

```swift
@Namespace private var taskChatNamespace
@State private var selectedChatItemID: UUID?
```

When `onOpenChat` fires:

```swift
withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
    selectedChatItemID = entry.id
}
```

Add dismiss helper:

```swift
private func dismissChat() {
    let animation: Animation = reduceMotion
        ? .easeOut(duration: 0.16)
        : .spring(response: 0.42, dampingFraction: 0.86)
    withAnimation(animation) {
        selectedChatItemID = nil
    }
}
```

Add overlay:

```swift
.overlay {
    if let selectedChatItemID,
       let item = viewModel.item(for: selectedChatItemID) {
        let chatViewModel = viewModel.makeTaskChatViewModel(for: item)
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { dismissChat() }
            TaskChatPanelView(
                viewModel: chatViewModel,
                currentUserID: appContext.sessionStore.currentUser?.id,
                partnerAvatar: nil,
                currentUserAvatar: nil,
                onDismiss: dismissChat
            )
            .padding(.horizontal, AppTheme.spacing.md)
            .safeAreaPadding(.top, AppTheme.spacing.lg)
            .safeAreaPadding(.bottom, AppTheme.spacing.md)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}
```

If `matchedGeometryEffect` causes blur or unreadable text on device, keep the same state model but use scale/opacity transition; the spec allows native-feeling overlay morph without sacrificing readability.

- [ ] **Step 5: Add Reduce Motion fallback**

Check `@Environment(\.accessibilityReduceMotion)` and use:

```swift
let animation: Animation? = reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.86)
withAnimation(animation) { selectedChatItemID = nil }
```

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit UI panel**

Run:

```bash
git diff --check
git add Together/Features/Home/TaskChatPanelView.swift Together/Features/Home/HomeView.swift
git commit -m "feat: add task chat panel"
```

Expected: commit succeeds.

---

## Task 9: Full Regression and Project Memory

**Files:**
- Modify: `docs/PROJECT_MEMORY.md`

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests -only-testing:TogetherTests/TaskMessagePushDTOTests -only-testing:TogetherTests/SendReminderToPartnerTests -only-testing:TogetherTests/TaskChatViewModelTests
```

Expected: PASS.

- [ ] **Step 2: Run full unit test suite if focused tests pass**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS. If unrelated failures appear, capture exact failing test names and do not claim full suite success.

- [ ] **Step 3: Build for simulator**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Update project memory**

Append one concise entry to `docs/PROJECT_MEMORY.md` under verification records:

```markdown
- 2026-05-01：双人任务卡片聊天方案落地：`task_messages` 成为任务聊天主数据源，`assignmentMessages` 仅保留旧数据兼容；新增任务内 comment、nudge/system timeline 聚合、latest comment 卡片预览、本地未读游标和 morph 聊天面板。验证：`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/TaskMessageRepositoryTests -only-testing:TogetherTests/TaskMessagePushDTOTests -only-testing:TogetherTests/SendReminderToPartnerTests -only-testing:TogetherTests/TaskChatViewModelTests`、`xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'`、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'` 通过。
```

- [ ] **Step 5: Commit memory and final verification**

Run:

```bash
git diff --check
git add docs/PROJECT_MEMORY.md
git commit -m "docs: record task chat implementation"
git status --short
```

Expected: status is clean.

---

## Plan Self-Review

Spec coverage:
- UI card preview: Task 7 and Task 8 cover single-line preview, separate chat entry, 44pt hit area, Material overlay, Reduce Motion, keyboard composer.
- Data source: Tasks 2-5 move comments to `task_messages`, add content, add local read state, and keep `assignmentMessages` as fallback.
- Sync/backend: Tasks 1 and 5 cover SQL constraints, push DTO content, pull/catch-up, Realtime, and FK retry.
- Permissions: Tasks 1 and 4 enforce completed/deleted task comment guard on both backend and app service.
- Tests: Tasks 2-9 include repository, application service, DTO, sync, ViewModel, build, and final regression.

Placeholder scan:
- No undefined task remains. Any instruction with an implementation choice includes a concrete fallback.

Type consistency:
- `TaskMessageType.comment.rawValue` maps to Supabase `type='comment'`.
- `PersistentTaskChatReadState.lastReadMessageCreatedAt` matches the spec.
- `sendTaskComment(in:taskID:actorID:content:)` is used consistently by service, Home, and ViewModel tasks.
