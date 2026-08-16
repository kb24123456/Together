import Combine
import Foundation
import SwiftUI

enum AmbientParticleMotionTiming {
    static let decelerationDuration: TimeInterval = 0.55
    static let accelerationDuration: TimeInterval = 0.42
    static let reducedMotionFadeDuration: TimeInterval = 0.14
    static let visibilityFadeDuration: TimeInterval = 0.18
}

enum AmbientParticleRenderingPolicy {
    static let maximumFramesPerSecond = 60.0
    static let minimumFrameInterval = 1.0 / maximumFramesPerSecond
    static let layerCount = 4
    static let candidateEvaluationsPerPixel = layerCount
    static let increasedContrastMultiplier = 0.60
}

struct AmbientParticleMotionSample: Equatable, Sendable {
    let phase: TimeInterval
    let speed: Double
}

struct AmbientParticleMotionTrack: Equatable, Sendable {
    private(set) var originDate: Date
    private(set) var originPhase: TimeInterval
    private(set) var originSpeed: Double
    private(set) var targetSpeed: Double
    private(set) var transitionDuration: TimeInterval

    init(stationaryAt date: Date) {
        originDate = date
        originPhase = 0
        originSpeed = 0
        targetSpeed = 0
        transitionDuration = 0
    }

    private init(
        originDate: Date,
        originPhase: TimeInterval,
        originSpeed: Double,
        targetSpeed: Double,
        transitionDuration: TimeInterval
    ) {
        self.originDate = originDate
        self.originPhase = originPhase
        self.originSpeed = originSpeed
        self.targetSpeed = targetSpeed
        self.transitionDuration = transitionDuration
    }

    func sample(at date: Date) -> AmbientParticleMotionSample {
        let elapsed = max(date.timeIntervalSince(originDate), 0)
        guard transitionDuration > 0 else {
            return AmbientParticleMotionSample(
                phase: originPhase + targetSpeed * elapsed,
                speed: targetSpeed
            )
        }

        let normalizedTime = min(elapsed / transitionDuration, 1)
        let easedSpeedProgress = normalizedTime * normalizedTime * (3 - 2 * normalizedTime)
        let integratedSpeedProgress = pow(normalizedTime, 3) - 0.5 * pow(normalizedTime, 4)
        let speedDelta = targetSpeed - originSpeed
        let transitionPhase = originPhase + transitionDuration * (
            originSpeed * normalizedTime + speedDelta * integratedSpeedProgress
        )

        if elapsed <= transitionDuration {
            return AmbientParticleMotionSample(
                phase: transitionPhase,
                speed: originSpeed + speedDelta * easedSpeedProgress
            )
        }

        return AmbientParticleMotionSample(
            phase: transitionPhase + targetSpeed * (elapsed - transitionDuration),
            speed: targetSpeed
        )
    }

    func retarget(
        to speed: Double,
        at date: Date,
        duration: TimeInterval
    ) -> AmbientParticleMotionTrack {
        let current = sample(at: date)
        return AmbientParticleMotionTrack(
            originDate: date,
            originPhase: current.phase,
            originSpeed: current.speed,
            targetSpeed: min(max(speed, 0), 1),
            transitionDuration: max(duration, 0)
        )
    }

    func resolved(at date: Date) -> AmbientParticleMotionTrack {
        let current = sample(at: date)
        return AmbientParticleMotionTrack(
            originDate: date,
            originPhase: current.phase,
            originSpeed: current.speed,
            targetSpeed: current.speed,
            transitionDuration: 0
        )
    }
}

struct AmbientParticleMotionDemand: Equatable {
    let isEnabled: Bool
    let reduceMotion: Bool
    let isSceneActive: Bool
    let isSurfaceVisible: Bool
    let isFocusActive: Bool
    let isLowPowerModeEnabled: Bool
    let isThermallyConstrained: Bool

    var shouldMove: Bool {
        isEnabled
            && reduceMotion == false
            && isSceneActive
            && isSurfaceVisible
            && isFocusActive == false
            && isLowPowerModeEnabled == false
            && isThermallyConstrained == false
    }

    var requiresImmediateStop: Bool {
        reduceMotion || isSceneActive == false
    }
}

struct AmbientParticleBackground: View {
    let isEnabled: Bool
    let isMotionSuppressed: Bool
    let isSurfaceVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    @State private var motionTrack: AmbientParticleMotionTrack
    @State private var isTimelinePaused = true
    @State private var isParticleLayerVisible: Bool
    @State private var completionTask: Task<Void, Never>?

