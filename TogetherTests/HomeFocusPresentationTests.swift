import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Home focus presentation foundation")
struct HomeFocusPresentationTests {
    @Test func presentationWaitsForSwiftUILayoutAndCompletedCallbackCanStartNextSession() async throws {
        let model = HomeFocusPresentationModel()
        let driver = FocusPresentationDriverSpy()
        let itemID = UUID()
        let nextCreationID = UUID()
        model.driver = driver
        model.recordAvailableFrame(CGRect(x: 0, y: 59, width: 390, height: 751))
        model.recordViewportFrame(CGRect(x: 0, y: 80, width: 390, height: 700))
        model.recordTaskFrame(
            domain: .todo,
            itemID: itemID,
            frame: CGRect(x: 0, y: 180, width: 390, height: 68)
        )

        #expect(model.presentDetail(domain: .todo, itemID: itemID, proposedHeight: 320))
        #expect(driver.presentedToken == nil)
        for _ in 0..<4 { await Task.yield() }
        let opening = try #require(driver.presentedToken)
        model.finishPresentation(using: opening)

        model.onDismissCompleted = { _ in
            _ = model.presentCreation(
                domain: .todo,
                sessionID: nextCreationID,
                proposedSize: CGSize(width: 358, height: 320)
            )
        }
        model.dismissToSource()
        let closing = try #require(driver.dismissedToken)
        model.finishDismissal(using: closing)

        #expect(model.subject == .creation(domain: .todo, sessionID: nextCreationID))
        #expect(model.phase == .transitioningIn)
    }

    @Test func focusSessionAllowsOnlyOneActiveSubject() throws {
        var session = HomeFocusSession()
        let firstItemID = UUID()

        let preparedResult = session.prepare(subject: .detail(domain: .todo, itemID: firstItemID))
        let token = try #require(preparedResult)

        #expect(session.phase == .preparing)
        #expect(session.subject == .detail(domain: .todo, itemID: firstItemID))
        let competingResult = session.prepare(subject: .creation(domain: .todo, sessionID: UUID()))
        #expect(competingResult == nil)
        #expect(session.isCurrent(token))
    }

    @Test func focusSessionRejectsStaleCompletionAfterReversal() throws {
        var session = HomeFocusSession()
        let preparedResult = session.prepare(subject: .detail(domain: .todo, itemID: UUID()))
        let prepared = try #require(preparedResult)
        let openingResult = session.beginTransitionIn(using: prepared)
        let opening = try #require(openingResult)
        let closingResult = session.beginTransitionOut()
        let closing = try #require(closingResult)

        session.finishTransitionIn(using: opening)
        #expect(session.phase == .transitioningOut)

        let reopenedResult = session.reverseTransitionOut()
        let reopened = try #require(reopenedResult)
        session.finishTransitionOut(using: closing)
        #expect(session.phase == .transitioningIn)

        session.finishTransitionIn(using: reopened)
        #expect(session.phase == .focused)
    }

    @Test func creationCommitIsTheOnlyLockedPath() throws {
        var session = HomeFocusSession()
        let preparedResult = session.prepare(subject: .creation(domain: .todo, sessionID: UUID()))
        let prepared = try #require(preparedResult)
        let openingResult = session.beginTransitionIn(using: prepared)
        let opening = try #require(openingResult)
        session.finishTransitionIn(using: opening)

        let savingResult = session.beginSaving()
        let saving = try #require(savingResult)
        #expect(session.phase == .saving)
        let closingResult = session.beginTransitionOut()
        let reversalResult = session.reverseTransitionOut()
        #expect(closingResult == nil)
        #expect(reversalResult == nil)

        let landingPreparationResult = session.finishSaving(using: saving, succeeded: true)
        let landingPreparation = try #require(landingPreparationResult)
        let landingResult = session.beginLanding(using: landingPreparation)
        let landing = try #require(landingResult)
        session.finishLanding(using: landing)

        #expect(session.phase == .idle)
        #expect(session.subject == nil)
    }

