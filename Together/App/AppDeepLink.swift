import Foundation

enum AppDeepLink: Equatable, Sendable {
    case today
    case task(UUID)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "together" else { return nil }
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "today", pathComponents.isEmpty {
            self = .today
        } else if host == "task",
                  pathComponents.count == 1,
                  let id = UUID(uuidString: pathComponents[0]) {
            self = .task(id)
        } else {
            return nil
        }
    }

    var url: URL {
        switch self {
        case .today:
            return URL(string: "together://today")!
        case .task(let id):
            return URL(string: "together://task/\(id.uuidString)")!
        }
    }
}
