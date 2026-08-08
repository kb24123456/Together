import Observation
import SwiftUI
import UIKit

@MainActor
protocol HomeFocusPresentationDriving: AnyObject {
    func present(
        subject: HomeFocusSubject,
        sourceFrame: CGRect,
        targetFrame: CGRect,
        token: HomeFocusSessionToken
    )
    func dismiss(to targetFrame: CGRect, token: HomeFocusSessionToken)
    func land(to targetFrame: CGRect, token: HomeFocusSessionToken)
    func recover(token: HomeFocusSessionToken)
}

/// The single observable bridge between SwiftUI intents and the UIKit focus host.
/// Only discrete lifecycle state crosses this boundary; animation progress stays
/// inside `HomeFocusPresentationCoordinator`.
@MainActor
@Observable
final class HomeFocusPresentationModel {
    private(set) var session = HomeFocusSession()
    private(set) var subject: HomeFocusSubject?
    private(set) var landingDescriptor: HomeFocusLandingDescriptor?
    private(set) var surfaceRevision: UInt = 0
    private(set) var geometryRevision: UInt = 0
    private(set) var errorMessage: String?

    @ObservationIgnored weak var driver: HomeFocusPresentationDriving?
    @ObservationIgnored var onDismissIntent: ((HomeFocusSubject) -> Void)?
    @ObservationIgnored var onBackgroundTap: (() -> Void)?
    @ObservationIgnored var onDismissCompleted: ((HomeFocusSubject) -> Void)?
    @ObservationIgnored var onLandingCompleted: ((HomeFocusSubject) -> Void)?
    @ObservationIgnored var onRecoveryCompleted: ((HomeFocusSubject) -> Void)?
    @ObservationIgnored var onCompletionIntent: ((HomeFocusSubject) -> Void)?

    @ObservationIgnored private var registry = HomeFocusGeometryRegistry(windowID: UUID())
    @ObservationIgnored private var frozenGeometry: HomeFocusFrozenGeometry?
    @ObservationIgnored private var openingToken: HomeFocusSessionToken?
    @ObservationIgnored private var closingToken: HomeFocusSessionToken?
    @ObservationIgnored private var landingToken: HomeFocusSessionToken?
    @ObservationIgnored private var pendingLandingTarget: HomeFocusSubject?
    @ObservationIgnored private var dismissalFrame: CGRect?

    var phase: HomeFocusPhase { session.phase }
    var isActive: Bool { session.isActive }
    var isBackgroundDeemphasized: Bool { session.isActive }
    var isInteractive: Bool { session.phase == .focused }
    var isCommitLocked: Bool { session.phase.isCommitLocked }

    func replaceWindow(with id: UUID) {
        registry.replaceWindow(with: id)
    }

    func recordAvailableFrame(_ frame: CGRect) {
        _ = registry.recordAvailableFrame(frame, windowID: registry.windowID)
    }

    func recordViewportFrame(_ frame: CGRect) {
        _ = registry.recordViewportFrame(frame, windowID: registry.windowID)
    }

    func recordTaskFrame(
        domain: HomeFocusDomain,
        itemID: UUID,
        frame: CGRect
    ) {
        let target = HomeFocusSubject.detail(domain: domain, itemID: itemID)
        guard registry.recordTaskFrame(subject: target, frame: frame, windowID: registry.windowID) else { return }
        guard pendingLandingTarget == target,
              let token = landingToken,
              session.phase == .preparingLanding
        else { return }

        pendingLandingTarget = nil
        guard let landing = registry.taskFrame(for: target),
              let activeToken = session.beginLanding(using: token)
        else { return }
        landingToken = activeToken
        driver?.land(to: landing, token: activeToken)
    }

    @discardableResult
    func presentDetail(
        domain: HomeFocusDomain,
        itemID: UUID,
        proposedHeight: CGFloat,
        horizontalMargin: CGFloat = 16,
        verticalMargin: CGFloat = 12
    ) -> Bool {
        let requested = HomeFocusSubject.detail(domain: domain, itemID: itemID)
        guard let prepared = session.prepare(subject: requested),
              let geometry = registry.freeze(for: requested)
        else { return false }

        frozenGeometry = geometry
        dismissalFrame = geometry.sourceFrame
        subject = requested
        landingDescriptor = nil
        errorMessage = nil
        surfaceRevision &+= 1

        let target = HomeFocusGeometryPolicy.detailTargetFrame(
            sourceFrame: geometry.sourceFrame,
            proposedHeight: proposedHeight,
            availableFrame: geometry.availableFrame,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin
        )
        guard let opening = session.beginTransitionIn(using: prepared) else {
            resetImmediately()
            return false
        }
        openingToken = opening
        presentAfterSwiftUILayout(
            subject: requested,
            sourceFrame: geometry.sourceFrame,
            targetFrame: target,
            token: opening
        )
        return true
    }

