import Foundation

protocol AuthServiceProtocol: Sendable {
    func currentSession() async -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signOut() async
}
