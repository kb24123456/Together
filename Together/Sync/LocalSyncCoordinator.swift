import Foundation
import SwiftData

actor LocalSyncCoordinator: SyncCoordinatorProtocol {
    private let container: ModelContainer

    /// Optional forwarder: routes recorded changes to CKSyncEngine coordinator.
    /// Set during app wiring (Phase 1+) so CKSyncEngine picks up local mutations.
    private var onChangeRecorded: (@Sendable (SyncChange) async -> Void)?

    func setOnChangeRecorded(_ callback: @escaping @Sendable (SyncChange) async -> Void) {
        onChangeRecorded = callback
    }

    init(container: ModelContainer) {
        self.container = container
    }

    func recordLocalChange(_ change: SyncChange) async {
        let context = ModelContext(container)

        do {
            if let existing = try fetchRecord(
                recordID: change.recordID,
                entityKind: change.entityKind,
                context: context
            ) {
                existing.update(from: change)
            } else {
                context.insert(PersistentSyncChange(change: change))
            }

            try context.save()

            // Forward to CKSyncEngine coordinator if wired
            await onChangeRecorded?(change)
        } catch {
            assertionFailure("Failed to persist sync change: \(error)")
        }
    }

    func pendingChanges() async -> [SyncChange] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            sortBy: [SortDescriptor(\PersistentSyncChange.changedAt, order: .forward)]
        )

        do {
            return try context.fetch(descriptor).map(\.domainModel)
        } catch {
            assertionFailure("Failed to fetch pending sync changes: \(error)")
            return []
        }
    }

    func clearPendingChanges(recordIDs: [UUID]) async {
        guard recordIDs.isEmpty == false else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> { recordIDs.contains($0.recordID) }
        )

        do {
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
        } catch {
            assertionFailure("Failed to clear pending sync changes: \(error)")
        }
    }

    func syncState(for spaceID: UUID) async -> SyncState? {
        let context = ModelContext(container)

        do {
            return try fetchStateRecord(spaceID: spaceID, context: context)?.domainModel
        } catch {
            assertionFailure("Failed to fetch sync state: \(error)")
            return nil
        }
    }

    func markPushSuccess(
        for spaceID: UUID,
        cursor: SyncCursor?,
        clearedRecordIDs: [UUID],
        syncedAt: Date
    ) async {
        let context = ModelContext(container)

        do {
            try clearPendingChanges(recordIDs: clearedRecordIDs, context: context)
            let state = SyncState(
                spaceID: spaceID,
                cursor: cursor,
                lastSyncedAt: syncedAt,
                lastError: nil,
                retryCount: 0,
                updatedAt: syncedAt
            )
            try upsertState(state, context: context)
            try context.save()
        } catch {
            assertionFailure("Failed to mark sync success: \(error)")
        }
    }

    func markSyncFailure(
        for spaceID: UUID,
        errorMessage: String,
        failedAt: Date
    ) async {
        let context = ModelContext(container)

        do {
            let current = try fetchStateRecord(spaceID: spaceID, context: context)?.domainModel
            let nextState = SyncState(
                spaceID: spaceID,
                cursor: current?.cursor,
                lastSyncedAt: current?.lastSyncedAt,
                lastError: errorMessage,
                retryCount: (current?.retryCount ?? 0) + 1,
                updatedAt: failedAt
            )
            try upsertState(nextState, context: context)
            try context.save()
        } catch {
            assertionFailure("Failed to mark sync failure: \(error)")
        }
    }

    private func fetchRecord(
        recordID: UUID,
        entityKind: SyncEntityKind,
        context: ModelContext
    ) throws -> PersistentSyncChange? {
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> {
                $0.recordID == recordID && $0.entityKindRawValue == entityKind.rawValue
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchStateRecord(
        spaceID: UUID,
        context: ModelContext
    ) throws -> PersistentSyncState? {
        let descriptor = FetchDescriptor<PersistentSyncState>(
            predicate: #Predicate<PersistentSyncState> { $0.spaceID == spaceID }
        )
        return try context.fetch(descriptor).first
    }

    private func upsertState(
        _ state: SyncState,
        context: ModelContext
    ) throws {
        if let existing = try fetchStateRecord(spaceID: state.spaceID, context: context) {
            existing.update(from: state)
        } else {
            context.insert(PersistentSyncState(state: state))
        }
    }

    private func clearPendingChanges(
        recordIDs: [UUID],
        context: ModelContext
    ) throws {
        guard recordIDs.isEmpty == false else { return }

        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> { recordIDs.contains($0.recordID) }
        )
        let records = try context.fetch(descriptor)
        for record in records {
            context.delete(record)
        }
    }
}
