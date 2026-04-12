import CloudKit
import CryptoKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "PairSyncBridge")

/// Encapsulates the full sync pipeline for a single pair space:
/// - CKSyncEngine for private zone multi-device sync
/// - SyncRelayGateway for cross-user sync via public DB relay
///
/// ## Data Flow
///
/// **Outbound (local → partner):**
/// 1. Local mutation → CKSyncEngine pushes to private zone
/// 2. `onLocalChangesPushed` fires with saved CKRecords
/// 3. Records converted to ChangeEntry → encrypted → posted as SyncRelay
///
/// **Inbound (partner → local):**
/// 1. CKQuerySubscription fires silent push (or backup poll)
/// 2. `fetchAndApplyRelays()` fetches new SyncRelay records
/// 3. Decrypted ChangeEntries applied to local SwiftData
/// 4. Changes also queued to CKSyncEngine for multi-device sync
final class PairSyncBridge: Sendable {
    let pairSpaceID: UUID

    /// The CKSyncEngine managing the private zone for this pair space.
    let engine: CKSyncEngine

    /// The relay gateway for posting/receiving encrypted changes to/from the partner.
    let relayGateway: SyncRelayGateway

    /// The CKSyncEngineDelegate for this pair zone.
    let delegate: SyncEngineDelegate

    /// The zone ID for this pair space's private zone.
    let zoneID: CKRecordZone.ID

    /// The model container for SwiftData operations.
    private let modelContainer: ModelContainer

    /// The codec registry for encoding/decoding CKRecords.
    private let codecRegistry: RecordCodecRegistry

    init(
        pairSpaceID: UUID,
        engine: CKSyncEngine,
        delegate: SyncEngineDelegate,
        relayGateway: SyncRelayGateway,
        zoneID: CKRecordZone.ID,
        modelContainer: ModelContainer,
        codecRegistry: RecordCodecRegistry
    ) {
        self.pairSpaceID = pairSpaceID
        self.engine = engine
        self.delegate = delegate
        self.relayGateway = relayGateway
        self.zoneID = zoneID
        self.modelContainer = modelContainer
        self.codecRegistry = codecRegistry

        // Wire the relay posting callback: when CKSyncEngine successfully pushes
        // records to private zone, convert them to ChangeEntries and post as relay.
        delegate.onLocalChangesPushed = { [weak self] savedRecords in
            guard let self else { return }
            Task {
                await self.postRelayForPushedRecords(savedRecords)
            }
        }

        // Wire the deletion relay callback: confirmed server deletions are relayed.
        delegate.onLocalDeletesPushed = { [weak self] deletions in
            guard let self else { return }
            Task {
                await self.postRelayForDeletions(deletions)
            }
        }
    }

    // MARK: - Outbound Relay Posting

    /// Converts pushed CKRecords to ChangeEntries and posts them as encrypted relay.
    private func postRelayForPushedRecords(_ records: [CKRecord]) async {
        let changes = records.compactMap { RelayChangeConverter.toChangeEntry(from: $0) }
        guard !changes.isEmpty else { return }

        do {
            let seq = try await relayGateway.postRelay(changes: changes)
            saveLastSentSequence(seq)
        } catch {
            logger.error("[PairBridge] ❌ Failed to post relay for space \(self.pairSpaceID.uuidString.prefix(8)): \(error)")
            persistFailedRelay(changes: changes)
        }
    }

    /// Posts deletion entries as encrypted relay to the partner.
    private func postRelayForDeletions(_ deletions: [(recordID: CKRecord.ID, recordType: String)]) async {
        let changes = deletions.map {
            RelayChangeConverter.toDeletionEntry(recordID: $0.recordID, recordType: $0.recordType)
        }
        guard !changes.isEmpty else { return }

        do {
            let seq = try await relayGateway.postRelay(changes: changes)
            saveLastSentSequence(seq)
        } catch {
            logger.error("[PairBridge] ❌ Failed to post deletion relay for space \(self.pairSpaceID.uuidString.prefix(8)): \(error)")
            persistFailedRelay(changes: changes)
        }
    }

