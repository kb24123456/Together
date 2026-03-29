import Foundation
import SwiftData

actor LocalUserProfileRepository: UserProfileRepositoryProtocol {
    private let container: ModelContainer

    init(
        container: ModelContainer
    ) {
        self.container = container
    }

    func mergedUser(_ user: User?) async -> User? {
        guard let user else { return nil }
        let context = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        guard let record = try? context.fetch(descriptor).first else {
            return user
        }

        var mergedUser = record.apply(to: user)
        if let fileName = mergedUser.avatarPhotoFileName, avatarFileExists(fileName) == false {
            mergedUser.avatarPhotoFileName = nil
        }
        return mergedUser
    }

    func saveProfile(
        for user: User,
        displayName: String,
        avatarUpdate: UserAvatarUpdate
    ) async throws -> User {
        let context = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        let sanitizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedUser = user
        updatedUser.displayName = sanitizedName
        updatedUser.updatedAt = .now

        switch avatarUpdate {
        case .preserveExisting:
            break
        case .removeCustomPhoto:
            if let existingFileName = updatedUser.avatarPhotoFileName {
                try? removeAvatarFile(named: existingFileName)
            }
            updatedUser.avatarPhotoFileName = nil
        case .replacePhoto(let data):
            let fileName = try writeAvatarFile(data: data, userID: user.id)
            if let existingFileName = updatedUser.avatarPhotoFileName, existingFileName != fileName {
                try? removeAvatarFile(named: existingFileName)
            }
            updatedUser.avatarPhotoFileName = fileName
        }

        if let existingRecord = try context.fetch(descriptor).first {
            existingRecord.update(from: updatedUser)
        } else {
            context.insert(PersistentUserProfile(user: updatedUser))
        }

        try context.save()
        return updatedUser
    }

    func savePreferences(
        for user: User,
        preferences: NotificationSettings
    ) async throws -> User {
        let context = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        var updatedUser = user
        updatedUser.preferences = preferences
        updatedUser.updatedAt = .now

        if let existingRecord = try context.fetch(descriptor).first {
            existingRecord.update(from: updatedUser)
        } else {
            context.insert(PersistentUserProfile(user: updatedUser))
        }

        try context.save()
        return updatedUser
    }

    private var avatarDirectoryURL: URL {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        let directory = applicationSupportDirectory
            .appending(path: "Together", directoryHint: .isDirectory)
            .appending(path: "Avatars", directoryHint: .isDirectory)

        if fileManager.fileExists(atPath: directory.path) == false {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private func avatarFileURL(fileName: String) -> URL {
        avatarDirectoryURL.appending(path: fileName)
    }

    private func avatarFileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: avatarFileURL(fileName: fileName).path)
    }

    private func writeAvatarFile(data: Data, userID: UUID) throws -> String {
        let timestamp = Int(Date.now.timeIntervalSince1970 * 1_000)
        let fileName = "\(userID.uuidString.lowercased())-avatar-\(timestamp).jpg"
        let url = avatarFileURL(fileName: fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    private func removeAvatarFile(named fileName: String) throws {
        let fileManager = FileManager.default
        let url = avatarFileURL(fileName: fileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum UserAvatarStorage {
    static func fileURL(fileName: String) -> URL {
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
