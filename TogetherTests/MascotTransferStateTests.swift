import Foundation
import CoreGraphics
import Testing
@testable import Together

@MainActor
struct MascotTransferStateTests {
    @Test func openingAndReturningSettleAtTheirDestinations() {
        var state = MascotTransferState()
        let editor = MascotSurface.editor(UUID())
        #expect(state.settledSurface == .home)
        #expect(state.transition == nil)

        let opening = state.begin(from: .home, to: editor)
        #expect(state.settledSurface == .home)
        #expect(state.transition == opening)
        #expect(state.complete(id: opening.id, cancelled: false) == editor)
        #expect(state.settledSurface == editor)
        #expect(state.transition == nil)

        let returning = state.begin(from: editor, to: .home)
        #expect(state.complete(id: returning.id, cancelled: false) == .home)
        #expect(state.settledSurface == .home)
        #expect(state.transition == nil)
        #expect(state.complete(id: returning.id, cancelled: false) == nil)
    }

    @Test func cancelledDismissalRestoresTheEditorAndAllowsAnotherReturn() {
        var state = MascotTransferState()
        let editor = MascotSurface.editor(UUID())
        state.settle(at: editor)
        let firstReturn = state.begin(from: editor, to: .home)

        #expect(state.complete(id: firstReturn.id, cancelled: true) == editor)
        #expect(state.settledSurface == editor)
        #expect(state.transition == nil)
        let nextReturn = state.begin(from: editor, to: .home)
        #expect(nextReturn.id != firstReturn.id)
        #expect(state.complete(id: firstReturn.id, cancelled: false) == nil)
        #expect(state.transition == nextReturn)
        #expect(state.complete(id: nextReturn.id, cancelled: false) == .home)
    }

    @Test func cancelledOpeningRestoresItsSource() {
        var state = MascotTransferState()
        let opening = state.begin(from: .home, to: .editor(UUID()))
        #expect(state.complete(id: opening.id, cancelled: true) == .home)
        #expect(state.settledSurface == .home)
        #expect(state.transition == nil)
    }

    @Test func replacementRejectsThePreviousTransitionsCallbacks() {
        var state = MascotTransferState()
        let editor = MascotSurface.editor(UUID())
        let opening = state.begin(from: .home, to: editor)
        let returning = state.begin(from: editor, to: .home)
        #expect(opening.id != returning.id)
        #expect(state.complete(id: opening.id, cancelled: false) == nil)
        #expect(state.complete(id: opening.id, cancelled: true) == nil)
        #expect(state.transition == returning)
        #expect(state.complete(id: returning.id, cancelled: true) == editor)
    }

    @Test func repeatedRegistrationKeepsTheSameActiveTransition() {
        var state = MascotTransferState()
        let editor = MascotSurface.editor(UUID())
        let first = state.begin(from: .home, to: editor)
        let repeated = state.begin(from: .home, to: editor)
        #expect(first == repeated)
        #expect(state.transition?.id == first.id)
        #expect(state.complete(id: first.id, cancelled: false) == editor)
    }

    @Test func settlingDirectlyInvalidatesAStillPendingTransition() {
        var state = MascotTransferState()
        let opening = state.begin(from: .home, to: .editor(UUID()))
        let actualSurface = MascotSurface.editor(UUID())
        state.settle(at: actualSurface)
        #expect(state.transition == nil)
        #expect(state.settledSurface == actualSurface)
        #expect(state.complete(id: opening.id, cancelled: false) == nil)
        #expect(state.settledSurface == actualSurface)
    }

    @Test func geometryAccountsForNonzeroBoundsAndIndependentScales() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 200)
        let frame = CGRect(x: 50, y: 80, width: 200, height: 100)
        let anchor = CGRect(x: 30, y: 60, width: 20, height: 40)
        #expect(MascotTransferGeometry.map(anchor, from: bounds, to: frame)
            == CGRect(x: 90, y: 100, width: 40, height: 20))
        #expect(MascotTransferGeometry.map(anchor, from: bounds, to: bounds) == anchor)
    }

    @Test func geometryRejectsZeroNegativeAndNonfiniteInputs() {
        let valid = CGRect(x: 0, y: 0, width: 40, height: 40)
        let invalid: [CGRect] = [
            .zero,
            .null,
            .infinite,
            CGRect(x: 0, y: 0, width: 0, height: 40),
            CGRect(x: 0, y: 0, width: 40, height: 0),
            CGRect(x: 0, y: 0, width: -1, height: 40),
            CGRect(x: CGFloat.nan, y: 0, width: 40, height: 40),
            CGRect(x: 0, y: CGFloat.infinity, width: 40, height: 40),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 40)
        ]
        for rect in invalid {
            #expect(MascotTransferGeometry.map(valid, from: rect, to: valid) == nil)
            #expect(MascotTransferGeometry.map(valid, from: valid, to: rect) == nil)
            #expect(MascotTransferGeometry.map(rect, from: valid, to: valid) == nil)
        }
    }

    @Test func geometryRejectsOverflowEvenWhenInputsAreFinite() {
        let anchor = CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: 1, height: 1)
        let bounds = CGRect(x: -CGFloat.greatestFiniteMagnitude, y: 0, width: 1, height: 1)
        let frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        #expect(MascotTransferGeometry.map(anchor, from: bounds, to: frame) == nil)
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
struct MascotNativeTransferTests {
    @Test func oneArtworkKeepsItsIdentityThroughLiftDockAndReturn() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let artwork = fixture.visual.artwork

