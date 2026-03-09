import Foundation

enum ItemExecutionRole: String, Hashable, Sendable {
    case initiator
    case recipient
    case both

    func label(for viewerID: UUID, creatorID: UUID) -> String {
        switch self {
        case .initiator:
            return viewerID == creatorID ? "我负责" : "对方负责"
        case .recipient:
            return viewerID == creatorID ? "对方负责" : "我负责"
        case .both:
            return "一起做"
        }
    }
}

enum ItemPriority: String, CaseIterable, Hashable, Sendable {
    case normal
    case important
    case critical

    var title: String {
        switch self {
        case .normal:
            return "普通"
        case .important:
            return "重要"
        case .critical:
            return "很重要"
        }
    }
}

enum ItemResponseKind: String, CaseIterable, Hashable, Sendable {
    case willing
    case notAvailableNow
    case notSuitable
    case acknowledged

    var title: String {
        switch self {
        case .willing:
            return "愿意处理"
        case .notAvailableNow:
            return "暂不方便"
        case .notSuitable:
            return "这次不合适"
        case .acknowledged:
            return "知道了"
        }
    }
}

enum ItemStatus: String, Hashable, Sendable {
    case pendingConfirmation
    case inProgress
    case completed
    case declinedOrBlocked

    var title: String {
        switch self {
        case .pendingConfirmation:
            return "待确认"
        case .inProgress:
            return "进行中"
        case .completed:
            return "已完成"
        case .declinedOrBlocked:
            return "未同意/无法完成"
        }
    }
}
