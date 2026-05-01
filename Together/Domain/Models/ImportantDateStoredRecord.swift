import Foundation

struct ImportantDateStoredRecord: Identifiable, Hashable, Sendable {
    var id: UUID { event.id }
    let event: ImportantDate
    let createdAt: Date
}
