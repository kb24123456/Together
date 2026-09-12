import Foundation
import Testing
@testable import Together

@MainActor
struct MascotBehaviorTests {
    private struct SeededRandom: RandomNumberGenerator {
        private var state: UInt64 = 0xD1CE_BA11

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private func activeBehavior(at now: TimeInterval = 0) -> MascotBehaviorState {
        var behavior = MascotBehaviorState()
        behavior.updateContext(MascotContext(isVisible: true), at: now)
        behavior.setPlaybackAllowed(true, at: now)
        return behavior
    }

    @Test func persistentStatesFollowEditingProcessingOverduePriority() {
        var behavior = activeBehavior()
        behavior.updateContext(
            MascotContext(isVisible: true, isEditing: true, isProcessing: true, hasOverdueTasks: true, isInteracting: true),
            at: 0
        )
        #expect(behavior.presentation(at: 200).mode == 1)
        #expect(behavior.presentation(at: 200).staticPose == .holding)

        behavior.updateContext(
            MascotContext(isVisible: true, isProcessing: true, hasOverdueTasks: true, isInteracting: true),
            at: 200
        )
        #expect(behavior.presentation(at: 400).mode == 3)
        #expect(behavior.presentation(at: 400).staticPose == .thinking)

        behavior.updateContext(MascotContext(isVisible: true, hasOverdueTasks: true, isInteracting: true), at: 400)
        #expect(behavior.presentation(at: 600).mode == 2)
        #expect(behavior.presentation(at: 600).staticPose == .concerned)
    }

    @Test func enteringEditorHoldsPenUntilRealTextInput() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0)
        behavior.recordUserActivity(at: 10)

        #expect(behavior.presentation(at: 10).mode == 1)
        #expect(behavior.presentation(at: 10).isTyping == false)
        #expect(behavior.nextDeadline(after: 10) == nil)

