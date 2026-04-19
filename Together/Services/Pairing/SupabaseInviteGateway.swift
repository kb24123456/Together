import Foundation
import Supabase

/// Supabase 配对邀请网关
/// 处理 6 位邀请码的创建、查询、接受和取消
actor SupabaseInviteGateway {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared

    struct InviteRecord: Codable, Sendable {
        let id: UUID
        let spaceId: UUID
        let inviterId: UUID
        let inviteCode: String
        let status: String
        let acceptedBy: UUID?
        let inviterLocalUserId: UUID?
        let inviterDisplayName: String?
        let createdAt: Date
        let expiresAt: Date
        let respondedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, status
            case spaceId = "space_id"
            case inviterId = "inviter_id"
            case inviteCode = "invite_code"
            case acceptedBy = "accepted_by"
            case inviterLocalUserId = "inviter_local_user_id"
            case inviterDisplayName = "inviter_display_name"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
            case respondedAt = "responded_at"
        }
    }

    struct MemberRecord: Codable, Sendable {
        let userId: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case displayName = "display_name"
        }
    }

    /// 创建配对邀请（Device A）
    /// - Parameters:
    ///   - spaceID: Supabase space UUID
    ///   - inviterID: Supabase auth.uid()
    ///   - inviterLocalUserID: App 本地 User.id
    ///   - inviterDisplayName: 邀请方显示名
    func createInvite(
        spaceID: UUID,
        inviterID: UUID,
        inviterLocalUserID: UUID,
        inviterDisplayName: String
    ) async throws -> InviteRecord {
        let code = generateNumericCode(digits: 6)

        struct InsertPayload: Encodable {
            let space_id: String
            let inviter_id: String
            let invite_code: String
            let status: String
            let inviter_local_user_id: String
            let inviter_display_name: String
        }

        let invite: InviteRecord = try await client.from("pair_invites")
            .insert(InsertPayload(
                space_id: spaceID.uuidString,
                inviter_id: inviterID.uuidString,
                invite_code: code,
                status: "pending",
                inviter_local_user_id: inviterLocalUserID.uuidString,
                inviter_display_name: inviterDisplayName
            ))
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

    /// 轮询邀请状态（Device A 用于检测对方是否已接受）
    func pollInviteStatus(spaceID: UUID) async throws -> InviteRecord? {
        let invites: [InviteRecord] = try await client.from("pair_invites")
            .select()
            .eq("space_id", value: spaceID.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return invites.first
    }

    /// 查询 space 中对方成员信息（排除自己）
    func getPartnerMember(spaceID: UUID, excludeUserID: UUID) async throws -> MemberRecord? {
        let members: [MemberRecord] = try await client.from("space_members")
            .select("user_id, display_name")
            .eq("space_id", value: spaceID.uuidString)
            .neq("user_id", value: excludeUserID.uuidString)
            .execute()
            .value

        return members.first
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

    /// 将 space 归档（解绑时调用，通知对方 space 已失效）
    func archiveSpace(spaceID: UUID) async throws {
        struct Body: Encodable {
            let status: String
            let archivedAt: String
            enum CodingKeys: String, CodingKey {
                case status
                case archivedAt = "archived_at"
            }
        }
        try await client.from("spaces")
            .update(Body(status: "archived", archivedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: spaceID.uuidString)
            .execute()
    }

    /// 从 space_members 删除自己（对方 Realtime 会收到 DELETE 事件）
    func leaveSpace(spaceID: UUID, userID: UUID) async throws {
        try await client.from("space_members")
            .delete()
            .eq("space_id", value: spaceID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    /// 查询 space 当前剩余成员数（用于判断是否最后一人离开）
    func remainingMemberCount(spaceID: UUID) async throws -> Int {
        struct Row: Decodable { let userId: UUID; enum CodingKeys: String, CodingKey { case userId = "user_id" } }
        let rows: [Row] = try await client.from("space_members")
            .select("user_id")
            .eq("space_id", value: spaceID.uuidString)
            .execute()
            .value
        return rows.count
    }

    /// 生成 6 位数字邀请码
    private func generateNumericCode(digits: Int) -> String {
        let max = Int(pow(10.0, Double(digits))) - 1
        let code = Int.random(in: 0...max)
        return String(format: "%0\(digits)d", code)
    }
}
