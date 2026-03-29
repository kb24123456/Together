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
}
