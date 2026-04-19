import Foundation
import SwiftData

@Model
final class PersistentImportantDate {
    @Attribute(.unique) var id: UUID
    var spaceID: UUID
    var creatorID: UUID
    var kindRawValue: String
    var memberUserID: UUID?
    var title: String
    var dateValue: Date
    var recurrenceRawValue: String
    var notifyDaysBefore: Int
    var notifyOnDay: Bool
    var icon: String?
    var isPresetHoliday: Bool
    var presetHolidayIDRawValue: String?
    var createdAt: Date
    var updatedAt: Date
    var isLocallyDeleted: Bool
    var deletedAt: Date?

    init(
        id: UUID,
        spaceID: UUID,
        creatorID: UUID,
        kindRawValue: String,
        memberUserID: UUID? = nil,
        title: String,
        dateValue: Date,
        recurrenceRawValue: String,
        notifyDaysBefore: Int = 7,
        notifyOnDay: Bool = true,
        icon: String? = nil,
        isPresetHoliday: Bool = false,
        presetHolidayIDRawValue: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isLocallyDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.kindRawValue = kindRawValue
        self.memberUserID = memberUserID
        self.title = title
        self.dateValue = dateValue
        self.recurrenceRawValue = recurrenceRawValue
        self.notifyDaysBefore = notifyDaysBefore
        self.notifyOnDay = notifyOnDay
        self.icon = icon
        self.isPresetHoliday = isPresetHoliday
        self.presetHolidayIDRawValue = presetHolidayIDRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocallyDeleted = isLocallyDeleted
        self.deletedAt = deletedAt
    }

    func domainModel() -> ImportantDate {
        let kind: ImportantDateKind
        switch kindRawValue {
        case "birthday":
            kind = .birthday(memberUserID: memberUserID ?? UUID())
        case "anniversary":
            kind = .anniversary
        case "holiday":
            kind = .holiday
        default:
            kind = .custom
        }
        return ImportantDate(
            id: id,
            spaceID: spaceID,
            creatorID: creatorID,
            kind: kind,
            title: title,
            dateValue: dateValue,
            recurrence: Recurrence(rawValue: recurrenceRawValue) ?? .none,
            notifyDaysBefore: notifyDaysBefore,
            notifyOnDay: notifyOnDay,
            icon: icon,
            presetHolidayID: presetHolidayIDRawValue.flatMap(PresetHolidayID.init(rawValue:)),
            updatedAt: updatedAt
        )
    }

    static func make(from event: ImportantDate) -> PersistentImportantDate {
        let (kindRaw, memberID): (String, UUID?) = {
            switch event.kind {
            case .birthday(let mID): return ("birthday", mID)
            case .anniversary: return ("anniversary", nil)
            case .holiday: return ("holiday", nil)
            case .custom: return ("custom", nil)
            }
        }()
        return PersistentImportantDate(
            id: event.id,
            spaceID: event.spaceID,
            creatorID: event.creatorID,
            kindRawValue: kindRaw,
            memberUserID: memberID,
            title: event.title,
            dateValue: event.dateValue,
            recurrenceRawValue: event.recurrence.rawValue,
            notifyDaysBefore: event.notifyDaysBefore,
            notifyOnDay: event.notifyOnDay,
            icon: event.icon,
            isPresetHoliday: event.presetHolidayID != nil,
            presetHolidayIDRawValue: event.presetHolidayID?.rawValue,
            updatedAt: event.updatedAt
        )
    }

    func apply(from event: ImportantDate) {
        let (kindRaw, memberID): (String, UUID?) = {
            switch event.kind {
            case .birthday(let mID): return ("birthday", mID)
            case .anniversary: return ("anniversary", nil)
            case .holiday: return ("holiday", nil)
            case .custom: return ("custom", nil)
            }
        }()
        self.spaceID = event.spaceID
        self.creatorID = event.creatorID
        self.kindRawValue = kindRaw
        self.memberUserID = memberID
        self.title = event.title
        self.dateValue = event.dateValue
        self.recurrenceRawValue = event.recurrence.rawValue
        self.notifyDaysBefore = event.notifyDaysBefore
        self.notifyOnDay = event.notifyOnDay
        self.icon = event.icon
        self.isPresetHoliday = event.presetHolidayID != nil
        self.presetHolidayIDRawValue = event.presetHolidayID?.rawValue
        self.updatedAt = event.updatedAt
    }
}
