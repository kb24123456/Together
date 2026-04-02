import Foundation
import SwiftData

@Model
final class PersistentItemOccurrenceCompletion {
    var id: UUID
    var itemID: UUID
    var occurrenceDate: Date
    var completedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        occurrenceDate: Date,
        completedAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.occurrenceDate = occurrenceDate
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
