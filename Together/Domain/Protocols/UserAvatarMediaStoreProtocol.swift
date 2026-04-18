import Foundation

protocol UserAvatarMediaStoreProtocol: Sendable {
    nonisolated func canonicalFileName(for userID: UUID) -> String
    nonisolated func cacheFileName(for assetID: String) -> String
    nonisolated func partnerCacheFileName(for assetID: String, version: Int) -> String
    nonisolated func avatarData(named fileName: String) throws -> Data
    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws
    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws
    nonisolated func removeAvatar(named fileName: String) throws
    nonisolated func fileExists(named fileName: String) -> Bool
}