    @discardableResult
    func presentCreation(
        domain: HomeFocusDomain,
        sessionID: UUID,
        proposedSize: CGSize,
        horizontalMargin: CGFloat = 16,
        verticalMargin: CGFloat = 16
    ) -> Bool {
        let requested = HomeFocusSubject.creation(domain: domain, sessionID: sessionID)
        guard let prepared = session.prepare(subject: requested),
              let geometry = registry.freeze(for: requested)
        else { return false }

        frozenGeometry = geometry
        subject = requested
        landingDescriptor = nil
        errorMessage = nil
        surfaceRevision &+= 1

        let target = HomeFocusGeometryPolicy.creationFocusFrame(
            proposedSize: proposedSize,
            availableFrame: geometry.availableFrame,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin
        )
        let source = CGRect(
            x: target.minX + target.width * 0.02,
            y: target.midY - 32,
            width: target.width * 0.96,
            height: 64
        )
        dismissalFrame = source
        guard let opening = session.beginTransitionIn(using: prepared) else {
            resetImmediately()
            return false
        }
        openingToken = opening
        presentAfterSwiftUILayout(
            subject: requested,
            sourceFrame: source,
            targetFrame: target,
            token: opening
        )
        return true
    }

    func finishPresentation(using token: HomeFocusSessionToken) {
        guard openingToken == token else { return }
        session.finishTransitionIn(using: token)
        openingToken = nil
    }

    func requestDismissal() {
        guard let subject else { return }
        if session.phase == .transitioningIn {
            dismissToSource()
            return
        }
        onDismissIntent?(subject)
    }

    func handleBackgroundTap() {
        onBackgroundTap?()
        requestDismissal()
    }

    func requestCompletion() {
        guard let subject, session.phase == .focused else { return }
        onCompletionIntent?(subject)
    }

    func dismissToSource() {
        guard let target = dismissalFrame,
              let token = session.beginTransitionOut()
        else { return }
        closingToken = token
        driver?.dismiss(to: target, token: token)
    }

    func beginSaving() -> HomeFocusSessionToken? {
        errorMessage = nil
        return session.beginSaving()
    }

    func finishSaving(
        using token: HomeFocusSessionToken,
        result: HomeFocusPersistenceResult
    ) {
        switch result {
        case .failed(let message):
            errorMessage = message
            _ = session.finishSaving(using: token, succeeded: false)
        case .saved(let descriptor):
            guard let preparing = session.finishSaving(using: token, succeeded: true) else { return }
            landingDescriptor = descriptor
            landingToken = preparing
            pendingLandingTarget = .detail(domain: descriptor.domain, itemID: descriptor.itemID)
            geometryRevision &+= 1
        }
    }

    func finishDismissal(using token: HomeFocusSessionToken) {
        guard closingToken == token else { return }
        let completedSubject = subject
        session.finishTransitionOut(using: token)
        resetPresentationState()
        if let completedSubject { onDismissCompleted?(completedSubject) }
    }

    func finishLanding(using token: HomeFocusSessionToken) {
        guard landingToken == token else { return }
        let completedSubject = subject
        session.finishLanding(using: token)
        resetPresentationState()
        if let completedSubject { onLandingCompleted?(completedSubject) }
    }

    func recover() {
        guard let token = session.beginRecovery() else { return }
        driver?.recover(token: token)
    }

    func finishRecovery(using token: HomeFocusSessionToken) {
        let completedSubject = subject
        session.finishRecovery(using: token)
        resetPresentationState()
        if let completedSubject { onRecoveryCompleted?(completedSubject) }
    }

    func isIdentityHidden(domain: HomeFocusDomain, itemID: UUID) -> Bool {
        guard session.isActive else { return false }
        if subject?.domain == domain, subject?.identity == itemID { return true }
        return landingDescriptor?.domain == domain && landingDescriptor?.itemID == itemID
    }

    private func presentAfterSwiftUILayout(
        subject: HomeFocusSubject,
        sourceFrame: CGRect,
        targetFrame: CGRect,
        token: HomeFocusSessionToken
    ) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.openingToken == token,
                  self.session.isCurrent(token)
            else { return }
            self.driver?.present(
                subject: subject,
                sourceFrame: sourceFrame,
                targetFrame: targetFrame,
                token: token
            )
        }
    }

    private func resetImmediately() {
        if let token = session.beginRecovery() {
            session.finishRecovery(using: token)
        }
        resetPresentationState()
    }

    private func resetPresentationState() {
        subject = nil
        landingDescriptor = nil
        errorMessage = nil
        openingToken = nil
        closingToken = nil
        landingToken = nil
        pendingLandingTarget = nil
        frozenGeometry = nil
        dismissalFrame = nil
        registry.clearFrozenGeometry()
        surfaceRevision &+= 1
    }
}
