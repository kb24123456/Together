import Foundation
import Observation
import SwiftUI

enum TaskMorphDomain: String, Equatable, Hashable, Sendable {
    case todo
    case periodic
}

enum TaskMorphVisualState: Equatable, Sendable {
    case compact
    case editing
    case expanded
}

enum TaskMorphSubject: Equatable, Hashable, Sendable {
    case draft(domain: TaskMorphDomain, id: UUID)
    case persisted(domain: TaskMorphDomain, id: UUID)

    var domain: TaskMorphDomain {
        switch self {
        case .draft(let domain, _), .persisted(let domain, _):
            domain
        }
    }

    var id: UUID {
        switch self {
        case .draft(_, let id), .persisted(_, let id):
            id
        }
    }

    var isDraft: Bool {
        if case .draft = self { return true }
        return false
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
    let index: Int
    let presentationID: String

    init(
        provisionalSection: TaskMorphSection,
        finalSection: TaskMorphSection? = nil,
        index: Int,
        presentationID: String
    ) {
        self.provisionalSection = provisionalSection
        self.finalSection = finalSection ?? provisionalSection
        self.index = index
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
    case heroEntering
    case active
    case saving
    case collapsing
    case relocating

    var locksMutations: Bool {
        switch self {
        case .saving, .collapsing, .relocating:
            true
        case .idle, .heroEntering, .active:
            false
        }
    }
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
    private(set) var heroSourceFrame: CGRect?
    private(set) var heroTargetFrame: CGRect?
    private(set) var heroProgress: CGFloat = 0
    private(set) var isCreationListRevealEnabled = false
    private(set) var isCreationFlow = false

    @ObservationIgnored var onDismissIntent: ((TaskMorphSubject) -> Void)?
    @ObservationIgnored var onCommitIntent: ((TaskMorphSubject) -> Void)?
    @ObservationIgnored var onCompletionIntent: ((TaskMorphSubject) -> Void)?
    @ObservationIgnored var onCreationRevealCompletionIntent: ((TaskMorphSubject, HomeMorphSessionToken) -> Void)?

    var isActive: Bool { phase != .idle }
    var isInteractive: Bool { phase == .active }
    var isCreationOverlayVisible: Bool {
        isCreationFlow && phase != .idle && phase != .relocating
    }
    var isFocusDepthActive: Bool {
        if isCreationFlow {
            return phase != .idle && phase != .relocating
        }
        return visualState == .expanded
    }
    var isHeroVisible: Bool {
        isCreationFlow && phase == .heroEntering && heroSourceFrame != nil && heroTargetFrame != nil
    }

    @discardableResult
    func beginCreation(
        domain: TaskMorphDomain,
        id: UUID,
        placement: TaskMorphPlacement,
        heroSourceFrame: CGRect?
    ) -> HomeMorphSessionToken? {
        guard phase == .idle else { return nil }
        sessionID = UUID()
        subject = .draft(domain: domain, id: id)
        isCreationFlow = true
        self.placement = placement
        errorMessage = nil
        heroTargetFrame = nil
        heroProgress = 0
        isCreationListRevealEnabled = false

        if let heroSourceFrame, Self.isValid(frame: heroSourceFrame) {
            self.heroSourceFrame = heroSourceFrame
            visualState = .compact
            return advance(to: .heroEntering)
        }

        self.heroSourceFrame = nil
        visualState = .editing
        return advance(to: .active)
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
        isCreationFlow = false
        self.placement = placement
        errorMessage = nil
        heroSourceFrame = nil
        heroTargetFrame = nil
        heroProgress = 0
        isCreationListRevealEnabled = false
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
              subject?.isDraft == false,
              visualState == .compact
        else { return false }
        visualState = .expanded
        return true
    }

    func recordHeroTargetFrame(_ frame: CGRect) {
        guard phase == .heroEntering,
              heroTargetFrame == nil,
              Self.isValid(frame: frame)
        else { return }
        heroTargetFrame = frame
    }

    func setHeroProgress(_ progress: CGFloat, using token: HomeMorphSessionToken) {
        guard phase == .heroEntering, isCurrent(token) else { return }
        heroProgress = min(max(progress, 0), 1)
    }

    func finishHero(using token: HomeMorphSessionToken) {
        guard phase == .heroEntering, isCurrent(token) else { return }
        heroProgress = 1
        heroSourceFrame = nil
        heroTargetFrame = nil
        visualState = .editing
        _ = advance(to: .active)
    }

    func requestDismissal() {
        guard phase == .active, let subject else { return }
        onDismissIntent?(subject)
    }

    func requestCommit() {
        guard phase == .active, let subject, subject.isDraft else { return }
        onCommitIntent?(subject)
    }

    func requestCompletion() {
        guard phase == .active, let subject, subject.isDraft == false else { return }
        onCompletionIntent?(subject)
    }

    func requestCreationRevealCompletion(
        _ subject: TaskMorphSubject,
        using token: HomeMorphSessionToken
    ) {
        guard isCreationFlow,
              phase == .relocating,
              self.subject == subject,
              isCurrent(token),
              isCreationListRevealEnabled
        else { return }
        onCreationRevealCompletionIntent?(subject, token)
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
        persistedSubject: TaskMorphSubject? = nil,
        finalPlacement: TaskMorphPlacement? = nil
    ) -> HomeMorphSessionToken? {
        guard phase == .saving, isCurrent(token) else { return nil }
        if let persistedSubject {
            guard persistedSubject.id == subject?.id else { return nil }
            subject = persistedSubject
        }
        if let finalPlacement {
            placement = TaskMorphPlacement(
                provisionalSection: placement?.provisionalSection ?? finalPlacement.provisionalSection,
                finalSection: finalPlacement.finalSection,
                index: finalPlacement.index,
                presentationID: finalPlacement.presentationID
            )
        }
        errorMessage = nil
        visualState = .compact
        return advance(to: .collapsing)
    }

    func beginDiscardCollapse() -> HomeMorphSessionToken? {
        guard phase == .active, subject?.isDraft == true else { return nil }
        errorMessage = nil
        visualState = .compact
        return advance(to: .collapsing)
    }

    func beginDetailCollapseAfterSave(
        using token: HomeMorphSessionToken,
        finalPlacement: TaskMorphPlacement
    ) -> HomeMorphSessionToken? {
        beginCollapseAfterSave(using: token, finalPlacement: finalPlacement)
    }

    func beginRelocating(using token: HomeMorphSessionToken) -> HomeMorphSessionToken? {
        guard phase == .collapsing, isCurrent(token) else { return nil }
        isCreationListRevealEnabled = false
        return advance(to: .relocating)
    }

    func enableCreationListReveal(using token: HomeMorphSessionToken) {
        guard isCreationFlow, phase == .relocating, isCurrent(token) else { return }
        isCreationListRevealEnabled = true
    }

    func finishRelocating(using token: HomeMorphSessionToken) {
        guard phase == .relocating, isCurrent(token) else { return }
        finishSession()
    }

    func finishCollapse(using token: HomeMorphSessionToken) {
        guard phase == .collapsing, isCurrent(token) else { return }
        finishSession()
    }

    func finishDiscard(using token: HomeMorphSessionToken) {
        guard phase == .collapsing, isCurrent(token) else { return }
        finishSession()
    }

    func recover() {
        guard phase != .idle else { return }
        finishSession()
    }

    func isActive(_ domain: TaskMorphDomain, id: UUID) -> Bool {
        isCreationFlow == false
            && subject?.domain == domain
            && subject?.id == id
            && isActive
    }

    func isCreationListRevealTarget(_ domain: TaskMorphDomain, id: UUID) -> Bool {
        isCreationFlow
            && phase == .relocating
            && subject == .persisted(domain: domain, id: id)
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
        heroSourceFrame = nil
        heroTargetFrame = nil
        heroProgress = 0
        isCreationListRevealEnabled = false
        isCreationFlow = false
    }

    private static func isValid(frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
