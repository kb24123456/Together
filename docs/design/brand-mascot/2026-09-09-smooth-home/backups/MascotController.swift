import Foundation
import Observation

@MainActor
@Observable
final class MascotController {
    private(set) var presentation = MascotPresentation()

    var mode: Int { presentation.mode }
    var expression: Int { presentation.expression }
    var isTyping: Bool { presentation.isTyping }
    var isPlaying: Bool { presentation.isPlaying }
    var staticPose: MascotStaticPose { presentation.staticPose }
    var feedback: MascotFeedback? { presentation.feedback }

    @ObservationIgnored private var behavior = MascotBehaviorState()
    @ObservationIgnored private var random = SystemRandomNumberGenerator()
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    func updateContext(
        isVisible: Bool,
        isEditing: Bool = false,
        isProcessing: Bool = false,
        hasOverdueTasks: Bool = false,
        isInteracting: Bool = false
    ) {
        behavior.updateContext(
            MascotContext(
                isVisible: isVisible,
                isEditing: isEditing,
                isProcessing: isProcessing,
                hasOverdueTasks: hasOverdueTasks,
                isInteracting: isInteracting
            ),
            at: Self.now
        )
        refresh()
    }

    func setPlaybackAllowed(_ allowed: Bool) {
        behavior.setPlaybackAllowed(allowed, at: Self.now)
        refresh()
    }

    func recordUserActivity() {
        behavior.recordUserActivity(at: Self.now)
        refresh()
    }

    func recordTextInput() {
        behavior.recordTextInput(at: Self.now)
        refresh()
    }

    func stopTyping() {
        behavior.stopTyping()
        refresh()
    }

    func requestAcknowledgement() {
        behavior.requestFeedback(.acknowledge, at: Self.now)
        refresh()
    }

    func requestCelebration() {
        behavior.requestFeedback(.celebrate, at: Self.now)
        refresh()
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func refresh() {
        deadlineTask?.cancel()
        deadlineTask = nil
        let now = Self.now
        behavior.advanceIdleExpression(at: now, using: &random)
        let next = behavior.presentation(at: now)
        if next != presentation { presentation = next }
        guard let deadline = behavior.nextDeadline(after: now) else { return }
        deadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, deadline - now)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
