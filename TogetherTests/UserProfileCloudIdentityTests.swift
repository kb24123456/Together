import Foundation
import Testing
@testable import Together

@Suite("User profile cloud identity")
struct UserProfileCloudIdentityTests {

    @Test("Cloud profile DTO uses Supabase auth uid, not local user id")
    func dtoUsesSupabaseAuthUID() {
        let localUserID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let supabaseUserID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let user = User(
            id: localUserID,
            appleUserID: "apple-user",
            displayName: "Alice",
            avatarSystemName: "person.crop.circle",
            avatarPhotoFileName: nil,
            avatarAssetID: "asset-1",
            avatarVersion: 7,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: false,
                calendarReminderEnabled: false,
                futureCollaborationInviteEnabled: true
            )
        )

        let dto = AppContext.makeCloudUserProfileDTO(
            from: user,
            supabaseUserID: supabaseUserID,
            avatarURLString: "https://example.test/avatar.jpg"
        )

        #expect(dto.userID == supabaseUserID)
        #expect(dto.userID != localUserID)
        #expect(dto.displayName == "Alice")
        #expect(dto.avatarURL == "https://example.test/avatar.jpg")
        #expect(dto.avatarVersion == 7)
    }

    @Test("Cloud profile watermark is keyed by Supabase auth uid")
    func watermarkUsesSupabaseAuthUID() {
        let supabaseUserID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let key = AppContext.userProfileCloudWatermarkKey(supabaseUserID: supabaseUserID)

        #expect(key == "together.userProfile.lastSyncedAvatarVersion.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }
}
