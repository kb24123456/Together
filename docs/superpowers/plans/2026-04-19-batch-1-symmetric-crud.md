# Batch 1 — 对称 CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PeriodicTask` / `ProjectSubtask` / `TaskList` / `Project` 四个同步 entity 升级到与 `Item` 对齐的「save+record+tombstone」对称 CRUD 模型，补齐 `pullProjectSubtasks`，每个 entity 配三件套测试绿灯。

**Architecture:**
- **Pattern P4**（`LocalItemRepository.saveItem/deleteItem` 模板）：Repository 内部在每个变更入口调用 `syncCoordinator.recordLocalChange`，删除统一走 tombstone（`isLocallyDeleted = true`），不再硬删。
- **Pattern P6**（DTO 三分支 applyToLocal）：UPDATE 分支遇到 `isDeleted=true` 时设置 `existing.isLocallyDeleted = true`（而不是 `context.delete(existing)`），INSERT 分支若 `!isDeleted` 才创建。
- 所有 fetch 查询 + `count` 统计都要用谓词 `$0.isLocallyDeleted == false` 过滤掉 tombstone。
- 补 `pullProjectSubtasks(spaceID:since:)` 到 `catchUp()` —— `project_subtasks` 表已有 `space_id uuid NOT NULL`（migration 002 加的）+ `deleted_at`（migration 004 补的），单步查询 `eq("space_id", ...).gte("updated_at", ...)` 即可，不需要 join。

**Tech Stack:** Swift 6 / SwiftData / Supabase swift SDK / Swift Testing (`Testing`) / Supabase MCP (`execute_sql`, `get_logs`, `apply_migration`)

---

## Pre-Flight: Playbook §4 Verification Checklist

在动工前，把 `docs/superpowers/retros/2026-04-18-pair-sync-playbook.md` §4 的清单抄进本 plan 尾部，为**每个 entity** 单独维护一份。实施过程中逐项打勾，commit message 或 PR 描述贴清单截图。

本 plan 末尾已预留 4 张空清单（§ "Verification Checklist per Entity"）。

---

## File Map

### 修改的文件

| 文件 | 内容 |
|---|---|
| `Together/Persistence/Models/PersistentPeriodicTask.swift` | 加 `isLocallyDeleted: Bool = false` |
| `Together/Persistence/Models/PersistentTaskList.swift` | 加 `isLocallyDeleted: Bool = false` |
| `Together/Persistence/Models/PersistentProject.swift` | 加 `isLocallyDeleted: Bool = false` |
| `Together/Persistence/Models/PersistentProjectSubtask.swift` | 加 `isLocallyDeleted: Bool = false` |
| `Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift` | 注入 `SyncCoordinatorProtocol`、record、tombstone |
| `Together/Services/TaskLists/LocalTaskListRepository.swift` | `fetchTaskLists` / taskCount 加 tombstone filter |
| `Together/Services/Projects/LocalProjectRepository.swift` | `deleteProject` / `deleteSubtask` 改 tombstone；所有 fetch 加 filter |
| `Together/Sync/SupabaseSyncService.swift` | 4 个 DTO `applyToLocal` UPDATE 分支 `context.delete` → tombstone；新增 `pullProjectSubtasks`；`catchUp` 调用；`ProjectSubtaskDTO.init(from:projectSpaceID:)` 新签名 |
| `Together/Services/LocalServiceFactory.swift` | `LocalPeriodicTaskRepository` 构造传入 `syncCoordinator` |
| `Together/Domain/Protocols/PeriodicTaskRepositoryProtocol.swift` | 如需 `deleteTask` 语义变化则同步 |

### 新建的文件

| 文件 | 内容 |
|---|---|
| `TogetherTests/PeriodicTaskDTOInsertTests.swift` | Insert/update/tombstone 三断言 |
| `TogetherTests/PeriodicTaskDTOConflictTests.swift` | 旧 DTO 不覆盖 |
| `TogetherTests/PeriodicTaskRepositorySyncTests.swift` | save/delete 触发 record |
| `TogetherTests/ProjectSubtaskDTOInsertTests.swift` | 同上 |
| `TogetherTests/ProjectSubtaskDTOConflictTests.swift` | 同上 |
| `TogetherTests/ProjectSubtaskRepositorySyncTests.swift` | 用 `LocalProjectRepository.addSubtask/deleteSubtask` 触发 record |
| `TogetherTests/TaskListDTOInsertTests.swift` | 同上 |
| `TogetherTests/TaskListDTOConflictTests.swift` | 同上 |
| `TogetherTests/TaskListRepositorySyncTests.swift` | 同上 |
| `TogetherTests/ProjectDTOInsertTests.swift` | 同上 |
| `TogetherTests/ProjectDTOConflictTests.swift` | 同上 |
| `TogetherTests/ProjectRepositorySyncTests.swift` | 同上 |

### 不改的文件（明确列出以防误改）

- `Together/Services/Items/LocalItemRepository.swift`（已是 Pattern P4 标杆，不动）
- `Together/Sync/SyncCoordinatorProtocol.swift`（`SyncEntityKind` 四个 case 都已存在）
- Supabase schema：现有 `003_sync_completeness.sql` 已经给 `task_lists` / `projects` / `periodic_tasks` / `project_subtasks` 加了 `is_deleted` + `deleted_at` 列；不需新 migration。若 Task 3 发现 `project_subtasks` 缺列，再单独新建 004。

---

## 通用基线约定（所有任务默认遵守）

1. **Swift Testing 而非 XCTest**：用 `import Testing` 和 `@Test` / `#expect`，跟随 `SyncInsertTests.swift` 现有风格。
2. **ModelContainer in-memory 全 schema**：所有测试里 `makeContainer()` 必须列出 15 个 `Persistent*` 模型（参考 `TogetherTests/SyncInsertTests.swift:11-30`），缺一个就 `loadIssueModelContainer` 崩。
3. **SpyCoordinator 已存在**：位于 `TogetherTests/ItemRepositorySyncTests.swift:8-35`，跨文件直接引用（同 module `@testable import Together`）。**不要重复实现**。
4. **诊断日志统一用 `os.Logger`**：`Logger(subsystem: "com.pigdog.Together", category: "<feature>")`。禁止 `print`。
5. **每个 entity commit message 格式**：
   ```
   feat(sync): <entity> symmetric CRUD — tombstone, record, pull

   - PersistentX.isLocallyDeleted + query filter
   - <Repository> records save/delete via SyncCoordinator
   - <DTO>.applyToLocal UPDATE tombstone instead of hard delete
   - 3 tests passing: <Entity>DTOInsertTests / <Entity>DTOConflictTests / <Entity>RepositorySyncTests

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   ```
6. **不新建 `print`、不留 `// TODO`**：照 playbook §A1，所有 TODO 必须配失败测试或直接实现。
7. **每个任务结尾都要跑 build + 全测试绿灯再 commit**：不要攒着一起 commit，单 entity 一个 atomic commit。

---

## Task 1: 准备 — 创建 plan 跟踪文档 + 确认 schema 就位

**Files:**
- Create: `docs/superpowers/plans/2026-04-19-batch-1-symmetric-crud.md`（已是本文件）
- Modify: 本文件尾部的 "Verification Checklist per Entity" 区块

- [ ] **Step 1: 确认 Supabase 已有 `is_deleted` / `deleted_at` 列**

用 MCP 查 4 张表的列定义：

```
execute_sql(project_id="nxielmwdoiwiwhzczrmt", query=
  "SELECT table_name, column_name, data_type
   FROM information_schema.columns
   WHERE table_schema='public'
     AND table_name IN ('task_lists','projects','project_subtasks','periodic_tasks')
     AND column_name IN ('is_deleted','deleted_at','space_id')
   ORDER BY table_name, column_name;")
```

