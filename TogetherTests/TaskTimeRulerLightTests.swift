import Foundation
import Testing
@testable import Together

struct TaskTimeRulerLightTests {
    @Test func lensHasOneBoundedSymmetricMagnificationAndFlatOuterMarks() {
        let scales = (-6...6).map { TaskTimeRulerLens.magnification(distance: CGFloat($0) * 10, pitch: 10) }
        #expect(scales[6] == 1.24)
        #expect(scales.allSatisfy { $0 >= 1 && $0 <= 1.24 })
        #expect(scales.filter { $0 > 1 }.count == 9)
        #expect(scales == Array(scales.reversed()))
        #expect(scales[6] > scales[7] && scales[7] > scales[8] && scales[8] > scales[9])
        #expect(scales[11] == 1)
    }

    @Test func lensHandsOffSmoothlyAndKeepsProjectedMarksInOrder() {
        let leftOfPointer = TaskTimeRulerLens.magnification(distance: -5, pitch: 10)
        let rightOfPointer = TaskTimeRulerLens.magnification(distance: 5, pitch: 10)
        #expect(leftOfPointer == rightOfPointer)
        #expect(leftOfPointer > 1.23 && leftOfPointer < 1.24)
        #expect(TaskTimeRulerLens.magnification(distance: 49.99, pitch: 10) - 1 < 0.0001)
        #expect(TaskTimeRulerLens.magnification(distance: 50.01, pitch: 10) == 1)
        for step in -600...600 {
            let distance = CGFloat(step) / 10
            let before = TaskTimeRulerLens.magnification(distance: distance, pitch: 10)
            let after = TaskTimeRulerLens.magnification(distance: distance + 0.1, pitch: 10)
            #expect(abs(after - before) < 0.001)
            #expect((distance + 0.1) * after > distance * before)
            let next = TaskTimeRulerLens.magnification(distance: distance + 10, pitch: 10)
            let clearGap = (distance + 10) * next - distance * before - 1.5 * (next + before)
            #expect(clearGap > 4)
        }
    }

    @Test func positioningWithoutContactNeverIlluminates() {
        var mark = TaskTimeRulerLightState()
        mark.move(to: .trailing)
        mark.move(to: .center)
        mark.move(to: .leading)
        #expect(mark.pulse == 0)
    }

    @Test func touchDownIlluminatesWithoutMovingTheMark() {
        var mark = TaskTimeRulerLightState()
        mark.move(to: .center)
        mark.setContact(true)
        #expect(mark.pulse == 1)
        // The tracking -> interacting transition must not restart the same flash.
        mark.setContact(true)
        mark.move(to: .center)
        #expect(mark.pulse == 1)
        mark.setContact(false)
        mark.setContact(true)
        #expect(mark.pulse == 2)
    }

    @Test func successiveMarksKeepIndependentAfterglowWhenDirectionReverses() {
        var first = TaskTimeRulerLightState()
        var second = TaskTimeRulerLightState()
        first.move(to: .center)
        second.move(to: .trailing)
        first.setContact(true)
        second.setContact(true)
        first.move(to: .leading)
        second.move(to: .center)
        #expect(first.pulse == 1) // Leaving center does not cancel its animation.
        #expect(second.pulse == 1)
        second.move(to: .trailing)
        first.move(to: .center)
        #expect(first.pulse == 2)
        #expect(second.pulse == 1)
    }

    @Test func fastDragStillLightsMarksThatCrossCenterBetweenFrames() {
        var mark = TaskTimeRulerLightState()
        mark.move(to: .trailing)
        mark.setContact(true)
        mark.move(to: .leading)
        #expect(mark.pulse == 1)
        mark.move(to: .trailing)
        #expect(mark.pulse == 2)
    }

    @Test func releaseAndInertialScrollingDoNotStartOrCancelPulses() {
        var mark = TaskTimeRulerLightState()
        mark.move(to: .center)
        mark.setContact(true)
        mark.setContact(false)
        mark.move(to: .leading)
        mark.move(to: .trailing)
        mark.move(to: .center)
        #expect(mark.pulse == 1)
        #expect(!mark.isTouching)
    }

    @Test func newlyMountedOffCenterMarksDoNotFlashDuringADrag() {
        var mark = TaskTimeRulerLightState()
        mark.setContact(true)
        mark.move(to: .leading)
        #expect(mark.pulse == 0)
        mark.move(to: .center)
        #expect(mark.pulse == 1)
    }

    @Test func adjacentMarksShareExactlyOneCenterRegionAtBoundaries() {
        typealias Position = TaskTimeRulerLightState.Position
        #expect(Position(distance: -5, pitch: 10) == .center)
        #expect(Position(distance: 5, pitch: 10) == .trailing)
        #expect(Position(distance: -5.01, pitch: 10) == .leading)
    }
}
