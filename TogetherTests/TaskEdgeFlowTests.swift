import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Task edge flow")
struct TaskEdgeFlowTests {
    @Test func centerRowsKeepTheirNativeGeometryAndClarity() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 300, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: false
        )

        #expect(metrics == .identity)
    }

    @Test func rowsAboveTheViewportAreIgnoredByTheBottomOnlyPolicy() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: -80, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: false
        )

        #expect(metrics == .identity)
    }

    @Test func bottomEdgeConvergesTowardDockAndBecomesNoninteractiveWhenDeep() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 760, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: false
        )

        #expect(metrics.edge == .bottom)
        #expect(metrics.offsetY > 0)
        #expect(metrics.scaleY < 1)
        #expect(metrics.opacity < 0.3)
        #expect(metrics.blurRadius == 0)
        #expect(metrics.isDeeplyOccluded)
    }

    @Test func shallowBottomEdgeRemainsInteractive() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 688, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: false
        )

        #expect(metrics.edge == .bottom)
        #expect(metrics.opacity > 0.7)
        #expect(metrics.isDeeplyOccluded == false)
    }

    @Test func reduceMotionKeepsOnlyTheBottomFadeWithoutBlur() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 780, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: true
        )

        #expect(metrics.offsetY == 0)
        #expect(metrics.scaleX == 1)
        #expect(metrics.scaleY == 1)
        #expect(metrics.opacity < 1)
        #expect(metrics.blurRadius == 0)
    }

    @Test func activeMorphSuspendsEveryEdgeEffect() {
        let metrics = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 780, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 0,
            reduceMotion: false
        )

        #expect(metrics == .identity)
    }

    @Test func morphHandoffInterpolatesEveryVisualEffectContinuously() {
        let full = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 760, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 1,
            reduceMotion: false
        )
        let halfway = TaskEdgeFlowPolicy.metrics(
            rowFrame: CGRect(x: 0, y: 760, width: 360, height: 64),
            viewportHeight: 800,
            intensity: 0.5,
            reduceMotion: false
        )

        #expect(abs(halfway.offsetY - full.offsetY * 0.5) < 0.0001)
        #expect(abs(halfway.scaleX - (1 + (full.scaleX - 1) * 0.5)) < 0.0001)
        #expect(abs(halfway.scaleY - (1 + (full.scaleY - 1) * 0.5)) < 0.0001)
        #expect(abs(halfway.opacity - (1 + (full.opacity - 1) * 0.5)) < 0.0001)
        #expect(abs(halfway.blurRadius - full.blurRadius * 0.5) < 0.0001)
        #expect(halfway.edge == .bottom)
        #expect(halfway.isDeeplyOccluded == false)
    }
}