Expected: 4 × (`is_deleted boolean`, `deleted_at timestamp`) 齐全；`project_subtasks` 没有 `space_id`（确认是正常的）；其余三张表有 `space_id uuid NOT NULL`。

若缺列：新建 `supabase/migrations/004_tombstone_backfill.sql`，用 `apply_migration` 补上；否则跳过。

- [ ] **Step 2: 确认 Realtime publication 已包含这些表**

```
execute_sql(project_id="nxielmwdoiwiwhzczrmt", query=
  "SELECT schemaname, tablename
   FROM pg_publication_tables
   WHERE pubname='supabase_realtime'
   ORDER BY tablename;")
```

Expected: `task_lists`, `projects`, `project_subtasks`, `periodic_tasks` 全部在 publication 里。

若缺：执行 `ALTER PUBLICATION supabase_realtime ADD TABLE <missing>;`。

- [ ] **Step 3: 建分支 + 开工**

```bash
cd /Users/papertiger/Desktop/Together
git status       # 确认工作树干净（或已 stash 无关 diff）
git pull --ff-only origin main
git checkout -b batch-1-symmetric-crud
```

无需 commit（只是建分支）。

---

## Task 2: PeriodicTask 全栈升级

### File Map (Task 2)

- Modify: `Together/Persistence/Models/PersistentPeriodicTask.swift`
- Modify: `Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift`
- Modify: `Together/Services/LocalServiceFactory.swift:42`
- Modify: `Together/Sync/SupabaseSyncService.swift:1107-1143` (`PeriodicTaskDTO.applyToLocal`)
- Create: `TogetherTests/PeriodicTaskDTOInsertTests.swift`
- Create: `TogetherTests/PeriodicTaskDTOConflictTests.swift`
- Create: `TogetherTests/PeriodicTaskRepositorySyncTests.swift`

### Step 1: 给 `PersistentPeriodicTask` 加 tombstone 字段

- [ ] 用 Edit 把 `Together/Persistence/Models/PersistentPeriodicTask.swift` 的模型改成：

```swift
@Model
final class PersistentPeriodicTask {
    var id: UUID
    var spaceID: UUID?
    var creatorID: UUID
    var title: String
    var notes: String?
    var cycleRawValue: String
    var reminderRulesData: Data?
    var completionsData: Data
    var sortOrder: Double
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isLocallyDeleted: Bool = false   // 新增

    init(
        id: UUID,
        spaceID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        cycleRawValue: String,
        reminderRulesData: Data?,
        completionsData: Data,
        sortOrder: Double,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date,
        isLocallyDeleted: Bool = false   // 新增
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.cycleRawValue = cycleRawValue
        self.reminderRulesData = reminderRulesData
        self.completionsData = completionsData
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}
```

SwiftData `@Model` 的新字段**必须带默认值**，否则旧持久库打开时会迁移失败。

### Step 2: Repository 接入 syncCoordinator + tombstone + 过滤

- [ ] 重写 `Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift` 为：

```swift
import Foundation
import SwiftData

actor LocalPeriodicTaskRepository: PeriodicTaskRepositoryProtocol {
    private let container: ModelContainer
    private let syncCoordinator: SyncCoordinatorProtocol?

    init(container: ModelContainer, syncCoordinator: SyncCoordinatorProtocol? = nil) {
        self.container = container
        self.syncCoordinator = syncCoordinator
    }

    func fetchActiveTasks(spaceID: UUID?) async throws -> [PeriodicTask] {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.isActive == true && $0.isLocallyDeleted == false
                }
            )
        )
        return records
            .filter { $0.spaceID == spaceID }
            .map { $0.domainModel() }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchTask(taskID: UUID) async throws -> PeriodicTask? {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
            )
        )
        return records.first?.domainModel()
    }

    func saveTask(_ task: PeriodicTask) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == task.id }
            )
        )

        var savedTask = task
        savedTask.updatedAt = .now

        if let record = existing.first {
            record.update(from: savedTask)
            record.isLocallyDeleted = false   // 重新保存即恢复
        } else {
            context.insert(PersistentPeriodicTask(task: savedTask))
        }

        try context.save()

        if let sid = savedTask.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: savedTask.id, spaceID: sid)
            )
        }
        return savedTask
    }

    func deleteTask(taskID: UUID) async throws {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
            )
        )
        guard let record = records.first else { return }

        let spaceID = record.spaceID
        record.isLocallyDeleted = true
        record.updatedAt = .now
        try context.save()

        if let sid = spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .delete, recordID: taskID, spaceID: sid)
            )
        }
    }

    func markCompleted(taskID: UUID, periodKey: String, completedAt: Date) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
            )
        )
        guard let record = records.first else { throw PeriodicTaskError.notFound }

        var task = record.domainModel()
        if !task.isCompleted(forPeriodKey: periodKey) {
            task.completions.append(PeriodicCompletion(periodKey: periodKey, completedAt: completedAt))
            task.updatedAt = completedAt
            record.update(from: task)
            try context.save()

            if let sid = record.spaceID {
                await syncCoordinator?.recordLocalChange(
                    SyncChange(entityKind: .periodicTask, operation: .complete, recordID: taskID, spaceID: sid)
                )
            }
        }
        return task
    }

    func markIncomplete(taskID: UUID, periodKey: String) async throws -> PeriodicTask {
        let context = ModelContext(container)
        let records = try context.fetch(
            FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> {
                    $0.id == taskID && $0.isLocallyDeleted == false
                }
            )
        )
        guard let record = records.first else { throw PeriodicTaskError.notFound }

        var task = record.domainModel()
        task.completions.removeAll { $0.periodKey == periodKey }
        task.updatedAt = .now
        record.update(from: task)
        try context.save()

        if let sid = record.spaceID {
            await syncCoordinator?.recordLocalChange(
                SyncChange(entityKind: .periodicTask, operation: .upsert, recordID: taskID, spaceID: sid)
            )
        }
        return task
    }
}

enum PeriodicTaskError: Error {
    case notFound
}
```

### Step 3: 工厂注入 syncCoordinator

- [ ] Edit `Together/Services/LocalServiceFactory.swift:42`：

```swift
// 原：
let periodicTaskRepository = LocalPeriodicTaskRepository(container: modelContainer)

// 改为：
let periodicTaskRepository = LocalPeriodicTaskRepository(
    container: modelContainer,
    syncCoordinator: syncCoordinator
)
```

### Step 4: DTO applyToLocal UPDATE 分支改 tombstone

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:1107-1143`：

```swift
nonisolated func applyToLocal(context: ModelContext) {
    let descriptor = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate { $0.id == id })
    if let existing = try? context.fetch(descriptor).first {
        if updatedAt < existing.updatedAt { return } // 冲突保护
        existing.title = title
        existing.notes = notes
        existing.cycleRawValue = cycle
        if let jsonString = reminderRules, let data = jsonString.data(using: .utf8) {
            existing.reminderRulesData = data
        }
        if let jsonString = completions, let data = jsonString.data(using: .utf8) {
            existing.completionsData = data
        }
        existing.sortOrder = sortOrder
        existing.isActive = isActive
        existing.updatedAt = updatedAt
        if isDeleted {
            existing.isLocallyDeleted = true   // tombstone 代替 context.delete
        }
    } else if !isDeleted {
        let periodic = PersistentPeriodicTask(
            id: id,
            spaceID: spaceId,
            creatorID: creatorId,
            title: title,
            notes: notes,
            cycleRawValue: cycle,
            reminderRulesData: reminderRules?.data(using: .utf8),
            completionsData: completions?.data(using: .utf8) ?? Data("{}".utf8),
            sortOrder: sortOrder,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        context.insert(periodic)
    }
}
```

### Step 5: 写 `PeriodicTaskDTOInsertTests` — red first

- [ ] 创建 `TogetherTests/PeriodicTaskDTOInsertTests.swift`：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct PeriodicTaskDTOInsertTests {
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
            configurations: config
        )
    }

    @Test func periodicTaskDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id = UUID()
        let spaceID = UUID()
        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "倒垃圾")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func periodicTaskDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒厨余", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "倒厨余")
    }

    @Test func periodicTaskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "倒垃圾", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(
            id: id, spaceID: spaceID, title: "倒垃圾",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension PeriodicTaskDTO {
    static func fixture(
        id: UUID,
        spaceID: UUID,
        title: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> PeriodicTaskDTO {
        let persistent = PersistentPeriodicTask(
            id: id,
            spaceID: spaceID,
            creatorID: UUID(),
            title: title,
            notes: nil,
            cycleRawValue: PeriodicCycle.monthly.rawValue,
            reminderRulesData: nil,
            completionsData: Data("{}".utf8),
            sortOrder: 0,
            isActive: true,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        var dto = PeriodicTaskDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
```

