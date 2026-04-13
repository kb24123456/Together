import Foundation
import SwiftData

@Model
final class PersistentSyncChange {
    var id: UUID
    var entityKindRawValue: String
    var operationRawValue: String
    var recordID: UUID
    var spaceID: UUID
    var changedAt: Date
    var lifecycleStateRawValue: String
    var lastAttemptedAt: Date?
    var confirmedAt: Date?
    var lastError: String?

    init(change: SyncChange) {
        self.id = change.id
        self.entityKindRawValue = change.entityKind.rawValue
        self.operationRawValue = change.operation.rawValue
        self.recordID = change.recordID
        self.spaceID = change.spaceID
        self.changedAt = change.changedAt
        self.lifecycleStateRawValue = SyncMutationLifecycleState.pending.rawValue
        self.lastAttemptedAt = nil
        self.confirmedAt = nil
        self.lastError = nil
    }

    var domainModel: SyncChange {
        SyncChange(
            id: id,
            entityKind: SyncEntityKind(rawValue: entityKindRawValue) ?? .task,
            operation: SyncOperationKind(rawValue: operationRawValue) ?? .upsert,
            recordID: recordID,
            spaceID: spaceID,
            changedAt: changedAt
        )
    }

    func update(from change: SyncChange) {
        entityKindRawValue = change.entityKind.rawValue
        operationRawValue = change.operation.rawValue
        recordID = change.recordID
        spaceID = change.spaceID
        changedAt = change.changedAt
        lifecycleStateRawValue = SyncMutationLifecycleState.pending.rawValue
        lastAttemptedAt = nil
        confirmedAt = nil
        lastError = nil
    }

    var lifecycleState: SyncMutationLifecycleState {
        get { SyncMutationLifecycleState(rawValue: lifecycleStateRawValue) ?? .pending }
        set { lifecycleStateRawValue = newValue.rawValue }
    }

    var snapshot: SyncMutationSnapshot {
        SyncMutationSnapshot(
            change: domainModel,
            lifecycleState: lifecycleState,
            lastAttemptedAt: lastAttemptedAt,
            confirmedAt: confirmedAt,
            lastError: lastError
        )
    }
}
