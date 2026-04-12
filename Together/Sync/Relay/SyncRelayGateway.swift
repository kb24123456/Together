import CloudKit
import CryptoKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncRelayGateway")

/// Posts and receives encrypted SyncRelay records via CloudKit public database.
///
/// Each pair space has its own SyncRelayGateway instance. The gateway handles:
/// - Posting local changes as encrypted relay records
/// - Fetching new relay records from the partner
/// - Sequence number tracking for ordered, gap-free delivery
///
/// ## Phase 2 implementation — stubbed methods are marked for Phase 3 activation.
actor SyncRelayGateway {
    static let recordType = "SyncRelay"

    private let container: CKContainer
    private let pairSpaceID: UUID
    private let myUserID: UUID
    private let encryptionKey: SymmetricKey
    private let healthMonitor: SyncHealthMonitor

    /// Monotonically increasing per-sender, per-space sequence number.
    private var nextSequence: Int64

    init(
        container: CKContainer,
        pairSpaceID: UUID,
        myUserID: UUID,
        encryptionKey: SymmetricKey,
        healthMonitor: SyncHealthMonitor,
        lastSequence: Int64 = 0
    ) {
        self.container = container
        self.pairSpaceID = pairSpaceID
        self.myUserID = myUserID
        self.encryptionKey = encryptionKey
        self.healthMonitor = healthMonitor
        self.nextSequence = lastSequence + 1
    }

    // MARK: - Post Relay

    /// Posts a batch of change entries as an encrypted relay record to the public DB.
    /// Returns the sequence number used for persistence.
    @discardableResult
    func postRelay(changes: [ChangeEntry]) async throws -> Int64 {
        guard !changes.isEmpty else { return nextSequence - 1 }

        let payload = try JSONEncoder().encode(changes)
        let encrypted = try RelayEncryption.encrypt(payload, key: encryptionKey)
        let base64Payload = encrypted.base64EncodedString()

        let seq = nextSequence
        let recordName = "relay-\(pairSpaceID.uuidString)-\(myUserID.uuidString)-\(seq)"
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        record["senderUserID"] = myUserID.uuidString as CKRecordValue
        record["pairSpaceID"] = pairSpaceID.uuidString as CKRecordValue
        record["sequenceNumber"] = seq as CKRecordValue
        record["encryptedPayload"] = base64Payload as CKRecordValue
        record["timestamp"] = Date.now as CKRecordValue

        try await container.publicCloudDatabase.save(record)

        nextSequence = seq + 1

        healthMonitor.updateRelay(pairSpaceID) { $0.lastRelayPosted = .now }

        logger.info("[Relay] ✅ Posted relay seq=\(seq) with \(changes.count) changes for space \(self.pairSpaceID.uuidString.prefix(8))")

        return seq
    }

    // MARK: - Fetch Relays

    /// Fetches new relay records from the partner since the given sequence number.
    func fetchNewRelays(since lastSequence: Int64) async throws -> [RelayMessage] {
        let predicate = NSPredicate(
            format: "pairSpaceID == %@ AND senderUserID != %@ AND sequenceNumber > %lld",
            pairSpaceID.uuidString as NSString,
            myUserID.uuidString as NSString,
            lastSequence
        )

        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]

        let (results, _) = try await container.publicCloudDatabase.records(
            matching: query,
            inZoneWith: nil,
            resultsLimit: 100
        )

        var messages: [RelayMessage] = []
        for (_, result) in results {
            guard let record = try? result.get() else { continue }
            if let message = try? decryptRelay(record) {
                messages.append(message)
            }
        }

        if !messages.isEmpty {
            healthMonitor.updateRelay(pairSpaceID) { $0.lastRelayReceived = .now }
            logger.info("[Relay] Fetched \(messages.count) new relays for space \(self.pairSpaceID.uuidString.prefix(8))")
        }

        return messages
    }

    // MARK: - Cleanup

    /// Deletes relay records older than the specified age.
    func cleanupOldRelays(olderThan age: TimeInterval = 7 * 24 * 3600) async throws {
        let cutoff = Date.now.addingTimeInterval(-age)
        let predicate = NSPredicate(
            format: "pairSpaceID == %@ AND timestamp < %@",
            pairSpaceID.uuidString as NSString,
            cutoff as NSDate
        )

        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        let (results, _) = try await container.publicCloudDatabase.records(
            matching: query,
            inZoneWith: nil,
            resultsLimit: CKQueryOperation.maximumResults
        )

        let recordIDs = results.compactMap { (id, _) in id }
        guard !recordIDs.isEmpty else { return }

        _ = try await container.publicCloudDatabase.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .allKeys,
            atomically: false
        )

        logger.info("[Relay] 🧹 Cleaned up \(recordIDs.count) old relay records")
    }

    // MARK: - Decrypt

    private func decryptRelay(_ record: CKRecord) throws -> RelayMessage {
        guard
            let senderIDString = record["senderUserID"] as? String,
            let senderID = UUID(uuidString: senderIDString),
            let base64Payload = record["encryptedPayload"] as? String,
            let sequenceNumber = record["sequenceNumber"] as? Int64,
            let timestamp = record["timestamp"] as? Date
        else {
            throw RelayEncryptionError.invalidInput
        }

        let jsonString = try RelayEncryption.decryptFromBase64(base64Payload, key: encryptionKey)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw RelayEncryptionError.invalidDecryptedData
        }

        let changes = try JSONDecoder().decode([ChangeEntry].self, from: jsonData)

        return RelayMessage(
            senderUserID: senderID,
            pairSpaceID: pairSpaceID,
            sequenceNumber: sequenceNumber,
            changes: changes,
            timestamp: timestamp
        )
    }
}