- [ ] **Step 6: 跑测试确认 GREEN**

```bash
xcodebuild test \
  -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/PeriodicTaskDTOInsertTests \
  2>&1 | grep -E "Test case|passed|failed|TEST"
```

Expected: 3 passed。若 red：回头看 Step 4 的 tombstone 改动是否到位。

### Step 7: 写 `PeriodicTaskDTOConflictTests`

- [ ] 创建 `TogetherTests/PeriodicTaskDTOConflictTests.swift`：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct PeriodicTaskDTOConflictTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    @Test func older_dto_does_not_overwrite_newer_local() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let now = Date()
        let earlier = now.addingTimeInterval(-60)

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "newer", updatedAt: now)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "older", updatedAt: earlier)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.first?.title == "newer")
    }

    @Test func tombstone_preserved_when_stale_upsert_arrives() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let spaceID = UUID()
        let base = Date()

        PeriodicTaskDTO.fixture(id: id, spaceID: spaceID, title: "X", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()

        PeriodicTaskDTO.fixture(
            id: id, spaceID: spaceID, title: "X",
            updatedAt: base.addingTimeInterval(60), isDeleted: true
        ).applyToLocal(context: context)
        try context.save()

        // 对方 stale 消息不能复活 tombstone
        PeriodicTaskDTO.fixture(
            id: id, spaceID: spaceID, title: "X",
            updatedAt: base.addingTimeInterval(120), isDeleted: false
        ).applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}
```

- [ ] **Step 8: 跑测试确认 GREEN**

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/PeriodicTaskDTOConflictTests \
  2>&1 | grep -E "Test case|passed|failed|TEST"
```

### Step 9: 写 `PeriodicTaskRepositorySyncTests`

- [ ] 创建 `TogetherTests/PeriodicTaskRepositorySyncTests.swift`：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct PeriodicTaskRepositorySyncTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    private func makeTask(spaceID: UUID) -> PeriodicTask {
        PeriodicTask(
            id: UUID(),
            spaceID: spaceID,
            creatorID: UUID(),
            title: "每月体检",
            notes: nil,
            cycle: .monthly,
            reminderRules: [],
            completions: [],
            sortOrder: 0,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func saveTask_records_upsert() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)

        let recorded = await spy.recorded
        #expect(recorded.count == 1)
        #expect(recorded.first?.entityKind == .periodicTask)
        #expect(recorded.first?.operation == .upsert)
        #expect(recorded.first?.recordID == task.id)
        #expect(recorded.first?.spaceID == spaceID)
    }

    @Test func deleteTask_records_delete_and_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)

        try await repo.deleteTask(taskID: task.id)

        let recorded = await spy.recorded
        let deletes = recorded.filter { $0.operation == .delete }
        #expect(deletes.count == 1)
        #expect(deletes.first?.entityKind == .periodicTask)
        #expect(deletes.first?.recordID == task.id)

        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == true)
    }

    @Test func fetchActiveTasks_excludes_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let repo = LocalPeriodicTaskRepository(container: container, syncCoordinator: spy)

        let spaceID = UUID()
        let task = makeTask(spaceID: spaceID)
        _ = try await repo.saveTask(task)
        try await repo.deleteTask(taskID: task.id)

        let active = try await repo.fetchActiveTasks(spaceID: spaceID)
        #expect(active.isEmpty)
    }
}
```

- [ ] **Step 10: 跑全套 3 test suites 确认 GREEN**

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/PeriodicTaskDTOInsertTests \
  -only-testing:TogetherTests/PeriodicTaskDTOConflictTests \
  -only-testing:TogetherTests/PeriodicTaskRepositorySyncTests \
  2>&1 | grep -E "Test case|passed|failed|TEST"
```

Expected: all passed。

- [ ] **Step 11: 跑全量测试确认没有 regression**

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|passed|failed" | tail -10
```

Expected: TEST SUCCEEDED。

- [ ] **Step 12: Commit**

```bash
git add Together/Persistence/Models/PersistentPeriodicTask.swift \
        Together/Services/PeriodicTasks/LocalPeriodicTaskRepository.swift \
        Together/Services/LocalServiceFactory.swift \
        Together/Sync/SupabaseSyncService.swift \
        TogetherTests/PeriodicTaskDTOInsertTests.swift \
        TogetherTests/PeriodicTaskDTOConflictTests.swift \
        TogetherTests/PeriodicTaskRepositorySyncTests.swift

git commit -m "$(cat <<'EOF'
feat(sync): periodicTask symmetric CRUD — tombstone, record, pull

- PersistentPeriodicTask.isLocallyDeleted + fetch filter
- LocalPeriodicTaskRepository records save/delete via SyncCoordinator
- PeriodicTaskDTO.applyToLocal UPDATE tombstone instead of context.delete
- 3 tests passing: PeriodicTaskDTOInsertTests / PeriodicTaskDTOConflictTests / PeriodicTaskRepositorySyncTests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ProjectSubtask 全栈升级

### File Map (Task 3)

- Modify: `Together/Persistence/Models/PersistentProjectSubtask.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift` (`ProjectSubtaskDTO` init + applyToLocal + 新增 `pullProjectSubtasks` + `catchUp`)
- Modify: `Together/Services/Projects/LocalProjectRepository.swift` (`deleteSubtask` / `deleteProject` 改 tombstone)
- Create: `TogetherTests/ProjectSubtaskDTOInsertTests.swift`
- Create: `TogetherTests/ProjectSubtaskDTOConflictTests.swift`
- Create: `TogetherTests/ProjectSubtaskRepositorySyncTests.swift`

### Step 1: `PersistentProjectSubtask` 加 tombstone

- [ ] 改 `Together/Persistence/Models/PersistentProjectSubtask.swift`：

```swift
@Model
final class PersistentProjectSubtask {
    var id: UUID
    var projectID: UUID
    var creatorID: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date
    var isLocallyDeleted: Bool = false   // 新增

    init(
        id: UUID,
        projectID: UUID,
        creatorID: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int,
        updatedAt: Date = .now,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
    }
}
```

extensions 保持不变。

### Step 2: `ProjectSubtaskDTO` 加 `spaceId` 字段 + `deletedAt`，applyToLocal 用 tombstone

