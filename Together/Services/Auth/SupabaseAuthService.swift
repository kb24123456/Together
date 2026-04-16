import Foundation
import AuthenticationServices
import CryptoKit
import Supabase

/// Supabase 认证服务
/// 负责 Sign in with Apple → Supabase JWT 的转换
/// 以及 session 恢复和登出
actor SupabaseAuthService {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared

    /// 当前 Supabase 用户 ID（auth.uid()）
    var currentUserID: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    /// 是否已登录 Supabase
    var isSignedIn: Bool {
        get async {
            (try? await client.auth.session) != nil
        }
    }

    /// 使用 Apple ID Token 登录 Supabase
    /// - Parameters:
    ///   - idToken: ASAuthorizationAppleIDCredential.identityToken 的字符串形式
    ///   - nonce: 原始 nonce（未 hash 的）
    /// - Returns: Supabase User ID
    @discardableResult
    func signInWithApple(idToken: String, nonce: String?) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return session.user.id
    }

    /// 登出 Supabase
    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// 尝试恢复已有 session（App 启动时调用）
    /// - Returns: 如果 session 有效返回用户 ID，否则 nil
    func restoreSession() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }

    // MARK: - Nonce 工具方法

    /// 生成随机 nonce 字符串（用于 Apple Sign In 的防重放攻击）
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("无法生成安全随机字节: \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    /// 将 nonce 做 SHA256 hash（Apple Sign In 请求需要 hash 后的 nonce）
    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
