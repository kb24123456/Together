import Foundation

enum TodayWidgetSnapshotStoreError: Error {
    case missingAppGroupContainer
}

struct TodayWidgetSnapshotStore: Sendable {
    private let containerURL: URL?

    nonisolated init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.containerURL = containerURL
    }

    nonisolated func read() throws -> TodayWidgetSnapshot {
        guard let fileURL else { return .empty }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.todayWidget.decode(TodayWidgetSnapshot.self, from: data)
    }

    nonisolated func write(_ snapshot: TodayWidgetSnapshot) throws {
        guard let fileURL else {
            throw TodayWidgetSnapshotStoreError.missingAppGroupContainer
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder.todayWidget.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    nonisolated func clear() throws {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private nonisolated var fileURL: URL? {
        containerURL?.appending(path: TodayWidgetConstants.snapshotFileName)
    }
}

private extension JSONEncoder {
    static var todayWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var todayWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