Schema 现状（2026-04-18 MCP 验证）：`project_subtasks` 有 `space_id uuid NOT NULL`（migration 002）+ `is_deleted boolean` + `deleted_at timestamptz`（migration 004）。DTO 与 schema 对齐即可，不需要两步查询。

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:996-1052`，把整个 `ProjectSubtaskDTO` 替换成：

```swift
/// 项目子任务 DTO
struct ProjectSubtaskDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let projectId: UUID
    let creatorId: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title
        case spaceId = "space_id"
        case projectId = "project_id"
        case creatorId = "creator_id"
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    /// `spaceID` 必填：project_subtasks 表的 space_id NOT NULL。
    /// 一般由 pushUpsert 从 parent project 取得，测试 fixture 直接传。
    nonisolated init(from persistent: PersistentProjectSubtask, spaceID: UUID) {
        self.id = persistent.id
        self.spaceId = spaceID
        self.projectId = persistent.projectID
        self.creatorId = persistent.creatorID
        self.title = persistent.title
        self.isCompleted = persistent.isCompleted
        self.sortOrder = persistent.sortOrder
        self.updatedAt = persistent.updatedAt
        self.isDeleted = false
        self.deletedAt = nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            if updatedAt < existing.updatedAt { return } // 冲突保护
            existing.title = title
            existing.isCompleted = isCompleted
            existing.sortOrder = sortOrder
            existing.updatedAt = updatedAt
            if isDeleted {
                existing.isLocallyDeleted = true   // tombstone
            }
        } else if !isDeleted {
            let subtask = PersistentProjectSubtask(
                id: id,
                projectID: projectId,
                creatorID: creatorId,
                title: title,
                isCompleted: isCompleted,
                sortOrder: sortOrder,
                updatedAt: updatedAt
            )
            context.insert(subtask)
        }
    }
}
```

### Step 3: `pushUpsert` 里更新 init 调用（传 spaceID）

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:333-337`：

```swift
case .projectSubtask:
    let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == recordID })
    guard let subtask = try? context.fetch(descriptor).first else { return }
    let dto = ProjectSubtaskDTO(from: subtask, spaceID: spaceID)
    try await client.from(tableName).upsert(dto, onConflict: "id").execute()
```

### Step 4: 新增 `pullProjectSubtasks(spaceID:since:)`

`project_subtasks` 表已有 `space_id uuid NOT NULL`，直接按 space 单步过滤。

- [ ] 在 `Together/Sync/SupabaseSyncService.swift:463` 之前（`pullPeriodicTasks` 函数结束后、`pullSpaceMembers` 之前）插入：

```swift
private func pullProjectSubtasks(spaceID: UUID, since: String) async throws {
    let rows: [ProjectSubtaskDTO] = try await client.from("project_subtasks")
        .select()
        .eq("space_id", value: spaceID.uuidString)
        .gte("updated_at", value: since)
        .execute()
        .value

    if !rows.isEmpty {
        let context = ModelContext(modelContainer)
        for dto in rows {
            dto.applyToLocal(context: context)
        }
        try context.save()
    }
}
```

### Step 5: `catchUp` 加调用 + Realtime 订阅确认

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:185-209`：在 `pullProjects` 之后插入 `pullProjectSubtasks`：

```swift
func catchUp() async {
    guard let spaceID else { return }
    let since = lastSyncedAt ?? Date.distantPast
    let sinceISO = ISO8601DateFormatter().string(from: since)

    do {
        try await pullTasks(spaceID: spaceID, since: sinceISO)
        try await pullTaskLists(spaceID: spaceID, since: sinceISO)
        try await pullProjects(spaceID: spaceID, since: sinceISO)
        try await pullProjectSubtasks(spaceID: spaceID, since: sinceISO)  // 新增
        try await pullPeriodicTasks(spaceID: spaceID, since: sinceISO)
        try await pullSpaceMembers(spaceID: spaceID, since: sinceISO)
        try await pullSpaces(spaceID: spaceID, since: sinceISO)

        lastSyncedAt = Date()
        logger.info("[CatchUp] ✅ 完成补拉")

        await MainActor.run {
            NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
        }
    } catch {
        logger.error("[CatchUp] ❌ \(error.localizedDescription)")
    }
}
```

- [ ] **Step 5b**: 打开 `Together/Sync/SupabaseSyncService.swift` 搜索 Realtime 订阅处（`postgresChange` 注册），**确认 `project_subtasks` 表已经被订阅**。如已有 → 跳过；如没有 → 对照 `projects` 订阅处加一条同构的订阅，并在 `handleRealtimeChange` 分发到 `ProjectSubtaskDTO.applyToLocal`。

  用 `Grep -n "project_subtasks"` 在 `SupabaseSyncService.swift` 里确认订阅是否已经 wiring。若否，补完订阅代码后再进下一步。

### Step 6: `LocalProjectRepository.deleteSubtask` 改 tombstone

- [ ] Edit `Together/Services/Projects/LocalProjectRepository.swift:229-265`：

```swift
func deleteSubtask(projectID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Project {
    let context = ModelContext(container)
    guard let record = try fetchRecord(projectID: projectID, context: context) else {
        throw RepositoryError.notFound
    }
    guard PairPermissionService.canDeleteProjectSubtask(projectCreatorID: record.creatorID, actorID: actorID) else {
        throw PermissionError.notCreator
    }
    guard let subtaskRecord = try fetchSubtaskRecord(subtaskID: subtaskID, context: context) else {
        throw RepositoryError.notFound
    }

    // Tombstone 代替硬删，防止下次 pull 复活
    subtaskRecord.isLocallyDeleted = true
    subtaskRecord.updatedAt = .now
    record.updatedAt = .now
    try context.save()

    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .projectSubtask, operation: .delete, recordID: subtaskID, spaceID: record.spaceID)
    )

    try resequenceSubtasks(projectID: projectID, context: context)
    try normalizeProjectStatus(record: record, context: context)
    try context.save()

    let remainingSubtasks = try subtasks(for: projectID, in: context)
    for sibling in remainingSubtasks {
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .projectSubtask, operation: .upsert, recordID: sibling.id, spaceID: record.spaceID)
        )
    }
    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .project, operation: .upsert, recordID: projectID, spaceID: record.spaceID)
    )

    return try await finalizedProject(projectID: projectID, context: context)
}
```

### Step 7: 所有 subtask fetch 加 tombstone 过滤

- [ ] Edit `Together/Services/Projects/LocalProjectRepository.swift` 里所有 `FetchDescriptor<PersistentProjectSubtask>` 的 predicate 加 `&& $0.isLocallyDeleted == false`：

- 行 274-278 `fetchSubtaskRecord` 保持 — 允许按 ID 精确查找（含 tombstone），因为 `deleteSubtask` 第二次调用时要能看到原 record。**不改**。
- 行 281-296 `subtasksByProject` 的 `allSubtasks` 查询加过滤。
- 行 298-304 `subtasks(for:in:)` 加过滤。
- 行 306-315 `resequenceSubtasks` 加过滤。

改法示例：

```swift
// 原：
private func subtasks(for projectID: UUID, in context: ModelContext) throws -> [ProjectSubtask] {
    let descriptor = FetchDescriptor<PersistentProjectSubtask>(
        predicate: #Predicate<PersistentProjectSubtask> { $0.projectID == projectID },
        sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
    )
    return try context.fetch(descriptor).map { $0.domainModel() }
}

