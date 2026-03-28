import Foundation

enum RepositoryError: LocalizedError {
    case notFound
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到目标数据"
        case let .invalidInput(message):
            return message
        }
    }
}
