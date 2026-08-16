import Foundation
import Testing
@testable import Together

@MainActor
@Suite("Ambient particle background")
struct AmbientParticleBackgroundTests {
    @Test func localSettingDefaultsOnAndPersistsPerDevice() throws {
        let suiteName = "AmbientParticleBackgroundTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AmbientBackgroundSettings(defaults: defaults)
        #expect(initial.isEnabled)

        initial.isEnabled = false
        let restored = AmbientBackgroundSettings(defaults: defaults)
        #expect(restored.isEnabled == false)
    }

    @Test func accelerationAndDecelerationIntegratePhaseWithoutReversal() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let accelerating = AmbientParticleMotionTrack(stationaryAt: start).retarget(
            to: 1,
            at: start,
            duration: AmbientParticleMotionTiming.accelerationDuration
        )
        let accelerationEndDate = start.addingTimeInterval(
            AmbientParticleMotionTiming.accelerationDuration
        )
        let accelerated = accelerating.sample(at: accelerationEndDate)

        #expect(abs(accelerated.speed - 1) < 0.000_001)
        #expect(abs(accelerated.phase - AmbientParticleMotionTiming.accelerationDuration * 0.5) < 0.000_001)

        let decelerating = accelerating.retarget(
            to: 0,
            at: accelerationEndDate,
            duration: AmbientParticleMotionTiming.decelerationDuration
        )
        let halfwayDate = accelerationEndDate.addingTimeInterval(
            AmbientParticleMotionTiming.decelerationDuration * 0.5
        )
        let halfway = decelerating.sample(at: halfwayDate)
        let stopped = decelerating.sample(
            at: accelerationEndDate.addingTimeInterval(AmbientParticleMotionTiming.decelerationDuration)
        )

        #expect(abs(halfway.speed - 0.5) < 0.000_001)
        #expect(halfway.phase > accelerated.phase)
        #expect(stopped.phase > halfway.phase)
        #expect(abs(stopped.speed) < 0.000_001)
    }

    @Test func interruptedDecelerationPreservesCurrentPositionAndSpeed() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let moving = AmbientParticleMotionTrack(stationaryAt: start).retarget(
            to: 1,
            at: start,
            duration: 0
        )
        let decelerationStart = start.addingTimeInterval(2)
        let decelerating = moving.retarget(
            to: 0,
            at: decelerationStart,
            duration: AmbientParticleMotionTiming.decelerationDuration
        )
        let interruptionDate = decelerationStart.addingTimeInterval(0.20)
        let beforeInterruption = decelerating.sample(at: interruptionDate)
        let accelerating = decelerating.retarget(
            to: 1,
            at: interruptionDate,
            duration: AmbientParticleMotionTiming.accelerationDuration
        )
        let afterInterruption = accelerating.sample(at: interruptionDate)

        #expect(abs(afterInterruption.phase - beforeInterruption.phase) < 0.000_001)
        #expect(abs(afterInterruption.speed - beforeInterruption.speed) < 0.000_001)
    }

    @Test func motionDemandPrioritizesAccessibilityAndEnergyConstraints() {
        let baseline = AmbientParticleMotionDemand(
            isEnabled: true,
            reduceMotion: false,
            isSceneActive: true,
            isSurfaceVisible: true,
            isFocusActive: false,
            isLowPowerModeEnabled: false,
            isThermallyConstrained: false
        )
        #expect(baseline.shouldMove)
        #expect(baseline.requiresImmediateStop == false)

        #expect(demand(from: baseline, reduceMotion: true).shouldMove == false)
        #expect(demand(from: baseline, reduceMotion: true).requiresImmediateStop)
        #expect(demand(from: baseline, isSceneActive: false).requiresImmediateStop)
        #expect(demand(from: baseline, isSurfaceVisible: false).shouldMove == false)
        #expect(demand(from: baseline, isFocusActive: true).shouldMove == false)
        #expect(demand(from: baseline, isLowPowerModeEnabled: true).shouldMove == false)
        #expect(demand(from: baseline, isThermallyConstrained: true).shouldMove == false)
    }

    @Test func renderingPolicyCapsSecondaryAnimationWork() {
        #expect(AmbientParticleRenderingPolicy.maximumFramesPerSecond == 60)
        #expect(AmbientParticleRenderingPolicy.layerCount == 4)
        #expect(AmbientParticleRenderingPolicy.candidateEvaluationsPerPixel == 4)
        #expect(AmbientParticleRenderingPolicy.increasedContrastMultiplier == 0.60)
    }

    private func demand(
        from baseline: AmbientParticleMotionDemand,
        reduceMotion: Bool? = nil,
        isSceneActive: Bool? = nil,
        isSurfaceVisible: Bool? = nil,
        isFocusActive: Bool? = nil,
        isLowPowerModeEnabled: Bool? = nil,
        isThermallyConstrained: Bool? = nil
    ) -> AmbientParticleMotionDemand {
        AmbientParticleMotionDemand(
            isEnabled: baseline.isEnabled,
            reduceMotion: reduceMotion ?? baseline.reduceMotion,
            isSceneActive: isSceneActive ?? baseline.isSceneActive,
            isSurfaceVisible: isSurfaceVisible ?? baseline.isSurfaceVisible,
            isFocusActive: isFocusActive ?? baseline.isFocusActive,
            isLowPowerModeEnabled: isLowPowerModeEnabled ?? baseline.isLowPowerModeEnabled,
            isThermallyConstrained: isThermallyConstrained ?? baseline.isThermallyConstrained
        )
    }
}