// 改为：
private func subtasks(for projectID: UUID, in context: ModelContext) throws -> [ProjectSubtask] {
    let descriptor = FetchDescriptor<PersistentProjectSubtask>(
        predicate: #Predicate<PersistentProjectSubtask> {
            $0.projectID == projectID && $0.isLocallyDeleted == false
        },
        sortBy: [SortDescriptor(\PersistentProjectSubtask.sortOrder, order: .forward)]
    )
    return try context.fetch(descriptor).map { $0.domainModel() }
}
```

### Step 8: 写三件套测试

- [ ] 创建 `TogetherTests/ProjectSubtaskDTOInsertTests.swift`（template 模板同 Task 2 Step 5，但用 `ProjectSubtaskDTO.fixture(id:projectID:title:updatedAt:isDeleted:)`）：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectSubtaskDTOInsertTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    @Test func subtaskDTO_inserts_new_when_absent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "步骤一")
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "步骤一")
        #expect(fetched.first?.isLocallyDeleted == false)
    }

    @Test func subtaskDTO_updates_existing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let base = Date()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "a", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "b", updatedAt: base.addingTimeInterval(60))
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.first?.title == "b")
    }

    @Test func subtaskDTO_marks_tombstone_on_soft_delete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let base = Date()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "a", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "a",
                                  updatedAt: base.addingTimeInterval(60), isDeleted: true)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}

extension ProjectSubtaskDTO {
    static func fixture(
        id: UUID,
        projectID: UUID,
        title: String,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) -> ProjectSubtaskDTO {
        let persistent = PersistentProjectSubtask(
            id: id, projectID: projectID, creatorID: UUID(),
            title: title, isCompleted: false, sortOrder: 0, updatedAt: updatedAt
        )
        var dto = ProjectSubtaskDTO(from: persistent, spaceID: UUID())
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
```

> Fixture 里 `spaceID` 用新 UUID 即可，applyToLocal 不校验 space 归属（保存在 DTO 里只为 push 路径用）。

- [ ] 创建 `TogetherTests/ProjectSubtaskDTOConflictTests.swift`：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectSubtaskDTOConflictTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    @Test func older_dto_does_not_overwrite_newer_local() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let now = Date()
        let earlier = now.addingTimeInterval(-60)

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "newer", updatedAt: now)
            .applyToLocal(context: context)
        try context.save()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "older", updatedAt: earlier)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.first?.title == "newer")
    }

    @Test func tombstone_preserved_when_stale_upsert_arrives() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let projectID = UUID()
        let base = Date()

        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "x", updatedAt: base)
            .applyToLocal(context: context)
        try context.save()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "x",
                                  updatedAt: base.addingTimeInterval(60), isDeleted: true)
            .applyToLocal(context: context)
        try context.save()
        ProjectSubtaskDTO.fixture(id: id, projectID: projectID, title: "x",
                                  updatedAt: base.addingTimeInterval(120), isDeleted: false)
            .applyToLocal(context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(fetched.first?.isLocallyDeleted == true)
    }
}
```

- [ ] 创建 `TogetherTests/ProjectSubtaskRepositorySyncTests.swift`：

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@MainActor
struct ProjectSubtaskRepositorySyncTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: config
        )
    }

    private func makeProject(spaceID: UUID, creatorID: UUID) -> Project {
        Project(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            name: "项目 A",
            notes: nil,
            colorToken: nil,
            status: .active,
            targetDate: nil,
            remindAt: nil,
            taskCount: 0,
            subtasks: [],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
    }

    @Test func deleteSubtask_records_delete_and_tombstones() async throws {
        let container = try makeContainer()
        let spy = SpyCoordinator()
        let scheduler = NoopReminderScheduler()
        let repo = LocalProjectRepository(
            container: container,
            reminderScheduler: scheduler,
            syncCoordinator: spy
        )

        let spaceID = UUID()
        let actorID = UUID()
        let project = makeProject(spaceID: spaceID, creatorID: actorID)
        _ = try await repo.saveProject(project, actorID: actorID)

        let withSubtask = try await repo.addSubtask(
            projectID: project.id, title: "子任务", isCompleted: false,
            creatorID: actorID, actorID: actorID
        )
        let subtaskID = withSubtask.subtasks.first!.id

        _ = try await repo.deleteSubtask(projectID: project.id, subtaskID: subtaskID, actorID: actorID)

        let recorded = await spy.recorded
        let subtaskDeletes = recorded.filter {
            $0.entityKind == .projectSubtask && $0.operation == .delete
        }
        #expect(subtaskDeletes.count == 1)
        #expect(subtaskDeletes.first?.recordID == subtaskID)

        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isLocallyDeleted == true)
    }
}

// 最小 reminder scheduler 替身
actor NoopReminderScheduler: ReminderSchedulerProtocol {
    func syncProjectReminder(for project: Project) async {}
    func removeProjectReminder(for projectID: UUID) async {}
    func syncItemReminder(for item: Item) async {}
    func removeItemReminder(for itemID: UUID) async {}
    func syncPeriodicTaskReminder(for task: PeriodicTask) async {}
    func removePeriodicTaskReminder(for taskID: UUID) async {}
}
```

> **注意**：`NoopReminderScheduler` 的方法签名必须**完整匹配** `ReminderSchedulerProtocol`。在写之前 Grep 确认该协议的全部方法：`Grep -n "func " Together/Domain/Protocols/ReminderSchedulerProtocol.swift`。若协议名字不是 `ReminderSchedulerProtocol`，调整 import/方法列表。

- [ ] **Step 9: 跑 3 suites + 全量测试**

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/ProjectSubtaskDTOInsertTests \
  -only-testing:TogetherTests/ProjectSubtaskDTOConflictTests \
  -only-testing:TogetherTests/ProjectSubtaskRepositorySyncTests \
  2>&1 | grep -E "Test case|passed|failed|TEST"
```

再跑全量：

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: TEST SUCCEEDED。

- [ ] **Step 10: Commit**

```bash
git add Together/Persistence/Models/PersistentProjectSubtask.swift \
        Together/Sync/SupabaseSyncService.swift \
        Together/Services/Projects/LocalProjectRepository.swift \
        TogetherTests/ProjectSubtaskDTOInsertTests.swift \
        TogetherTests/ProjectSubtaskDTOConflictTests.swift \
        TogetherTests/ProjectSubtaskRepositorySyncTests.swift

git commit -m "$(cat <<'EOF'
feat(sync): projectSubtask symmetric CRUD — tombstone, record, pull

- PersistentProjectSubtask.isLocallyDeleted + fetch filter
- ProjectSubtaskDTO.init(from:projectSpaceID:) symmetric signature
- ProjectSubtaskDTO.applyToLocal UPDATE tombstone instead of context.delete
- pullProjectSubtasks via two-step query (projects → subtasks) wired into catchUp
- LocalProjectRepository.deleteSubtask tombstones instead of hard-delete
- 3 tests passing: ProjectSubtaskDTOInsertTests / ProjectSubtaskDTOConflictTests / ProjectSubtaskRepositorySyncTests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: TaskList 全栈升级

### File Map (Task 4)

- Modify: `Together/Persistence/Models/PersistentTaskList.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift:882-910` (`TaskListDTO.applyToLocal`)
- Modify: `Together/Services/TaskLists/LocalTaskListRepository.swift` (fetch filter)
- Create: `TogetherTests/TaskListDTOInsertTests.swift`
- Create: `TogetherTests/TaskListDTOConflictTests.swift`
- Create: `TogetherTests/TaskListRepositorySyncTests.swift`

### Step 1: `PersistentTaskList.isLocallyDeleted`

- [ ] Edit `Together/Persistence/Models/PersistentTaskList.swift`：在字段列表末尾加 `var isLocallyDeleted: Bool = false`，init 加 `isLocallyDeleted: Bool = false` 形参 + 赋值。`convenience init(list:)` / `update(from:)` 不改（Domain 层 `TaskList` 模型没有该字段，tombstone 只在 DTO 和 Repository 处理）。

