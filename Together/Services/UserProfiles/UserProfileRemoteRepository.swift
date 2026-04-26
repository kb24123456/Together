import Foundation
import Supabase
import os

actor UserProfileRemoteRepository: UserProfileRemoteRepositoryProtocol {
    private let client: SupabaseClient
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "UserProfileRemote")
    private let table = "user_profiles"

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchOwn() async throws -> UserProfileDTO? {
        guard let session = try? await client.auth.session else { return nil }
        return try await fetchByUserID(session.user.id)
    }

    func fetchByUserID(_ userID: UUID) async throws -> UserProfileDTO? {
        // Use limit(1) instead of single() — single() throws PGRST116 on empty
        // result, which would force callers to distinguish "no row" from "real
        // error" by inspecting the thrown PostgrestError. limit(1) returns []
        // cleanly and lets the caller treat nil as "not found".
        let rows: [UserProfileDTO] = try await client
            .from(table)
            .select()
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func upsertOwn(_ dto: UserProfileDTO) async throws {
        // Re-encode `updated_at = nil` so the server-side trigger sets it.
        // Sending the local Date risks clock skew clobbering a more recent
        // remote write.
        let payload = UserProfileUpsertPayload(
            userID: dto.userID,
            displayName: dto.displayName,
            avatarURL: dto.avatarURL,
            avatarAssetID: dto.avatarAssetID,
            avatarSystemName: dto.avatarSystemName,
            avatarVersion: dto.avatarVersion
        )
        try await client
            .from(table)
            .upsert(payload, onConflict: "user_id")
            .execute()
        logger.info("upserted user_profile user_id=\(dto.userID.uuidString, privacy: .public) version=\(dto.avatarVersion)")
    }

    private struct UserProfileUpsertPayload: Encodable {
        let userID: UUID
        let displayName: String
        let avatarURL: String?
        let avatarAssetID: String?
        let avatarSystemName: String?
        let avatarVersion: Int

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case avatarAssetID = "avatar_asset_id"
            case avatarSystemName = "avatar_system_name"
            case avatarVersion = "avatar_version"
        }
    }
}
