import Foundation
import CoreGraphics
import Testing
@testable import Together

struct MascotConfirmationTests {
    @Test func drawingKeepsEyesUntilExpansionAndMeetsTheDrawingSeed() {
        #expect(MascotConfirmationMotion.entering(at: 0) == MascotConfirmationMotion.idle)
        #expect(MascotConfirmationMotion.entering(at: 0.18) == MascotConfirmationMotion.idle)
        #expect(MascotConfirmationMotion.retractionDelay > MascotConfirmationMotion.restorationDuration)
        let before = MascotConfirmationMotion.entering(at: 0.32 - 0.000001)
        let after = MascotConfirmationMotion.entering(at: 0.32)
        for point in before.main + before.secondary + after.main + after.secondary {
            #expect(hypot(point.x - MascotConfirmationMotion.start.x,
                          point.y - MascotConfirmationMotion.start.y) < 0.0001)
        }
    }

    @Test func shortStrokeFinishesBeforeLongStrokeGrowsAndTheCheckHolds() {
        let early = MascotConfirmationMotion.entering(at: 0.38)
        #expect(early.main[1] == early.main[2])
        #expect(early.main[1].y > MascotConfirmationMotion.start.y)
        #expect(early.main[1].y < MascotConfirmationMotion.corner.y)
        let late = MascotConfirmationMotion.entering(at: 0.54)
        #expect(late.main[1] == MascotConfirmationMotion.corner)
        #expect(late.main[2].x > MascotConfirmationMotion.corner.x)
        #expect(late.main[2].y < MascotConfirmationMotion.corner.y)
        #expect(MascotConfirmationMotion.entering(at: 0.60) == MascotConfirmationMotion.check)
        #expect(MascotConfirmationMotion.entering(at: 30) == MascotConfirmationMotion.check)
    }

    @Test func returnErasesLongStrokeThenShortStrokeBeforeUnfoldingEyes() {
        let early = MascotConfirmationMotion.restoring(at: 0.06)
        #expect(early.main[1] == MascotConfirmationMotion.corner)
        #expect(early.main[2].x < MascotConfirmationMotion.end.x)
        let late = MascotConfirmationMotion.restoring(at: 0.16)
        #expect(late.main[1] == late.main[2])
        #expect(late.main[1].x < MascotConfirmationMotion.corner.x)
        let seed = MascotConfirmationMotion.restoring(at: 0.20)
        #expect((seed.main + seed.secondary).allSatisfy { $0 == MascotConfirmationMotion.start })
        let eyes = MascotConfirmationMotion.restoring(at: 0.28)
        #expect(eyes.secondaryOpacity == 1)
        #expect(eyes.main[0].x < eyes.secondary[0].x)
        #expect(MascotConfirmationMotion.restoring(at: 0.36) == MascotConfirmationMotion.idle)
    }

    @Test func interruptedReturnStartsAtTheVisiblePartialDrawing() {
        for time in [0.20, 0.38, 0.48, 0.60] {
            let partial = MascotConfirmationMotion.entering(at: time)
            #expect(MascotConfirmationMotion.restoring(at: 0, from: partial) == partial)
            let seed = MascotConfirmationMotion.restoring(at: 0.20, from: partial)
            #expect((seed.main + seed.secondary).allSatisfy { $0 == partial.main[0] })
            #expect(MascotConfirmationMotion.restoring(at: 0.36, from: partial) == MascotConfirmationMotion.idle)
        }
    }

}

#if canImport(UIKit)
import UIKit

@MainActor
struct MascotConfirmationLifecycleTests {
    @Test func replacementDoesNotReplayAndInterruptionCanResume() {
        let view = MascotConfirmationView()
        view.prepare(animated: true)
        view.confirm(animated: true)
        #expect(view.phase == .confirming)
        view.confirm(animated: true)
        #expect(view.phase == .confirming)
        view.restore(animated: true, duration: 0.32)
        #expect(view.phase == .restoring)
        view.confirm(animated: true)
        #expect(view.phase == .confirming)
        view.reset()
        #expect(view.phase == .idle && view.isHidden)
    }

    @Test func reducedMotionNeverReplaysSuppressedConfirmation() {
        let view = MascotConfirmationView()
        view.prepare(animated: true)
        view.confirm(animated: true)
        view.suppress()
        view.confirm(animated: true)
        #expect(view.phase == .suppressed && view.isHidden)
        view.prepare(animated: false)
        view.restore(animated: false, duration: 0)
        #expect(view.isHidden)
        view.reset()
    }
}
#endif
