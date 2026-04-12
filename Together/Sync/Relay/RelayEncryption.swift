import CryptoKit
import Foundation

/// Handles encryption/decryption of SyncRelay payloads using ChaChaPoly.
///
/// The symmetric key is derived from the pair space identity (pairSpaceID + inviterID + responderID)
/// using HKDF, so both partners can independently compute the same key without key exchange.
enum RelayEncryption {

    // MARK: - Key Derivation

    /// Derives a shared symmetric key from the pair identifiers.
    ///
    /// Both partners can compute this independently since they both know
    /// the pairSpaceID, inviterID, and responderID after pairing completes.
    static func deriveKey(pairSpaceID: UUID, inviterID: UUID, responderID: UUID) -> SymmetricKey {
        let material = "\(pairSpaceID.uuidString)-\(inviterID.uuidString)-\(responderID.uuidString)"
        let inputKey = SymmetricKey(data: material.data(using: .utf8)!)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            info: "Together.SyncRelay.v1".data(using: .utf8)!,
            outputByteCount: 32
        )
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypts a payload (typically JSON data) using ChaChaPoly.
    /// Returns the combined sealed box (nonce + ciphertext + tag) as Data.
    static func encrypt(_ payload: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(payload, using: key)
        return sealedBox.combined
    }

    /// Decrypts a ChaChaPoly sealed payload.
    static func decrypt(_ data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    // MARK: - Convenience (String ↔ Data)

    /// Encrypts JSON string, returns base64-encoded ciphertext.
    static func encryptToBase64(_ jsonString: String, key: SymmetricKey) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw RelayEncryptionError.invalidInput
        }
        let encrypted = try encrypt(data, key: key)
        return encrypted.base64EncodedString()
    }

    /// Decrypts base64-encoded ciphertext, returns JSON string.
    static func decryptFromBase64(_ base64String: String, key: SymmetricKey) throws -> String {
        guard let data = Data(base64Encoded: base64String) else {
            throw RelayEncryptionError.invalidBase64
        }
        let decrypted = try decrypt(data, key: key)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw RelayEncryptionError.invalidDecryptedData
        }
        return string
    }
}

// MARK: - Errors

enum RelayEncryptionError: Error, LocalizedError {
    case invalidInput
    case invalidBase64
    case invalidDecryptedData

    var errorDescription: String? {
        switch self {
        case .invalidInput: "Invalid input data for encryption"
        case .invalidBase64: "Invalid base64 string for decryption"
        case .invalidDecryptedData: "Decrypted data is not valid UTF-8"
        }
    }
}
