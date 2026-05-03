import Foundation
import Testing
@testable import Together

@Suite("Today Widget Snapshot Store")
@MainActor
struct TodayWidgetSnapshotStoreTests {
    @Test("writes and reads a snapshot")
    func writesAndReadsSnapshot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = TodayWidgetSnapshotStore(containerURL: root)
        let taskID = UUID()
        let snapshot = TodayWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_777_837_512),
            referenceDate: Date(timeIntervalSince1970: 1_777_800_000),
            remainingCount: 1,
            tasks: [
                TodayWidgetTaskSnapshot(
                    id: taskID,
                    title: "核对审核备注",
                    dueTimeText: "18:00",
                    sortIndex: 0
                )
            ]
        )

        try store.write(snapshot)
        let read = try store.read()

        #expect(read == snapshot)
    }

    @Test("returns fallback empty snapshot when file missing")
    func returnsFallbackWhenMissing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = TodayWidgetSnapshotStore(containerURL: root)

        let read = try store.read()

        #expect(read.remainingCount == 0)
        #expect(read.tasks.isEmpty)
    }
}
