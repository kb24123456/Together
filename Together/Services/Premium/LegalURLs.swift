import Foundation

/// 法律文档 URL single source of truth。
/// 部署在独立 repo `together-app-legal`（GitHub Pages, Jekyll minima theme）。
/// Source of truth 在 main repo `docs/legal/*.md`；每次修订需要同步 push 到 legal repo。
/// Phase 2（正式上架前）：升级到自定义域名（如 `together.app/legal/...`），仅改本文件。
enum LegalURLs {
    static let privacy = URL(string: "https://kb24123456.github.io/together-app-legal/privacy-policy/")!
    static let terms = URL(string: "https://kb24123456.github.io/together-app-legal/terms-of-service/")!
}
