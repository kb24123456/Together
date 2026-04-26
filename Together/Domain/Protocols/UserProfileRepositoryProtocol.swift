import Foundation

enum UserAvatarUpdate: Sendable {
    case preserveExisting
    case replacePhoto(Data)
    case removeCustomPhoto
}

protocol UserProfileRepositoryProtocol: Sendable {
    func mergedUser(_ user: User?) async -> User?
    func saveProfile(
        for user: User,
        displayName: String,
        avatarUpdate: UserAvatarUpdate
    ) async throws -> User
    func savePreferences(
        for user: User,
        preferences: NotificationSettings
    ) async throws -> User

    /// Writes a profile snapshot received from cloud (`user_profiles` row) into
    /// local SwiftData + the avatar file cache. Used by reinstall + SIWA recovery.
    /// Does NOT bump `avatarVersion` — preserves the cloud value verbatim so the
    /// next outgoing sync doesn't trigger a redundant upload.
    func hydrateFromRemote(
        for user: User,
        displayName: String,
        avatarBytes: Data?,
        avatarAssetID: String?,
        avatarSystemName: String?,
        avatarVersion: Int
    ) async throws -> User
}
