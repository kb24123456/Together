import Foundation

enum AnniversaryWidgetSnapshotStoreError: Error {
    case missingAppGroupContainer
}

struct AnniversaryWidgetSnapshotStore {
    private let containerURL: URL?

    nonisolated init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.containerURL = containerURL
    }

    nonisolated func read() throws -> AnniversaryWidgetSnapshot {
        guard let fileURL else { return .empty }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.todayWidget.decode(AnniversaryWidgetSnapshot.self, from: data)
    }

    nonisolated func write(_ snapshot: AnniversaryWidgetSnapshot) throws {
        guard let fileURL else {
            throw AnniversaryWidgetSnapshotStoreError.missingAppGroupContainer
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder.todayWidget.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    nonisolated var diagnosticFilePath: String {
        fileURL?.path ?? "<missing app group container>"
    }

    nonisolated var fileExistsForDiagnostics: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private nonisolated var fileURL: URL? {
        containerURL?.appending(path: TodayWidgetConstants.anniversarySnapshotFileName)
    }
}

private extension JSONEncoder {
    nonisolated static var todayWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var todayWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
