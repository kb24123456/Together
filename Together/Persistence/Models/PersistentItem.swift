import Foundation
import SwiftData

@Model
final class PersistentItem {
    var id: UUID = UUID()
    var spaceID: UUID?
    var listID: UUID?
    var projectID: UUID?
    var creatorID: UUID = UUID()
    var title: String = ""
    var notes: String?
    var locationText: String?
    var dueAt: Date?
    var hasExplicitTime: Bool = false
    var remindAt: Date?
    var statusRawValue: String = ItemStatus.inProgress.rawValue
    var lastActionByUserID: UUID?
    var lastActionAt: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var completedAt: Date?
    /// Authoritative completer — set once on markCompleted, cleared on
    /// markIncomplete. Preserved across later post-completion actions
    /// (archive/unarchive) unlike lastActionByUserID.
    var completedByUserID: UUID?
    var sortOrder: Double = 0
    var isPinned: Bool = false
    var isDraft: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date?
    var repeatRuleData: Data?
    var isLocallyDeleted: Bool = false

    init(
        id: UUID,
        spaceID: UUID?,
        listID: UUID?,
        projectID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        locationText: String?,
        dueAt: Date?,
        hasExplicitTime: Bool,
        remindAt: Date?,
        statusRawValue: String,
        lastActionByUserID: UUID?,
        lastActionAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        completedByUserID: UUID? = nil,
        sortOrder: Double = 0,
        isPinned: Bool,
        isDraft: Bool,
        isArchived: Bool,
        archivedAt: Date?,
        repeatRuleData: Data?,
        isLocallyDeleted: Bool = false
    ) {
        self.id = id
        self.spaceID = spaceID
        self.listID = listID
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.locationText = locationText
        self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime
        self.remindAt = remindAt
        self.statusRawValue = statusRawValue
        self.lastActionByUserID = lastActionByUserID
        self.lastActionAt = lastActionAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.completedByUserID = completedByUserID
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.repeatRuleData = repeatRuleData
        self.isLocallyDeleted = isLocallyDeleted
    }
}

extension PersistentItem {
    convenience init(item: Item) {
        self.init(
            id: item.id,
            spaceID: item.spaceID,
            listID: item.listID,
            projectID: item.projectID,
            creatorID: item.creatorID,
            title: item.title,
            notes: item.notes,
            locationText: item.locationText,
            dueAt: item.dueAt,
            hasExplicitTime: item.hasExplicitTime,
            remindAt: item.remindAt,
            statusRawValue: item.status.rawValue,
            lastActionByUserID: item.lastActionByUserID,
            lastActionAt: item.lastActionAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            completedAt: item.completedAt,
            completedByUserID: item.completedByUserID,
            sortOrder: item.sortOrder,
            isPinned: item.isPinned,
            isDraft: item.isDraft,
            isArchived: item.isArchived,
            archivedAt: item.archivedAt,
            repeatRuleData: Self.encode(item.repeatRule)
        )
    }

    func domainModel(occurrenceCompletions: [ItemOccurrenceCompletion] = []) -> Item {
        Item(
            id: id,
            spaceID: spaceID,
            listID: listID,
            projectID: projectID,
            creatorID: creatorID,
            title: title,
            notes: notes,
            locationText: locationText,
            dueAt: dueAt,
            hasExplicitTime: hasExplicitTime,
            remindAt: remindAt,
            status: ItemStatus(rawValue: statusRawValue) ?? .inProgress,
            lastActionByUserID: lastActionByUserID,
            lastActionAt: lastActionAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: repeatRuleData == nil ? completedAt : nil,
            completedByUserID: completedByUserID,
            occurrenceCompletions: occurrenceCompletions,
            sortOrder: sortOrder,
            isPinned: isPinned,
            isDraft: isDraft,
            isArchived: isArchived,
            archivedAt: archivedAt,
            repeatRule: Self.decode(repeatRuleData, defaultValue: nil)
        )
    }

    func update(from item: Item) {
        spaceID = item.spaceID
        listID = item.listID
        projectID = item.projectID
        title = item.title
        notes = item.notes
        locationText = item.locationText
        dueAt = item.dueAt
        hasExplicitTime = item.hasExplicitTime
        remindAt = item.remindAt
        statusRawValue = item.status.rawValue
        lastActionByUserID = item.lastActionByUserID
        lastActionAt = item.lastActionAt
        updatedAt = item.updatedAt
        completedAt = item.repeatRule == nil ? item.completedAt : nil
        completedByUserID = item.completedByUserID
        sortOrder = item.sortOrder
        isPinned = item.isPinned
        isDraft = item.isDraft
        isArchived = item.isArchived
        archivedAt = item.archivedAt
        repeatRuleData = Self.encode(item.repeatRule)
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ data: Data?, defaultValue: T) -> T {
        guard let data, let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return defaultValue
        }
        return decoded
    }
}
