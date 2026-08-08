import Foundation

enum HomeFocusDomain: String, Equatable, Hashable, Sendable {
    case todo
    case periodic
}

enum HomeFocusSubject: Equatable, Hashable, Sendable {
    case detail(domain: HomeFocusDomain, itemID: UUID)
    case creation(domain: HomeFocusDomain, sessionID: UUID)

    var domain: HomeFocusDomain {
        switch self {
        case .detail(let domain, _), .creation(let domain, _):
            domain
        }
    }

    var identity: UUID {
        switch self {
        case .detail(_, let itemID):
            itemID
        case .creation(_, let sessionID):
            sessionID
        }
    }
}

enum HomeFocusSection: Equatable, Hashable, Sendable {
    case todo(dayStart: Date?, isUnscheduled: Bool)
    case todoCompleted(dayStart: Date)
    case periodic(cycle: PeriodicCycle)
}

struct HomeFocusLandingDescriptor: Equatable, Hashable, Sendable {
    let domain: HomeFocusDomain
    let itemID: UUID
    let section: HomeFocusSection
    let index: Int
    let presentationID: String
}

nonisolated struct HomeFocusFrameObservation: Equatable, Sendable {
    let frame: CGRect
    let revision: UInt
}

enum HomeFocusPersistenceResult: Equatable, Sendable {
    case saved(HomeFocusLandingDescriptor)
    case failed(message: String)
}

enum HomeFocusPhase: Equatable, Sendable {
    case idle
    case preparing
    case transitioningIn
    case focused
    case transitioningOut
    case saving
    case preparingLanding
    case landing
    case recovering

    var isCommitLocked: Bool {
        switch self {
        case .saving, .preparingLanding, .landing:
            true
        case .idle, .preparing, .transitioningIn, .focused, .transitioningOut, .recovering:
            false
        }
    }
}

struct HomeFocusSessionToken: Equatable, Sendable {
    let sessionID: UUID
    let revision: UInt
}

struct HomeFocusSession: Equatable, Sendable {
    private(set) var sessionID: UUID?
    private(set) var subject: HomeFocusSubject?
    private(set) var phase: HomeFocusPhase = .idle
    private(set) var revision: UInt = 0

    var isActive: Bool {
        phase != .idle
    }

    mutating func prepare(
        subject: HomeFocusSubject,
        sessionID requestedSessionID: UUID = UUID()
    ) -> HomeFocusSessionToken? {
        guard phase == .idle else { return nil }
        sessionID = requestedSessionID
        self.subject = subject
        return advance(to: .preparing)
    }

    mutating func beginTransitionIn(
        using token: HomeFocusSessionToken
    ) -> HomeFocusSessionToken? {
        guard phase == .preparing, isCurrent(token) else { return nil }
        return advance(to: .transitioningIn)
    }

    mutating func finishTransitionIn(using token: HomeFocusSessionToken) {
        guard phase == .transitioningIn, isCurrent(token) else { return }
        _ = advance(to: .focused)
    }

    mutating func beginTransitionOut() -> HomeFocusSessionToken? {
        guard phase == .focused || phase == .transitioningIn else { return nil }
        return advance(to: .transitioningOut)
    }

    mutating func reverseTransitionOut() -> HomeFocusSessionToken? {
        guard phase == .transitioningOut else { return nil }
        return advance(to: .transitioningIn)
    }

    mutating func finishTransitionOut(using token: HomeFocusSessionToken) {
        guard phase == .transitioningOut, isCurrent(token) else { return }
        finishSession()
    }

    mutating func beginSaving() -> HomeFocusSessionToken? {
        guard phase == .focused,
              subject != nil
        else { return nil }
        return advance(to: .saving)
    }

    mutating func finishSaving(
        using token: HomeFocusSessionToken,
        succeeded: Bool
    ) -> HomeFocusSessionToken? {
        guard phase == .saving, isCurrent(token) else { return nil }
        return advance(to: succeeded ? .preparingLanding : .focused)
    }

    mutating func beginLanding(
        using token: HomeFocusSessionToken
    ) -> HomeFocusSessionToken? {
        guard phase == .preparingLanding, isCurrent(token) else { return nil }
        return advance(to: .landing)
    }

    mutating func finishLanding(using token: HomeFocusSessionToken) {
        guard phase == .landing, isCurrent(token) else { return }
        finishSession()
    }

    mutating func beginRecovery() -> HomeFocusSessionToken? {
        guard phase != .idle, phase != .recovering else { return nil }
        return advance(to: .recovering)
    }

    mutating func finishRecovery(using token: HomeFocusSessionToken) {
        guard phase == .recovering, isCurrent(token) else { return }
        finishSession()
    }

    func isCurrent(_ token: HomeFocusSessionToken) -> Bool {
        sessionID == token.sessionID && revision == token.revision
    }

    @discardableResult
    private mutating func advance(to nextPhase: HomeFocusPhase) -> HomeFocusSessionToken? {
        guard let sessionID else { return nil }
        revision &+= 1
        phase = nextPhase
        return HomeFocusSessionToken(sessionID: sessionID, revision: revision)
    }

    private mutating func finishSession() {
        revision &+= 1
        sessionID = nil
        subject = nil
        phase = .idle
    }
}