    @Test func failedCreationSaveReturnsToSameFocusedSession() throws {
        var session = HomeFocusSession()
        let creationID = UUID()
        let preparedResult = session.prepare(subject: .creation(domain: .todo, sessionID: creationID))
        let prepared = try #require(preparedResult)
        let openingResult = session.beginTransitionIn(using: prepared)
        let opening = try #require(openingResult)
        session.finishTransitionIn(using: opening)

        let savingResult = session.beginSaving()
        let saving = try #require(savingResult)
        let focusedResult = session.finishSaving(using: saving, succeeded: false)
        let focused = try #require(focusedResult)

        #expect(session.phase == .focused)
        #expect(session.subject == .creation(domain: .todo, sessionID: creationID))
        #expect(session.isCurrent(focused))
    }

    @Test func recoveryInvalidatesEarlierAnimatorCompletions() throws {
        var session = HomeFocusSession()
        let preparedResult = session.prepare(subject: .detail(domain: .todo, itemID: UUID()))
        let prepared = try #require(preparedResult)
        let openingResult = session.beginTransitionIn(using: prepared)
        let opening = try #require(openingResult)
        let recoveryResult = session.beginRecovery()
        let recovery = try #require(recoveryResult)

        session.finishTransitionIn(using: opening)
        #expect(session.phase == .recovering)

        session.finishRecovery(using: recovery)
        #expect(session.phase == .idle)
        #expect(session.subject == nil)
    }

    @Test func geometryRegistryRejectsInvalidAndForeignWindowFrames() {
        var registry = HomeFocusGeometryRegistry(windowID: UUID())
        let itemID = UUID()
        let subject = HomeFocusSubject.detail(domain: .todo, itemID: itemID)

        let foreignResult = registry.recordTaskFrame(
            subject: subject,
            frame: CGRect(x: 20, y: 100, width: 320, height: 56),
            windowID: UUID()
        )
        let invalidResult = registry.recordTaskFrame(
            subject: subject,
            frame: CGRect(x: CGFloat.nan, y: 100, width: 320, height: 56),
            windowID: registry.windowID
        )
        #expect(foreignResult == false)
        #expect(invalidResult == false)
        #expect(registry.taskFrame(for: subject) == nil)

        let validResult = registry.recordTaskFrame(
            subject: subject,
            frame: CGRect(x: 20, y: 100, width: 320, height: 56),
            windowID: registry.windowID
        )
        #expect(validResult)
        #expect(registry.taskFrame(for: subject) == CGRect(x: 20, y: 100, width: 320, height: 56))
    }

    @Test func geometryRegistryFreezesSourceAndViewportForTheSession() throws {
        let windowID = UUID()
        let itemID = UUID()
        let source = CGRect(x: 20, y: 100, width: 320, height: 56)
        let viewport = CGRect(x: 0, y: 80, width: 390, height: 700)
        let available = CGRect(x: 0, y: 59, width: 390, height: 751)
        var registry = HomeFocusGeometryRegistry(windowID: windowID)

        let subject = HomeFocusSubject.detail(domain: .todo, itemID: itemID)
        let taskResult = registry.recordTaskFrame(subject: subject, frame: source, windowID: windowID)
        let viewportResult = registry.recordViewportFrame(viewport, windowID: windowID)
        let availableResult = registry.recordAvailableFrame(available, windowID: windowID)
        #expect(taskResult)
        #expect(viewportResult)
        #expect(availableResult)
        let frozenResult = registry.freeze(for: subject)
        let frozen = try #require(frozenResult)

        let movingResult = registry.recordTaskFrame(
            subject: subject,
            frame: CGRect(x: 20, y: 240, width: 320, height: 56),
            windowID: windowID
        )
        #expect(movingResult)
        #expect(registry.frozenGeometry == frozen)
        #expect(frozen.sourceFrame == source)
        #expect(frozen.viewportFrame == viewport)
        #expect(frozen.availableFrame == available)
    }

    @Test func geometryPolicyRespectsSafeAreaAndGrowsDetailMostlyDownward() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let available = HomeFocusGeometryPolicy.availableFrame(
            in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        )
        let source = CGRect(x: 20, y: 180, width: 350, height: 56)
        let target = HomeFocusGeometryPolicy.detailTargetFrame(
            sourceFrame: source,
            proposedHeight: 360,
            availableFrame: available,
            horizontalMargin: 16,
            verticalMargin: 12
        )

