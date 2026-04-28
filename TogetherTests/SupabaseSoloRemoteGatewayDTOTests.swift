import Foundation
import Testing
@testable import Together

@Suite("SupabaseSoloRemoteGateway DTOs")
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
}
