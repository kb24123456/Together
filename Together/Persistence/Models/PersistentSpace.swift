import Foundation
import TogetherCore

nonisolated extension PersistentSpace {
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
