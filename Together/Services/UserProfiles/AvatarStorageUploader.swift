import Foundation
import os

final class AvatarStorageUploader: AvatarStorageUploaderProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AvatarStorageUploader")

    init() {}

    func uploadAvatar(
        bytes: Data,
        spaceID: UUID,
        userID: UUID,
        version: Int
    ) async throws -> URL {
        logger.debug("avatar upload skipped; bytes=\(bytes.count)")
        return URL(fileURLWithPath: Self.avatarPath(spaceID: spaceID, userID: userID, version: version))
    }

    func uploadAvatarUserScoped(
        bytes: Data,
        userID: UUID,
        version: Int
    ) async throws -> URL {
        logger.debug("user-scoped avatar upload skipped; bytes=\(bytes.count)")
        return URL(fileURLWithPath: Self.userScopedAvatarPath(userID: userID, version: version))
    }

    static func userScopedAvatarPath(userID: UUID, version: Int) -> String {
        "users/\(userID.uuidString.lowercased())/\(version).jpg"
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
