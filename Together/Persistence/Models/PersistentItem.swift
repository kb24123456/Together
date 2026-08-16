import Foundation
import TogetherCore

nonisolated extension PersistentItem {
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
            isPinned: item.isUrgent,
            isDraft: item.isDraft,
            isArchived: item.isArchived,
            archivedAt: item.archivedAt,
            repeatRuleData: Self.encode(item.repeatRule)
        )
    }

    func domainModel(
        occurrenceCompletions: [ItemOccurrenceCompletion] = [],
        subtasks: [TaskSubtask] = [],
        isFollowed: Bool = false,
        followedAt: Date? = nil
    ) -> Item {
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
            subtasks: subtasks,
            sortOrder: sortOrder,
            isUrgent: isPinned,
            isDraft: isDraft,
            isArchived: isArchived,
            archivedAt: archivedAt,
            repeatRule: Self.decode(repeatRuleData, defaultValue: nil),
            isFollowed: isFollowed,
            followedAt: followedAt
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
        isPinned = item.isUrgent
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
