import Foundation

enum RepositoryError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到目标数据"
        }
    }
}
