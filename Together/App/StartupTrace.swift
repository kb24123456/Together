import Foundation

enum StartupTrace {
    nonisolated static func mark(_ name: String) {
        #if DEBUG
        let uptime = ProcessInfo.processInfo.systemUptime
        let formatted = String(format: "%.3f", uptime)
        let line = "[StartupTrace uptime=\(formatted)s] \(name)"
        print(line)
        append(line)
        #endif
    }

    #if DEBUG
    nonisolated private static func append(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        let url = traceURL()

        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    nonisolated private static func traceURL() -> URL {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        ) ?? FileManager.default.temporaryDirectory
        return directory.appending(path: "startup-trace.log")
    }
    #endif
}
