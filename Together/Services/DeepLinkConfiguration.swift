import Foundation

/// Universal Link 的域名与路径配置。
///
/// **上线前需要做的事（开发者）：**
/// 1. 将 `host` 替换为你拥有的域名（例如 `together.pigdog.app`）
/// 2. 在该域名根目录托管 `/.well-known/apple-app-site-association` 文件（见下方注释）
/// 3. 在 Xcode → Signing & Capabilities → Associated Domains 添加 `applinks:<host>`
/// 4. 在 `/invite/` 路径下放一个 HTML 页面，未安装 app 时跳转到 App Store
///
/// **apple-app-site-association 示例（替换 TEAMID）：**
/// ```json
/// {
///   "applinks": {
///     "details": [
///       {
///         "appIDs": ["TEAMID.com.pigdog.Together"],
///         "components": [
///           { "/": "/invite/*", "comment": "邀请链接" }
///         ]
///       }
///     ]
///   }
/// }
/// ```
///
/// **`/invite/[code]` 的 HTML 重定向页示例（未安装时跳 App Store）：**
/// ```html
/// <!DOCTYPE html>
/// <html>
/// <head>
///   <meta charset="UTF-8">
///   <title>加入 Together</title>
///   <meta name="apple-itunes-app" content="app-id=YOUR_APPSTORE_ID">
/// </head>
/// <body>
///   <script>
///     // 到达这里说明 app 未安装，直接跳 App Store
///     window.location = "https://apps.apple.com/app/idYOUR_APPSTORE_ID";
///   </script>
///   <p>正在跳转到 App Store，请稍候…</p>
/// </body>
/// </html>
/// ```
enum DeepLinkConfiguration {

    // ── 正式域名 ──────────────────────────────────────────────────────────────
    static let primaryHost = "onetwotogether.xyz"

    // ── Vercel 分配的临时域名（DNS 审核期间作为 fallback）────────────────────
    static let fallbackHost = "together-web-theta.vercel.app"

    // ── primaryHost 可达性缓存 ─────────────────────────────────────────────
    private static let _primaryReachable = PrimaryReachableCache()

    /// 当前分享用的 host。
    /// DNS 生效前用 fallbackHost；生效后改为 primaryHost。
    static var activeHost: String {
        fallbackHost  // ← DNS 生效后改为 primaryHost
    }
    // ──────────────────────────────────────────────────────────────────────────

    private static let invitePathComponent = "invite"

    // MARK: - URL 构建

    /// 生成邀请跳转链接。
    /// code = pairSpaceID UUID string (lowercase, with hyphens)
    static func inviteURL(for code: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = activeHost
        components.path = "/\(invitePathComponent)/\(code)"
        return components.url
    }

    // MARK: - URL 解析

    /// 从 Universal Link URL 中提取邀请码（同时接受 primaryHost 和 fallbackHost）。
    static func inviteCode(from url: URL) -> String? {
        guard
            url.scheme == "https",
            url.host == primaryHost || url.host == fallbackHost
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == invitePathComponent else { return nil }

        let code = parts[1]
        return code.isEmpty ? nil : code
    }
}

// MARK: - 正式域名 DNS 可达性缓存

/// 后台每 5 分钟检测一次正式域名是否可达，避免分享时同步等待。
/// 一旦检测到可达，之后永久返回 true（DNS 生效不会回退）。
private final class PrimaryReachableCache: @unchecked Sendable {
    private var _reachable = false
    private let lock = NSLock()

    var isReachable: Bool {
        lock.lock()
        let val = _reachable
        lock.unlock()
        if val { return true }
        // 首次调用 & 定期后台探测
        scheduleProbeIfNeeded()
        return false
    }

    private var probeScheduled = false

    private func scheduleProbeIfNeeded() {
        lock.lock()
        if probeScheduled { lock.unlock(); return }
        probeScheduled = true
        lock.unlock()

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for _ in 0..<288 { // 最多轮询 24 小时（5 分钟 × 288）
                if await self.probe() {
                    self.lock.lock()
                    self._reachable = true
                    self.lock.unlock()
                    return
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func probe() async -> Bool {
        guard let url = URL(string: "https://\(DeepLinkConfiguration.primaryHost)/.well-known/apple-app-site-association") else {
            return false
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
