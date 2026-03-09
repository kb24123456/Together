import Foundation

enum BindingState: String, CaseIterable, Hashable, Sendable {
    case singleTrial
    case invitePending
    case inviteReceived
    case paired
    case unbound

    var supportsSharedCollaboration: Bool {
        self == .paired
    }

    var description: String {
        switch self {
        case .singleTrial:
            return "单人试用"
        case .invitePending:
            return "已发出邀请"
        case .inviteReceived:
            return "收到邀请待处理"
        case .paired:
            return "已绑定"
        case .unbound:
            return "已解绑"
        }
    }
}
