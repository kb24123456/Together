import Foundation

enum PairingError: Error, LocalizedError {
    /// Caller must use CloudPairingService for cross-device operations.
    case crossDeviceNotSupported
    /// No invite record found matching the given code.
    case inviteNotFound
    /// Invite has passed its expiry date.
    case inviteExpired
    /// Invite was already accepted by another user.
    case inviteAlreadyAccepted
    /// iCloud / CloudKit is not available (user not signed in).
    case cloudKitUnavailable
    /// CloudKit record type fields not marked as Queryable in Dashboard.
    case cloudKitNotConfigured
    /// Generic CloudKit operation failure.
    case cloudOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .crossDeviceNotSupported:
            return "跨设备配对需要通过 CloudPairingService"
        case .inviteNotFound:
            return "邀请码无效或已过期，请确认后重试"
        case .inviteExpired:
            return "邀请码已过期，请让对方重新发起邀请"
        case .inviteAlreadyAccepted:
            return "该邀请已被接受"
        case .cloudKitUnavailable:
            return "iCloud 不可用，请在设置中检查 iCloud 登录状态"
        case .cloudKitNotConfigured:
            return "服务尚未就绪，请稍后重试（CloudKit 索引配置中）"
        case .cloudOperationFailed(let error):
            return "云端操作失败：\(error.localizedDescription)"
        }
    }
}
