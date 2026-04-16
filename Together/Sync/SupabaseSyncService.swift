import Foundation
import Supabase
import SwiftData
import os

/// Supabase 双人同步服务
/// 三大职责：Push（本地→Supabase）、Pull（catch-up 补拉）、Listen（Realtime 订阅）
actor SupabaseSyncService {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared
    private nonisolated(unsafe) let logger = Logger(subsystem: "com.pigdog.Together", category: "SupabaseSync")
    private let modelContainer: ModelContainer

    private var spaceID: UUID?
    private var myUserID: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var lastSyncedAt: Date?
    private var listeningTasks: [Task<Void, Never>] = []

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// 配置同步目标
    func configure(spaceID: UUID, myUserID: UUID) {
        self.spaceID = spaceID
        self.myUserID = myUserID
    }

    /// 清理资源
    func teardown() async {
        for task in listeningTasks {
            task.cancel()
        }
        listeningTasks.removeAll()
        await realtimeChannel?.unsubscribe()
        realtimeChannel = nil
        spaceID = nil
        myUserID = nil
        lastSyncedAt = nil
    }

    // MARK: - Push（本地 → Supabase）

    /// 推送待同步的本地变更到 Supabase
    func push() async {
        guard let spaceID else { return }

        let context = ModelContext(modelContainer)

        let pendingRaw = SyncMutationLifecycleState.pending.rawValue
        let failedRaw = SyncMutationLifecycleState.failed.rawValue
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate {
                $0.spaceID == spaceID &&
                ($0.lifecycleStateRawValue == pendingRaw || $0.lifecycleStateRawValue == failedRaw)
            },
            sortBy: [SortDescriptor(\.changedAt)]
        )

        guard let changes = try? context.fetch(descriptor), !changes.isEmpty else { return }

        for change in changes {
            do {
                change.lifecycleStateRawValue = SyncMutationLifecycleState.sending.rawValue
                change.lastAttemptedAt = Date()
                try context.save()

                let entityKind = SyncEntityKind(rawValue: change.entityKindRawValue) ?? .task
                let operation = SyncOperationKind(rawValue: change.operationRawValue) ?? .upsert

                if operation == .delete {
                    try await pushDelete(entityKind: entityKind, recordID: change.recordID)
                } else {
                    try await pushUpsert(entityKind: entityKind, recordID: change.recordID, spaceID: spaceID, context: context)
                }

                // 标记成功
                change.lifecycleStateRawValue = SyncMutationLifecycleState.confirmed.rawValue
                change.confirmedAt = Date()
                try context.save()

                logger.info("[Push] ✅ \(entityKind.rawValue) \(operation.rawValue) \(change.recordID)")

            } catch {
                change.lifecycleStateRawValue = SyncMutationLifecycleState.failed.rawValue
                change.lastError = error.localizedDescription
                try? context.save()
                logger.error("[Push] ❌ \(error.localizedDescription)")
            }
        }

        // 清理已确认的变更
        purgeConfirmedChanges(context: context)
    }

    // MARK: - Pull（Supabase → 本地，catch-up 补拉）

    /// 从 Supabase 拉取最新数据
    func catchUp() async {
        guard let spaceID else { return }
        let since = lastSyncedAt ?? Date.distantPast
        let sinceISO = ISO8601DateFormatter().string(from: since)

        do {
            // 拉取各业务表
            try await pullTasks(spaceID: spaceID, since: sinceISO)
            try await pullTaskLists(spaceID: spaceID, since: sinceISO)
            try await pullProjects(spaceID: spaceID, since: sinceISO)
            try await pullPeriodicTasks(spaceID: spaceID, since: sinceISO)

            lastSyncedAt = Date()
            logger.info("[CatchUp] ✅ 完成补拉")
        } catch {
            logger.error("[CatchUp] ❌ \(error.localizedDescription)")
        }
    }

    // MARK: - Realtime 订阅

    /// 开始监听 Realtime 变更（Query first, Subscribe second）
    func startListening() async {
        guard let spaceID else { return }

        // 先补拉最新数据
        await catchUp()

        let channel = client.realtimeV2.channel("space-\(spaceID.uuidString)")

        let spaceFilter = "space_id=eq.\(spaceID.uuidString)"
        let tasksStream = channel.postgresChange(AnyAction.self, schema: "public", table: "tasks", filter: spaceFilter)
        let listsStream = channel.postgresChange(AnyAction.self, schema: "public", table: "task_lists", filter: spaceFilter)
        let projectsStream = channel.postgresChange(AnyAction.self, schema: "public", table: "projects", filter: spaceFilter)
        let periodicStream = channel.postgresChange(AnyAction.self, schema: "public", table: "periodic_tasks", filter: spaceFilter)
        let membersStream = channel.postgresChange(AnyAction.self, schema: "public", table: "space_members", filter: spaceFilter)

        try? await channel.subscribe()
        self.realtimeChannel = channel

        // 启动各表的监听任务
        listeningTasks.append(Task { [weak self] in
            for await change in tasksStream {
                await self?.handleRealtimeChange(change, table: "tasks")
            }
        })
        listeningTasks.append(Task { [weak self] in
            for await change in listsStream {
                await self?.handleRealtimeChange(change, table: "task_lists")
            }
        })
        listeningTasks.append(Task { [weak self] in
            for await change in projectsStream {
                await self?.handleRealtimeChange(change, table: "projects")
            }
        })
        listeningTasks.append(Task { [weak self] in
            for await change in periodicStream {
                await self?.handleRealtimeChange(change, table: "periodic_tasks")
            }
        })
        listeningTasks.append(Task { [weak self] in
            for await change in membersStream {
                await self?.handleMemberChange(change)
            }
        })

        logger.info("[Realtime] ✅ 已订阅 space: \(spaceID)")
    }

    // MARK: - 已读状态

    /// 标记任务为已读
    func markTaskAsRead(taskID: UUID) async {
        struct ReadUpdate: Encodable {
            let is_read_by_partner: Bool
            let read_at: String
        }
        do {
            try await client.from("tasks")
                .update(ReadUpdate(
                    is_read_by_partner: true,
                    read_at: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("id", value: taskID.uuidString)
                .execute()
        } catch {
            logger.error("[ReadStatus] ❌ \(error.localizedDescription)")
        }
    }

    // MARK: - Private Push Helpers

    private func pushUpsert(entityKind: SyncEntityKind, recordID: UUID, spaceID: UUID, context: ModelContext) async throws {
        let tableName = entityKind.supabaseTableName

        switch entityKind {
        case .task:
            let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == recordID })
            guard let item = try? context.fetch(descriptor).first else { return }
            let dto = TaskDTO(from: item, spaceID: spaceID)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .taskList:
            let descriptor = FetchDescriptor<PersistentTaskList>(predicate: #Predicate { $0.id == recordID })
            guard let list = try? context.fetch(descriptor).first else { return }
            let dto = TaskListDTO(from: list)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .project:
            let descriptor = FetchDescriptor<PersistentProject>(predicate: #Predicate { $0.id == recordID })
            guard let project = try? context.fetch(descriptor).first else { return }
            let dto = ProjectDTO(from: project)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .projectSubtask:
            let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == recordID })
            guard let subtask = try? context.fetch(descriptor).first else { return }
            let dto = ProjectSubtaskDTO(from: subtask)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .periodicTask:
            let descriptor = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate { $0.id == recordID })
            guard let periodic = try? context.fetch(descriptor).first else { return }
            let dto = PeriodicTaskDTO(from: periodic)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .space, .memberProfile, .avatarAsset:
            break // 由配对流程或 Storage 管理
        }
    }

    private func pushDelete(entityKind: SyncEntityKind, recordID: UUID) async throws {
        struct SoftDelete: Encodable {
            let is_deleted: Bool
            let deleted_at: String
        }
        let tableName = entityKind.supabaseTableName
        try await client.from(tableName)
            .update(SoftDelete(
                is_deleted: true,
                deleted_at: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: recordID.uuidString)
            .execute()
    }

    // MARK: - Private Pull Helpers

    private func pullTasks(spaceID: UUID, since: String) async throws {
        let rows: [TaskDTO] = try await client.from("tasks")
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

    private func pullTaskLists(spaceID: UUID, since: String) async throws {
        let rows: [TaskListDTO] = try await client.from("task_lists")
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

    private func pullProjects(spaceID: UUID, since: String) async throws {
        let rows: [ProjectDTO] = try await client.from("projects")
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

    private func pullPeriodicTasks(spaceID: UUID, since: String) async throws {
        let rows: [PeriodicTaskDTO] = try await client.from("periodic_tasks")
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

    // MARK: - Realtime Handlers

    private func handleRealtimeChange(_ change: AnyAction, table: String) async {
        // 回声过滤和数据应用将在集成测试中完善
        // 基本框架：收到 Realtime 事件 → 触发 catch-up 补拉
        await catchUp()
        lastSyncedAt = Date()

        // 通知 UI 刷新
        await MainActor.run {
            NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
        }
    }

    private func handleMemberChange(_ change: AnyAction) async {
        // 检测配对/解绑事件
        switch change {
        case .insert:
            await MainActor.run {
                NotificationCenter.default.post(name: .pairMemberJoined, object: nil)
            }
        case .delete:
            await MainActor.run {
                NotificationCenter.default.post(name: .pairMemberRemoved, object: nil)
            }
        default:
            break
        }
    }

    // MARK: - Cleanup

    private func purgeConfirmedChanges(context: ModelContext) {
        let confirmedRaw = SyncMutationLifecycleState.confirmed.rawValue
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate { $0.lifecycleStateRawValue == confirmedRaw }
        )
        if let confirmed = try? context.fetch(descriptor) {
            for change in confirmed {
                context.delete(change)
            }
            try? context.save()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pairMemberJoined = Notification.Name("pairMemberJoined")
    static let pairMemberRemoved = Notification.Name("pairMemberRemoved")
    static let supabaseRealtimeChanged = Notification.Name("supabaseRealtimeChanged")
}

// MARK: - SyncEntityKind Supabase 扩展

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
        }
    }
}

// MARK: - DTO 数据传输对象

/// 任务 DTO（匹配 Supabase tasks 表结构）
struct TaskDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let listId: UUID?
    let projectId: UUID?
    let creatorId: UUID
    var title: String
    var notes: String?
    var assigneeMode: String
    var status: String
    var dueAt: Date?
    var hasExplicitTime: Bool
    var remindAt: Date?
    var isPinned: Bool
    var isDraft: Bool
    var isReadByPartner: Bool
    var readAt: Date?
    var repeatRule: String?
    var occurrenceCompletions: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isArchived: Bool
    var archivedAt: Date?
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status
        case spaceId = "space_id"
        case listId = "list_id"
        case projectId = "project_id"
        case creatorId = "creator_id"
        case assigneeMode = "assignee_mode"
        case dueAt = "due_at"
        case hasExplicitTime = "has_explicit_time"
        case remindAt = "remind_at"
        case isPinned = "is_pinned"
        case isDraft = "is_draft"
        case isReadByPartner = "is_read_by_partner"
        case readAt = "read_at"
        case repeatRule = "repeat_rule"
        case occurrenceCompletions = "occurrence_completions"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    nonisolated init(from persistent: PersistentItem, spaceID: UUID) {
        self.id = persistent.id
        self.spaceId = spaceID
        self.listId = persistent.listID
        self.projectId = persistent.projectID
        self.creatorId = persistent.creatorID
        self.title = persistent.title
        self.notes = persistent.notes
        self.assigneeMode = persistent.assigneeModeRawValue
        self.status = persistent.statusRawValue
        self.dueAt = persistent.dueAt
        self.hasExplicitTime = persistent.hasExplicitTime
        self.remindAt = persistent.remindAt
        self.isPinned = persistent.isPinned
        self.isDraft = persistent.isDraft
        self.isReadByPartner = false
        self.readAt = nil
        // repeatRule 和 occurrenceCompletions 在 PersistentItem 中是 Data，
        // 转为 JSON String 供 Supabase jsonb 列使用
        if let data = persistent.repeatRuleData {
            self.repeatRule = String(data: data, encoding: .utf8)
        } else {
            self.repeatRule = nil
        }
        self.occurrenceCompletions = nil // PersistentItem 中无此独立字段
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.completedAt = persistent.completedAt
        self.isArchived = persistent.isArchived
        self.archivedAt = persistent.archivedAt
        self.isDeleted = false // 本地不存储此字段，Supabase 端独有
        self.deletedAt = nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.title = title
            existing.notes = notes
            existing.assigneeModeRawValue = assigneeMode
            existing.statusRawValue = status
            existing.dueAt = dueAt
            existing.hasExplicitTime = hasExplicitTime
            existing.remindAt = remindAt
            existing.isPinned = isPinned
            existing.isDraft = isDraft
            existing.completedAt = completedAt
            existing.isArchived = isArchived
            existing.archivedAt = archivedAt
            existing.updatedAt = updatedAt
        }
        // 新记录的创建需要完整的 PersistentItem 初始化，
        // 将在集成测试阶段补充完善
    }
}

