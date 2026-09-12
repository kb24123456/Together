import Foundation
import Testing
@testable import Together

@MainActor
struct MascotBehaviorTests {
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
        #expect(behavior.nextDeadline(after: 1) == 15)
    }

    @Test func visibleIdleDozesAfterFifteenSecondsAndActivityWakesIt() {
        var behavior = activeBehavior()
        #expect(behavior.presentation(at: 14.999).mode == 0)
        #expect(behavior.presentation(at: 15).mode == 4)
        #expect(behavior.presentation(at: 15).staticPose == .doze)
        #expect(behavior.nextDeadline(after: 15) == nil)

        behavior.recordUserActivity(at: 100)
        #expect(behavior.presentation(at: 100).mode == 0)
        #expect(behavior.presentation(at: 114.999).mode == 0)
        #expect(behavior.presentation(at: 115).mode == 4)
    }

    @Test func activityRestartsIdleClockWhileUnchangedContextDoesNot() {
        var behavior = activeBehavior()
        behavior.recordUserActivity(at: 14)
        #expect(behavior.presentation(at: 15).mode == 0)
        #expect(behavior.nextDeadline(after: 15) == 29)

        behavior.updateContext(MascotContext(isVisible: true), at: 28)
        #expect(behavior.presentation(at: 28.999).mode == 0)
        #expect(behavior.presentation(at: 29).mode == 4)
    }

    @Test func continuousScrollWakesAndStaysAwakeUntilFifteenSecondsAfterItStops() {
        var behavior = activeBehavior()
        #expect(behavior.presentation(at: 15).mode == 4)

        behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: 20)
        #expect(behavior.presentation(at: 20).mode == 0)
        #expect(behavior.presentation(at: 1000).mode == 0)
        #expect(behavior.nextDeadline(after: 1000) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 1000)
        #expect(behavior.nextDeadline(after: 1000) == 1015)
        #expect(behavior.presentation(at: 1014.999).mode == 0)
        #expect(behavior.presentation(at: 1015).mode == 4)
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
        #expect(behavior.presentation(at: 1015).mode == 4)
    }

    @Test func pausedPlaybackDiscardsScrollSoRestoringDoesNotStayAwakeForever() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isInteracting: true), at: 1)
        behavior.setPlaybackAllowed(false, at: 2)
        #expect(behavior.context.isInteracting == false)
        #expect(behavior.nextDeadline(after: 2) == nil)

        behavior.setPlaybackAllowed(true, at: 1000)
        #expect(behavior.presentation(at: 1000).mode == 0)
        #expect(behavior.presentation(at: 1015).mode == 4)
    }

    @Test func hiddenTimeDoesNotCountTowardVisibleIdle() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: false), at: 10)
        #expect(behavior.nextDeadline(after: 1000) == nil)

        behavior.updateContext(MascotContext(isVisible: true), at: 1000)
        #expect(behavior.presentation(at: 1014.999).mode == 0)
        #expect(behavior.presentation(at: 1015).mode == 4)
    }

    @Test func leavingLongProcessingStartsFreshIdleInterval() {
        var behavior = activeBehavior()
        behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 0)
        #expect(behavior.presentation(at: 500).mode == 3)

        behavior.updateContext(MascotContext(isVisible: true), at: 500)
        #expect(behavior.presentation(at: 500).mode == 0)
        #expect(behavior.presentation(at: 514.999).mode == 0)
        #expect(behavior.presentation(at: 515).mode == 4)
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
        #expect(behavior.nextDeadline(after: 0.3) == 15.3)
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
        #expect(behavior.presentation(at: 45).mode == 4)
        #expect(behavior.requestFeedback(.celebrate, at: 45) == false)
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

    @Test func deadlinesTrackNextVisibleChangeWithoutPolling() {
        var behavior = activeBehavior()
        #expect(behavior.nextDeadline(after: 0) == 15)
        #expect(behavior.requestFeedback(.acknowledge, at: 1) == true)
        #expect(behavior.nextDeadline(after: 1) == 1.9)
        #expect(behavior.presentation(at: 1.9).feedback == nil)
        #expect(behavior.nextDeadline(after: 1.9) == 16)

        behavior.updateContext(MascotContext(isVisible: true, isProcessing: true), at: 2)
        #expect(behavior.nextDeadline(after: 2) == nil)
        behavior.updateContext(MascotContext(isVisible: false), at: 3)
        #expect(behavior.nextDeadline(after: 3) == nil)
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
