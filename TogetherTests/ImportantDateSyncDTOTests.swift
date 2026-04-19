import Testing
import Foundation
@testable import Together

@Suite("ImportantDateDTO serialization")
struct ImportantDateSyncDTOTests {

    @Test("DTO encodes snake_case keys correctly")
    func encodesSnakeCase() throws {
        let dto = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "birthday", title: "Test birthday",
            dateValue: Date(timeIntervalSince1970: 0),
            isRecurring: true, recurrenceRule: "solar_annual",
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "gift.fill", memberUserId: UUID(),
            isPresetHoliday: false, presetHolidayId: nil,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["space_id"] != nil)
        #expect(json?["creator_id"] != nil)
        #expect(json?["date_value"] != nil)
        #expect(json?["notify_days_before"] as? Int == 7)
        #expect(json?["recurrence_rule"] as? String == "solar_annual")
    }

    @Test("DTO round-trips through encode/decode")
    func roundTrip() throws {
        let original = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "anniversary", title: "在一起纪念日",
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            isRecurring: true, recurrenceRule: "solar_annual",
            notifyDaysBefore: 15, notifyOnDay: true,
            icon: "heart.fill", memberUserId: nil,
            isPresetHoliday: false, presetHolidayId: nil,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportantDateDTO.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.notifyDaysBefore == 15)
        #expect(decoded.recurrenceRule == "solar_annual")
    }

    @Test("preset holiday encodes flag + id")
    func presetHoliday() throws {
        let dto = ImportantDateDTO(
            id: UUID(), spaceId: UUID(), creatorId: UUID(),
            kind: "holiday", title: "七夕",
            dateValue: .now,
            isRecurring: true, recurrenceRule: "lunar_annual",
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "sparkles", memberUserId: nil,
            isPresetHoliday: true, presetHolidayId: "qixi",
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["is_preset_holiday"] as? Bool == true)
        #expect(json?["preset_holiday_id"] as? String == "qixi")
    }
}
