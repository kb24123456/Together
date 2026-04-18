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
}
