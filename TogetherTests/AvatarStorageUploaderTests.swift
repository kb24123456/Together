import Testing
import Foundation
@testable import Together

@Suite("AvatarStorageUploader")
struct AvatarStorageUploaderTests {

    @Test("avatarPath produces {space}/{user}/{version}.jpg with lowercased UUIDs")
    func pathFormat() {
        let spaceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let path = AvatarStorageUploader.avatarPath(spaceID: spaceID, userID: userID, version: 3)
        #expect(path == "11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/3.jpg")
    }

    @Test("avatarPath encodes different versions in filename")
    func pathVersions() {
        let spaceID = UUID()
        let userID = UUID()
        let v1 = AvatarStorageUploader.avatarPath(spaceID: spaceID, userID: userID, version: 1)
        let v99 = AvatarStorageUploader.avatarPath(spaceID: spaceID, userID: userID, version: 99)
        #expect(v1.hasSuffix("/1.jpg"))
        #expect(v99.hasSuffix("/99.jpg"))
    }

    @Test("userScopedAvatarPath produces users/{user}/{version}.jpg lowercased")
    func userScopedPathFormat() {
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let path = AvatarStorageUploader.userScopedAvatarPath(userID: userID, version: 5)
        #expect(path == "users/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/5.jpg")
    }

    @Test("userScopedAvatarPath encodes different versions in filename")
    func userScopedPathVersions() {
        let userID = UUID()
        let v0 = AvatarStorageUploader.userScopedAvatarPath(userID: userID, version: 0)
        let v42 = AvatarStorageUploader.userScopedAvatarPath(userID: userID, version: 42)
        #expect(v0.hasSuffix("/0.jpg"))
        #expect(v42.hasSuffix("/42.jpg"))
        #expect(v0.hasPrefix("users/"))
    }
}

@Suite("UserProfileDTO codable")
struct UserProfileDTOCodableTests {

    @Test("Encodes snake_case keys matching user_profiles schema")
    func encodesSnakeCaseKeys() throws {
        let dto = UserProfileDTO(
            userID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            displayName: "Alice",
            avatarURL: "https://example.test/a.jpg",
            avatarAssetID: "asset-1",
            avatarSystemName: nil,
            avatarVersion: 3,
            updatedAt: nil
        )
        let data = try JSONEncoder().encode(dto)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["user_id"] as? String == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(json["display_name"] as? String == "Alice")
        #expect(json["avatar_url"] as? String == "https://example.test/a.jpg")
        #expect(json["avatar_asset_id"] as? String == "asset-1")
        #expect(json["avatar_version"] as? Int == 3)
    }

    @Test("Decodes snake_case keys + handles nil optional fields")
    func decodesSnakeCaseKeys() throws {
        let userID = UUID()
        let json: [String: Any] = [
            "user_id": userID.uuidString,
            "display_name": "Bob",
            "avatar_url": NSNull(),
            "avatar_asset_id": NSNull(),
            "avatar_system_name": "person.crop.circle",
            "avatar_version": 0,
            "updated_at": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let dto = try JSONDecoder().decode(UserProfileDTO.self, from: data)

        #expect(dto.userID == userID)
        #expect(dto.displayName == "Bob")
        #expect(dto.avatarURL == nil)
        #expect(dto.avatarAssetID == nil)
        #expect(dto.avatarSystemName == "person.crop.circle")
        #expect(dto.avatarVersion == 0)
    }
}