        behavior.recordTextInput(at: 11)
        #expect(behavior.presentation(at: 11).isTyping)
        behavior.stopTyping()
        #expect(behavior.presentation(at: 11).isTyping == false)
    }

    @Test func typingStopsAtPauseBoundaryAndNewInputExtendsIt() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0)
        behavior.recordTextInput(at: 0)

        #expect(behavior.presentation(at: 0.899).isTyping)
        #expect(behavior.presentation(at: 0.9).isTyping == false)

        behavior.recordTextInput(at: 1)
        behavior.recordTextInput(at: 1.8)
        #expect(behavior.presentation(at: 1.91).isTyping)
        #expect(behavior.presentation(at: 2.69).isTyping)
        #expect(behavior.presentation(at: 2.71).isTyping == false)
    }

    @Test func typingSignalsOutsideEditorAreIgnored() {
        var behavior = activeBehavior()
        behavior.recordTextInput(at: 1)

        #expect(behavior.presentation(at: 1).isTyping == false)
        #expect(behavior.nextDeadline(after: 1) == nil)
    }

    @Test func deferredInputKeepsItsOriginalPauseDeadlineAfterArrival() {
        var behavior = activeBehavior()
        let originalInputTime: TimeInterval = 10
        let arrivalTime: TimeInterval = 10.4
        let originalDeadline = originalInputTime + MascotBehaviorState.typingPause
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: arrivalTime)
        behavior.recordTextInput(at: originalInputTime)

        #expect(behavior.presentation(at: arrivalTime).isTyping)
        #expect(behavior.nextDeadline(after: arrivalTime) == originalDeadline)
        #expect(behavior.presentation(at: originalDeadline).isTyping == false)
        #expect(behavior.nextDeadline(after: originalDeadline) == nil)
        #expect(behavior.presentation(at: arrivalTime + MascotBehaviorState.typingPause).isTyping == false)

        var lateArrival = activeBehavior()
        lateArrival.updateContext(MascotContext(isVisible: true, isEditing: true), at: 12)
        lateArrival.recordTextInput(at: originalInputTime)
        #expect(lateArrival.presentation(at: 12).isTyping == false)
        #expect(lateArrival.nextDeadline(after: 12) == nil)
    }

    @Test func controllerDoesNotRenewAnAlreadyExpiredDeferredInput() {
        let controller = MascotController()
        controller.updateContext(isVisible: true, isEditing: true)
        controller.setPlaybackAllowed(true)
        let expiredInputTime = ProcessInfo.processInfo.systemUptime - 2

        controller.recordTextInput(at: expiredInputTime)
        #expect(controller.mode == 1)
        #expect(controller.isPlaying)
        #expect(controller.isTyping == false)
        controller.setPlaybackAllowed(false)
    }

    @Test func visibleIdleNeverEntersSleepRegardlessOfElapsedTime() {
        let behavior = activeBehavior()
        for now: TimeInterval in [15, 90, 3600, 86_400] {
            let presentation = behavior.presentation(at: now)
            #expect(presentation.mode == 0)
            #expect(presentation.staticPose == .idle)
            #expect(presentation.expression == 0)
        }
    }

    @Test func activityRestartsExpressionDelayWhileUnchangedContextDoesNot() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let originalDeadline = try #require(behavior.nextDeadline(after: 0))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(originalDeadline))

        behavior.updateContext(MascotContext(isVisible: true), at: 1)
        behavior.advanceIdleExpression(at: 1, using: &random)
        #expect(behavior.nextDeadline(after: 1) == originalDeadline)

        let activityTime = originalDeadline - 0.1
        behavior.recordUserActivity(at: activityTime)
        #expect(behavior.nextDeadline(after: activityTime) == nil)
        behavior.advanceIdleExpression(at: activityTime, using: &random)
        let renewedDeadline = try #require(behavior.nextDeadline(after: activityTime))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(renewedDeadline - activityTime))
        #expect(renewedDeadline > originalDeadline)
    }

    @Test func continuousScrollDefersRandomExpressionUntilAfterScrollingStops() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)

        behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: 20)
        behavior.advanceIdleExpression(at: 20, using: &random)
        #expect(behavior.presentation(at: 20).mode == 0)
        #expect(behavior.presentation(at: 1000).mode == 0)
        #expect(behavior.presentation(at: 1000).expression == 0)
        #expect(behavior.nextDeadline(after: 1000) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 1000)
        behavior.advanceIdleExpression(at: 1000, using: &random)
        let deadline = try #require(behavior.nextDeadline(after: 1000))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(deadline - 1000))
        #expect(behavior.presentation(at: 1000).expression == 0)
    }

    @Test func hidingClearsScrollAndIgnoresLateHiddenInteraction() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: 1)
        behavior.updateContext(MascotContext(isVisible: false, isInteracting: true), at: 2)
        #expect(behavior.context.isInteracting == false)
        behavior.updateContext(MascotContext(isVisible: false, isInteracting: true), at: 3)
        #expect(behavior.context.isInteracting == false)
        #expect(behavior.nextDeadline(after: 3) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 1000)
        #expect(behavior.presentation(at: 1000).mode == 0)
        #expect(behavior.presentation(at: 1015).mode == 0)
    }

    @Test func pausedPlaybackDiscardsScrollSoRestoringCanScheduleIdleExpressions() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: 1)
        behavior.setPlaybackAllowed(false, at: 2)
        #expect(behavior.context.isInteracting == false)
        #expect(behavior.nextDeadline(after: 2) == nil)

        behavior.setPlaybackAllowed(true, at: 1000)
        #expect(behavior.presentation(at: 1000).mode == 0)
        behavior.advanceIdleExpression(at: 1000, using: &random)
        let deadline = try #require(behavior.nextDeadline(after: 1000))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(deadline - 1000))
    }

    @Test func hiddenTimeDoesNotConsumeTheNextVisibleExpressionDelay() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        behavior.updateContext(MascotContext(isVisible: false), at: 10)
        behavior.advanceIdleExpression(at: 1000, using: &random)
        #expect(behavior.nextDeadline(after: 1000) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 1000)
        behavior.advanceIdleExpression(at: 1000, using: &random)
        let deadline = try #require(behavior.nextDeadline(after: 1000))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(deadline - 1000))
        #expect(behavior.presentation(at: 1000).expression == 0)
    }

    @Test func leavingLongProcessingStartsFreshExpressionDelay() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 0)
        behavior.advanceIdleExpression(at: 0, using: &random)
        #expect(behavior.presentation(at: 500).mode == 3)
        #expect(behavior.nextDeadline(after: 500) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 500)
        behavior.advanceIdleExpression(at: 500, using: &random)
        let deadline = try #require(behavior.nextDeadline(after: 500))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(deadline - 500))
        #expect(behavior.presentation(at: 500).mode == 0)
        #expect(behavior.presentation(at: 500).expression == 0)
    }

    @Test func hiddenEditorClearsTypingAndDoesNotReplayHiddenEvents() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0)
        behavior.recordTextInput(at: 0)
        behavior.updateContext(MascotContext(isVisible: false, isEditing: true), at: 0.1)
        behavior.recordTextInput(at: 0.2)

        #expect(behavior.presentation(at: 0.2).isPlaying == false)
        #expect(behavior.presentation(at: 0.2).isTyping == false)
        #expect(behavior.requestFeedback(.celebrate, at: 0.2) == false)
        #expect(behavior.requestFeedback(.acknowledge, at: 0.2) == false)
        #expect(behavior.nextDeadline(after: 0.2) == nil)

        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0.3)
        #expect(behavior.presentation(at: 0.3).isTyping == false)
        #expect(behavior.presentation(at: 0.3).feedback == nil)
    }

    @Test func playbackSuppressionClearsTypingAndPreservesStaticTaskPose() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0)
        behavior.recordTextInput(at: 0)
        // Background, Reduce Motion, and resource limits share this playback permission.
        behavior.setPlaybackAllowed(false, at: 0.1)
        behavior.recordTextInput(at: 0.2)

        let stopped = behavior.presentation(at: 0.2)
        #expect(stopped.isPlaying == false)
        #expect(stopped.isTyping == false)
        #expect(stopped.staticPose == .holding)
        #expect(behavior.requestFeedback(.celebrate, at: 0.2) == false)
        #expect(behavior.nextDeadline(after: 0.2) == nil)

        behavior.setPlaybackAllowed(true, at: 0.3)
        #expect(behavior.presentation(at: 0.3).isTyping == false)
        #expect(behavior.presentation(at: 0.3).feedback == nil)
    }

    @Test(arguments: [true, false])
    func interruptionDropsFeedbackAndDoesNotResumeIt(hide: Bool) {
        var behavior = activeBehavior()
        #expect(behavior.requestFeedback(.celebrate, at: 0) == true)
        if hide {
            behavior.updateContext(MascotContext(isVisible: false), at: 0.1)
        } else {
            behavior.setPlaybackAllowed(false, at: 0.1)
        }

        #expect(behavior.presentation(at: 0.2).feedback == nil)
        #expect(behavior.requestFeedback(.celebrate, at: 0.2) == false)
        #expect(behavior.nextDeadline(after: 0.2) == nil)

        if hide {
            behavior.updateContext(MascotContext(isVisible: true), at: 0.3)
        } else {
            behavior.setPlaybackAllowed(true, at: 0.3)
        }
        #expect(behavior.presentation(at: 0.3).feedback == nil)
        #expect(behavior.presentation(at: 0.3).mode == 0)
        #expect(behavior.nextDeadline(after: 0.3) == nil)
    }

    @Test func frequentCompletionsCoalesceWithSharedFourSecondCooldown() throws {
        var behavior = activeBehavior()
        #expect(behavior.requestFeedback(.celebrate, at: 0) == true)
        let first = try #require(behavior.presentation(at: 0).feedback)

        #expect(behavior.requestFeedback(.celebrate, at: 0.1) == false)
        #expect(behavior.requestFeedback(.acknowledge, at: 1) == false)
        #expect(behavior.presentation(at: 1).feedback?.id == first.id)
        #expect(behavior.presentation(at: 1.8).feedback == nil)
        #expect(behavior.requestFeedback(.celebrate, at: 3.999) == false)
        #expect(behavior.requestFeedback(.celebrate, at: 4) == true)
        #expect(behavior.presentation(at: 4).feedback?.id != first.id)
    }

    @Test func feedbackAdmissionRespectsPersistentBehavior() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, hasOverdueTasks: true), at: 0)
        #expect(behavior.requestFeedback(.acknowledge, at: 0) == false)
        #expect(behavior.requestFeedback(.celebrate, at: 0) == true)

        behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 10)
        #expect(behavior.requestFeedback(.celebrate, at: 10) == false)
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 20)
        #expect(behavior.requestFeedback(.celebrate, at: 20) == false)
        behavior.updateContext(MascotContext(isVisible: true), at: 30)
        #expect(behavior.presentation(at: 45).mode == 0)
        #expect(behavior.requestFeedback(.celebrate, at: 45) == true)
    }

    @Test func contextChangeInterruptsFeedbackWithoutClearingCooldown() {
        var behavior = activeBehavior()
        #expect(behavior.requestFeedback(.celebrate, at: 0) == true)
        behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0.1)
        #expect(behavior.presentation(at: 0.1).feedback == nil)
        behavior.updateContext(MascotContext(isVisible: true), at: 0.2)
        #expect(behavior.requestFeedback(.celebrate, at: 0.2) == false)
        #expect(behavior.requestFeedback(.celebrate, at: 4) == true)
    }

    @Test func deadlinesTrackNextVisibleChangeWithoutPolling() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        #expect(behavior.nextDeadline(after: 0) == nil)
        behavior.advanceIdleExpression(at: 0, using: &random)
        let firstDeadline = try #require(behavior.nextDeadline(after: 0))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(firstDeadline))
        #expect(behavior.requestFeedback(.acknowledge, at: 1) == true)
        behavior.advanceIdleExpression(at: 1, using: &random)
        #expect(behavior.nextDeadline(after: 1) == 1.9)
        #expect(behavior.presentation(at: 1).expression == 0)
        #expect(behavior.presentation(at: 1.9).feedback == nil)
        behavior.advanceIdleExpression(at: 1.9, using: &random)
        let afterFeedback = try #require(behavior.nextDeadline(after: 1.9))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(afterFeedback - 5))

        behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 2)
        behavior.advanceIdleExpression(at: 2, using: &random)
        #expect(behavior.nextDeadline(after: 2) == nil)
        behavior.updateContext(MascotContext(isVisible: false), at: 3)
        #expect(behavior.nextDeadline(after: 3) == nil)
    }

    @Test func idleExpressionsUseOnlyTheApprovedSetWithoutConsecutiveRepeats() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        let allowed = Set(MascotIdleExpression.allCases.map(\.rawValue))
        #expect(allowed == [2, 21])
        var now: TimeInterval = 0
        var previousExpression: Int?
        behavior.advanceIdleExpression(at: now, using: &random)

        for _ in 0..<32 {
            let start = try #require(behavior.nextDeadline(after: now))
            #expect(MascotBehaviorState.idleExpressionDelay.contains(start - now))
            #expect(behavior.presentation(at: start - 0.001).expression == 0)
            behavior.advanceIdleExpression(at: start, using: &random)
            let expression = behavior.presentation(at: start).expression
            #expect(allowed.contains(expression))
            #expect(expression != previousExpression)
            #expect(behavior.presentation(at: start).mode == 0)

            let end = try #require(behavior.nextDeadline(after: start))
            #expect(MascotBehaviorState.idleExpressionDuration.contains(end - start))
            #expect(behavior.presentation(at: end - 0.001).expression == expression)
            // Presentation must expire the override even before its owner advances the schedule.
            #expect(behavior.presentation(at: end).expression == 0)
            behavior.advanceIdleExpression(at: end, using: &random)
            #expect(behavior.presentation(at: end).expression == 0)
            previousExpression = expression
            now = end
        }
    }

    @Test func lateDeadlineStartsOnlyOneExpressionAndNeverReplaysMissedCycles() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let initialDeadline = try #require(behavior.nextDeadline(after: 0))
        let lateStart = initialDeadline + 3600

        behavior.advanceIdleExpression(at: lateStart, using: &random)
        let expression = behavior.presentation(at: lateStart).expression
        #expect(MascotIdleExpression.allCases.map(\.rawValue).contains(expression))
        let end = try #require(behavior.nextDeadline(after: lateStart))
        #expect(MascotBehaviorState.idleExpressionDuration.contains(end - lateStart))
        behavior.advanceIdleExpression(at: lateStart, using: &random)
        #expect(behavior.presentation(at: lateStart).expression == expression)
        #expect(behavior.nextDeadline(after: lateStart) == end)

        let lateEnd = end + 3600
        behavior.advanceIdleExpression(at: lateEnd, using: &random)
        #expect(behavior.presentation(at: lateEnd).expression == 0)
        let next = try #require(behavior.nextDeadline(after: lateEnd))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(next - lateEnd))
    }

    @Test(arguments: ["hidden", "disabled", "editing", "processing", "overdue", "scrolling", "activity"])
    func interruptionClearsAnActiveExpressionAndStartsAFreshDelay(kind: String) throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let start = try #require(behavior.nextDeadline(after: 0))
        behavior.advanceIdleExpression(at: start, using: &random)
        #expect(behavior.presentation(at: start).expression != 0)
        let interruptedAt = start + 0.1

        switch kind {
        case "hidden":
            behavior.updateContext(MascotContext(isVisible: false), at: interruptedAt)
        case "disabled":
            behavior.setPlaybackAllowed(false, at: interruptedAt)
        case "editing":
            behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: interruptedAt)
        case "processing":
            behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: interruptedAt)
        case "overdue":
            behavior.updateContext(MascotContext(isVisible: true, hasOverdueTasks: true), at: interruptedAt)
        case "scrolling":
            behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: interruptedAt)
        default:
            behavior.recordUserActivity(at: interruptedAt)
        }
        #expect(behavior.presentation(at: interruptedAt).expression == 0)
        #expect(behavior.nextDeadline(after: interruptedAt) == nil)

        let restoredAt = interruptedAt + 100
        behavior.updateContext(MascotContext(isVisible: true), at: restoredAt)
        behavior.setPlaybackAllowed(true, at: restoredAt)
        behavior.advanceIdleExpression(at: restoredAt, using: &random)
        #expect(behavior.presentation(at: restoredAt).expression == 0)
        let next = try #require(behavior.nextDeadline(after: restoredAt))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(next - restoredAt))
    }

    @Test func admittedFeedbackReplacesIdleExpressionThenRestoresTheDailySchedule() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let start = try #require(behavior.nextDeadline(after: 0))
        behavior.advanceIdleExpression(at: start, using: &random)
        #expect(behavior.presentation(at: start).expression != 0)

        let feedbackStart = start + 0.1
        #expect(behavior.requestFeedback(.celebrate, at: feedbackStart) == true)
        #expect(behavior.presentation(at: feedbackStart).expression == 0)
        behavior.advanceIdleExpression(at: feedbackStart, using: &random)
        let feedbackEnd = try #require(behavior.nextDeadline(after: feedbackStart))
        #expect(abs(feedbackEnd - feedbackStart - 1.8) < 0.000_001)
        #expect(behavior.presentation(at: feedbackEnd - 0.001).expression == 0)
        #expect(behavior.presentation(at: feedbackEnd).feedback == nil)

        behavior.advanceIdleExpression(at: feedbackEnd, using: &random)
        #expect(behavior.presentation(at: feedbackEnd).expression == 0)
        let next = try #require(behavior.nextDeadline(after: feedbackEnd))
        let cooldownEnd = feedbackStart + MascotBehaviorState.feedbackCooldown
        #expect(MascotBehaviorState.idleExpressionDelay.contains(next - cooldownEnd))
    }

    @Test(arguments: [false, true])
    func resultGlanceKeepsPersistentModeAndEndsAfterNineTenths(hasOverdueTasks: Bool) {
        var behavior = activeBehavior()
        behavior.updateContext(
            MascotContext(isVisible: true, hasOverdueTasks: hasOverdueTasks), at: 0
        )
        #expect(behavior.requestFeedback(.noticeResult, at: 0) == true)
        #expect(behavior.presentation(at: 0.899).feedback?.kind == .noticeResult)
        #expect(behavior.presentation(at: 0.899).mode == (hasOverdueTasks ? 2 : 0))
        #expect(behavior.presentation(at: 0.899).staticPose == (hasOverdueTasks ? .concerned : .idle))
        #expect(behavior.nextDeadline(after: 0) == 0.9)
        #expect(behavior.presentation(at: 0.9).feedback == nil)
        #expect(behavior.presentation(at: 0.9).mode == (hasOverdueTasks ? 2 : 0))
    }

    @Test func resultGlancePreservesTheCurrentFaceUntilItsOriginalDeadline() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let faceStart = try #require(behavior.nextDeadline(after: 0))
        behavior.advanceIdleExpression(at: faceStart, using: &random)
        let expression = behavior.presentation(at: faceStart).expression
        let faceEnd = try #require(behavior.nextDeadline(after: faceStart))
        let noticeStart = faceEnd - 0.3
        #expect(expression != 0)

        #expect(behavior.requestFeedback(.noticeResult, at: noticeStart) == true)
        behavior.advanceIdleExpression(at: noticeStart, using: &random)
        #expect(behavior.presentation(at: noticeStart).expression == expression)
        #expect(behavior.nextDeadline(after: noticeStart) == faceEnd)
        #expect(behavior.presentation(at: faceEnd - 0.001).expression == expression)

        behavior.advanceIdleExpression(at: faceEnd, using: &random)
        #expect(behavior.presentation(at: faceEnd).expression == 0)
        #expect(behavior.presentation(at: faceEnd).feedback?.kind == .noticeResult)
        let noticeEnd = try #require(behavior.nextDeadline(after: faceEnd))
        #expect(abs(noticeEnd - noticeStart - 0.9) < 0.000_001)
        behavior.advanceIdleExpression(at: noticeEnd, using: &random)
        #expect(behavior.presentation(at: noticeEnd).feedback == nil)
        #expect(behavior.presentation(at: noticeEnd).expression == 0)
        let nextFaceStart = try #require(behavior.nextDeadline(after: noticeEnd))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(nextFaceStart - faceEnd))
    }

    @Test func resultGlanceDefersAnIdleFaceThatWasAboutToBegin() throws {
        var behavior = activeBehavior()
        var random = SeededRandom()
        behavior.advanceIdleExpression(at: 0, using: &random)
        let pendingFaceStart = try #require(behavior.nextDeadline(after: 0))
        let noticeStart = pendingFaceStart - 0.1
        #expect(behavior.requestFeedback(.noticeResult, at: noticeStart) == true)

        behavior.advanceIdleExpression(at: pendingFaceStart, using: &random)
        #expect(behavior.presentation(at: pendingFaceStart).expression == 0)
        #expect(behavior.presentation(at: pendingFaceStart).feedback?.kind == .noticeResult)
        let noticeEnd = try #require(behavior.nextDeadline(after: pendingFaceStart))
        behavior.advanceIdleExpression(at: noticeEnd, using: &random)
        #expect(behavior.presentation(at: noticeEnd).expression == 0)
        let nextFaceStart = try #require(behavior.nextDeadline(after: noticeEnd))
        #expect(MascotBehaviorState.idleExpressionDelay.contains(nextFaceStart - pendingFaceStart))
    }

    @Test func resultGlanceSharesCooldownWithEveryShortResponse() {
        var behavior = activeBehavior()
        #expect(behavior.requestFeedback(.noticeResult, at: 0) == true)
        #expect(behavior.requestFeedback(.acknowledge, at: 0.9) == false)
        #expect(behavior.requestFeedback(.celebrate, at: 3.999) == false)
        #expect(behavior.requestFeedback(.noticeResult, at: 4) == true)

        var celebrating = activeBehavior()
        #expect(celebrating.requestFeedback(.celebrate, at: 0) == true)
        #expect(celebrating.requestFeedback(.noticeResult, at: 1.8) == false)
        #expect(celebrating.requestFeedback(.noticeResult, at: 4) == true)
    }

    @Test(arguments: ["editing", "processing", "hidden", "disabled"])
    func interruptedResultGlanceIsRejectedAndNeverReplayed(interruption: String) {
        var behavior = activeBehavior()
        #expect(behavior.requestFeedback(.noticeResult, at: 0) == true)
        switch interruption {
        case "editing":
            behavior.updateContext(MascotContext(isVisible: true, isEditing: true), at: 0.1)
        case "processing":
            behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 0.1)
        case "hidden":
            behavior.updateContext(MascotContext(isVisible: false), at: 0.1)
        default:
            behavior.setPlaybackAllowed(false, at: 0.1)
        }
        #expect(behavior.presentation(at: 0.1).feedback == nil)
        #expect(behavior.requestFeedback(.noticeResult, at: 0.2) == false)
        #expect(behavior.requestFeedback(.noticeResult, at: 4) == false)
        behavior.updateContext(MascotContext(isVisible: true), at: 4.1)
        behavior.setPlaybackAllowed(true, at: 4.1)
        #expect(behavior.presentation(at: 4.1).feedback == nil)
        #expect(behavior.presentation(at: 10).feedback == nil)
    }

    @Test func controllerPublishesResultGlanceAndInterruptionThroughItsCallback() {
        let controller = MascotController()
        controller.updateContext(isVisible: true, hasOverdueTasks: true)
        controller.setPlaybackAllowed(true)
        var publicationCount = 0
        controller.onPresentationChange = { publicationCount += 1 }

        controller.requestNoticeResult()
        #expect(controller.feedback?.kind == .noticeResult)
        #expect(controller.mode == 2)
        #expect(controller.staticPose == .concerned)
        #expect(publicationCount == 1)
        controller.updateContext(isVisible: false)
        #expect(controller.feedback == nil)
        #expect(publicationCount == 2)
    }

    @Test func controllerPublishesInputAndInterruptionSynchronously() {
        let controller = MascotController()
        controller.updateContext(isVisible: true, isEditing: true)
        controller.setPlaybackAllowed(true)
        #expect(controller.mode == 1)
        #expect(controller.isPlaying)
        #expect(controller.isTyping == false)

        controller.recordTextInput()
        #expect(controller.isTyping)
        controller.setPlaybackAllowed(false)
        #expect(controller.isTyping == false)
        controller.setPlaybackAllowed(true)
        #expect(controller.isTyping == false)

        controller.updateContext(isVisible: true)
        controller.requestCelebration()
        #expect(controller.feedback?.kind == .celebrate)
        controller.updateContext(isVisible: true, isProcessing: true)
        #expect(controller.mode == 3)
        #expect(controller.feedback == nil)
        controller.updateContext(isVisible: false)
        #expect(controller.isPlaying == false)
    }
}
