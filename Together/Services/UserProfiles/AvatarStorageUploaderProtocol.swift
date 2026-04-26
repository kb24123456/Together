import Foundation

protocol AvatarStorageUploaderProtocol: Sendable {
    /// Uploads JPEG bytes to avatars/{spaceID}/{userID}/{version}.jpg
    /// and returns a signed URL valid for ~1 year.
    func uploadAvatar(
        bytes: Data,
        spaceID: UUID,
        userID: UUID,
        version: Int
    ) async throws -> URL

    /// Uploads JPEG bytes to avatars/users/{userID}/{version}.jpg (user-scoped,
    /// not bound to any space) and returns a signed URL valid for ~1 year.
    /// Used by user_profiles writes so reinstall + SIWA can recover the avatar
    /// even if the user has never paired.
    func uploadAvatarUserScoped(
        bytes: Data,
        userID: UUID,
        version: Int
    ) async throws -> URL

    /// GETs the given signed URL and returns the JPEG bytes.
    func downloadAvatar(from url: URL) async throws -> Data
}

enum AvatarStorageError: Error {
    case downloadFailed(status: Int)
    case missingResponse
}
