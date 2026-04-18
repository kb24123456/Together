import Testing
import Foundation
@testable import Together

@Suite("Avatar sync DTO serialization")
struct AvatarSyncDTOTests {

    @Test("SpaceMember push DTO round-trips avatar_asset_id + avatar_system_name")
    func pushDTOIncludesAvatarMetadata() throws {
        let dto = SpaceMemberUpdateDTO(
            displayName: "小狗",
            avatarUrl: "https://example.test/avatars/abc.jpg?sig=x",
            avatarAssetID: "asset-abc",
            avatarSystemName: nil,
            avatarVersion: 7
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["avatar_asset_id"] as? String == "asset-abc")
        #expect(json?["avatar_version"] as? Int == 7)
        #expect(json?["avatar_url"] as? String == "https://example.test/avatars/abc.jpg?sig=x")
        // avatar_system_name is nil - may serialize as null or be omitted,
        // either is acceptable.
        if let systemNameValue = json?["avatar_system_name"] {
            #expect(systemNameValue is NSNull)
        }
    }

    @Test("SpaceMember push DTO carries SF Symbol name when avatar_url is nil")
    func pushDTOWithSystemName() throws {
        let dto = SpaceMemberUpdateDTO(
            displayName: "小狗",
            avatarUrl: nil,
            avatarAssetID: nil,
            avatarSystemName: "person.circle.fill",
            avatarVersion: 3
        )
        let data = try JSONEncoder().encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["avatar_system_name"] as? String == "person.circle.fill")
        if let urlValue = json?["avatar_url"] {
            #expect(urlValue is NSNull)
        }
    }
}
