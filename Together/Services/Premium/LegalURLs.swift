import Foundation

/// 法律文档 URL single source of truth.
/// Placeholder host — pre-TestFlight 必须由运营拍板部署方案后单独 PR 替换为终值。
enum LegalURLs {
    static let privacy = URL(string: "https://placeholder.together-app.com/privacy")!
    static let terms = URL(string: "https://placeholder.together-app.com/terms")!
}