/// 列表 DTO
struct TaskListDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let creatorId: UUID
    var name: String
    var kind: String
    var colorToken: String?
    var sortOrder: Double
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case spaceId = "space_id"
        case creatorId = "creator_id"
        case colorToken = "color_token"
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    nonisolated init(from persistent: PersistentTaskList) {
        self.id = persistent.id
        self.spaceId = persistent.spaceID
        self.creatorId = persistent.creatorID
        self.name = persistent.name
        self.kind = persistent.kindRawValue
        self.colorToken = persistent.colorToken
        self.sortOrder = persistent.sortOrder
        self.isArchived = persistent.isArchived
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.isDeleted = false
        self.deletedAt = nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentTaskList>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.name = name
            existing.kindRawValue = kind
            existing.colorToken = colorToken
            existing.sortOrder = sortOrder
            existing.isArchived = isArchived
            existing.updatedAt = updatedAt
        }
    }
}

/// 项目 DTO
struct ProjectDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let creatorId: UUID
    var name: String
    var notes: String?
    var colorToken: String?
    var status: String
    var targetDate: Date?
    var remindAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, status
        case spaceId = "space_id"
        case creatorId = "creator_id"
        case colorToken = "color_token"
        case targetDate = "target_date"
        case remindAt = "remind_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    nonisolated init(from persistent: PersistentProject) {
        self.id = persistent.id
        self.spaceId = persistent.spaceID
        self.creatorId = persistent.creatorID
        self.name = persistent.name
        self.notes = persistent.notes
        self.colorToken = persistent.colorToken
        self.status = persistent.statusRawValue
        self.targetDate = persistent.targetDate
        self.remindAt = persistent.remindAt
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.completedAt = persistent.completedAt
        self.isDeleted = false
        self.deletedAt = nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentProject>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.name = name
            existing.notes = notes
            existing.colorToken = colorToken
            existing.statusRawValue = status
            existing.targetDate = targetDate
            existing.remindAt = remindAt
            existing.completedAt = completedAt
            existing.updatedAt = updatedAt
        }
    }
}

