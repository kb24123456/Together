import Foundation
import Testing
@testable import Together

@MainActor
@Suite("App intent handoff", .serialized)
struct AppIntentHandoffCenterTests {
    @Test func titleNormalizationTrimsAndCollapsesUnicodeWhitespace() {
        #expect(TaskCreationIntentTitle.normalized(nil) == nil)
        #expect(TaskCreationIntentTitle.normalized(" \n\t ") == nil)
        #expect(
            TaskCreationIntentTitle.normalized("  买\u{3000}牛奶\n\n明天\t ")
                == "买 牛奶 明天"
        )
    }

    @Test func handoffQueuePreservesFIFOOrderAndUniqueIdentity() throws {
        let center = AppIntentHandoffCenter()
        let first = center.enqueueTaskCreation(title: " 第一项 ")
        let second = center.enqueueTaskCreation(title: "第二项")

        #expect(first.id != second.id)
        #expect(center.taskCreationRequestRevision == 2)
        #expect(center.pendingTaskCreationCount == 2)
        #expect(center.nextTaskCreationRequestID == first.id)
        #expect(try #require(center.consumeNextTaskCreation()) == first)
        #expect(try #require(center.consumeNextTaskCreation()) == second)
        #expect(center.consumeNextTaskCreation() == nil)
    }

    @Test func repeatedComposerRouteStillProducesDistinctRequests() {
        let router = AppRouter()

        router.requestComposer(.newTask)
        let firstRevision = router.composerRequestRevision
        router.requestComposer(.newTask, title: "下一项")

        #expect(router.activeComposer == .newTask)
        #expect(router.pendingComposerTitle == "下一项")
        #expect(router.composerRequestRevision == firstRevision + 1)

        router.clearComposerRequest()
        #expect(router.activeComposer == nil)
        #expect(router.pendingComposerTitle == nil)
    }
}
