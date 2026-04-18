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

    /// GETs the given signed URL and returns the JPEG bytes.
    func downloadAvatar(from url: URL) async throws -> Data
}

enum AvatarStorageError: Error {
    case downloadFailed(status: Int)
    case missingResponse
}
