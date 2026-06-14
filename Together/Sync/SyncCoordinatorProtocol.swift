import Foundation

enum SyncEntityKind: String, Codable, Hashable, Sendable {
    case task
    case taskList
    case project
    case projectSubtask
    case periodicTask
    case space
    case memberProfile
    case avatarAsset
}

enum SyncOperationKind: String, Codable, Hashable, Sendable {
    case upsert
    case complete
    case archive
    case delete
}

struct SyncChange: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let entityKind: SyncEntityKind
    let operation: SyncOperationKind
    let recordID: UUID
    let spaceID: UUID
    let changedAt: Date

    init(
        id: UUID = UUID(),
        entityKind: SyncEntityKind,
        operation: SyncOperationKind,
        recordID: UUID,
        spaceID: UUID,
        changedAt: Date = .now
    ) {
        self.id = id
        self.entityKind = entityKind
        self.operation = operation
        self.recordID = recordID
        self.spaceID = spaceID
        self.changedAt = changedAt
    }
}

protocol SyncCoordinatorProtocol: Sendable {
    func recordLocalChange(_ change: SyncChange) async
}
