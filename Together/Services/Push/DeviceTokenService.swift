import Foundation
import Supabase

/// APNs Device Token 注册服务
/// 负责将设备推送令牌注册到 Supabase device_tokens 表
actor DeviceTokenService {

    private nonisolated(unsafe) let client = SupabaseClientProvider.shared

    /// 注册 APNs device token 到 Supabase
    func registerToken(_ tokenData: Data) async {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()

        guard let userID = try? await client.auth.session.user.id else { return }

        do {
            try await client.from("device_tokens")
                .upsert([
                    "user_id": userID.uuidString,
                    "token": tokenString,
                    "platform": "ios"
                ], onConflict: "user_id,token")
                .execute()
        } catch {
            print("[DeviceToken] 注册失败: \(error)")
        }
    }

    /// 注销 token（登出时调用）
    func unregisterToken(_ tokenData: Data) async {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()

        do {
            try await client.from("device_tokens")
                .delete()
                .eq("token", value: tokenString)
                .execute()
        } catch {
            print("[DeviceToken] 注销失败: \(error)")
        }
    }
}