        #expect(artwork.superview === fixture.home)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.home.frame)

        fixture.visual.prepare(from: .home, to: fixture.editor.surface)
        #expect(artwork.superview !== fixture.home)
        #expect(artwork.superview !== fixture.editor)
        #expect(artwork.window === fixture.window)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.home.frame)

        fixture.visual.arrive(at: fixture.editor.surface)
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === fixture.editor)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.editor.frame)

        fixture.visual.prepare(from: fixture.editor.surface, to: .home)
        fixture.visual.arrive(at: .home)
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === fixture.home)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.home.frame)
    }

    @Test func disabledLayoutDoesNotMoveTheArtworkBeforeAnimationsAreEnabled() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let visual = fixture.visual
        visual.update(
            rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
            playbackAllowed: false, motionAllowed: true, visible: true
        )
        visual.prepare(from: .home, to: fixture.editor.surface)
        let sourceFrame = visual.artwork.frame
        UIView.performWithoutAnimation {
            visual.arrive(at: fixture.editor.surface)
            visual.arrive(at: fixture.editor.surface)
            #expect(visual.artwork.superview !== fixture.editor)
            expectSameFrame(visual.artwork.frame, sourceFrame)
        }

        // A committed return supersedes the queued entrance before the next main turn.
        visual.prepare(from: fixture.editor.surface, to: .home)
        visual.update(
            rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
            playbackAllowed: false, motionAllowed: false, visible: true
        )
        visual.arrive(at: .home)
        #expect(visual.artwork.superview === fixture.home)
    }

    @Test func unregisteringAnOldAnchorDoesNotDetachTheReplacement() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let artwork = fixture.visual.artwork
        let replacement = MascotAnchorView(surface: .home)
        replacement.frame = CGRect(x: 240, y: 60, width: 48, height: 48)
        fixture.window.addSubview(replacement)
        fixture.visual.register(replacement)
        #expect(artwork.superview === replacement)

        fixture.visual.unregister(fixture.home)
        fixture.home.removeFromSuperview()
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === replacement)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), replacement.frame)
    }

    @Test func aLateDestinationAnchorRecoversTheSameArtworkAfterFailedDocking() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let artwork = fixture.visual.artwork
        fixture.visual.unregister(fixture.editor)
        fixture.editor.removeFromSuperview()

        fixture.visual.prepare(from: .home, to: fixture.editor.surface)
        fixture.visual.arrive(at: fixture.editor.surface)
        #expect(artwork.superview == nil)
        #expect(artworkCount(in: fixture.window) == 0)

        fixture.window.addSubview(fixture.editor)
        fixture.visual.register(fixture.editor)
        fixture.visual.anchorChanged(fixture.editor)
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === fixture.editor)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.editor.frame)
    }

    @Test func cancelledUnregisteredReturnRedocksAtTheEditorAndAllowsAnotherReturn() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let artwork = fixture.visual.artwork
        fixture.visual.prepare(from: .home, to: fixture.editor.surface)
        fixture.visual.arrive(at: fixture.editor.surface)
        let dockedWindowChildren = Set(fixture.window.subviews.map(ObjectIdentifier.init))

        fixture.visual.prepare(from: fixture.editor.surface, to: .home)
        #expect(artwork.superview !== fixture.editor)
        // Without a registered native clock, reappearing at the source means cancellation.
        fixture.visual.arrive(at: fixture.editor.surface)
        #expect(artwork.superview === fixture.editor)
        #expect(artworkCount(in: fixture.window) == 1)
        #expect(Set(fixture.window.subviews.map(ObjectIdentifier.init)) == dockedWindowChildren)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.editor.frame)

        fixture.visual.prepare(from: fixture.editor.surface, to: .home)
        fixture.visual.arrive(at: .home)
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === fixture.home)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.home.frame)
    }

    @Test func aReadyDestinationDocksWithoutAnySourceAnchorOrCachedFrame() {
        let window = makeMascotTestWindow()
        defer { for view in window.subviews { view.removeFromSuperview() } }
        let visual = MascotVisualTransfer()
        let artwork = visual.artwork
        let editor = MascotAnchorView(surface: .editor(UUID()))
        editor.frame = CGRect(x: 120, y: 70, width: 42, height: 42)
        window.addSubview(editor)
        visual.update(
            rive: nil, animatedArtwork: false, staticAsset: "MascotHolding",
            playbackAllowed: false, motionAllowed: false, visible: true
        )
        visual.register(editor)
        #expect(artwork.superview == nil)

        visual.prepare(from: .home, to: editor.surface)
        visual.arrive(at: editor.surface)
        #expect(visual.artwork === artwork)
        #expect(artwork.superview === editor)
        #expect(artworkCount(in: window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: window), editor.frame)
    }

    @Test func cachedDestinationGeometryDoesNotLeaveAnUndockedArtworkInTheWindow() {
        let fixture = TransferWindowFixture()
        defer { fixture.removeFromWindow() }
        let artwork = fixture.visual.artwork
        fixture.visual.prepare(from: .home, to: fixture.editor.surface)
        fixture.visual.arrive(at: fixture.editor.surface)
        fixture.visual.prepare(from: fixture.editor.surface, to: .home)
        fixture.visual.arrive(at: .home)
        fixture.visual.unregister(fixture.editor)
        fixture.editor.removeFromSuperview()
        let originalWindowChildren = Set(fixture.window.subviews.map(ObjectIdentifier.init))

        fixture.visual.prepare(from: .home, to: fixture.editor.surface)
        fixture.visual.arrive(at: fixture.editor.surface)
        #expect(artwork.superview == nil)
        #expect(artworkCount(in: fixture.window) == 0)
        #expect(Set(fixture.window.subviews.map(ObjectIdentifier.init)) == originalWindowChildren)

        fixture.window.addSubview(fixture.editor)
        fixture.visual.register(fixture.editor)
        fixture.visual.anchorChanged(fixture.editor)
        #expect(fixture.visual.artwork === artwork)
        #expect(artwork.superview === fixture.editor)
        #expect(artworkCount(in: fixture.window) == 1)
        expectSameFrame(artwork.convert(artwork.bounds, to: fixture.window), fixture.editor.frame)
    }

    private func artworkCount(in view: UIView) -> Int {
        (view is MascotArtworkView ? 1 : 0) + view.subviews.reduce(0) {
            $0 + artworkCount(in: $1)
        }
    }

    private func expectSameFrame(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.origin.x - expected.origin.x) < 0.001)
        #expect(abs(actual.origin.y - expected.origin.y) < 0.001)
        #expect(abs(actual.width - expected.width) < 0.001)
        #expect(abs(actual.height - expected.height) < 0.001)
    }
}

