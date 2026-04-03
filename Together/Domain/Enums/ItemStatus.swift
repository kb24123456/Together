import Foundation

enum TaskAssigneeMode: String, CaseIterable, Hashable, Sendable, Codable {
    case `self`
    case partner
    case both

    nonisolated var legacyExecutionRole: ItemExecutionRole {
        switch self {
        case .self:
            return .initiator
        case .partner:
            return .recipient
        case .both:
            return .both
        }
    }
}

enum TaskAssignmentState: String, CaseIterable, Hashable, Sendable, Codable {
    case pendingResponse
    case accepted
    case snoozed
    case declined
    case active
    case completed

    nonisolated var legacyStatus: ItemStatus {
        switch self {
        case .pendingResponse:
            return .pendingConfirmation
        case .accepted, .active:
            return .inProgress
        case .snoozed, .declined:
            return .declinedOrBlocked
        case .completed:
            return .completed
        }
    }
}

enum ItemExecutionRole: String, Hashable, Sendable, Codable {
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

extension ItemExecutionRole {
    nonisolated var assigneeMode: TaskAssigneeMode {
        switch self {
        case .initiator:
            return .self
        case .recipient:
            return .partner
        case .both:
            return .both
        }
    }
}

enum ItemResponseKind: String, CaseIterable, Hashable, Sendable, Codable {
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

enum ItemStatus: String, Hashable, Sendable, Codable {
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

extension ItemStatus {
    nonisolated var assignmentState: TaskAssignmentState {
        switch self {
        case .pendingConfirmation:
            return .pendingResponse
        case .inProgress:
            return .active
        case .completed:
            return .completed
        case .declinedOrBlocked:
            return .declined
        }
    }
}
