import Foundation
import Observation
import SwiftUI

struct TaskDeletionAnimationTiming: Equatable, Sendable {
    let particleDuration: TimeInterval
    let fallbackFadeDuration: TimeInterval
    let collapseDuration: TimeInterval

    nonisolated static let standard = TaskDeletionAnimationTiming(
        particleDuration: 1.80,
        fallbackFadeDuration: 0.18,
        collapseDuration: 0.22
    )
}

struct TaskDeletionEnvironmentSnapshot: Equatable, Sendable {
    let reduceMotion: Bool
    let isLowPowerModeEnabled: Bool
    let isThermallyConstrained: Bool

    static func current(reduceMotion: Bool) -> TaskDeletionEnvironmentSnapshot {
        let thermalState = ProcessInfo.processInfo.thermalState
        return TaskDeletionEnvironmentSnapshot(
            reduceMotion: reduceMotion,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isThermallyConstrained: thermalState == .serious || thermalState == .critical
        )
    }

    var allowsParticles: Bool {
        reduceMotion == false
            && isLowPowerModeEnabled == false
            && isThermallyConstrained == false
    }
}

struct TaskDeletionVisualState: Equatable, Sendable {
    let progress: CGFloat
    let controlOpacity: CGFloat
    let usesParticles: Bool
    let seed: Float

    static func idle(taskID: UUID) -> TaskDeletionVisualState {
        TaskDeletionVisualState(
            progress: 0,
            controlOpacity: 1,
            usesParticles: false,
            seed: TaskDeletionRenderingPolicy.seed(for: taskID)
        )
    }

    var controlScale: CGFloat {
        0.92 + 0.08 * controlOpacity
    }
}

enum TaskDeletionRenderingPolicy {
    nonisolated static let maximumSampleOffset = CGSize(width: 72, height: 24)

    static func seed(for taskID: UUID) -> Float {
        var uuid = taskID.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        var hash: UInt32 = 2_166_136_261
        for byte in bytes {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Float(hash % 10_000) / 10_000
    }
}

@MainActor
@Observable
final class TaskDeletionAnimationSession {
    enum Phase: Equatable, Sendable {
        case idle
        case committing
        case dispersing
        case collapsing
    }

    private(set) var activeTaskID: UUID?
    private(set) var phase: Phase = .idle
    private(set) var progress: CGFloat = 0
    private(set) var controlOpacity: CGFloat = 1
    private(set) var usesParticles = false

    @ObservationIgnored private let timing: TaskDeletionAnimationTiming
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var finalizeRemoval: (() -> Void)?
    @ObservationIgnored private var shouldFinishImmediately = false
    @ObservationIgnored private var didPersistDeletion = false

    init(timing: TaskDeletionAnimationTiming = .standard) {
        self.timing = timing
    }

    var isBusy: Bool {
        phase != .idle
    }

    func visualState(for taskID: UUID) -> TaskDeletionVisualState {
        guard activeTaskID == taskID else {
            return .idle(taskID: taskID)
        }
        return TaskDeletionVisualState(
            progress: progress,
            controlOpacity: controlOpacity,
            usesParticles: usesParticles,
            seed: TaskDeletionRenderingPolicy.seed(for: taskID)
        )
    }

    func requestDeletion(
        taskID: UUID,
        environment: TaskDeletionEnvironmentSnapshot,
        persist: @escaping () async -> Bool,
        finalize: @escaping () -> Void
    ) {
        guard isBusy == false else { return }

        activeTaskID = taskID
        phase = .committing
        progress = 0
        controlOpacity = 1
        usesParticles = false
        shouldFinishImmediately = false
        didPersistDeletion = false
        finalizeRemoval = finalize

        operationTask = Task { @MainActor in
            let didPersist = await persist()
            guard activeTaskID == taskID else {
                if didPersist {
                    finalize()
                }
                return
            }
            guard didPersist else {
                reset()
                return
            }

            didPersistDeletion = true
            if shouldFinishImmediately {
                finishImmediately()
                return
            }

            usesParticles = environment.allowsParticles
            phase = .dispersing
            let visualDuration = usesParticles
                ? timing.particleDuration
                : timing.fallbackFadeDuration

            withAnimation(
                usesParticles
                    ? .linear(duration: visualDuration)
                    : .easeOut(duration: visualDuration)
            ) {
                progress = 1
            }
            withAnimation(.easeOut(duration: min(visualDuration, 0.50))) {
                controlOpacity = 0
            }

            do {
                try await Task.sleep(for: .seconds(visualDuration))
            } catch {
                return
            }
            guard activeTaskID == taskID else { return }

            phase = .collapsing
            let removal = takeFinalizer()
            withAnimation(.smooth(duration: timing.collapseDuration, extraBounce: 0)) {
                removal?()
            }

            do {
                try await Task.sleep(for: .seconds(timing.collapseDuration))
            } catch {
                return
            }
            guard activeTaskID == taskID else { return }
            reset()
        }
    }

    func interrupt() {
        guard isBusy else { return }
        shouldFinishImmediately = true
        guard didPersistDeletion else { return }
        finishImmediately()
    }

    func waitForCurrentOperation() async {
        let task = operationTask
        await task?.value
    }

    private func finishImmediately() {
        operationTask?.cancel()
        let removal = takeFinalizer()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            removal?()
        }
        reset()
    }

    private func takeFinalizer() -> (() -> Void)? {
        defer { finalizeRemoval = nil }
        return finalizeRemoval
    }

    private func reset() {
        operationTask = nil
        finalizeRemoval = nil
        activeTaskID = nil
        phase = .idle
        progress = 0
        controlOpacity = 1
        usesParticles = false
        shouldFinishImmediately = false
        didPersistDeletion = false
    }
}

private struct TaskDeletionTypographyModifier: AnimatableModifier {
    var progress: CGFloat
    var controlOpacity: CGFloat
    let usesParticles: Bool
    let seed: Float

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, controlOpacity) }
        set {
            progress = newValue.first
            controlOpacity = newValue.second
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesParticles {
            content
                .visualEffect { visualContent, geometry in
                    visualContent.layerEffect(
                        ShaderLibrary.taskDeletionDisintegrate(
                            .float2(geometry.size),
                            .float(Float(progress)),
                            .float(seed),
                            .float(Float(controlOpacity))
                        ),
                        maxSampleOffset: TaskDeletionRenderingPolicy.maximumSampleOffset
                    )
                }
        } else {
            content.opacity(max(1 - progress, 0))
        }
    }
}

extension View {
    func taskDeletionTypographyEffect(_ state: TaskDeletionVisualState) -> some View {
        modifier(
            TaskDeletionTypographyModifier(
                progress: state.progress,
                controlOpacity: state.controlOpacity,
                usesParticles: state.usesParticles,
                seed: state.seed
            )
        )
    }
}
