import Foundation

actor MockUserProfileRepository: UserProfileRepositoryProtocol {
    private var records: [UUID: User] = [:]

    func mergedUser(_ user: User?) async -> User? {
        guard let user else { return nil }
        return records[user.id] ?? user
    }

    func saveProfile(
        for user: User,
        displayName: String,
        avatarUpdate: UserAvatarUpdate
    ) async throws -> User {
        var updatedUser = user
        updatedUser.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedUser.updatedAt = .now

        switch avatarUpdate {
        case .preserveExisting:
            break
        case .removeCustomPhoto:
            updatedUser.avatarPhotoFileName = nil
            updatedUser.avatarAssetID = nil
            updatedUser.avatarVersion += 1
        case .replacePhoto:
            updatedUser.avatarPhotoFileName = "mock-avatar.jpg"
            updatedUser.avatarAssetID = "mock-avatar.jpg"
            updatedUser.avatarVersion += 1
        }

        records[user.id] = updatedUser
        return updatedUser
    }

    func savePreferences(
        for user: User,
        preferences: NotificationSettings
    ) async throws -> User {
        var updatedUser = records[user.id] ?? user
        updatedUser.preferences = preferences
        updatedUser.updatedAt = .now
        records[user.id] = updatedUser
        return updatedUser
    }
}
