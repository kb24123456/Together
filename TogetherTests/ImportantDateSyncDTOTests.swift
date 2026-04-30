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
            showsElapsedDays: true,
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
        #expect(json?["shows_elapsed_days"] as? Bool == true)
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
            showsElapsedDays: true,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportantDateDTO.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.notifyDaysBefore == 15)
        #expect(decoded.recurrenceRule == "solar_annual")
        #expect(decoded.showsElapsedDays == true)
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
            showsElapsedDays: false,
            createdAt: .now, updatedAt: .now,
            isDeleted: false, deletedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["is_preset_holiday"] as? Bool == true)
        #expect(json?["preset_holiday_id"] as? String == "qixi")
    }

    @Test("old JSON missing shows_elapsed_days defaults anniversary to true and custom to false")
    func decodesMissingElapsedDaysWithKindDefaults() throws {
        let anniversaryJSONString = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "space_id":"00000000-0000-0000-0000-000000000002",
          "creator_id":"00000000-0000-0000-0000-000000000003",
          "kind":"anniversary",
          "title":"我们在一起的日子",
          "date_value":761529600,
          "is_recurring":true,
          "recurrence_rule":"solar_annual",
          "notify_days_before":7,
          "notify_on_day":true,
          "icon":"heart.fill",
          "member_user_id":null,
          "is_preset_holiday":false,
          "preset_holiday_id":null,
          "created_at":761529600,
          "updated_at":761529600,
          "is_deleted":false,
          "deleted_at":null
        }
        """

        let anniversaryJSON = anniversaryJSONString.data(using: .utf8)!
        let customJSON = anniversaryJSONString
            .replacingOccurrences(of: "\"kind\":\"anniversary\"", with: "\"kind\":\"custom\"")
            .replacingOccurrences(of: "\"title\":\"我们在一起的日子\"", with: "\"title\":\"第一次旅行\"")
            .data(using: .utf8)!

        let decoder = JSONDecoder()
        let anniversary = try decoder.decode(ImportantDateDTO.self, from: anniversaryJSON)
        let custom = try decoder.decode(ImportantDateDTO.self, from: customJSON)

        #expect(anniversary.showsElapsedDays == true)
        #expect(custom.showsElapsedDays == false)
    }
}