### Step 2: `TaskListDTO.applyToLocal` UPDATE 分支 tombstone

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:882-910`：把 `context.delete(existing)` 换成 `existing.isLocallyDeleted = true`，形如 Task 2 Step 4。

### Step 3: `LocalTaskListRepository` 查询过滤

- [ ] Edit `Together/Services/TaskLists/LocalTaskListRepository.swift`：
  - `fetchTaskLists` 的 descriptor 谓词加 `&& $0.isLocallyDeleted == false`（line 19 / line 24 两处）
  - `taskCountsByList` 的 `FetchDescriptor<PersistentItem>` 加 `$0.isLocallyDeleted == false`（line 95-101 两处）
  - `fetchRecord(listID:)` 用于按 ID 精确查找，**不加** tombstone 过滤（需要允许 save 覆盖已 tombstoned 的同 ID 列表）

### Step 4: （可选）新增 `deleteTaskList` 方法

TaskList 当前只有 `archiveTaskList`（软归档，不 tombstone）。如果 UI 现在没有"硬删列表"路径，**跳过此 step**。

实际检查：`Grep -n "archiveTaskList\|deleteTaskList" Together/Features Together/Application`，看是否有"彻底删除"UI。若有 → 加 `deleteTaskList`；若无 → 不加，避免 YAGNI。

### Step 5: 三件套测试

- [ ] `TogetherTests/TaskListDTOInsertTests.swift`、`TaskListDTOConflictTests.swift`、`TaskListRepositorySyncTests.swift` —— 完全按 Task 2 Step 5-9 的 template，只把 `PeriodicTask` 改成 `TaskList`，`PersistentPeriodicTask` 改成 `PersistentTaskList`，`PeriodicTaskDTO` 改成 `TaskListDTO`。

`TaskListDTO.fixture` helper：

```swift
extension TaskListDTO {
    static func fixture(
        id: UUID, spaceID: UUID, name: String,
        updatedAt: Date = Date(), isDeleted: Bool = false
    ) -> TaskListDTO {
        let persistent = PersistentTaskList(
            id: id, spaceID: spaceID, creatorID: UUID(),
            name: name, kindRawValue: TaskListKind.custom.rawValue,
            colorToken: nil, sortOrder: 0, isArchived: false,
            createdAt: updatedAt, updatedAt: updatedAt
        )
        var dto = TaskListDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
```

`TaskListRepositorySyncTests` 只需覆盖：
1. `saveTaskList_records_upsert` — 验证 `entityKind == .taskList`, `.upsert`
2. `archiveTaskList_records_archive` — 验证 `.archive`
3. `fetchTaskLists_excludes_tombstones` — 手工把某 record 的 `isLocallyDeleted` 设为 true，fetch 不应返回

`makeTaskList` helper：

```swift
private func makeTaskList(spaceID: UUID, actorID: UUID) -> TaskList {
    TaskList(
        id: UUID(),
        spaceID: spaceID,
        creatorID: actorID,
        name: "测试列表",
        kind: .custom,
        colorToken: nil,
        sortOrder: 0,
        isArchived: false,
        taskCount: 0,
        createdAt: Date(),
        updatedAt: Date()
    )
}
```

### Step 6: 跑 3 suites + 全量

同 Task 2 Step 10-11。

### Step 7: Commit

```bash
git add Together/Persistence/Models/PersistentTaskList.swift \
        Together/Sync/SupabaseSyncService.swift \
        Together/Services/TaskLists/LocalTaskListRepository.swift \
        TogetherTests/TaskListDTOInsertTests.swift \
        TogetherTests/TaskListDTOConflictTests.swift \
        TogetherTests/TaskListRepositorySyncTests.swift

git commit -m "$(cat <<'EOF'
feat(sync): taskList symmetric CRUD — tombstone on pull

- PersistentTaskList.isLocallyDeleted + fetch filter
- TaskListDTO.applyToLocal UPDATE tombstone instead of context.delete
- 3 tests passing: TaskListDTOInsertTests / TaskListDTOConflictTests / TaskListRepositorySyncTests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Project 全栈升级

### File Map (Task 5)

- Modify: `Together/Persistence/Models/PersistentProject.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift:961-993` (`ProjectDTO.applyToLocal`)
- Modify: `Together/Services/Projects/LocalProjectRepository.swift` (deleteProject tombstone + fetch filter)
- Create: `TogetherTests/ProjectDTOInsertTests.swift`
- Create: `TogetherTests/ProjectDTOConflictTests.swift`
- Create: `TogetherTests/ProjectRepositorySyncTests.swift`

### Step 1: `PersistentProject.isLocallyDeleted`

- [ ] Edit `Together/Persistence/Models/PersistentProject.swift`：照 Task 4 Step 1 模板加 `var isLocallyDeleted: Bool = false` + init 形参。

### Step 2: `ProjectDTO.applyToLocal` UPDATE 分支 tombstone

- [ ] Edit `Together/Sync/SupabaseSyncService.swift:961-993`：`context.delete(existing)` → `existing.isLocallyDeleted = true`。

### Step 3: `LocalProjectRepository.deleteProject` 改 tombstone

- [ ] Edit `Together/Services/Projects/LocalProjectRepository.swift:86-113`：

```swift
func deleteProject(projectID: UUID, actorID: UUID) async throws {
    let context = ModelContext(container)
    guard let record = try fetchRecord(projectID: projectID, context: context) else {
        throw RepositoryError.notFound
    }
    guard PairPermissionService.canDeleteProject(record.domainModel(taskCount: 0), actorID: actorID) else {
        throw PermissionError.notCreator
    }

    let spaceID = record.spaceID
    let subtaskDescriptor = FetchDescriptor<PersistentProjectSubtask>(
        predicate: #Predicate<PersistentProjectSubtask> { $0.projectID == projectID }
    )
    let subtaskRecords = try context.fetch(subtaskDescriptor)
    for subtaskRecord in subtaskRecords {
        // Tombstone 代替硬删
        subtaskRecord.isLocallyDeleted = true
        subtaskRecord.updatedAt = .now
        await syncCoordinator.recordLocalChange(
            SyncChange(entityKind: .projectSubtask, operation: .delete, recordID: subtaskRecord.id, spaceID: spaceID)
        )
    }
    record.isLocallyDeleted = true
    record.updatedAt = .now
    try context.save()

    await syncCoordinator.recordLocalChange(
        SyncChange(entityKind: .project, operation: .delete, recordID: projectID, spaceID: spaceID)
    )
    await reminderScheduler.removeProjectReminder(for: projectID)
}
```

### Step 4: 所有 project fetch 加 tombstone 过滤

- [ ] Edit `Together/Services/Projects/LocalProjectRepository.swift`：
  - `fetchProjects` descriptor（line 20 / 25）加 `&& $0.isLocallyDeleted == false`
  - `fetchRecord(projectID:)` **不加** tombstone 过滤（允许按 ID 精确查找，save 才能恢复已 tombstone 的项目）

### Step 5: 三件套测试

- [ ] `TogetherTests/ProjectDTOInsertTests.swift` / `ProjectDTOConflictTests.swift` / `ProjectRepositorySyncTests.swift`，照 Task 2 template。

`ProjectDTO.fixture`：

```swift
extension ProjectDTO {
    static func fixture(
        id: UUID, spaceID: UUID, name: String,
        updatedAt: Date = Date(), isDeleted: Bool = false
    ) -> ProjectDTO {
        let persistent = PersistentProject(
            id: id, spaceID: spaceID, creatorID: UUID(),
            name: name, notes: nil, colorToken: nil,
            statusRawValue: ProjectStatus.active.rawValue,
            targetDate: nil, remindAt: nil,
            createdAt: updatedAt, updatedAt: updatedAt, completedAt: nil
        )
        var dto = ProjectDTO(from: persistent, spaceID: spaceID)
        dto.isDeleted = isDeleted
        dto.updatedAt = updatedAt
        return dto
    }
}
```

`ProjectRepositorySyncTests` 覆盖：
1. `saveProject_records_upsert`
2. `deleteProject_records_delete_and_tombstones_project_and_subtasks`
3. `fetchProjects_excludes_tombstones`

Repository 实例化用 `NoopReminderScheduler`（在 `ProjectSubtaskRepositorySyncTests.swift` 已定义 —— 跨文件直接引用，同 test target）。

### Step 6: 跑 3 suites + 全量 + Commit

```bash
xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/ProjectDTOInsertTests \
  -only-testing:TogetherTests/ProjectDTOConflictTests \
  -only-testing:TogetherTests/ProjectRepositorySyncTests \
  2>&1 | grep -E "Test case|passed|failed|TEST"

xcodebuild test -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED" | tail -5
```

```bash
git add Together/Persistence/Models/PersistentProject.swift \
        Together/Sync/SupabaseSyncService.swift \
        Together/Services/Projects/LocalProjectRepository.swift \
        TogetherTests/ProjectDTOInsertTests.swift \
        TogetherTests/ProjectDTOConflictTests.swift \
        TogetherTests/ProjectRepositorySyncTests.swift

git commit -m "$(cat <<'EOF'
feat(sync): project symmetric CRUD — tombstone on pull and delete

- PersistentProject.isLocallyDeleted + fetch filter
- ProjectDTO.applyToLocal UPDATE tombstone instead of context.delete
- LocalProjectRepository.deleteProject tombstones project + cascaded subtasks
- 3 tests passing: ProjectDTOInsertTests / ProjectDTOConflictTests / ProjectRepositorySyncTests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 双端端到端验证 + push

### Step 1: Supabase 单端 SQL 先验证

用 iPhone（iPhone 物理机 or 模拟器）启 app、完成配对、执行如下操作；每步用 MCP 查 Supabase 表：

1. **新建 PeriodicTask** → `execute_sql("SELECT id, title, is_deleted FROM periodic_tasks WHERE space_id='<SID>' ORDER BY updated_at DESC LIMIT 5;")` —— 应看到新 row, `is_deleted=false`
2. **删除 PeriodicTask** → 同一查询 —— 应看到 `is_deleted=true, deleted_at` 非空
3. **新建 Project + 2 个 subtask** → `execute_sql("SELECT id FROM projects WHERE space_id='<SID>';")` + `execute_sql("SELECT id, title, is_deleted FROM project_subtasks WHERE project_id IN (...) ORDER BY updated_at DESC LIMIT 10;")` —— 2 行 `is_deleted=false`
4. **删除 1 个 subtask** → 应看到 1 行 `is_deleted=true`
5. **整个删 Project** → project row `is_deleted=true`，且剩余 subtasks `is_deleted=true`
6. **新建 / 归档 TaskList** → `execute_sql` 查 `task_lists` 表，同上模式

若任何一步本地 UI 能看到变化但 Supabase 查不到 → 用 `get_logs(service="api")` 找客户端请求。

### Step 2: 双端端到端

在 iPad（虎皮小猪）打开 app、同一对 space，验证 iPhone 做过的所有操作都在 3-10s 内出现在 iPad 上，且 tombstone 项目消失。

逐项打勾本 plan 末尾的 **Verification Checklist per Entity**。

### Step 3: Merge 回 main + push

```bash
git checkout main
git merge --ff-only batch-1-symmetric-crud
git push origin main
```

### Step 4: 在 plan 文件末尾追加 "实施日志" 小节

记录踩坑，示例：

```markdown
## 实施日志（2026-04-19）

- Task 2 Step 2：`LocalPeriodicTaskRepository.deleteTask` 之前直接 `context.delete`，改 tombstone 时还要处理 `markCompleted/markIncomplete` 在 tombstoned 记录上的行为 — 已通过 fetch 谓词过滤解决。
- Task 3 Step 4：`pullProjectSubtasks` 两步查询时，若 projects 结果为空直接 return，避免 `in.()` 空 list 报错。
- Task 5 Step 3：`deleteProject` 先 tombstone subtasks 再 tombstone project，顺序颠倒会导致 `normalizeProjectStatus` 把 completed 状态写回。
```

### Step 5: 等用户确认通过 → 开第二批

---

## Verification Checklist per Entity

### Entity: PeriodicTask

```
□ Supabase schema
  ☐ is_deleted + deleted_at 列存在（Task 1 Step 1 已查）
  ☐ space_id NOT NULL ✓
  ☐ Realtime publication 已含 periodic_tasks ✓
  ☐ updated_at trigger 存在 ✓

□ 客户端 DTO (A8)
  ☐ Codable + Sendable ✓
  ☐ CodingKeys snake_case ✓
  ☐ init(from:spaceID:) 签名一致 ✓

□ push 路径 (A1, A2)
  ☐ pushUpsert case .periodicTask 不为空 ✓
  ☐ pushDelete 走 soft-delete ✓
  ☐ LocalPeriodicTaskRepository 在 save/delete/complete/incomplete 都 recordLocalChange
  ☐ 上层 ViewModel 不重复 record

□ pull 路径 (A3)
  ☐ catchUp 调用 pullPeriodicTasks ✓
  ☐ space_id=eq 过滤 ✓
  ☐ Realtime 订阅 periodic_tasks 并路由到 applyToLocal

□ applyToLocal (P6, P7)
  ☐ UPDATE 首行 updatedAt guard ✓
  ☐ UPDATE isDeleted → tombstone（本批）
  ☐ INSERT !isDeleted 时创建 ✓

□ 并发 / 回声 (A5, P5)
  ☐ pushUpsert 成功后登记 recentlyPushedIDs ✓
  ☐ Realtime echo filter ✓

□ 测试 (P8)
  ☐ PeriodicTaskDTOInsertTests 3 assertions
  ☐ PeriodicTaskDTOConflictTests 2 assertions
  ☐ PeriodicTaskRepositorySyncTests 3 assertions

□ E2E (A7, P1, P2)
  ☐ iPhone 新建 → Supabase 行 + iPad 自动刷新
  ☐ iPhone 删除 → is_deleted=true + iPad 列表移除
  ☐ iPhone 完成 → completions JSON 更新 + iPad 同步
```

### Entity: ProjectSubtask

```
□ Supabase schema
  ☐ is_deleted + deleted_at 列存在（migration 004 补齐）
  ☐ space_id NOT NULL ✓（migration 002 已加）
  ☐ Realtime publication 已含 project_subtasks ✓
  ☐ updated_at trigger 存在

□ 客户端 DTO (A8)
  ☐ Codable + Sendable ✓
  ☐ CodingKeys snake_case ✓
  ☐ init(from:spaceID:) 签名（本批新加，spaceID 非可选）

□ push 路径 (A1, A2)
  ☐ pushUpsert case .projectSubtask 不为空 ✓
  ☐ pushDelete 走 soft-delete ✓
  ☐ LocalProjectRepository 在 add/toggle/update/delete 都 recordLocalChange ✓
  ☐ deleteSubtask 改 tombstone（本批）

□ pull 路径 (A3)
  ☐ catchUp 调用 pullProjectSubtasks（本批新加）
  ☐ 单步查询 eq space_id ✓
  ☐ Realtime 订阅 project_subtasks 并路由到 applyToLocal

□ applyToLocal (P6, P7)
  ☐ UPDATE 首行 updatedAt guard ✓
  ☐ UPDATE isDeleted → tombstone（本批）
  ☐ INSERT !isDeleted 时创建 ✓

□ 测试 (P8)
  ☐ ProjectSubtaskDTOInsertTests 3 assertions
  ☐ ProjectSubtaskDTOConflictTests 2 assertions
  ☐ ProjectSubtaskRepositorySyncTests 1 主断言 + tombstone

□ E2E
  ☐ iPhone addSubtask → Supabase 行 + iPad 看到 subtask
  ☐ iPhone deleteSubtask → is_deleted=true + iPad subtask 移除
  ☐ iPhone toggleSubtask → is_completed 同步
```

### Entity: TaskList

```
□ Supabase schema
  ☐ is_deleted + deleted_at 列存在
  ☐ space_id NOT NULL ✓
  ☐ Realtime publication 已含 task_lists ✓
  ☐ updated_at trigger 存在

□ 客户端 DTO (A8)
  ☐ Codable + Sendable ✓
  ☐ init(from:spaceID:) 签名一致 ✓

□ push 路径 (A1, A2)
  ☐ pushUpsert case .taskList 不为空 ✓
  ☐ pushDelete 走 soft-delete ✓
  ☐ LocalTaskListRepository.save/archive 都 recordLocalChange ✓

□ pull 路径 (A3)
  ☐ catchUp 调用 pullTaskLists ✓
  ☐ Realtime 订阅 task_lists ✓

□ applyToLocal (P6, P7)
  ☐ UPDATE isDeleted → tombstone（本批）

□ 测试 (P8)
  ☐ TaskListDTOInsertTests
  ☐ TaskListDTOConflictTests
  ☐ TaskListRepositorySyncTests

□ E2E
  ☐ iPhone 新建列表 → iPad 可见
  ☐ iPhone 归档列表 → iPad 同步归档
```

### Entity: Project

```
□ Supabase schema
  ☐ is_deleted + deleted_at 列存在
  ☐ space_id NOT NULL ✓
  ☐ Realtime publication 已含 projects ✓

□ 客户端 DTO (A8)
  ☐ Codable + Sendable ✓
  ☐ init(from:spaceID:) 签名一致 ✓

□ push 路径 (A1, A2)
  ☐ pushUpsert case .project 不为空 ✓
  ☐ pushDelete 走 soft-delete ✓
  ☐ LocalProjectRepository.save/archive/delete/setCompleted 都 recordLocalChange ✓
  ☐ deleteProject 改 tombstone（本批）+ 级联 subtasks tombstone

□ pull 路径 (A3)
  ☐ catchUp 调用 pullProjects ✓
  ☐ Realtime 订阅 projects ✓

□ applyToLocal (P6, P7)
  ☐ UPDATE isDeleted → tombstone（本批）

□ 测试 (P8)
  ☐ ProjectDTOInsertTests
  ☐ ProjectDTOConflictTests
  ☐ ProjectRepositorySyncTests

□ E2E
  ☐ iPhone 新建 project + 2 subtasks → iPad 同步
  ☐ iPhone 删除 project → iPad 该项目消失
  ☐ iPhone 归档 / completed → iPad 状态同步
```

---

## 实施日志（2026-04-18）

### 全部完成

8 个 commit on `batch-1-symmetric-crud`：

1. `e8d5f9e` feat(sync): periodicTask symmetric CRUD — tombstone, record, pull
2. `9602076` refactor(sync): tighten periodicTask — throw on missing, non-optional DTO spaceID, mark* test coverage
3. `f6aae55` feat(sync): projectSubtask symmetric CRUD — tombstone, record, pull
4. `97977fa` fix(sync): DTO init derives isDeleted from persistent.isLocallyDeleted
5. `2ce557a` feat(sync): taskList symmetric CRUD — tombstone on pull and resurrection
6. `2e98883` test(sync): strengthen taskList resurrection + tombstone-persistence assertions
7. `6ead31d` test(sync): make TaskList conflict assertion actually distinguish UPDATE ran
8. `650d715` feat(sync): project symmetric CRUD — cascading tombstone, record, pull

总体：21 files changed, +1517 / −51 lines。新增 12 个测试文件，39 个 @Test 用例（原 107 + 新 39 = 146 通过，regression `TEST SUCCEEDED`）。

### 实施期间踩坑

- **Task 2 code review 捞出 `deleteTask` silent return**：plan 的 Step 2 模板本来就是 `guard ... else { return }`，但 P4 gold standard（`LocalItemRepository.deleteItem`）是 `throw RepositoryError.notFound`。follow-up commit 改掉 + 补 `markCompleted/markIncomplete/resurrect` 的 3 件套漏测。
- **Task 3 spec review 发现跨 entity 系统性遗漏**：只有 `TaskDTO.init` 正确从 `persistent.isLocallyDeleted` 派生 `isDeleted` / `deletedAt`；`PeriodicTaskDTO` / `ProjectSubtaskDTO` / `TaskListDTO` / `ProjectDTO` 全部硬编码 `false`。虽然当前 `pushDelete()` 用独立 `SoftDelete` 结构不走 DTO，但如果未来有 `.upsert` 落在 tombstoned 记录上就会悄悄复活远端 row。`97977fa` 先修 PeriodicTask+ProjectSubtask 两个；TaskList / Project 在 Task 4/5 自己修。
- **Task 3 scheme 初次运行 `project_subtasks` Realtime 没订阅**：playbook §2 A6 "元数据表被遗忘"的复刻。`f6aae55` 顺手补订阅。
- **Task 3 `project_subtasks` schema 反转认知**：playbook 原以为该表没有 `space_id`，但 MCP 查 information_schema 确认 `space_id uuid NOT NULL` 已经存在（migration 002 加的），且只缺 `deleted_at`（单独补 `004_add_deleted_at_to_project_subtasks.sql`）。所以 `pullProjectSubtasks` 是单步 `eq("space_id")` 查询，不是 plan 初稿里写的两步 projects→subtasks join。
- **Task 4 code review 捞出测试写得"pass for the wrong reason"**：`tombstone_not_resurrected_by_later_remote_upsert` 三次 fixture 都用同一个 name 导致 `#expect(name == "x")` 退化成 tautology。`6ead31d` 把第三个 DTO 改成 `"x-after-tombstone"` 让断言真的能分辨 UPDATE 分支跑没跑。
- **Realtime 一方（subtasks）加订阅后 `NoopReminderScheduler` 协议签名对齐**：原计划 template 漏了 `snoozeTaskReminder` / `resync` 方法 + `syncPeriodicTaskReminder` 少一个 `referenceDate` 参数。实施前 `grep` 了实际协议纠正。

### 待后续批次处理（非 blocker）

- `TaskListRepositoryProtocol` 没有 `deleteTaskList` 方法（plan §Step 4 YAGNI 明确跳过）；tombstone 基建都到位，未来上 UI 硬删时几行代码补上即可。
- `PeriodicTask.syncCoordinator` 为 `SyncCoordinatorProtocol?` 可选（其他三个 repo 是非可选）。`LocalServiceFactory` 已注入，实际 prod 不会 nil；如要严格化可改成非可选 + `assertionFailure`。
- DTO `applyToLocal` UPDATE 分支现在依赖"没有 `else { isLocallyDeleted = false }`"这条**隐式**不变式来保证 tombstone 单向。如果后续代码有人加 reset 分支，会悄悄破坏语义。**建议在每个 DTO 的 applyToLocal UPDATE 头部加一行显式 guard**：`if existing.isLocallyDeleted { return }` —— 这样 remote pull 根本不触碰 tombstoned 记录，不变式变显式。但这是 batch 2+ 级别的强化。
- `makeContainer()` helper 现在在 8+ 个测试文件里复制；未来应提炼 `TogetherTests/TestContainer.swift`。
- DTO `deletedAt = Date()` 用的是 push 时的 wall clock，不是用户实际删除那一刻；如果服务端需要审计精确时间，应把 `deletedAt` 存到 Persistent 模型。

### Tasks 1-5 全部 ✅；Task 6 等待用户双端 E2E 验证 + 授权 push。

