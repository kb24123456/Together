import Foundation
import Observation
import SwiftUI

enum TaskMorphDomain: String, Equatable, Hashable, Sendable {
    case todo
    case periodic
}

enum TaskMorphVisualState: Equatable, Sendable {
    case compact
    case expanded
}

enum TaskMorphSubject: Equatable, Hashable, Sendable {
    case persisted(domain: TaskMorphDomain, id: UUID)

    var domain: TaskMorphDomain {
        switch self {
        case .persisted(let domain, _):
            domain
        }
    }

    var id: UUID {
        switch self {
        case .persisted(_, let id):
            id
        }
    }
}

enum TaskMorphSection: Equatable, Hashable, Sendable {
    case todo(dayStart: Date?, isUnscheduled: Bool)
    case todoCompleted(dayStart: Date)
    case periodic(cycle: PeriodicCycle)
}

struct TaskMorphPlacement: Equatable, Hashable, Sendable {
    let provisionalSection: TaskMorphSection
    let finalSection: TaskMorphSection
    let provisionalIndex: Int
    let index: Int
    let provisionalPresentationID: String
    let presentationID: String

    init(
        provisionalSection: TaskMorphSection,
        finalSection: TaskMorphSection? = nil,
        provisionalIndex: Int? = nil,
        index: Int,
        provisionalPresentationID: String? = nil,
        presentationID: String
    ) {
        self.provisionalSection = provisionalSection
        self.finalSection = finalSection ?? provisionalSection
        self.provisionalIndex = provisionalIndex ?? index
        self.index = index
        self.provisionalPresentationID = provisionalPresentationID ?? presentationID
        self.presentationID = presentationID
    }

    func requiresRelocation(to destination: TaskMorphPlacement) -> Bool {
        finalSection != destination.finalSection
            || index != destination.index
            || presentationID != destination.presentationID
    }
}

enum TaskMorphPersistenceResult: Equatable, Sendable {
    case saved(TaskMorphPlacement)
    case failed(message: String)
}

enum HomeMorphPhase: Equatable, Sendable {
    case idle
    case active
    case saving
    case collapsing
    case relocating

    var locksMutations: Bool {
        switch self {
        case .saving, .collapsing, .relocating:
            true
        case .idle, .active:
            false
        }
    }
}

enum HomeMorphDetailPresentationIntent: Equatable, Sendable {
    case compact
    case expanded
}

struct HomeMorphSessionToken: Equatable, Sendable {
    let sessionID: UUID
    let revision: UInt
}

@MainActor
@Observable
final class HomeMorphSession {
    private(set) var sessionID: UUID?
    private(set) var revision: UInt = 0
    private(set) var subject: TaskMorphSubject?
    private(set) var visualState: TaskMorphVisualState = .compact
    private(set) var phase: HomeMorphPhase = .idle
    private(set) var placement: TaskMorphPlacement?
    private(set) var errorMessage: String?
    private(set) var detailPresentationIntent: HomeMorphDetailPresentationIntent = .compact
    private var detailSourcePlacement: TaskMorphPlacement?

    @ObservationIgnored var onDismissIntent: ((TaskMorphSubject) -> Void)?
    @ObservationIgnored var onCompletionIntent: ((TaskMorphSubject) -> Void)?
    @ObservationIgnored var onDetailCollapseCompletionIntent: ((TaskMorphSubject, HomeMorphSessionToken) -> Void)?

    var isActive: Bool { phase != .idle }
    var isInteractive: Bool { phase == .active }
    var isDetailFocusDepthActive: Bool {
        visualState == .expanded
    }
    var isFocusDepthActive: Bool {
        isDetailFocusDepthActive
    }
    @discardableResult
    func prepareExpansion(
        domain: TaskMorphDomain,
        id: UUID,
        placement: TaskMorphPlacement
    ) -> HomeMorphSessionToken? {
        guard phase == .idle else { return nil }
        sessionID = UUID()
        subject = .persisted(domain: domain, id: id)
        self.placement = placement
        errorMessage = nil
        detailSourcePlacement = placement
        detailPresentationIntent = .expanded
        // First establish ownership while the real container is still compact.
        // The caller advances to `.expanded` in a following render turn so the
        // opening animation is the exact geometric inverse of collapse.
        visualState = .compact
        return advance(to: .active)
    }

    @discardableResult
    func activatePreparedExpansion(using token: HomeMorphSessionToken) -> Bool {
        guard phase == .active,
              isCurrent(token),
              visualState == .compact
        else { return false }
        visualState = .expanded
        return true
    }

    func requestDismissal() {
        guard let subject else { return }
        detailPresentationIntent = .compact
        guard phase == .active else { return }
        onDismissIntent?(subject)
    }

