import Foundation

/// Cloud-side mirror of a user's profile (displayName + avatar).
///
/// Backed by the `user_profiles` table (migration 025). Wire format mirrors
/// the column names; PK is `user_id` = `auth.users.id`.
struct UserProfileDTO: Codable, Hashable, Sendable {
    let userID: UUID
    let displayName: String
    let avatarURL: String?
    let avatarAssetID: String?
    let avatarSystemName: String?
    let avatarVersion: Int
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case avatarAssetID = "avatar_asset_id"
        case avatarSystemName = "avatar_system_name"
        case avatarVersion = "avatar_version"
        case updatedAt = "updated_at"
    }
}

/// Reads/writes the user-scoped `user_profiles` row.
///
/// This is independent of `space_members` (which is space-scoped and remains
/// dual-written for 1.0 compatibility — see migration 025 header).
protocol UserProfileRemoteRepositoryProtocol: Sendable {
    /// Fetches the caller's own row (auth.uid()). Returns nil if not signed in
    /// to Supabase or the row hasn't been seeded yet.
    func fetchOwn() async throws -> UserProfileDTO?

    /// Fetches another user's row. RLS gates this on shared space membership.
    /// Returns nil when the row doesn't exist (e.g. partner is still on 1.0).
    func fetchByUserID(_ userID: UUID) async throws -> UserProfileDTO?

    /// Upserts the caller's own row. RLS rejects writes where
    /// `dto.userID != auth.uid()`.
    func upsertOwn(_ dto: UserProfileDTO) async throws
}