    init(
        isEnabled: Bool,
        isMotionSuppressed: Bool,
        isSurfaceVisible: Bool
    ) {
        self.isEnabled = isEnabled
        self.isMotionSuppressed = isMotionSuppressed
        self.isSurfaceVisible = isSurfaceVisible
        _motionTrack = State(initialValue: AmbientParticleMotionTrack(stationaryAt: .now))
        _isParticleLayerVisible = State(initialValue: isEnabled)
    }

    private var motionDemand: AmbientParticleMotionDemand {
        AmbientParticleMotionDemand(
            isEnabled: isEnabled,
            reduceMotion: reduceMotion,
            isSceneActive: scenePhase == .active,
            isSurfaceVisible: isSurfaceVisible,
            isFocusActive: isMotionSuppressed,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            isThermallyConstrained: thermalState == .serious || thermalState == .critical
        )
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: AmbientParticleRenderingPolicy.minimumFrameInterval,
                paused: isTimelinePaused
            )
        ) { context in
            let sample = motionTrack.sample(at: context.date)
            let darkAppearance: Float = colorScheme == .dark ? 1 : 0
            let contrastMultiplier: Float = colorSchemeContrast == .increased
                ? Float(AmbientParticleRenderingPolicy.increasedContrastMultiplier)
                : 1
            Color.white
                .visualEffect { content, geometry in
                    content.colorEffect(
                        ShaderLibrary.ambientParticleField(
                            .float2(geometry.size),
                            .float(Float(sample.phase)),
                            .float(darkAppearance),
                            .float(contrastMultiplier)
                        )
                    )
                }
        }
        .opacity(isParticleLayerVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            synchronizeMotion(with: motionDemand)
        }
        .onChange(of: motionDemand) { _, demand in
            synchronizeMotion(with: demand)
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
        .onDisappear {
            completionTask?.cancel()
            completionTask = nil
            isTimelinePaused = true
        }
    }

    private func synchronizeMotion(with demand: AmbientParticleMotionDemand) {
        completionTask?.cancel()
        completionTask = nil

        let now = Date.now
        if demand.isEnabled == false {
            stopMotion(
                at: now,
                immediately: demand.requiresImmediateStop,
                hidesLayerWhenFinished: true
            )
            return
        }

        if isParticleLayerVisible == false {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: AmbientParticleMotionTiming.reducedMotionFadeDuration)
                    : .easeOut(duration: AmbientParticleMotionTiming.visibilityFadeDuration)
            ) {
                isParticleLayerVisible = true
            }
        }

        guard demand.shouldMove else {
            stopMotion(
                at: now,
                immediately: demand.requiresImmediateStop,
                hidesLayerWhenFinished: false
            )
            return
        }

        motionTrack = motionTrack.retarget(
            to: 1,
            at: now,
            duration: AmbientParticleMotionTiming.accelerationDuration
        )
        isTimelinePaused = false
    }

    private func stopMotion(
        at date: Date,
        immediately: Bool,
        hidesLayerWhenFinished: Bool
    ) {
        let currentSample = motionTrack.sample(at: date)
        if immediately || currentSample.speed <= 0.000_001 {
            motionTrack = motionTrack.retarget(to: 0, at: date, duration: 0)
            isTimelinePaused = true
            if hidesLayerWhenFinished, isParticleLayerVisible {
                let fadeDuration = immediately
                    ? AmbientParticleMotionTiming.reducedMotionFadeDuration
                    : AmbientParticleMotionTiming.visibilityFadeDuration
                withAnimation(.easeOut(duration: fadeDuration)) {
                    isParticleLayerVisible = false
                }
            }
            return
        }

        motionTrack = motionTrack.retarget(
            to: 0,
            at: date,
            duration: AmbientParticleMotionTiming.decelerationDuration
        )
        isTimelinePaused = false
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AmbientParticleMotionTiming.decelerationDuration))
            guard Task.isCancelled == false else { return }
            motionTrack = motionTrack.resolved(at: .now)
            isTimelinePaused = true
            if hidesLayerWhenFinished {
                withAnimation(.easeOut(duration: AmbientParticleMotionTiming.visibilityFadeDuration)) {
                    isParticleLayerVisible = false
                }
            }
            completionTask = nil
        }
    }
}
