import CloudKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "PairSyncBridge")

/// Encapsulates the sync pipeline for a single pair space.
///
/// Pair data now lives in a single shared CloudKit authority zone.
/// This bridge only exists to apply decoded remote entities into the local
/// SwiftData projection/cache.
final class PairSyncBridge: Sendable {
    let pairSpaceID: UUID

    /// The CKSyncEngine managing the shared-authority zone for this pair space.
    let engine: CKSyncEngine

    /// The CKSyncEngineDelegate for this pair zone.
    let delegate: SyncEngineDelegate

    /// The zone ID for this pair space's shared-authority zone.
    let zoneID: CKRecordZone.ID

    /// The model container for SwiftData operations.
    private let modelContainer: ModelContainer

    /// The codec registry for encoding/decoding CKRecords.
    private let codecRegistry: RecordCodecRegistry

    init(
        pairSpaceID: UUID,
        engine: CKSyncEngine,
        delegate: SyncEngineDelegate,
        zoneID: CKRecordZone.ID,
        modelContainer: ModelContainer,
        codecRegistry: RecordCodecRegistry
    ) {
        self.pairSpaceID = pairSpaceID
        self.engine = engine
        self.delegate = delegate
        self.zoneID = zoneID
        self.modelContainer = modelContainer
        self.codecRegistry = codecRegistry
    }

    // MARK: - Entity Application

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
        case let spaceCodable as SpaceRecordCodable:
            applySpace(spaceCodable.space, context: context)
        case let memberProfileCodable as MemberProfileRecordCodable:
            applyMemberProfile(memberProfileCodable.profile, context: context)
        default:
            logger.warning("[PairBridge] Unhandled entity type during shared apply")
        }
    }

    private func applyMemberProfile(
        _ profile: MemberProfileRecordCodable.Profile,
        context: ModelContext
    ) {
        let store = LocalUserAvatarMediaStore()
        let memberships = (try? context.fetch(FetchDescriptor<PersistentPairMembership>())) ?? []
        for membership in memberships where membership.userID == profile.userID {
            membership.nickname = profile.displayName
            membership.avatarSystemName = profile.avatarSystemName
            membership.avatarVersion = profile.avatarVersion

            if profile.avatarDeleted {
                if let fileName = membership.avatarPhotoFileName {
                    try? store.removeAvatar(named: fileName)
                }
                membership.avatarPhotoFileName = nil
                membership.avatarAssetID = nil
            } else if let avatarAssetID = profile.avatarAssetID {
                if store.fileExists(named: avatarAssetID) {
                    membership.avatarPhotoFileName = avatarAssetID
                } else if membership.avatarAssetID != avatarAssetID, membership.avatarPhotoFileName != avatarAssetID {
                    membership.avatarPhotoFileName = nil
                }
                membership.avatarAssetID = avatarAssetID
            }
        }

        let profiles = (try? context.fetch(FetchDescriptor<PersistentUserProfile>())) ?? []
        for userProfile in profiles where userProfile.userID == profile.userID {
            userProfile.displayName = profile.displayName
            userProfile.avatarSystemName = profile.avatarSystemName
            userProfile.avatarVersion = profile.avatarVersion
            if profile.avatarDeleted {
                userProfile.avatarPhotoFileName = nil
                userProfile.avatarAssetID = nil
                userProfile.avatarPhotoData = nil
            } else if let avatarAssetID = profile.avatarAssetID {
                if store.fileExists(named: avatarAssetID) {
                    userProfile.avatarPhotoFileName = avatarAssetID
                } else if userProfile.avatarAssetID != avatarAssetID, userProfile.avatarPhotoFileName != avatarAssetID {
                    userProfile.avatarPhotoFileName = nil
                    userProfile.avatarPhotoData = nil
                }
                userProfile.avatarAssetID = avatarAssetID
            }
            userProfile.updatedAt = profile.updatedAt
        }

        logger.info("[PairBridge] 👤 Applied profile update for userID=\(profile.userID.uuidString.prefix(8))")
    }

    private func applySpace(_ space: Space, context: ModelContext) {
        let spaceID = space.id
        let descriptor = FetchDescriptor<PersistentSpace>(
            predicate: #Predicate<PersistentSpace> { $0.id == spaceID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if SyncEngineDelegate.shouldApplyFetchedRecord(in: zoneID, remoteUpdatedAt: space.updatedAt, localUpdatedAt: existing.updatedAt) {
                existing.update(from: space)
            }
        } else {
            context.insert(PersistentSpace(space: space))
        }

    }

    private func applyItem(_ item: Item, context: ModelContext) {
        let itemID = item.id
        let descriptor = FetchDescriptor<PersistentItem>(
            predicate: #Predicate<PersistentItem> { $0.id == itemID }
        )
        if let existing = try? context.fetch(descriptor).first {
            if SyncEngineDelegate.shouldApplyFetchedRecord(in: zoneID, remoteUpdatedAt: item.updatedAt, localUpdatedAt: existing.updatedAt) {
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
            if SyncEngineDelegate.shouldApplyFetchedRecord(in: zoneID, remoteUpdatedAt: list.updatedAt, localUpdatedAt: existing.updatedAt) {
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
            if SyncEngineDelegate.shouldApplyFetchedRecord(in: zoneID, remoteUpdatedAt: project.updatedAt, localUpdatedAt: existing.updatedAt) {
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
            if SyncEngineDelegate.shouldApplyFetchedRecord(in: zoneID, remoteUpdatedAt: task.updatedAt, localUpdatedAt: existing.updatedAt) {
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
}
