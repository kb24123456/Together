import Foundation
import Testing
@testable import Together

@MainActor
@Suite("Today Widget Snapshot Builder")
struct TodayWidgetSnapshotBuilderTests {
    private let spaceID = UUID()
    private let actorID = UUID()
    private let calendar = Calendar(identifier: .gregorian)

    @Test("uses Today ordering and keeps only incomplete tasks")
    func usesTodayOrderingAndIncompleteTasks() {
        let now = Date(timeIntervalSince1970: 1_777_800_000)
        let first = item(title: "第一项", dueAt: now.addingTimeInterval(3_600), sortOrder: 0)
        var completed = item(title: "已完成", dueAt: now.addingTimeInterval(1_800), sortOrder: 1)
        completed.completedAt = now
        completed.status = .completed
        let second = item(title: "第二项", dueAt: now.addingTimeInterval(7_200), sortOrder: 2)

        let snapshot = TodayWidgetSnapshotBuilder(calendar: calendar).build(
            items: [second, completed, first],
            referenceDate: now,
            limit: 3
        )

        #expect(snapshot.remainingCount == 2)
        #expect(snapshot.tasks.map(\.title) == ["第一项", "第二项"])
    }

    @Test("formats explicit time and hides missing due time")
    func formatsDueTime() {
        let now = Date(timeIntervalSince1970: 1_777_800_000)
        let explicit = item(title: "有时间", dueAt: now, hasExplicitTime: true, sortOrder: 0)
        let noDate = item(title: "无时间", dueAt: nil, sortOrder: 1)

        let snapshot = TodayWidgetSnapshotBuilder(calendar: calendar).build(
            items: [explicit, noDate],
            referenceDate: now,
            limit: 3
        )

        #expect(snapshot.tasks[0].dueTimeText != nil)
        #expect(snapshot.tasks[1].dueTimeText == nil)
    }

    private func item(
        title: String,
        dueAt: Date?,
        hasExplicitTime: Bool = true,
        sortOrder: Double
    ) -> Item {
        Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: title,
            notes: nil,
            executionRole: .initiator,
            assigneeMode: .self,
            dueAt: dueAt,
            hasExplicitTime: hasExplicitTime,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: dueAt ?? .now,
            updatedAt: dueAt ?? .now,
            sortOrder: sortOrder,
            isDraft: false
        )
    }
}
