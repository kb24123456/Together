import Foundation
import Supabase
import SwiftData
import os

/// Supabase 双人同步服务
/// 三大职责：Push（本地→Supabase）、Pull（catch-up 补拉）、Listen（Realtime 订阅）
actor SupabaseSyncService {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared
    private nonisolated(unsafe) let logger = Logger(subsystem: "com.pigdog.Together", category: "SupabaseSync")
    /// Internal visibility allows the test target to seed data without production-visible mutation methods.
    nonisolated let modelContainer: ModelContainer
    private let avatarUploader: AvatarStorageUploaderProtocol
    private let avatarMediaStore: UserAvatarMediaStoreProtocol

    private var spaceID: UUID?
    private var myUserID: UUID?       // Supabase auth UUID
    private var myLocalUserID: UUID?  // 本地 app UUID（用于在 PairMembership 中区分自己和对方）
    private var isListening = false   // 防止 startListening 重复调用导致 Realtime 订阅失败
    private var realtimeChannel: RealtimeChannelV2?
    private var listeningTasks: [Task<Void, Never>] = []

    /// 每个 space 一把 key，持久化到 UserDefaults。
    /// App 重启不会再从 distantPast 全量拉取。
    private var lastSyncedAt: Date? {
        get {
            guard let spaceID else { return nil }
            return UserDefaults.standard.object(forKey: Self.lastSyncedKey(spaceID)) as? Date
        }
        set {
            guard let spaceID else { return }
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.lastSyncedKey(spaceID))
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey(spaceID))
            }
        }
    }

    private static func lastSyncedKey(_ spaceID: UUID) -> String {
        "together.supabase.lastSyncedAt.\(spaceID.uuidString)"
    }
    // push() 并发序列化：actor 本身不够，因为 await 网络时释放执行权，另一 Task 可进入
    private var isPushing = false
    private var pushRequestedDuringFlight = false
    // Realtime 回声过滤：自己 push 成功的 recordID 在短窗口内忽略
    private var recentlyPushedIDs: [UUID: Date] = [:]
    private let echoWindow: TimeInterval = 10

    /// Signed URL produced by the .avatarAsset push; consumed + cleared by the next .memberProfile push.
    /// Keyed by local user UUID (same as the recordID used for .memberProfile changes).
    private var pendingAvatarURL: [UUID: URL] = [:]

    private let spaceMemberWriter: SpaceMemberWriter
    private let spaceMemberReader: SpaceMemberReader

    init(
        modelContainer: ModelContainer,
        avatarUploader: AvatarStorageUploaderProtocol,
        avatarMediaStore: UserAvatarMediaStoreProtocol = LocalUserAvatarMediaStore(),
        spaceMemberWriter: SpaceMemberWriter? = nil,
        spaceMemberReader: SpaceMemberReader? = nil
    ) {
        self.modelContainer = modelContainer
        self.avatarUploader = avatarUploader
        self.avatarMediaStore = avatarMediaStore
        self.spaceMemberWriter = spaceMemberWriter ?? SupabaseSpaceMemberWriter()
        self.spaceMemberReader = spaceMemberReader ?? SupabaseSpaceMemberReader()
    }

    /// 配置同步目标
    func configure(spaceID: UUID, myUserID: UUID, myLocalUserID: UUID? = nil) {
        self.spaceID = spaceID
        self.myUserID = myUserID
        self.myLocalUserID = myLocalUserID
    }

    /// Test-only entry point to exercise pull without Supabase network I/O.
    internal func pullSpaceMembersForTesting(spaceID: UUID) async throws {
        try await pullSpaceMembers(spaceID: spaceID, since: ISO8601DateFormatter().string(from: .distantPast))
    }

    /// 清理资源
    func teardown() async {
        for task in listeningTasks {
            task.cancel()
        }
        listeningTasks.removeAll()
        // 关键：必须用 removeChannel 而非 unsubscribe —— SDK 把 channel 按 topic 缓存在
        // RealtimeClientV2 内部字典里；只 unsubscribe 不会从字典移除，下次同名 channel()
        // 会返回旧实例，再注册 postgresChange 报 "Cannot add callbacks after subscribe()"
        if let channel = realtimeChannel {
            await client.realtimeV2.removeChannel(channel)
        }
        realtimeChannel = nil
        spaceID = nil
        myUserID = nil
        myLocalUserID = nil
        // lastSyncedAt 不重置 —— 存 UserDefaults，同一 space 下次启动用
        isListening = false
        isPushing = false
        pushRequestedDuringFlight = false
        recentlyPushedIDs.removeAll()
    }

    // MARK: - Push（本地 → Supabase）

    /// 将上次进程遗留在 .sending 状态的变更复活成 .pending，避免永久卡死
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

    /// 推送待同步的本地变更到 Supabase
    func push() async {
        guard let spaceID else { return }

        // 序列化：避免两个 Task 同时读取同一批 pending 并重复 upsert
        if isPushing {
            pushRequestedDuringFlight = true
            return
        }
        isPushing = true

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

        guard let changes = try? context.fetch(descriptor), !changes.isEmpty else {
            // 关键：早返路径也必须释放 isPushing，否则后续 push 永远被守卫挡掉
            finishPush()
            return
        }
        logger.info("[Push] queue size = \(changes.count) for space \(spaceID)")

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

                // 回声过滤登记：这条 recordID 接下来几秒内从 Realtime 上回来，跳过 catchUp
                recentlyPushedIDs[change.recordID] = Date()

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

        // 清理过期的回声标记
        pruneEchoWindow()

        finishPush()
    }

    /// 释放 push 序列化锁；若飞行期间有合并请求，立即再跑一轮
    private func finishPush() {
        isPushing = false
        if pushRequestedDuringFlight {
            pushRequestedDuringFlight = false
            Task { [weak self] in await self?.push() }
        }
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
            try await pullProjectSubtasks(spaceID: spaceID, since: sinceISO)
            try await pullPeriodicTasks(spaceID: spaceID, since: sinceISO)
            try await pullSpaceMembers(spaceID: spaceID, since: sinceISO)
            try await pullSpaces(spaceID: spaceID, since: sinceISO)

            lastSyncedAt = Date()
            logger.info("[CatchUp] ✅ 完成补拉")

            // 通知 UI 刷新（即使没有新变更，首次 catchUp 也要让 ViewModel reload 一次）
            await MainActor.run {
                NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
            }
        } catch {
            logger.error("[CatchUp] ❌ \(error.localizedDescription)")
        }
    }

    // MARK: - Realtime 订阅

    /// 开始监听 Realtime 变更（Query first, Subscribe second）
    func startListening() async {
        guard let spaceID else { return }
        // 幂等：已经在监听则直接返回，避免重复 subscribe 导致 "Cannot add postgres_changes callbacks" 错误
        guard !isListening else {
            await catchUp()
            return
        }
        isListening = true

        // 启动时先恢复卡死的 sending 变更，再立即尝试一次 push，保证低延迟
        await resurrectStuckChanges()
        await push()

        // 然后补拉最新数据
        await catchUp()

        // 防御：如果 SDK 内部已经缓存了同名 channel（上次进程没干净 teardown，
        // 或被其他实例创建），先 remove 再重新创建，避免 "Cannot add callbacks after subscribe()"
        let topic = "space-\(spaceID.uuidString)"
        let realtimeTopic = "realtime:\(topic)"
        if let stale = client.realtimeV2.channels[realtimeTopic] {
            await client.realtimeV2.removeChannel(stale)
        }

        let channel = client.realtimeV2.channel(topic)

        let spaceFilter = "space_id=eq.\(spaceID.uuidString)"
        // spaces 表的主键列叫 id，不是 space_id，所以单独过滤
        let spacesFilter = "id=eq.\(spaceID.uuidString)"
        let tasksStream = channel.postgresChange(AnyAction.self, schema: "public", table: "tasks", filter: spaceFilter)
        let listsStream = channel.postgresChange(AnyAction.self, schema: "public", table: "task_lists", filter: spaceFilter)
        let projectsStream = channel.postgresChange(AnyAction.self, schema: "public", table: "projects", filter: spaceFilter)
        let subtasksStream = channel.postgresChange(AnyAction.self, schema: "public", table: "project_subtasks", filter: spaceFilter)
        let periodicStream = channel.postgresChange(AnyAction.self, schema: "public", table: "periodic_tasks", filter: spaceFilter)
        let membersStream = channel.postgresChange(AnyAction.self, schema: "public", table: "space_members", filter: spaceFilter)
        let spacesStream = channel.postgresChange(AnyAction.self, schema: "public", table: "spaces", filter: spacesFilter)

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
            for await change in subtasksStream {
                await self?.handleRealtimeChange(change, table: "project_subtasks")
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
        listeningTasks.append(Task { [weak self] in
            for await change in spacesStream {
                await self?.handleRealtimeChange(change, table: "spaces")
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

    /// Internal test seam: push a single SyncChange without going through the full queue.
    /// Production code uses `push()` which drains `PersistentSyncChange` rows from the DB.
    func pushUpsert(_ change: SyncChange) async throws {
        let context = ModelContext(modelContainer)
        try await pushUpsert(
            entityKind: change.entityKind,
            recordID: change.recordID,
            spaceID: change.spaceID,
            context: context
        )
    }

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
            let dto = TaskListDTO(from: list, spaceID: spaceID)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .project:
            let descriptor = FetchDescriptor<PersistentProject>(predicate: #Predicate { $0.id == recordID })
            guard let project = try? context.fetch(descriptor).first else { return }
            let dto = ProjectDTO(from: project, spaceID: spaceID)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .projectSubtask:
            let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == recordID })
            guard let subtask = try? context.fetch(descriptor).first else { return }
            let dto = ProjectSubtaskDTO(from: subtask, spaceID: spaceID)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .periodicTask:
            let descriptor = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate { $0.id == recordID })
            guard let periodic = try? context.fetch(descriptor).first else { return }
            let dto = PeriodicTaskDTO(from: periodic, spaceID: spaceID)
            try await client.from(tableName).upsert(dto, onConflict: "id").execute()

        case .memberProfile:
            // 更新 space_members 中自己的 display_name 和 avatar 信息
            guard let myUserID else { return }
            let descriptor = FetchDescriptor<PersistentUserProfile>(predicate: #Predicate { $0.userID == recordID })
            guard let profile = try? context.fetch(descriptor).first else { return }
            // Consume the signed URL cached by the preceding .avatarAsset push (if any).
            let signedURL = pendingAvatarURL.removeValue(forKey: recordID)
            let dto = SpaceMemberUpdateDTO(
                displayName: profile.displayName,
                avatarUrl: signedURL?.absoluteString,
                avatarAssetID: profile.avatarAssetID,
                avatarSystemName: profile.avatarSystemName,
                avatarVersion: profile.avatarVersion
            )
            try await spaceMemberWriter.updateMember(spaceID: spaceID, userID: myUserID, dto: dto)

        case .space:
            // 更新 spaces 表的 display_name
            let descriptor = FetchDescriptor<PersistentSpace>(predicate: #Predicate { $0.id == spaceID })
            guard let space = try? context.fetch(descriptor).first else {
                logger.error("[Push] ❌ .space: 本地找不到 PersistentSpace id=\(spaceID)")
                return
            }
            let dto = SpaceUpdateDTO(displayName: space.displayName)
            logger.info("[Push] → spaces UPDATE display_name='\(space.displayName)' WHERE id=\(spaceID)")
            try await client.from("spaces")
                .update(dto)
                .eq("id", value: spaceID.uuidString)
                .execute()

        case .avatarAsset:
            // recordID is the asset UUID (= UUID(uuidString: user.avatarAssetID)).
            // Find the owning profile via avatarAssetID and upload the avatar bytes.
            let assetIDString = recordID.uuidString.lowercased()
            let profileDescriptor = FetchDescriptor<PersistentUserProfile>(
                predicate: #Predicate { $0.avatarAssetID == assetIDString }
            )
            guard let profile = (try? context.fetch(profileDescriptor))?.first else {
                logger.warning("[Push] avatarAsset skipped — no profile with avatarAssetID=\(assetIDString)")
                return
            }
            guard let fileName = profile.avatarPhotoFileName else {
                // Symbol-only avatar; nothing to upload.
                return
            }
            let bytes: Data
            do {
                bytes = try avatarMediaStore.avatarData(named: fileName)
            } catch {
                logger.error("[Push] avatarAsset bytes read failed: \(error.localizedDescription)")
                return
            }
            do {
                let signedURL = try await avatarUploader.uploadAvatar(
                    bytes: bytes,
                    spaceID: spaceID,
                    userID: profile.userID,
                    version: profile.avatarVersion
                )
                pendingAvatarURL[profile.userID] = signedURL
                logger.info("[Push] avatarAsset uploaded bytes=\(bytes.count) version=\(profile.avatarVersion)")
            } catch {
                logger.error("[Push] avatarAsset upload failed: \(error.localizedDescription)")
                // Swallow — memberProfile push will still run with a nil avatar_url fallback.
            }

        case .taskMessage:
            let descriptor = FetchDescriptor<PersistentTaskMessage>(
                predicate: #Predicate { $0.id == recordID }
            )
            guard let message = try? context.fetch(descriptor).first else { return }
            let dto = TaskMessagePushDTO(from: message)
            // Insert, not upsert — each row is an immutable event-log entry.
            try await client.from(tableName).insert(dto).execute()

        case .importantDate:
            // Supabase push for important_dates lands in a later task.
            return
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

    private func pullSpaceMembers(spaceID: UUID, since: String) async throws {
        guard let myUserID else { return }
        let rows = try await spaceMemberReader.fetchMembers(spaceID: spaceID, since: since)

        // 只处理对方的 profile（跳过自己的 Supabase user_id）
        let partnerRows = rows.filter { $0.userId != myUserID }
        guard !partnerRows.isEmpty else { return }

        let context = ModelContext(modelContainer)

        // 找到 sharedSpaceID 匹配的 PairSpace
        let pairSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
        guard let pairSpace = pairSpaces.first(where: { $0.sharedSpaceID == spaceID }) else { return }

        // 找到 pair 中对方的 membership（排除当前用户的本地 UUID）
        let pairSpaceID = pairSpace.id
        let memberships = (try? context.fetch(
            FetchDescriptor<PersistentPairMembership>(
                predicate: #Predicate { $0.pairSpaceID == pairSpaceID }
            )
        )) ?? []

        let partnerMembership: PersistentPairMembership?
        if let myLocalID = myLocalUserID {
            partnerMembership = memberships.first(where: { $0.userID != myLocalID })
        } else {
            // fallback: pair 只有 2 人，取最后加入的那个
            partnerMembership = memberships.count == 2 ? memberships.last : memberships.first
        }

        guard let partner = partnerMembership, let dto = partnerRows.first else { return }

        partner.nickname = dto.displayName

        let remoteVersion = dto.avatarVersion ?? 0
        // Refresh on ANY divergence, not just forward bumps. Reinstall / restore
        // from CloudKit can regress remote_version below local_version while the
        // underlying bytes are actually new; a strict `>` gate would miss those.
        let versionDiffers = remoteVersion != partner.avatarVersion
        let assetChanged = partner.avatarAssetID != dto.avatarAssetID
        let shouldRefresh = versionDiffers || assetChanged

        if shouldRefresh {
            if let assetID = dto.avatarAssetID, !assetID.isEmpty {
                partner.avatarPhotoFileName = avatarMediaStore.partnerCacheFileName(for: assetID, version: remoteVersion)
            } else {
                partner.avatarPhotoFileName = nil
            }
            partner.avatarAssetID = dto.avatarAssetID
            partner.avatarSystemName = dto.avatarSystemName
            partner.avatarVersion = remoteVersion

            if let urlString = dto.avatarUrl,
               let url = URL(string: urlString),
               let assetID = dto.avatarAssetID {
                let uploaderRef = avatarUploader
                let storeRef = avatarMediaStore
                let log = logger
                let targetVersion = remoteVersion
                Task.detached(priority: .utility) {
                    do {
                        let bytes = try await uploaderRef.downloadAvatar(from: url)
                        let fileName = storeRef.partnerCacheFileName(for: assetID, version: targetVersion)
                        try storeRef.persistAvatarData(bytes, fileName: fileName)
                        #if canImport(UIKit)
                        // Evict any stale UIImage the UI cached under this name so
                        // the next render re-reads the freshly written bytes.
                        await MainActor.run {
                            UserAvatarRuntimeStore.remove(fileName: fileName)
                        }
                        #endif
                        log.info("downloaded partner avatar fileName=\(fileName, privacy: .public) bytes=\(bytes.count)")
                        NotificationCenter.default.post(
                            name: .partnerAvatarDownloaded,
                            object: nil,
                            userInfo: ["assetID": assetID, "version": targetVersion]
                        )
                    } catch {
                        log.error("partner avatar download failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        try context.save()
        logger.info("[Pull] ✅ 拉取对方 profile: \(dto.displayName)")
    }

    private func pullSpaces(spaceID: UUID, since: String) async throws {
        let rows: [SpaceDTO] = try await client.from("spaces")
            .select()
            .eq("id", value: spaceID.uuidString)
            .gte("updated_at", value: since)
            .execute()
            .value

        if !rows.isEmpty {
            let context = ModelContext(modelContainer)
            for dto in rows {
                dto.applyToLocal(context: context)
            }
            try context.save()
            logger.info("[Pull] ✅ 拉取 space 名称更新")
        }
    }

    // MARK: - Realtime Handlers

    private func handleRealtimeChange(_ change: AnyAction, table: String) async {
        // 回声过滤：若这条 recordID 我们刚刚 push 过，且 incoming 事件里的 updated_at
        // 不比我们推送的时间明显晚（<2s），视为自己 push 绕回来的回声，跳过。
        //
        // 关键：光看 recordID 会误把 partner 并发修改同一行的 Realtime 事件当作自己
        // 回声吞掉。必须把 incoming 的 updated_at 跟 push 时间做对比：明显晚（>2s）
        // 说明是服务端后续收到了 partner 的 UPDATE 并广播过来，不能跳过。
        if let recordID = Self.extractRecordID(from: change),
           let pushedAt = recentlyPushedIDs[recordID] {
            let incomingUpdatedAt = Self.extractUpdatedAt(from: change)
            let isLikelyPartnerUpdate: Bool
            if let incomingUpdatedAt {
                isLikelyPartnerUpdate = incomingUpdatedAt.timeIntervalSince(pushedAt) > 2.0
            } else {
                isLikelyPartnerUpdate = false
            }
            if !isLikelyPartnerUpdate,
               Date().timeIntervalSince(pushedAt) < echoWindow {
                return
            }
        }

        await catchUp()
        lastSyncedAt = Date()

        await MainActor.run {
            NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
        }
    }

    /// 从 AnyAction payload 中取 record id（insert/update 看 record；delete 看 oldRecord）
    private static func extractRecordID(from change: AnyAction) -> UUID? {
        let record: [String: AnyJSON]
        switch change {
        case .insert(let action): record = action.record
        case .update(let action): record = action.record
        case .delete(let action): record = action.oldRecord
        }
        guard let raw = record["id"]?.stringValue else { return nil }
        return UUID(uuidString: raw)
    }

    /// 从 AnyAction payload 取服务端最终写入的 updated_at（用于 echo filter 区分自己
    /// push 的回声 vs partner 的并发修改）。
    private static func extractUpdatedAt(from change: AnyAction) -> Date? {
        let record: [String: AnyJSON]
        switch change {
        case .insert(let action): record = action.record
        case .update(let action): record = action.record
        case .delete(let action): record = action.oldRecord
        }
        guard let raw = record["updated_at"]?.stringValue else { return nil }
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFull.date(from: raw) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    /// 清理过期的回声标记
    private func pruneEchoWindow() {
        let cutoff = Date().addingTimeInterval(-echoWindow)
        recentlyPushedIDs = recentlyPushedIDs.filter { $0.value > cutoff }
    }

    private func handleMemberChange(_ change: AnyAction) async {
        switch change {
        case .insert:
            await MainActor.run {
                NotificationCenter.default.post(name: .pairMemberJoined, object: nil)
            }
        case .update:
            // 对方更新了头像或名称，触发补拉刷新本地数据
            await catchUp()
            await MainActor.run {
                NotificationCenter.default.post(name: .supabaseRealtimeChanged, object: nil)
            }
        case .delete:
            await MainActor.run {
                NotificationCenter.default.post(name: .pairMemberRemoved, object: nil)
            }
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
    static let partnerAvatarDownloaded = Notification.Name("partnerAvatarDownloaded")
}

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
        case .taskMessage: return "task_messages"
        case .importantDate: return "important_dates"
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
    // 双人协作必需字段（Plan A 新增）
    var executionRole: String
    var assignmentState: String
    var responseHistory: String?
    var assignmentMessages: String?
    var reminderRequestedAt: Date?
    var locationText: String?

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
        case executionRole = "execution_role"
        case assignmentState = "assignment_state"
        case responseHistory = "response_history"
        case assignmentMessages = "assignment_messages"
        case reminderRequestedAt = "reminder_requested_at"
        case locationText = "location_text"
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
        if let data = persistent.repeatRuleData {
            self.repeatRule = String(data: data, encoding: .utf8)
        } else {
            self.repeatRule = nil
        }
        // occurrenceCompletions: 本地无独立字段；保持 nil 且通过自定义 encode 跳过，
        // 避免每次 push 抹掉远端已有数据
        self.occurrenceCompletions = nil
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        self.completedAt = persistent.completedAt
        self.isArchived = persistent.isArchived
        self.archivedAt = persistent.archivedAt
        // 软删除使用 tombstone；isLocallyDeleted=true 表示要让对方也删除
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
        // 双人协作字段
        self.executionRole = persistent.executionRoleRawValue
        self.assignmentState = persistent.assignmentStateRawValue
        self.responseHistory = String(data: persistent.responseHistoryData, encoding: .utf8)
        self.assignmentMessages = String(data: persistent.assignmentMessagesData, encoding: .utf8)
        self.reminderRequestedAt = persistent.reminderRequestedAt
        self.locationText = persistent.locationText
    }

    /// 自定义 encode：occurrenceCompletions 不编码，避免 push 时覆盖远端由对方维护的字段
    nonisolated func encode(to encoder: Encoder) throws {
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
        // occurrenceCompletions intentionally omitted
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(executionRole, forKey: .executionRole)
        try c.encode(assignmentState, forKey: .assignmentState)
        try c.encodeIfPresent(responseHistory, forKey: .responseHistory)
        try c.encodeIfPresent(assignmentMessages, forKey: .assignmentMessages)
        try c.encodeIfPresent(reminderRequestedAt, forKey: .reminderRequestedAt)
        try c.encodeIfPresent(locationText, forKey: .locationText)
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            // 冲突保护：incoming 比本地旧则跳过（网络乱序 / 时钟漂移场景）
            if updatedAt < existing.updatedAt { return }
            // UPDATE: 同步远端字段
            existing.title = title
            existing.notes = notes
            existing.listID = listId
            existing.projectID = projectId
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
            existing.executionRoleRawValue = executionRole
            existing.assignmentStateRawValue = assignmentState
            if let h = responseHistory, let d = h.data(using: .utf8) { existing.responseHistoryData = d }
            if let m = assignmentMessages, let d = m.data(using: .utf8) { existing.assignmentMessagesData = d }
            existing.reminderRequestedAt = reminderRequestedAt
            existing.locationText = locationText
            // 软删除：用 tombstone 标记，不硬删，避免下次 pull 被 INSERT 复活
            if isDeleted {
                existing.isLocallyDeleted = true
            }
        } else if !isDeleted {
            // INSERT: 本地不存在 & 未被软删除 → 创建新记录
            // assignmentState 直接用 DTO 传来的（服务端权威），不再从 status 派生
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
                assignmentStateRawValue: assignmentState,
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
        }
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

    nonisolated init(from persistent: PersistentTaskList, spaceID: UUID? = nil) {
        self.id = persistent.id
        self.spaceId = spaceID ?? persistent.spaceID
        self.creatorId = persistent.creatorID
        self.name = persistent.name
        self.kind = persistent.kindRawValue
        self.colorToken = persistent.colorToken
        self.sortOrder = persistent.sortOrder
        self.isArchived = persistent.isArchived
        self.createdAt = persistent.createdAt
        self.updatedAt = persistent.updatedAt
        // 软删除使用 tombstone；isLocallyDeleted=true 表示要让对方也删除
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentTaskList>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            if updatedAt < existing.updatedAt { return } // 冲突保护
            existing.name = name
            existing.kindRawValue = kind
            existing.colorToken = colorToken
            existing.sortOrder = sortOrder
            existing.isArchived = isArchived
            existing.updatedAt = updatedAt
            if isDeleted {
                existing.isLocallyDeleted = true   // tombstone 代替 context.delete
            }
        } else if !isDeleted {
            let list = PersistentTaskList(
                id: id,
                spaceID: spaceId,
                creatorID: creatorId,
                name: name,
                kindRawValue: kind,
                colorToken: colorToken,
                sortOrder: sortOrder,
                isArchived: isArchived,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            context.insert(list)
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

    nonisolated init(from persistent: PersistentProject, spaceID: UUID? = nil) {
        self.id = persistent.id
        self.spaceId = spaceID ?? persistent.spaceID
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
        // 软删除使用 tombstone；isLocallyDeleted=true 表示要让对方也删除
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
    }

    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentProject>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            if updatedAt < existing.updatedAt { return } // 冲突保护
            existing.name = name
            existing.notes = notes
            existing.colorToken = colorToken
            existing.statusRawValue = status
            existing.targetDate = targetDate
            existing.remindAt = remindAt
            existing.completedAt = completedAt
            existing.updatedAt = updatedAt
            if isDeleted {
                existing.isLocallyDeleted = true
            }
        } else if !isDeleted {
            let project = PersistentProject(
                id: id,
                spaceID: spaceId,
                creatorID: creatorId,
                name: name,
                notes: notes,
                colorToken: colorToken,
                statusRawValue: status,
                targetDate: targetDate,
                remindAt: remindAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt
            )
            context.insert(project)
        }
    }
}

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
        // 软删除使用 tombstone；isLocallyDeleted=true 表示要让对方也删除
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
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
                existing.isLocallyDeleted = true   // tombstone 代替 context.delete
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

    nonisolated init(from persistent: PersistentPeriodicTask, spaceID: UUID) {
        self.id = persistent.id
        self.spaceId = spaceID
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
        // 软删除使用 tombstone；isLocallyDeleted=true 表示要让对方也删除
        self.isDeleted = persistent.isLocallyDeleted
        self.deletedAt = persistent.isLocallyDeleted ? Date() : nil
    }

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
}

// MARK: - SpaceMemberWriter seam

/// Abstracts the space_members UPDATE call so tests can capture DTOs without hitting the network.
protocol SpaceMemberWriter: Sendable {
    func updateMember(spaceID: UUID, userID: UUID, dto: SpaceMemberUpdateDTO) async throws
}

/// Default production implementation that calls the Supabase client.
private struct SupabaseSpaceMemberWriter: SpaceMemberWriter {
    private let client = SupabaseClientProvider.shared

    func updateMember(spaceID: UUID, userID: UUID, dto: SpaceMemberUpdateDTO) async throws {
        try await client.from("space_members")
            .update(dto)
            .eq("space_id", value: spaceID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }
}

// MARK: - SpaceMemberReader seam

/// Abstracts the space_members SELECT call so tests can inject fake rows without hitting the network.
protocol SpaceMemberReader: Sendable {
    func fetchMembers(spaceID: UUID, since: String) async throws -> [SpaceMemberDTO]
}

/// Default production implementation that calls the Supabase client.
private struct SupabaseSpaceMemberReader: SpaceMemberReader {
    private let client = SupabaseClientProvider.shared

    func fetchMembers(spaceID: UUID, since: String) async throws -> [SpaceMemberDTO] {
        try await client.from("space_members")
            .select()
            .eq("space_id", value: spaceID.uuidString)
            .gte("updated_at", value: since)
            .execute()
            .value
    }
}

// MARK: - MemberProfile Push/Pull DTO

/// 更新 space_members 中自己的 profile（push 用）
struct SpaceMemberUpdateDTO: Encodable, Sendable {
    let displayName: String
    let avatarUrl: String?
    let avatarAssetID: String?
    let avatarSystemName: String?
    let avatarVersion: Int

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case avatarAssetID = "avatar_asset_id"
        case avatarSystemName = "avatar_system_name"
        case avatarVersion = "avatar_version"
    }
}

/// space_members 完整行（pull 用）
struct SpaceMemberDTO: Decodable, Sendable {
    let id: UUID
    let spaceId: UUID
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let avatarAssetID: String?
    let avatarSystemName: String?
    let avatarVersion: Int?
    let role: String?
    let joinedAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case spaceId = "space_id"
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case avatarAssetID = "avatar_asset_id"
        case avatarSystemName = "avatar_system_name"
        case avatarVersion = "avatar_version"
        case role
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }

    // applyToLocal 逻辑已在 pullSpaceMembers 中直接处理（需要 myLocalUserID 排除自己）
}

// MARK: - Space Push/Pull DTO

/// 更新 spaces 表的 display_name（push 用）
struct SpaceUpdateDTO: Encodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

/// spaces 行（pull 用）
struct SpaceDTO: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }

    /// 将空间名称更新应用到本地 PersistentSpace
    nonisolated func applyToLocal(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentSpace>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            // 冲突保护：远端 updatedAt 显式更早时跳过
            if let incoming = updatedAt, incoming < existing.updatedAt { return }
            existing.displayName = displayName
            if let updatedAt { existing.updatedAt = updatedAt }
        }
    }
}

struct ImportantDateDTO: Codable, Sendable {
    let id: UUID
    let spaceId: UUID
    let creatorId: UUID
    var kind: String
    var title: String
    var dateValue: Date
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

    nonisolated func applyToLocal(context: ModelContext) {
        let id = self.id
        let descriptor = FetchDescriptor<PersistentImportantDate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            if updatedAt < existing.updatedAt { return }
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

extension ImportantDateDTO {
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
}
