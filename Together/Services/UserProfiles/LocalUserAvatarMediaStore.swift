import Foundation

struct LocalUserAvatarMediaStore: UserAvatarMediaStoreProtocol {
    nonisolated init() {}

    nonisolated func canonicalFileName(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())-avatar.jpg"
    }

    nonisolated func cacheFileName(for assetID: String) -> String {
        UserAvatarStorage.fileName(forAssetID: assetID)
    }

    nonisolated func partnerCacheFileName(for assetID: String, version: Int) -> String {
        UserAvatarStorage.partnerFileName(forAssetID: assetID, version: version)
    }

    nonisolated func avatarData(named fileName: String) throws -> Data {
        try Data(contentsOf: UserAvatarStorage.fileURL(fileName: fileName))
    }

    nonisolated func persistAvatarData(_ data: Data, fileName: String) throws {
        let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated func migrateAvatarIfNeeded(from sourceFileName: String, to destinationFileName: String) throws {
        guard sourceFileName != destinationFileName else { return }

        let sourceURL = UserAvatarStorage.fileURL(fileName: sourceFileName)
        let destinationURL = UserAvatarStorage.fileURL(fileName: destinationFileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { return }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    nonisolated func removeAvatar(named fileName: String) throws {
        let fileURL = UserAvatarStorage.fileURL(fileName: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    nonisolated func fileExists(named fileName: String) -> Bool {
        FileManager.default.fileExists(
            atPath: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
        )
    }
}

enum UserAvatarStorage {
    nonisolated static func fileName(forAssetID assetID: String) -> String {
        if assetID.contains(".") {
            return assetID
        }
        return "asset-\(assetID.lowercased()).jpg"
    }

    /// Filename for partner-synced avatars that includes the version so each
    /// remote update lands at a distinct on-disk path (prevents SwiftUI /
    /// UIImage cache from serving stale bytes).
    nonisolated static func partnerFileName(forAssetID assetID: String, version: Int) -> String {
        "asset-\(assetID.lowercased())-v\(version).jpg"
    }

    nonisolated static func fileURL(fileName: String) -> URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        return applicationSupportDirectory
            .appending(path: "Together", directoryHint: .isDirectory)
            .appending(path: "Avatars", directoryHint: .isDirectory)
            .appending(path: fileName)
    }
}
