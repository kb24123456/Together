import XCTest
@testable import Together

final class ImportantDateDTOPinFieldTests: XCTestCase {
    func test_decode_with_pinTrue_setsIsPinnedToTodayTrue() throws {
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "space_id":"\(UUID().uuidString)",
          "creator_id":"\(UUID().uuidString)",
          "kind":"anniversary","title":"在一起",
          "date_value":"2024-06-01T00:00:00Z",
          "is_recurring":true,"recurrence_rule":"solar_annual",
          "notify_days_before":7,"notify_on_day":true,
          "icon":null,"member_user_id":null,
          "is_preset_holiday":false,"preset_holiday_id":null,
          "created_at":"2024-06-01T00:00:00Z","updated_at":"2024-06-01T00:00:00Z",
          "is_deleted":false,"deleted_at":null,
          "is_pinned_to_today":true
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(ImportantDateDTO.self, from: json)
        XCTAssertTrue(dto.isPinnedToToday)
    }

    func test_decode_without_pinField_defaultsToFalse() throws {
        // Pre-migration row (no is_pinned_to_today key) must still decode.
        let json = """
        {
          "id":"\(UUID().uuidString)",
          "space_id":"\(UUID().uuidString)",
          "creator_id":"\(UUID().uuidString)",
          "kind":"anniversary","title":"在一起",
          "date_value":"2024-06-01T00:00:00Z",
          "is_recurring":true,"recurrence_rule":"solar_annual",
          "notify_days_before":7,"notify_on_day":true,
          "icon":null,"member_user_id":null,
          "is_preset_holiday":false,"preset_holiday_id":null,
          "created_at":"2024-06-01T00:00:00Z","updated_at":"2024-06-01T00:00:00Z",
          "is_deleted":false,"deleted_at":null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(ImportantDateDTO.self, from: json)
        XCTAssertFalse(dto.isPinnedToToday)
    }
}
