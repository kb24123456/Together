import CryptoKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "RelayKeyManager")

/// Manages symmetric encryption keys for SyncRelay payloads.
///
/// Keys are derived from the pair space identity (pairSpaceID + inviterID + responderID)
/// using HKDF, then cached in Keychain so both partners can independently compute
/// the same key without key exchange.
enum RelayKeyManager {

    private static let keychainPrefix = "relay-encryption-key-"

    // MARK: - Key Lifecycle

    /// Derives and stores the relay encryption key for a pair space.
    /// Call this when pairing completes and both member IDs are known.
    @discardableResult
    static func deriveAndStore(
        pairSpaceID: UUID,
        inviterID: UUID,
        responderID: UUID
    ) -> SymmetricKey {
        let key = RelayEncryption.deriveKey(
            pairSpaceID: pairSpaceID,
            inviterID: inviterID,
            responderID: responderID
        )

        // Serialize key to raw bytes and store in Keychain
        let keyData = key.withUnsafeBytes { Data($0) }
        let keychainKey = keychainKey(for: pairSpaceID)

        if KeychainHelper.save(key: keychainKey, data: keyData) {
            logger.info("[RelayKey] ✅ Stored encryption key for space \(pairSpaceID.uuidString.prefix(8))")
        } else {
            logger.error("[RelayKey] ❌ Failed to store encryption key for space \(pairSpaceID.uuidString.prefix(8))")
        }

        return key
    }

    /// Loads the relay encryption key from Keychain.
    /// Returns nil if no key is stored (pairing incomplete or key was deleted).
    static func loadKey(for pairSpaceID: UUID) -> SymmetricKey? {
        let keychainKey = keychainKey(for: pairSpaceID)
        guard let keyData = KeychainHelper.read(key: keychainKey) else {
            return nil
        }
        return SymmetricKey(data: keyData)
    }

    /// Loads existing key or derives a new one if not found.
    static func loadOrDerive(
        pairSpaceID: UUID,
        inviterID: UUID,
        responderID: UUID
    ) -> SymmetricKey {
        if let existing = loadKey(for: pairSpaceID) {
            return existing
        }
        return deriveAndStore(
            pairSpaceID: pairSpaceID,
            inviterID: inviterID,
            responderID: responderID
        )
    }

    /// Removes the encryption key for a pair space (e.g., on unbind).
    static func deleteKey(for pairSpaceID: UUID) {
        let keychainKey = keychainKey(for: pairSpaceID)
        KeychainHelper.delete(key: keychainKey)
        logger.info("[RelayKey] 🗑️ Deleted encryption key for space \(pairSpaceID.uuidString.prefix(8))")
    }

    // MARK: - Helpers

    private static func keychainKey(for pairSpaceID: UUID) -> String {
        "\(keychainPrefix)\(pairSpaceID.uuidString)"
    }
}
