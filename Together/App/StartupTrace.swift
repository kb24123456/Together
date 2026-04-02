import Foundation

enum StartupTrace {
    nonisolated static func mark(_ name: String) {
        #if DEBUG
        let uptime = ProcessInfo.processInfo.systemUptime
        let formatted = String(format: "%.3f", uptime)
        print("[StartupTrace uptime=\(formatted)s] \(name)")
        #endif
    }
}