@MainActor
struct MascotSessionArrivalTests {
    @Test func entranceChangesToEditingBeforeTheArtworkDocks() {
        let fixture = SessionArrivalWindowFixture(includeEditor: true)
        defer { fixture.removeFromWindow() }
        let session = fixture.session

        #expect(session.animationAllowed == false)
        #expect(session.controller.mode == 2)
        #expect(session.beginEditing(id: fixture.editorID) == true)
        #expect(session.ownership.isEntering)
        #expect(session.ownership.hasArrivedAtEditor == false)
        #expect(session.controller.mode == 1)
        #expect(fixture.editor.subviews.contains { $0 is MascotArtworkView } == false)

        // Home updates must not interrupt the editor pose while the same artwork travels.
        session.updateHomeContext(MascotContext(isVisible: false))
        #expect(session.controller.mode == 1)
        #expect(session.staticAssetName(for: fixture.editor.surface) == "MascotHolding")
        session.editorDidAppear(id: fixture.editorID)

        #expect(fixture.editor.subviews.contains { $0 is MascotArtworkView })
        #expect(session.ownership.hasArrivedAtEditor)
        #expect(session.ownership.isEntering == false)
        #expect(session.controller.mode == 1)
        #expect(session.controller.isTyping == false)
        #expect(session.runtime.rive == nil)
    }

