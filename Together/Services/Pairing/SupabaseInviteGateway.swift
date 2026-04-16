import Foundation
import Supabase

/// Supabase 配对邀请网关
/// 处理 6 位邀请码的创建、查询、接受和取消
actor SupabaseInviteGateway {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared

    struct InviteRecord: Codable {
        let id: UUID
        let spaceId: UUID
        let inviterId: UUID
        let inviteCode: String
        let status: String
        let acceptedBy: UUID?
        let createdAt: Date
        let expiresAt: Date
        let respondedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, status
            case spaceId = "space_id"
            case inviterId = "inviter_id"
            case inviteCode = "invite_code"
            case acceptedBy = "accepted_by"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
            case respondedAt = "responded_at"
        }
    }

    /// 创建配对邀请（Device A）
    func createInvite(spaceID: UUID, inviterID: UUID) async throws -> InviteRecord {
        let code = generateNumericCode(digits: 6)

        let invite: InviteRecord = try await client.from("pair_invites")
            .insert([
                "space_id": spaceID.uuidString,
                "inviter_id": inviterID.uuidString,
                "invite_code": code,
                "status": "pending"
            ])
            .select()
            .single()
            .execute()
            .value

        return invite
    }

    /// 通过邀请码查询待处理的邀请（Device B）
    func lookupInvite(code: String) async throws -> InviteRecord? {
        let invites: [InviteRecord] = try await client.from("pair_invites")
            .select()
            .eq("invite_code", value: code)
            .eq("status", value: "pending")
            .gte("expires_at", value: ISO8601DateFormatter().string(from: Date()))
            .execute()
            .value

        return invites.first
    }

    /// 接受邀请（Device B）
    func acceptInvite(inviteID: UUID, acceptedBy: UUID) async throws -> InviteRecord {
        let invite: InviteRecord = try await client.from("pair_invites")
            .update([
                "status": "accepted",
                "accepted_by": acceptedBy.uuidString,
                "responded_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: inviteID.uuidString)
            .select()
            .single()
            .execute()
            .value

        return invite
    }

    /// 取消邀请（Device A）
    func cancelInvite(inviteID: UUID) async throws {
        try await client.from("pair_invites")
            .update(["status": "cancelled"])
            .eq("id", value: inviteID.uuidString)
            .execute()
    }

    /// 创建共享空间（配对流程第一步）
    func createSpace(ownerID: UUID, displayName: String) async throws -> UUID {
        struct SpaceRow: Codable {
            let id: UUID
            enum CodingKeys: String, CodingKey { case id }
        }

        let row: SpaceRow = try await client.from("spaces")
            .insert([
                "owner_user_id": ownerID.uuidString,
                "display_name": displayName,
                "type": "pair",
                "status": "active"
            ])
            .select("id")
            .single()
            .execute()
            .value

        return row.id
    }

    /// 加入共享空间（配对流程最后一步）
    func joinSpace(spaceID: UUID, userID: UUID, displayName: String, role: String = "member") async throws {
        try await client.from("space_members")
            .insert([
                "space_id": spaceID.uuidString,
                "user_id": userID.uuidString,
                "display_name": displayName,
                "role": role
            ])
            .execute()
    }

    /// 生成 6 位数字邀请码
    private func generateNumericCode(digits: Int) -> String {
        let max = Int(pow(10.0, Double(digits))) - 1
        let code = Int.random(in: 0...max)
        return String(format: "%0\(digits)d", code)
    }
}
