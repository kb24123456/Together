import Foundation
import LocalAuthentication

protocol BiometricAuthServiceProtocol: Sendable {
    func canEvaluateBiometrics() -> Bool
    func biometricTypeName() -> String
    func authenticate(reason: String) async throws -> Bool
}

struct BiometricAuthService: BiometricAuthServiceProtocol {
    func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func biometricTypeName() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "密码"
        }
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "生物识别"
        }
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用密码"
        // Uses deviceOwnerAuthentication to automatically fall back to passcode
        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
    }
}
