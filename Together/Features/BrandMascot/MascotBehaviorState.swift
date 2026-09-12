import Foundation

enum MascotStaticPose: String, Equatable, Sendable {
    case idle, holding, concerned, thinking
}

/// Reviewed, low-intensity faces from the existing Rive expression catalog.
enum MascotIdleExpression: Int, CaseIterable, Sendable {
    case softHappy = 2, curious = 21
}

struct MascotFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case acknowledge, celebrate, noticeResult
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
    var expression = 0
    var isTyping = false
    var isPlaying = false
    var staticPose: MascotStaticPose = .idle
    var feedback: MascotFeedback?
}

/// Presentation policy only. The task repositories remain the source of business state.
/// Time values are monotonic seconds, supplied by the owner so boundary tests need no sleeps.
struct MascotBehaviorState {
    static let typingPause: TimeInterval = 0.9
    static let idleExpressionDelay: ClosedRange<TimeInterval> = 6...11
    static let idleExpressionDuration: ClosedRange<TimeInterval> = 1...1.5
    static let feedbackCooldown: TimeInterval = 4

    private(set) var context = MascotContext()
    private(set) var playbackAllowed = false
    private var idleExpression: MascotIdleExpression?
    private var previousIdleExpression: MascotIdleExpression?
    private var idleExpressionDeadline: TimeInterval?
    private var idleExpressionNotBefore: TimeInterval = 0
    private var typingUntil: TimeInterval?
    private var feedbackUntil: TimeInterval?
    private var feedbackAllowedAfter: TimeInterval = 0
    private var feedback: MascotFeedback?

    private var isPlaying: Bool { context.isVisible && playbackAllowed }
    private var canShowIdleExpression: Bool {
        isPlaying && !context.isEditing && !context.isProcessing
            && !context.hasOverdueTasks && !context.isInteracting
    }

    mutating func updateContext(_ newContext: MascotContext, at now: TimeInterval) {
        var nextContext = newContext
        if !nextContext.isVisible { nextContext.isInteracting = false }
        guard nextContext != context else { return }
        let previous = context
        context = nextContext
        if previous.isVisible != context.isVisible || previous.isEditing != context.isEditing {
            typingUntil = nil
        }
        // Changing the persistent goal invalidates a short-lived response to the previous goal.
        feedback = nil
        feedbackUntil = nil
        if !context.isVisible { typingUntil = nil }
        resetIdleExpression(at: now)
    }

    mutating func setPlaybackAllowed(_ allowed: Bool, at now: TimeInterval) {
        guard playbackAllowed != allowed else { return }
        playbackAllowed = allowed
        if !allowed { context.isInteracting = false }
        resetIdleExpression(at: now)
        typingUntil = nil
        feedback = nil
        feedbackUntil = nil
    }

    mutating func recordUserActivity(at now: TimeInterval) {
        guard context.isVisible else { return }
        resetIdleExpression(at: now)
    }

    mutating func recordTextInput(at now: TimeInterval) {
        guard isPlaying, context.isEditing else { return }
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
        case .celebrate, .noticeResult:
            guard current.mode == 0 || current.mode == 2 else { return false }
        }
        feedback = MascotFeedback(id: UUID(), kind: kind)
        feedbackUntil = now + (kind == .celebrate ? 1.8 : 0.9)
        feedbackAllowedAfter = now + Self.feedbackCooldown
        if kind != .noticeResult {
            resetIdleExpression(at: now)
        }
        return true
    }

    /// Advances only at a visible state boundary. The owner supplies randomness so tests
    /// can follow real deadlines without sleeping; missed intervals are never replayed.
    mutating func advanceIdleExpression<R: RandomNumberGenerator>(at now: TimeInterval, using random: inout R) {
        let feedbackIsActive = feedbackUntil.map { now < $0 } == true
        let isNoticingResult = feedbackIsActive && feedback?.kind == .noticeResult
        guard canShowIdleExpression, !feedbackIsActive || isNoticingResult else {
            resetIdleExpression(at: now)
            return
        }
        guard let deadline = idleExpressionDeadline else {
            idleExpressionDeadline = max(now, max(idleExpressionNotBefore, feedbackAllowedAfter))
                + Double.random(in: Self.idleExpressionDelay, using: &random)
            return
        }
        guard now >= deadline else { return }
        // A result glance layers over the current face. Let that face finish on its
        // original deadline, but do not start a new expression during the glance.
        if idleExpression != nil || isNoticingResult {
            idleExpression = nil
            idleExpressionDeadline = now + Double.random(in: Self.idleExpressionDelay, using: &random)
        } else {
            let choices = MascotIdleExpression.allCases.filter { $0 != previousIdleExpression }
            let next = choices.randomElement(using: &random)!
            idleExpression = next
            previousIdleExpression = next
            idleExpressionDeadline = now + Double.random(in: Self.idleExpressionDuration, using: &random)
        }
    }

    private mutating func resetIdleExpression(at now: TimeInterval) {
        idleExpression = nil
        idleExpressionDeadline = nil
        idleExpressionNotBefore = now
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
        } else {
            (mode, pose) = (0, .idle)
        }
        return MascotPresentation(
            mode: mode,
            expression: canShowIdleExpression && idleExpressionDeadline.map { now < $0 } == true
                ? (idleExpression?.rawValue ?? 0) : 0,
            isTyping: isPlaying && mode == 1 && typingUntil.map { now < $0 } == true,
            isPlaying: isPlaying,
            staticPose: pose,
            feedback: isPlaying && feedbackUntil.map { now < $0 } == true ? feedback : nil
        )
    }

    func nextDeadline(after now: TimeInterval) -> TimeInterval? {
        guard isPlaying else { return nil }
        return [typingUntil, feedbackUntil, canShowIdleExpression ? idleExpressionDeadline : nil]
            .compactMap { $0 }.filter { $0 > now }.min()
    }
}
