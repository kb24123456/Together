import Foundation
import SwiftData

@Model
final class PersistentSpace {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var displayName: String
    var ownerUserID: UUID
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    init(
        id: UUID,
        typeRawValue: String,
        displayName: String,
        ownerUserID: UUID,
        statusRawValue: String,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.typeRawValue = typeRawValue
        self.displayName = displayName
        self.ownerUserID = ownerUserID
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

extension PersistentSpace {
    convenience init(space: Space) {
        self.init(
            id: space.id,
            typeRawValue: space.type.rawValue,
            displayName: space.displayName,
            ownerUserID: space.ownerUserID,
            statusRawValue: space.status.rawValue,
            createdAt: space.createdAt,
            updatedAt: space.updatedAt,
            archivedAt: space.archivedAt
        )
    }

    var domainModel: Space {
        Space(
            id: id,
            type: SpaceType(rawValue: typeRawValue) ?? .single,
            displayName: displayName,
            ownerUserID: ownerUserID,
            status: SpaceStatus(rawValue: statusRawValue) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: archivedAt
        )
    }

    func update(from space: Space) {
        typeRawValue = space.type.rawValue
        displayName = space.displayName
        ownerUserID = space.ownerUserID
        statusRawValue = space.status.rawValue
        updatedAt = space.updatedAt
        archivedAt = space.archivedAt
    }
}
