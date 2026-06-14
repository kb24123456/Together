import Foundation
import SwiftData

@Model
final class PersistentItemOccurrenceCompletion {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var occurrenceDate: Date = Date.now
    var completedAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

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
