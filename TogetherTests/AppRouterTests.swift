import Testing
@testable import Together

@MainActor
@Suite("App router")
struct AppRouterTests {
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
