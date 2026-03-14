import Foundation
import SwiftData

@Model
final class PersistentItem {
    @Attribute(.unique) var id: UUID
    var spaceID: UUID?
    var listID: UUID?
    var projectID: UUID?
    var creatorID: UUID
    var title: String
    var notes: String?
    var locationText: String?
    var executionRoleRawValue: String
    var priorityRawValue: String
    var dueAt: Date?
    var remindAt: Date?
    var statusRawValue: String
    var latestResponseData: Data?
    var responseHistoryData: Data
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var isPinned: Bool
    var isDraft: Bool
    var isArchived: Bool
    var archivedAt: Date?
    var repeatRuleData: Data?

    init(
        id: UUID,
        spaceID: UUID?,
        listID: UUID?,
        projectID: UUID?,
        creatorID: UUID,
        title: String,
        notes: String?,
        locationText: String?,
        executionRoleRawValue: String,
        priorityRawValue: String,
        dueAt: Date?,
        remindAt: Date?,
        statusRawValue: String,
        latestResponseData: Data?,
        responseHistoryData: Data,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        isPinned: Bool,
        isDraft: Bool,
        isArchived: Bool,
        archivedAt: Date?,
        repeatRuleData: Data?
    ) {
        self.id = id
        self.spaceID = spaceID
        self.listID = listID
        self.projectID = projectID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.locationText = locationText
        self.executionRoleRawValue = executionRoleRawValue
        self.priorityRawValue = priorityRawValue
        self.dueAt = dueAt
        self.remindAt = remindAt
        self.statusRawValue = statusRawValue
        self.latestResponseData = latestResponseData
        self.responseHistoryData = responseHistoryData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.isPinned = isPinned
        self.isDraft = isDraft
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.repeatRuleData = repeatRuleData
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
            executionRoleRawValue: item.executionRole.rawValue,
            priorityRawValue: item.priority.rawValue,
            dueAt: item.dueAt,
            remindAt: item.remindAt,
            statusRawValue: item.status.rawValue,
            latestResponseData: Self.encode(item.latestResponse),
            responseHistoryData: Self.encode(item.responseHistory),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            completedAt: item.completedAt,
            isPinned: item.isPinned,
            isDraft: item.isDraft,
            isArchived: item.isArchived,
            archivedAt: item.archivedAt,
            repeatRuleData: Self.encode(item.repeatRule)
        )
    }

    var domainModel: Item {
        Item(
            id: id,
            spaceID: spaceID,
            listID: listID,
            projectID: projectID,
            creatorID: creatorID,
            title: title,
            notes: notes,
            locationText: locationText,
            executionRole: ItemExecutionRole(rawValue: executionRoleRawValue) ?? .initiator,
            priority: ItemPriority(rawValue: priorityRawValue) ?? .normal,
            dueAt: dueAt,
            remindAt: remindAt,
            status: ItemStatus(rawValue: statusRawValue) ?? .pendingConfirmation,
            latestResponse: Self.decode(latestResponseData, defaultValue: nil),
            responseHistory: Self.decode(responseHistoryData, defaultValue: []),
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
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
        executionRoleRawValue = item.executionRole.rawValue
        priorityRawValue = item.priority.rawValue
        dueAt = item.dueAt
        remindAt = item.remindAt
        statusRawValue = item.status.rawValue
        latestResponseData = Self.encode(item.latestResponse)
        responseHistoryData = Self.encode(item.responseHistory)
        updatedAt = item.updatedAt
        completedAt = item.completedAt
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