    func requestCompletion() {
        guard phase == .active, let subject else { return }
        detailPresentationIntent = .compact
        onCompletionIntent?(subject)
    }

    @discardableResult
    func requestExpansionRetention(domain: TaskMorphDomain, id: UUID) -> Bool {
        guard subject == .persisted(domain: domain, id: id),
              phase == .saving || phase == .collapsing
        else { return false }
        detailPresentationIntent = .expanded
        return true
    }

    func beginSaving() -> HomeMorphSessionToken? {
        guard phase == .active, subject != nil else { return nil }
        errorMessage = nil
        return advance(to: .saving)
    }

    func failSaving(using token: HomeMorphSessionToken, message: String) {
        guard phase == .saving, isCurrent(token) else { return }
        errorMessage = message
        _ = advance(to: .active)
    }

    func beginCollapseAfterSave(
        using token: HomeMorphSessionToken,
        finalPlacement: TaskMorphPlacement? = nil
    ) -> HomeMorphSessionToken? {
        guard phase == .saving, isCurrent(token) else { return nil }
        if let finalPlacement {
            placement = TaskMorphPlacement(
                provisionalSection: placement?.provisionalSection ?? finalPlacement.provisionalSection,
                finalSection: finalPlacement.finalSection,
                provisionalIndex: placement?.provisionalIndex,
                index: finalPlacement.index,
                provisionalPresentationID: placement?.provisionalPresentationID,
                presentationID: finalPlacement.presentationID
            )
        }
        errorMessage = nil
        detailPresentationIntent = .compact
        visualState = .compact
        return advance(to: .collapsing)
    }

    func beginDetailCollapseAfterSave(
        using token: HomeMorphSessionToken,
        finalPlacement: TaskMorphPlacement
    ) -> HomeMorphSessionToken? {
        beginCollapseAfterSave(using: token, finalPlacement: finalPlacement)
    }

    @discardableResult
    func finishSavingKeepingDetail(
        using token: HomeMorphSessionToken,
        finalPlacement: TaskMorphPlacement
    ) -> HomeMorphSessionToken? {
        guard phase == .saving,
              isCurrent(token),
              detailPresentationIntent == .expanded
        else { return nil }
        placement = finalPlacement
        visualState = .expanded
        return advance(to: .active)
    }

    @discardableResult
    func reverseDetailCollapse(
        domain: TaskMorphDomain,
        id: UUID
    ) -> HomeMorphSessionToken? {
        guard phase == .collapsing,
              subject == .persisted(domain: domain, id: id)
        else { return nil }
        if let detailSourcePlacement {
            placement = detailSourcePlacement
        }
        errorMessage = nil
        detailPresentationIntent = .expanded
        visualState = .expanded
        return advance(to: .active)
    }

    func beginRelocating(using token: HomeMorphSessionToken) -> HomeMorphSessionToken? {
        guard phase == .collapsing, isCurrent(token) else { return nil }
        return advance(to: .relocating)
    }

    func finishRelocating(using token: HomeMorphSessionToken) {
        guard phase == .relocating, isCurrent(token) else { return }
        finishSession()
    }

    func finishCollapse(using token: HomeMorphSessionToken) {
        guard phase == .collapsing, isCurrent(token) else { return }
        finishSession()
    }

    var detailRequiresRelocation: Bool {
        guard let detailSourcePlacement, let placement else { return true }
        return detailSourcePlacement.requiresRelocation(to: placement)
    }

    func requestDetailCollapseCompletion(
        _ subject: TaskMorphSubject,
        using token: HomeMorphSessionToken
    ) {
        guard phase == .collapsing,
              visualState == .compact,
              self.subject == subject,
              isCurrent(token)
        else { return }
        onDetailCollapseCompletionIntent?(subject, token)
    }

    func recover() {
        guard phase != .idle else { return }
        finishSession()
    }

    func isActive(_ domain: TaskMorphDomain, id: UUID) -> Bool {
        subject?.domain == domain
            && subject?.id == id
            && isActive
    }

    func currentToken() -> HomeMorphSessionToken? {
        guard let sessionID else { return nil }
        return HomeMorphSessionToken(sessionID: sessionID, revision: revision)
    }

    func isCurrent(_ token: HomeMorphSessionToken) -> Bool {
        sessionID == token.sessionID && revision == token.revision
    }

    @discardableResult
    private func advance(to nextPhase: HomeMorphPhase) -> HomeMorphSessionToken? {
        guard let sessionID else { return nil }
        revision &+= 1
        phase = nextPhase
        return HomeMorphSessionToken(sessionID: sessionID, revision: revision)
    }

    private func finishSession() {
        revision &+= 1
        sessionID = nil
        subject = nil
        visualState = .compact
        phase = .idle
        placement = nil
        errorMessage = nil
        detailSourcePlacement = nil
        detailPresentationIntent = .compact
    }
}