    // MARK: - Inbound Relay Fetching

    /// Fetches new relay messages from the partner and applies them locally.
    /// Returns the number of changes applied.
    @discardableResult
    func fetchAndApplyRelays() async -> Int {
        let lastSeq = loadLastReceivedSequence()

        let messages: [RelayMessage]
        do {
            messages = try await relayGateway.fetchNewRelays(since: lastSeq)
        } catch {
            logger.error("[PairBridge] ❌ Failed to fetch relays for space \(self.pairSpaceID.uuidString.prefix(8)): \(error)")
            return 0
        }

        guard !messages.isEmpty else { return 0 }

        let context = ModelContext(modelContainer)
        var appliedCount = 0

        var maxSequence: Int64 = 0

        for message in messages.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            for entry in message.changes {
                if entry.operation == "delete" {
                    if let uuid = UUID(uuidString: entry.recordID) {
                        archiveOrDelete(uuid: uuid, recordType: entry.recordType, context: context)
                        appliedCount += 1
                    }
                } else if entry.operation == "upsert" {
                    // MemberProfile: decode via dedicated codec (not in registry)
                    if entry.recordType == CloudKitProfileRecordCodec.recordType {
                        if let record = RelayChangeConverter.toCKRecord(from: entry, in: zoneID),
                           let payload = CloudKitProfileRecordCodec.decode(record: record) {
                            applyMemberProfile(payload, context: context)
                            appliedCount += 1
                        }
                    } else if let record = RelayChangeConverter.toCKRecord(from: entry, in: zoneID) {
                        if codecRegistry.canDecode(record.recordType) {
                            if let entity = try? codecRegistry.decode(record) {
                                applyEntity(entity, context: context)
                                appliedCount += 1
                            }
                        }
                    }
                }
            }
            maxSequence = max(maxSequence, message.sequenceNumber)
        }

        if appliedCount > 0 {
            do {
                try context.save()
                // Only advance the cursor AFTER entities are persisted
                saveLastReceivedSequence(maxSequence)
                logger.info("[PairBridge] ✅ Applied \(appliedCount) relay changes for space \(self.pairSpaceID.uuidString.prefix(8))")
            } catch {
                logger.error("[PairBridge] ❌ Failed to save relay changes: \(error)")
                // Do NOT advance sequence — next fetch will re-deliver these messages
            }
        } else if maxSequence > 0 {
            // All messages were no-ops (e.g. already applied), still advance cursor
            saveLastReceivedSequence(maxSequence)
        }

