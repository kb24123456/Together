import Foundation

enum MascotStaticPose: String, Equatable, Sendable {
    case idle, holding, concerned, thinking, doze
}

struct MascotFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case acknowledge, celebrate
    }

    let id: UUID
    let kind: Kind
}

struct MascotContext: Equatable, Sendable {
    var isVisible = false
    var isEditing = false
    var isProcessing = false
    var hasOverdueTasks = false
    var isInteracting = false
}

struct MascotPresentation: Equatable, Sendable {
    var mode = 0
    var isTyping = false
    var isPlaying = false
    var staticPose: MascotStaticPose = .idle
    var feedback: MascotFeedback?
}

/// Presentation policy only. The task repositories remain the source of business state.
/// Time values are monotonic seconds, supplied by the owner so boundary tests need no sleeps.
struct MascotBehaviorState {
    static let typingPause: TimeInterval = 0.9
    static let idleDelay: TimeInterval = 15
    static let feedbackCooldown: TimeInterval = 4

    private(set) var context = MascotContext()
    private(set) var playbackAllowed = false
    private var lastActivity: TimeInterval = 0
    private var typingUntil: TimeInterval?
    private var feedbackUntil: TimeInterval?
    private var feedbackAllowedAfter: TimeInterval = 0
    private var feedback: MascotFeedback?

    private var isPlaying: Bool { context.isVisible && playbackAllowed }

    mutating func updateContext(_ newContext: MascotContext, at now: TimeInterval) {
        var nextContext = newContext
        if !nextContext.isVisible { nextContext.isInteracting = false }
        guard nextContext != context else { return }
        let previous = context
        context = nextContext
        if previous.isVisible != context.isVisible || previous.isEditing != context.isEditing {
            typingUntil = nil
            lastActivity = now
        }
        // Changing the persistent goal invalidates a short-lived response to the previous goal.
        feedback = nil
        feedbackUntil = nil
        if !context.isVisible { typingUntil = nil }
        if previous.isProcessing != context.isProcessing || previous.hasOverdueTasks != context.hasOverdueTasks {
            lastActivity = now
        }
        if previous.isInteracting != context.isInteracting {
            lastActivity = now
        }
    }

    mutating func setPlaybackAllowed(_ allowed: Bool, at now: TimeInterval) {
        guard playbackAllowed != allowed else { return }
        playbackAllowed = allowed
        if !allowed { context.isInteracting = false }
        lastActivity = now
        typingUntil = nil
        feedback = nil
        feedbackUntil = nil
    }

    mutating func recordUserActivity(at now: TimeInterval) {
        guard context.isVisible else { return }
        lastActivity = now
    }

    mutating func recordTextInput(at now: TimeInterval) {
        guard isPlaying, context.isEditing else { return }
        lastActivity = now
        typingUntil = now + Self.typingPause
    }

    mutating func stopTyping() {
        typingUntil = nil
    }

    @discardableResult
    mutating func requestFeedback(_ kind: MascotFeedback.Kind, at now: TimeInterval) -> Bool {
        let current = presentation(at: now)
        guard current.isPlaying, now >= feedbackAllowedAfter else { return false }
        switch kind {
        case .acknowledge:
            guard current.mode == 0 else { return false }
        case .celebrate:
            guard current.mode == 0 || current.mode == 2 else { return false }
        }
        feedback = MascotFeedback(id: UUID(), kind: kind)
        feedbackUntil = now + (kind == .acknowledge ? 0.9 : 1.8)
        feedbackAllowedAfter = now + Self.feedbackCooldown
        lastActivity = now
        return true
    }

    func presentation(at now: TimeInterval) -> MascotPresentation {
        let mode: Int
        let pose: MascotStaticPose
        if context.isEditing {
            (mode, pose) = (1, .holding)
        } else if context.isProcessing {
            (mode, pose) = (3, .thinking)
        } else if context.hasOverdueTasks {
            (mode, pose) = (2, .concerned)
        } else if isPlaying, !context.isInteracting, now - lastActivity >= Self.idleDelay {
            (mode, pose) = (4, .doze)
        } else {
            (mode, pose) = (0, .idle)
        }
        return MascotPresentation(
            mode: mode,
            isTyping: isPlaying && mode == 1 && typingUntil.map { now < $0 } == true,
            isPlaying: isPlaying,
            staticPose: pose,
            feedback: isPlaying && feedbackUntil.map { now < $0 } == true ? feedback : nil
        )
    }

    func nextDeadline(after now: TimeInterval) -> TimeInterval? {
        guard isPlaying else { return nil }
        var deadlines = [typingUntil, feedbackUntil].compactMap { $0 }.filter { $0 > now }
        if !context.isEditing && !context.isProcessing && !context.hasOverdueTasks && !context.isInteracting {
            let idleDeadline = lastActivity + Self.idleDelay
            if idleDeadline > now { deadlines.append(idleDeadline) }
        }
        return deadlines.min()
    }
}