/// 项目子任务 DTO
struct ProjectSubtaskDTO: Codable, Sendable {
    let id: UUID
    let projectId: UUID
    let creatorId: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date
    var isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, title
        case projectId = "project_id"
        case creatorId = "creator_id"
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
    }

    nonisolated init(from persistent: PersistentProjectSubtask) {
        self.id = persistent.id
        self.projectId = persistent.projectID
        self.creatorId = persistent.creatorID
        self.title = persistent.title
        self.isCompleted = persistent.isCompleted
        self.sortOrder = persistent.sortOrder
        self.updatedAt = persistent.updatedAt
        self.isDeleted = false
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.title = title
            existing.isCompleted = isCompleted
            existing.sortOrder = sortOrder
            existing.updatedAt = updatedAt
        }
    }
}

/// 例行事务 DTO
struct PeriodicTaskDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let creatorId: UUID
    var title: String
    var notes: String?
    var cycle: String
    var reminderRules: String?
    var completions: String?
    var sortOrder: Double
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, cycle
        case spaceId = "space_id"
        case creatorId = "creator_id"
        case reminderRules = "reminder_rules"
        case completions
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }

    nonisolated init(from persistent: PersistentPeriodicTask) {
        self.id = persistent.id
        self.spaceId = persistent.spaceID ?? UUID() // spaceID 在 PersistentPeriodicTask 中是可选的
        self.creatorId = persistent.creatorID
        self.title = persistent.title
        self.notes = persistent.notes
        self.cycle = persistent.cycleRawValue
        // reminderRulesData 和 completionsData 是 Data 类型，转为 JSON String
        if let data = persistent.reminderRulesData {
            self.reminderRules = String(data: data, encoding: .utf8)
        } else {
            self.reminderRules = "[]"
        }
        self.completions = String(data: persistent.completionsData, encoding: .utf8) ?? "{}"
        self.sortOrder = persistent.sortOrder
        self.isActive = persistent.isActive
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.isDeleted = false
        self.deletedAt = nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
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
        }
    }
}
