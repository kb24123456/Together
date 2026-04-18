import Foundation
import Supabase
import os

final class AvatarStorageUploader: AvatarStorageUploaderProtocol, @unchecked Sendable {
    private let client: SupabaseClient
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AvatarStorageUploader")
    private let bucketID = "avatars"
    private let signedURLExpirySeconds: Int = 60 * 60 * 24 * 365  // 1 year

    init(client: SupabaseClient) {
        self.client = client
    }

    func uploadAvatar(
        bytes: Data,
        spaceID: UUID,
        userID: UUID,
        version: Int
    ) async throws -> URL {
        let path = Self.avatarPath(spaceID: spaceID, userID: userID, version: version)
        _ = try await client.storage
            .from(bucketID)
            .upload(
                path,
                data: bytes,
                options: FileOptions(
                    cacheControl: "31536000",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        let signed = try await client.storage
            .from(bucketID)
            .createSignedURL(path: path, expiresIn: signedURLExpirySeconds)
        logger.info("uploaded avatar path=\(path, privacy: .public) bytes=\(bytes.count)")
        return signed
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw AvatarStorageError.missingResponse
        }
        if http.statusCode >= 400 {
            throw AvatarStorageError.downloadFailed(status: http.statusCode)
        }
        return data
    }

    static func avatarPath(spaceID: UUID, userID: UUID, version: Int) -> String {
        "\(spaceID.uuidString.lowercased())/\(userID.uuidString.lowercased())/\(version).jpg"
    }
}