        #expect(available == CGRect(x: 0, y: 59, width: 390, height: 751))
        #expect(target.minX == 16)
        #expect(target.maxX == 374)
        #expect(target.minY == source.minY)
        #expect(target.height == 360)
        #expect(available.insetBy(dx: 0, dy: 12).contains(target))
    }

    @Test func creationFocusFrameIsStableAndCenteredInsideAvailableArea() {
        let available = CGRect(x: 0, y: 59, width: 390, height: 751)
        let frame = HomeFocusGeometryPolicy.creationFocusFrame(
            proposedSize: CGSize(width: 358, height: 360),
            availableFrame: available,
            horizontalMargin: 16,
            verticalMargin: 12
        )

        #expect(frame == CGRect(x: 16, y: 254.5, width: 358, height: 360))
        #expect(available.insetBy(dx: 16, dy: 12).contains(frame))
    }

    @Test func keyboardCorrectionIsMinimalAndNeverCrossesSafeTop() {
        let available = CGRect(x: 0, y: 59, width: 390, height: 751)
        let card = CGRect(x: 16, y: 410, width: 358, height: 330)
        let keyboard = CGRect(x: 0, y: 510, width: 390, height: 334)

        let correction = HomeFocusGeometryPolicy.keyboardVerticalCorrection(
            cardFrame: card,
            keyboardFrame: keyboard,
            availableFrame: available,
            clearance: 12
        )

        #expect(correction == -242)
        #expect(card.offsetBy(dx: 0, dy: correction).minY >= available.minY + 12)
        #expect(card.offsetBy(dx: 0, dy: correction).maxY == keyboard.minY - 12)
    }

    @Test(arguments: [
        (CGRect(x: 16, y: 100, width: 358, height: 56), true),
        (CGRect(x: 16, y: 760, width: 358, height: 56), false),
        (CGRect(x: 16, y: 40, width: 358, height: 56), false),
    ])
    func landingVisibilityRequiresTheWholeTarget(
        argument: (frame: CGRect, expected: Bool)
    ) {
        let viewport = CGRect(x: 0, y: 80, width: 390, height: 700)
        #expect(
            HomeFocusGeometryPolicy.isFullyVisible(argument.frame, in: viewport)
                == argument.expected
        )
    }

    @Test func persistentRootContainerOwnsBackgroundAndFocusChildren() {
        let model = HomeFocusPresentationModel()
        let controller = HomeRootContainerController(
            rootView: Text("Background"),
            focusView: AnyView(Text("Focus")),
            focusModel: model
        )
        controller.loadViewIfNeeded()

        #expect(controller.children.count == 3)
        #expect(controller.backdropController.parent === controller)
        #expect(controller.backgroundController.parent === controller)
        #expect(controller.focusPresentationController.parent === controller)
        #expect(controller.focusPresentationController.view.isUserInteractionEnabled == false)
        #expect(controller.view.subviews.last === controller.focusPresentationController.view)
        #expect(controller.childForStatusBarStyle === controller.backgroundController)
        #expect(controller.childForStatusBarHidden === controller.backgroundController)
    }

    @Test func persistentRootContainerReleasesItsFocusChild() {
        weak var releasedFocusController: HomeFocusPresentationController?

        autoreleasepool {
            let model = HomeFocusPresentationModel()
            var controller: HomeRootContainerController<Text>? = HomeRootContainerController(
                rootView: Text("Background"),
                focusView: AnyView(Text("Focus")),
                focusModel: model
            )
            controller?.loadViewIfNeeded()
            releasedFocusController = controller?.focusPresentationController
            controller = nil
        }

        #expect(releasedFocusController == nil)
    }
}

@MainActor
private final class FocusPresentationDriverSpy: HomeFocusPresentationDriving {
    var presentedToken: HomeFocusSessionToken?
    var dismissedToken: HomeFocusSessionToken?

    func present(
        subject: HomeFocusSubject,
        sourceFrame: CGRect,
        targetFrame: CGRect,
        token: HomeFocusSessionToken
    ) {
        presentedToken = token
    }

    func dismiss(to targetFrame: CGRect, token: HomeFocusSessionToken) {
        dismissedToken = token
    }

    func land(to targetFrame: CGRect, token: HomeFocusSessionToken) {}
    func recover(token: HomeFocusSessionToken) {}
}