    @Test func appearanceCallbacksWaitForTheActualEditorAnchor() {
        let fixture = SessionArrivalWindowFixture(includeEditor: false)
        defer { fixture.removeFromWindow() }
        let session = fixture.session
        #expect(session.beginEditing(id: fixture.editorID) == true)

        session.editorDidAppear(id: UUID())
        session.editorDidAppear(id: fixture.editorID)
        session.editorDidAppear(id: fixture.editorID)
        #expect(session.controller.mode == 1)
        #expect(session.ownership.isEntering)
        #expect(session.ownership.hasArrivedAtEditor == false)

        // Registering the real destination completes the pending transfer without another appearance.
        fixture.addEditorToWindow()
        #expect(fixture.editor.subviews.contains { $0 is MascotArtworkView })
        #expect(session.ownership.hasArrivedAtEditor)
        #expect(session.controller.mode == 1)
        session.editorDidAppear(id: UUID())
        session.editorDidAppear(id: fixture.editorID)
        #expect(session.ownership.editorID == fixture.editorID)
        #expect(session.ownership.hasArrivedAtEditor)
        #expect(session.controller.mode == 1)
        #expect(session.runtime.rive == nil)
    }

    @Test func returningBeforeDockingRejectsLateArrivalAndWriting() {
        let fixture = SessionArrivalWindowFixture(includeEditor: false)
        defer { fixture.removeFromWindow() }
        let session = fixture.session
        #expect(session.beginEditing(id: fixture.editorID) == true)
        session.editorDidAppear(id: fixture.editorID)
        session.recordTextInput(from: fixture.editor.surface)
        session.beginReturn(id: fixture.editorID)
        fixture.addEditorToWindow()
        session.editorDidAppear(id: fixture.editorID)
        session.recordTextInput(from: fixture.editor.surface)

        #expect(session.ownership.isReturning)
        #expect(session.ownership.hasArrivedAtEditor == false)
        #expect(session.controller.mode == 2)
        #expect(session.controller.isTyping == false)

        session.finishEditing(id: fixture.editorID)
        session.editorDidAppear(id: fixture.editorID)
        session.recordTextInput(from: fixture.editor.surface)
        #expect(session.ownership.surface == .home)
        #expect(session.ownership.hasArrivedAtEditor == false)
        #expect(fixture.home.subviews.contains { $0 is MascotArtworkView })
        #expect(fixture.editor.subviews.contains { $0 is MascotArtworkView } == false)
        #expect(session.controller.mode == 2)
        #expect(session.controller.isTyping == false)
        #expect(session.runtime.rive == nil)
    }
}

@MainActor
private func makeMascotTestWindow() -> UIWindow {
    let window = UIWindow()
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    return window
}

@MainActor
private struct SessionArrivalWindowFixture {
    // A hidden, scene-less window exercises attachment without presenting application UI.
    let window = makeMascotTestWindow()
    let session = MascotPlaybackSession()
    let editorID = UUID()
    let home = MascotAnchorView(surface: .home)
    let editor: MascotAnchorView

    init(includeEditor: Bool) {
        editor = MascotAnchorView(surface: .editor(editorID))
        home.frame = CGRect(x: 310, y: 60, width: 56, height: 56)
        editor.frame = CGRect(x: 120, y: 70, width: 42, height: 42)
        window.addSubview(home)
        home.attach(to: session)
        if includeEditor { addEditorToWindow() }
        session.updateHomeContext(MascotContext(isVisible: true, hasOverdueTasks: true))
    }

    func addEditorToWindow() {
        window.addSubview(editor)
        editor.attach(to: session)
    }

    func removeFromWindow() {
        home.detach()
        editor.detach()
        for view in window.subviews { view.removeFromSuperview() }
    }
}

@MainActor
private struct TransferWindowFixture {
    let window = makeMascotTestWindow()
    let visual = MascotVisualTransfer()
    let home = MascotAnchorView(surface: .home)
    let editor = MascotAnchorView(surface: .editor(UUID()))

    init() {
        home.frame = CGRect(x: 310, y: 60, width: 56, height: 56)
        editor.frame = CGRect(x: 120, y: 70, width: 42, height: 42)
        window.addSubview(home)
        window.addSubview(editor)
        visual.update(
            rive: nil, animatedArtwork: false, staticAsset: "MascotIdle",
            playbackAllowed: false, motionAllowed: false, visible: true
        )
        visual.register(home)
        visual.register(editor)
    }

    func removeFromWindow() {
        for view in window.subviews { view.removeFromSuperview() }
    }
}
#endif