        return appliedCount
    }

    // MARK: - Retry Queue

    /// Retries failed relay posts from the persistent queue.
    func retryFailedRelays() async {
        let context = ModelContext(modelContainer)
        let spaceID = pairSpaceID
        let descriptor = FetchDescriptor<PersistentSyncRelayQueue>(
            predicate: #Predicate<PersistentSyncRelayQueue> { $0.pairSpaceID == spaceID },
            sortBy: [SortDescriptor(\PersistentSyncRelayQueue.createdAt, order: .forward)]
        )

        guard let queued = try? context.fetch(descriptor), !queued.isEmpty else { return }

        for item in queued {
            guard item.attemptCount < 10 else {
                logger.warning("[PairBridge] Dropping relay after 10 attempts for space \(self.pairSpaceID.uuidString.prefix(8))")
                context.delete(item)
                continue
            }

            guard let data = item.payloadJSON.data(using: .utf8),
                  let changes = try? JSONDecoder().decode([ChangeEntry].self, from: data)
            else {
                context.delete(item)
                continue
            }

            do {
                let seq = try await relayGateway.postRelay(changes: changes)
                saveLastSentSequence(seq)
                context.delete(item)
                logger.info("[PairBridge] ✅ Retried relay successfully for space \(self.pairSpaceID.uuidString.prefix(8))")
            } catch {
                item.attemptCount += 1
                item.lastAttemptAt = .now
                item.lastError = error.localizedDescription
            }
        }

        try? context.save()
    }

    // MARK: - Entity Application (from relay)

    private func applyEntity(_ entity: any RecordCodable, context: ModelContext) {
        switch entity {
        case let itemCodable as ItemRecordCodable:
            applyItem(itemCodable.item, context: context)
        case let listCodable as TaskListRecordCodable:
            applyTaskList(listCodable.taskList, context: context)
        case let projectCodable as ProjectRecordCodable:
            applyProject(projectCodable.project, context: context)
        case let subtaskCodable as ProjectSubtaskRecordCodable:
            applyProjectSubtask(subtaskCodable.subtask, context: context)
        case let periodicCodable as PeriodicTaskRecordCodable:
            applyPeriodicTask(periodicCodable.periodicTask, context: context)
        default:
            logger.warning("[PairBridge] Unhandled entity type during relay apply")
        }
    }

    private func applyMemberProfile(
        _ profile: CloudKitProfileRecordCodec.MemberProfilePayload,
        context: ModelContext
    ) {
        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.userID == profile.userID {
            membership.nickname = profile.displayName
            membership.avatarSystemName = profile.avatarSystemName

            // nil = relay 不涉及头像（metadata-only），保持原样
            // ""  = 发送方显式删除了自定义头像
            // 非空 = 新头像 base64 数据
            if let base64 = profile.avatarPhotoBase64 {
                if !base64.isEmpty, let imageData = Data(base64Encoded: base64) {
                    let store = LocalUserAvatarMediaStore()
                    let fileName = store.canonicalFileName(for: profile.userID)
                    try? store.persistAvatarData(imageData, fileName: fileName)
                    membership.avatarPhotoFileName = fileName
                } else {
                    // 空字符串 → 显式清除自定义头像
                    membership.avatarPhotoFileName = nil
                }
            }
            // avatarPhotoBase64 == nil → 不动 avatarPhotoFileName
        }

        // Update pair space display name if provided
        if let newDisplayName = profile.pairSpaceDisplayName {
            let resolvedName: String? = newDisplayName.isEmpty ? nil : newDisplayName
            let pairSpaces = (try? context.fetch(FetchDescriptor<PersistentPairSpace>())) ?? []
            for pairSpace in pairSpaces where pairSpace.sharedSpaceID == profile.spaceID {
                pairSpace.displayName = resolvedName
            }
            // 同步更新关联的 PersistentSpace，确保 Today/Home 读到一致的名称
            if let name = resolvedName {
                let spaceID = profile.spaceID
                let spaces = (try? context.fetch(
                    FetchDescriptor<PersistentSpace>(
                        predicate: #Predicate<PersistentSpace> { $0.id == spaceID }
                    )
                )) ?? []
                for space in spaces {
                    space.displayName = name
                }
            }
        }

        logger.info("[PairBridge] 👤 Applied profile update for userID=\(profile.userID.uuidString.prefix(8))")
    }

    private func applyItem(_ item: Item, context: ModelContext) {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.id == itemID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if item.updatedAt >= existing.updatedAt {
                existing.update(from: item)
            }
        } else {
            context.insert(PersistentItem(item: item))
        }
    }

    private func applyTaskList(_ list: TaskList, context: ModelContext) {
        let listID = list.id
        let descriptor = FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate<PersistentTaskList> { $0.id == listID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if list.updatedAt >= existing.updatedAt {
                existing.update(from: list)
            }
        } else {
            context.insert(PersistentTaskList(list: list))
        }
    }

    private func applyProject(_ project: Project, context: ModelContext) {
        let projectID = project.id
        let descriptor = FetchDescriptor<PersistentProject>(
            predicate: #Predicate<PersistentProject> { $0.id == projectID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if project.updatedAt >= existing.updatedAt {
                existing.update(from: project)
            }
        } else {
            context.insert(PersistentProject(project: project))
        }
    }

    private func applyProjectSubtask(_ subtask: ProjectSubtask, context: ModelContext) {
        let subtaskID = subtask.id
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(
            predicate: #Predicate<PersistentProjectSubtask> { $0.id == subtaskID }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.title = subtask.title
            existing.isCompleted = subtask.isCompleted
            existing.sortOrder = subtask.sortOrder
        } else {
            context.insert(PersistentProjectSubtask(subtask: subtask))
        }
    }

    private func applyPeriodicTask(_ task: PeriodicTask, context: ModelContext) {
        let taskID = task.id
        let descriptor = FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate<PersistentPeriodicTask> { $0.id == taskID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if task.updatedAt >= existing.updatedAt {
                existing.update(from: task)
            }
        } else {
            context.insert(PersistentPeriodicTask(task: task))
        }
    }

    private func archiveOrDelete(uuid: UUID, recordType: String, context: ModelContext) {
        if recordType == ItemRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.id == uuid }
            )
            if let item = try? context.fetch(descriptor).first, !item.isArchived {
                item.isArchived = true
                item.archivedAt = .now
                item.updatedAt = .now
            }
        } else if recordType == TaskListRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentTaskList>(
                predicate: #Predicate<PersistentTaskList> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == ProjectRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentProject>(
                predicate: #Predicate<PersistentProject> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == ProjectSubtaskRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentProjectSubtask>(
                predicate: #Predicate<PersistentProjectSubtask> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        } else if recordType == PeriodicTaskRecordCodable.ckRecordType {
            let descriptor = FetchDescriptor<PersistentPeriodicTask>(
                predicate: #Predicate<PersistentPeriodicTask> { $0.id == uuid }
            )
            if let entity = try? context.fetch(descriptor).first {
                context.delete(entity)
            }
        }
    }

    // MARK: - Sequence Persistence

    private func loadLastReceivedSequence() -> Int64 {
        let context = ModelContext(modelContainer)
        let spaceID = pairSpaceID
        let descriptor = FetchDescriptor<PersistentRelaySequence>(
            predicate: #Predicate<PersistentRelaySequence> { $0.pairSpaceID == spaceID }
        )
        return (try? context.fetch(descriptor).first?.lastReceivedSequence) ?? 0
    }

    /// Exposed for coordinator-level profile relay posting.
    func saveLastSentSequencePublic(_ seq: Int64) {
        saveLastSentSequence(seq)
    }

    private func saveLastSentSequence(_ seq: Int64) {
        let context = ModelContext(modelContainer)
        let spaceID = pairSpaceID
        let descriptor = FetchDescriptor<PersistentRelaySequence>(
            predicate: #Predicate<PersistentRelaySequence> { $0.pairSpaceID == spaceID }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.lastSentSequence = seq
            existing.updatedAt = .now
        } else {
            context.insert(PersistentRelaySequence(
                pairSpaceID: pairSpaceID,
                lastSentSequence: seq
            ))
        }
        try? context.save()
    }

    private func saveLastReceivedSequence(_ seq: Int64) {
        let context = ModelContext(modelContainer)
        let spaceID = pairSpaceID
        let descriptor = FetchDescriptor<PersistentRelaySequence>(
            predicate: #Predicate<PersistentRelaySequence> { $0.pairSpaceID == spaceID }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.lastReceivedSequence = seq
            existing.updatedAt = .now
        } else {
            context.insert(PersistentRelaySequence(
                pairSpaceID: pairSpaceID,
                lastReceivedSequence: seq
            ))
        }
        try? context.save()
    }

    /// Exposed for coordinator-level profile relay failure persistence (same queue as task relay).
    func persistFailedRelayPublic(changes: [ChangeEntry]) {
        persistFailedRelay(changes: changes)
    }

    private func persistFailedRelay(changes: [ChangeEntry]) {
        guard let data = try? JSONEncoder().encode(changes),
              let json = String(data: data, encoding: .utf8) else { return }

        let context = ModelContext(modelContainer)
        context.insert(PersistentSyncRelayQueue(
            pairSpaceID: pairSpaceID,
            payloadJSON: json
        ))
        try? context.save()
    }
}
