import Foundation

enum StartupTrace {
    private static let startUptime = ProcessInfo.processInfo.systemUptime

    static func mark(_ name: String) {
        #if DEBUG
        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        let formatted = String(format: "%.3f", elapsed)
        print("[StartupTrace +\(formatted)s] \(name)")
        #endif
    }
}
