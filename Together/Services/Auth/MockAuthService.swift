import Foundation

struct MockAuthService: AuthServiceProtocol {
    func currentSession() async -> AuthSession {
        AuthSession(state: .signedIn, user: MockDataFactory.makeCurrentUser())
    }

    func signInWithApple() async throws -> AuthSession {
        AuthSession(state: .signedIn, user: MockDataFactory.makeCurrentUser())
    }

    func signOut() async {}
}
