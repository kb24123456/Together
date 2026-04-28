import Foundation
import Testing
@testable import Together

@Suite("SupabaseSoloRemoteGateway DTOs")
@MainActor
struct SupabaseSoloRemoteGatewayDTOTests {
    @Test("single space insert uses auth uid and single type")
    func singleSpaceInsertUsesAuthUID() {
        let userID = UUID()
        let dto = SoloSpaceUpsertDTO.newSingle(ownerUserID: userID, displayName: "我的空间")

        #expect(dto.ownerUserID == userID)
        #expect(dto.type == "single")
        #expect(dto.status == "active")
        #expect(dto.displayName == "我的空间")
    }

    @Test("single space insert encodes snake case keys")
    func singleSpaceInsertEncodesSnakeCaseKeys() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let now = Date(timeIntervalSince1970: 1_000)
        let dto = SoloSpaceUpsertDTO.newSingle(ownerUserID: userID, displayName: "我的空间", now: now)

        let payload = try encodedJSONObject(dto)

        #expect(payload["owner_user_id"] as? String == userID.uuidString)
        #expect(payload["display_name"] as? String == "我的空间")
        #expect(payload["updated_at"] != nil)
        #expect(payload["ownerUserID"] == nil)
        #expect(payload["displayName"] == nil)
        #expect(payload["updatedAt"] == nil)
    }

    @Test("device installation upsert uses platform and user id")
    func deviceInstallationUsesPlatformAndUserID() {
        let userID = UUID()
        let installationID = UUID()
        let dto = DeviceInstallationUpsertDTO(
            userID: userID,
            installationID: installationID,
            platform: .iphone,
            deviceName: "iPhone",
            appVersion: "1.0",
            buildNumber: "13"
        )

        #expect(dto.userID == userID)
        #expect(dto.installationID == installationID)
        #expect(dto.platform == "iphone")
        #expect(dto.deviceName == "iPhone")
    }

    @Test("device installation upsert encodes snake case keys")
    func deviceInstallationEncodesSnakeCaseKeys() throws {
        let userID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let installationID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let dto = DeviceInstallationUpsertDTO(
            userID: userID,
            installationID: installationID,
            platform: .iphone,
            deviceName: "iPhone",
            appVersion: "1.0",
            buildNumber: "13",
            now: Date(timeIntervalSince1970: 2_000)
        )

        let payload = try encodedJSONObject(dto)

        #expect(payload["user_id"] as? String == userID.uuidString)
        #expect(payload["installation_id"] as? String == installationID.uuidString)
        #expect(payload["device_name"] as? String == "iPhone")
        #expect(payload["app_version"] as? String == "1.0")
        #expect(payload["build_number"] as? String == "13")
        #expect(payload["is_active"] as? Bool == true)
        #expect(payload["last_seen_at"] != nil)
        #expect(payload["userID"] == nil)
        #expect(payload["installationID"] == nil)
        #expect(payload["deviceName"] == nil)
    }

    @Test("ensure single space rpc params encode snake case argument names")
    func ensureSingleSpaceRPCParamsEncodeSnakeCaseArgumentNames() throws {
        let userID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let dto = EnsureSingleSpaceRPCParams(userID: userID, displayName: "我的空间")

        let payload = try encodedJSONObject(dto)

        #expect(payload["p_user_id"] as? String == userID.uuidString)
        #expect(payload["p_display_name"] as? String == "我的空间")
        #expect(payload["userID"] == nil)
        #expect(payload["displayName"] == nil)
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
