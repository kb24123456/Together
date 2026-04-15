import Foundation

/// Errors thrown when a pair-space permission check fails.
enum PermissionError: LocalizedError {
    case notCreator
    case notSpaceOwner
    case notAssignee

    var errorDescription: String? {
        switch self {
        case .notCreator:
            "只有创建者可以执行此操作"
        case .notSpaceOwner:
            "只有空间创建者可以修改空间名称"
        case .notAssignee:
            "只有被分配的人可以执行此操作"
        }
    }
}
