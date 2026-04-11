import AuthenticationServices
import Foundation
import SwiftData

enum AppleAuthError: LocalizedError {
    case credentialNotAppleID
    case presentationFailed
    case credentialRevoked
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .credentialNotAppleID:
            return "未获取到 Apple ID 凭证。"
        case .presentationFailed:
            return "Apple 登录弹窗展示失败。"
        case .credentialRevoked:
            return "Apple ID 授权已被撤销，请重新登录。"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

final class AppleAuthService: AuthServiceProtocol, @unchecked Sendable {
    private static let appleUserIDKey = "appleUserID"
    private static let displayNameKey = "appleDisplayName"

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func currentSession() async -> AuthSession {
        guard let appleUserID = KeychainHelper.readString(key: Self.appleUserIDKey) else {
            return AuthSession(state: .signedOut, user: nil)
        }

        let credentialState = await checkCredentialState(appleUserID: appleUserID)

        guard credentialState == .authorized else {
            KeychainHelper.delete(key: Self.appleUserIDKey)
            KeychainHelper.delete(key: Self.displayNameKey)
            return AuthSession(state: .signedOut, user: nil)
        }

        let user = await loadOrCreateUser(appleUserID: appleUserID, fullName: nil)
        return AuthSession(state: .signedIn, user: user)
    }

    func signInWithApple() async throws -> AuthSession {
        let credential = try await performAppleSignIn()

        guard let appleIDCredential = credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.credentialNotAppleID
        }

        let appleUserID = appleIDCredential.user

        KeychainHelper.save(key: Self.appleUserIDKey, string: appleUserID)

        // Apple only provides fullName on the very first authorization.
        // Capture and persist it immediately.
        var fullName: String?
        if let nameComponents = appleIDCredential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty == false {
                fullName = name
                KeychainHelper.save(key: Self.displayNameKey, string: name)
            }
        }

        let user = await loadOrCreateUser(appleUserID: appleUserID, fullName: fullName)
        return AuthSession(state: .signedIn, user: user)
    }

    func signOut() async {
        KeychainHelper.delete(key: Self.appleUserIDKey)
        KeychainHelper.delete(key: Self.displayNameKey)
    }

    // MARK: - Private

    private func performAppleSignIn() async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let delegate = SignInDelegate(continuation: continuation)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate

            // Retain delegate until callback fires
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            controller.performRequests()
        }
    }

    private func checkCredentialState(appleUserID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    @MainActor
    private func loadOrCreateUser(appleUserID: String, fullName: String?) -> User {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<PersistentUserProfile>()
        let allProfiles = (try? context.fetch(descriptor)) ?? []

        // Try to find existing profile — match by checking stored appleUserID in Keychain
        // Since PersistentUserProfile doesn't have an appleUserID field,
        // we look for the first profile (single-user app for now)
        if let existingProfile = allProfiles.first {
            let now = Date.now
            var user = User(
                id: existingProfile.userID,
                appleUserID: appleUserID,
                displayName: existingProfile.displayName,
                avatarSystemName: existingProfile.avatarSystemName,
                avatarPhotoFileName: existingProfile.avatarPhotoFileName,
                createdAt: now,
                updatedAt: existingProfile.updatedAt,
                preferences: NotificationSettings(
                    taskReminderEnabled: existingProfile.taskReminderEnabled,
                    dailySummaryEnabled: existingProfile.dailySummaryEnabled,
                    calendarReminderEnabled: existingProfile.calendarReminderEnabled,
                    futureCollaborationInviteEnabled: existingProfile.futureCollaborationInviteEnabled,
                    taskUrgencyWindowMinutes: existingProfile.taskUrgencyWindowMinutes,
                    defaultSnoozeMinutes: existingProfile.defaultSnoozeMinutes,
                    quickTimePresetMinutes: existingProfile.quickTimePresetMinutes,
                    completedTaskAutoArchiveEnabled: existingProfile.completedTaskAutoArchiveEnabled,
                    completedTaskAutoArchiveDays: existingProfile.completedTaskAutoArchiveDays
                )
            )
            // Update display name from Apple if this is first sign-in and we got a name
            if let fullName, existingProfile.displayName.isEmpty || existingProfile.displayName == "我" {
                user.displayName = fullName
                existingProfile.displayName = fullName
                try? context.save()
            }
            return user
        }

        // Create new user on first sign-in
        let cachedName = KeychainHelper.readString(key: Self.displayNameKey)
        let displayName = fullName ?? cachedName ?? "我"
        let now = Date.now
        let user = User(
            id: UUID(),
            appleUserID: appleUserID,
            displayName: displayName,
            createdAt: now,
            updatedAt: now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: false,
                calendarReminderEnabled: false,
                futureCollaborationInviteEnabled: true
            )
        )

        let profile = PersistentUserProfile(user: user)
        context.insert(profile)
        try? context.save()

        return user
    }
}

// MARK: - ASAuthorizationController Delegate

private final class SignInDelegate: NSObject, ASAuthorizationControllerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<ASAuthorizationCredential, Error>?

    init(continuation: CheckedContinuation<ASAuthorizationCredential, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization.credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: AppleAuthError.unknown(error))
        continuation = nil
    }
}
