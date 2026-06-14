import Foundation

enum ItemStatus: String, Hashable, Sendable, Codable {
    case inProgress
    case completed

    var title: String {
        switch self {
        case .inProgress:
            return "进行中"
        case .completed:
            return "已完成"
        }
    }
}
