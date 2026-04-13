import CloudKit
import Foundation

// MARK: - Data model returned by the gateway

struct CloudInviteDetails: Sendable {
    let inviteCode: String
    let inviterUserUUID: UUID
    let inviterDisplayName: String
    let ownerRecordID: String?
    let pairSpaceID: UUID
    let sharedSpaceID: UUID
    let expiresAt: Date
    let status: String          // "pending" | "accepted"
    let responderUserUUID: UUID?
    let responderDisplayName: String?
    let shareURL: URL?          // CKShare URL for Device B to accept the share
}

// MARK: - Gateway

/// Manages PairInvite records in CloudKit's **public** database.
///
/// CloudKit Dashboard setup required (one-time):
///   Record type "PairInvite" with the following **Queryable** fields:
///   - inviteCode      (String, Queryable + Sortable)
///   - pairSpaceID     (String, Queryable)
///   - status          (String, Queryable)
///   - inviterUserUUID, inviterDisplayName, sharedSpaceID,
///     expiresAt, responderUserUUID, responderDisplayName
actor CloudKitInviteGateway {

    // MARK: CloudKit record details

    nonisolated static let recordType = "PairInvite"

    /// Deterministic record name so Device A can always overwrite/update the same record.
    nonisolated static func recordName(for pairSpaceID: UUID) -> String {
        "invite-\(pairSpaceID.uuidString)"
    }

    // MARK: Dependencies

    private let container: CKContainer

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    // MARK: Public API

    /// Device A: write a new PairInvite record to the public database.
    func publishInvite(
        code: String,
        inviterUserUUID: UUID,
        inviterDisplayName: String,
        ownerRecordID: String,
        pairSpaceID: UUID,
        sharedSpaceID: UUID,
        expiresAt: Date,
        shareURL: URL?
    ) async throws {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: pairSpaceID))
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["inviteCode"] = code as CKRecordValue
        record["inviterUserUUID"] = inviterUserUUID.uuidString as CKRecordValue
        record["inviterDisplayName"] = inviterDisplayName as CKRecordValue
        record["ownerRecordID"] = ownerRecordID as CKRecordValue
        record["pairSpaceID"] = pairSpaceID.uuidString as CKRecordValue
        record["sharedSpaceID"] = sharedSpaceID.uuidString as CKRecordValue
        record["expiresAt"] = expiresAt as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        record["shareURL"] = shareURL?.absoluteString as CKRecordValue?

        try await container.publicCloudDatabase.save(record)
    }

    /// Device B: look up an invite by its 6-digit numeric code.
    ///
    /// Uses CKQuery on the `inviteCode` field (must be marked **Queryable** in CloudKit Dashboard).
    /// Only returns pending, non-expired invites.
    func lookupInvite(byCode code: String) async throws -> CloudInviteDetails? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let db = container.publicCloudDatabase
        let predicate = NSPredicate(format: "inviteCode == %@ AND status == %@", normalized, "pending")
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 1)

            if results.isEmpty {
                // 查询成功但没有匹配记录 — 可能是邀请码错误、已过期、或已被接受
                // 尝试不带 status 过滤再查一次，以提供更准确的诊断
                let broadPredicate = NSPredicate(format: "inviteCode == %@", normalized)
                let broadQuery = CKQuery(recordType: Self.recordType, predicate: broadPredicate)
                let (broadResults, _) = try await db.records(matching: broadQuery, resultsLimit: 1)

                if let (_, broadRecordResult) = broadResults.first,
                   let broadRecord = try? broadRecordResult.get() {
                    let status = broadRecord["status"] as? String ?? "unknown"
                    if status == "accepted" {
                        throw PairingError.inviteAlreadyAccepted
                    }
                    let expiresAt = broadRecord["expiresAt"] as? Date
                    if let expiresAt, expiresAt < Date.now {
                        throw PairingError.inviteExpired
                    }
                    // 记录存在但 status 不是 pending — 返回 nil 让上层显示"无效"
                }
                return nil
            }

            guard let (_, recordResult) = results.first,
                  let record = try? recordResult.get() else {
                return nil
            }
            return Self.decode(record: record)
        } catch let pairingError as PairingError {
            // 重新抛出我们自己的诊断错误
            throw pairingError
        } catch let ckError as CKError {
            switch ckError.code {
            case .invalidArguments, .serverRejectedRequest:
                throw PairingError.cloudKitNotConfigured
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                throw PairingError.cloudOperationFailed(ckError)
            case .unknownItem:
                return nil
            default:
                throw PairingError.cloudOperationFailed(ckError)
            }
        } catch {
            // 捕获所有非 CKError 的异常，避免静默失败
            throw PairingError.cloudOperationFailed(error)
        }
    }

    /// Device B: mark the invite as accepted and write the responder's details back.
    func acceptInvite(
        pairSpaceID: UUID,
        responderUserUUID: UUID,
        responderDisplayName: String
    ) async throws {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: pairSpaceID))
        // Fetch first so we don't lose server-side fields (CloudKit merge safety).
        let existing = try await container.publicCloudDatabase.record(for: recordID)
        existing["status"] = "accepted" as CKRecordValue
        existing["responderUserUUID"] = responderUserUUID.uuidString as CKRecordValue
        existing["responderDisplayName"] = responderDisplayName as CKRecordValue
        try await container.publicCloudDatabase.save(existing)
    }

    /// Device A: check whether the invite was accepted (poll).
    func pollInviteStatus(pairSpaceID: UUID) async throws -> CloudInviteDetails? {
        let recordID = CKRecord.ID(recordName: Self.recordName(for: pairSpaceID))
        let record = try await container.publicCloudDatabase.record(for: recordID)
        return Self.decode(record: record)
    }

    // MARK: Private

    private nonisolated static func decode(record: CKRecord) -> CloudInviteDetails? {
        guard
            let code = record["inviteCode"] as? String,
            let inviterUUIDStr = record["inviterUserUUID"] as? String,
            let inviterUserUUID = UUID(uuidString: inviterUUIDStr),
            let inviterDisplayName = record["inviterDisplayName"] as? String,
            let pairSpaceIDStr = record["pairSpaceID"] as? String,
            let pairSpaceID = UUID(uuidString: pairSpaceIDStr),
            let sharedSpaceIDStr = record["sharedSpaceID"] as? String,
            let sharedSpaceID = UUID(uuidString: sharedSpaceIDStr),
            let expiresAt = record["expiresAt"] as? Date,
            let status = record["status"] as? String
        else { return nil }

        let responderUserUUID = (record["responderUserUUID"] as? String).flatMap(UUID.init(uuidString:))
        let responderDisplayName = record["responderDisplayName"] as? String
        let ownerRecordID = record["ownerRecordID"] as? String

        let shareURL = (record["shareURL"] as? String).flatMap(URL.init(string:))

        return CloudInviteDetails(
            inviteCode: code,
            inviterUserUUID: inviterUserUUID,
            inviterDisplayName: inviterDisplayName,
            ownerRecordID: ownerRecordID,
            pairSpaceID: pairSpaceID,
            sharedSpaceID: sharedSpaceID,
            expiresAt: expiresAt,
            status: status,
            responderUserUUID: responderUserUUID,
            responderDisplayName: responderDisplayName,
            shareURL: shareURL
        )
    }
}
