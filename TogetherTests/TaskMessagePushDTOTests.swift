import Foundation
import Testing
@testable import Together

@MainActor
struct TaskMessagePushDTOTests {
    @Test func encode_producesSnakeCaseKeys() throws {
        let dto = TaskMessagePushDTO(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            taskId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            senderId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            type: "nudge",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"id\":\"11111111-1111-1111-1111-111111111111\""))
        #expect(json.contains("\"task_id\":\"22222222-2222-2222-2222-222222222222\""))
        #expect(json.contains("\"sender_id\":\"33333333-3333-3333-3333-333333333333\""))
        #expect(json.contains("\"type\":\"nudge\""))
        #expect(json.contains("\"created_at\":"))
    }
}
