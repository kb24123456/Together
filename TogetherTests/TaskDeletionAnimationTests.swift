import Foundation
import Testing
@testable import Together

@Suite("Task deletion animation")
@MainActor
struct TaskDeletionAnimationTests {
    @Test("粒子降级策略覆盖动态减弱、低电量和严重温控")
    func renderingPolicyFallbacks() {
        #expect(
            TaskDeletionEnvironmentSnapshot(
                reduceMotion: false,
                isLowPowerModeEnabled: false,
                isThermallyConstrained: false
            ).allowsParticles
        )
        #expect(
            TaskDeletionEnvironmentSnapshot(
                reduceMotion: true,
                isLowPowerModeEnabled: false,
                isThermallyConstrained: false
            ).allowsParticles == false
        )
        #expect(
            TaskDeletionEnvironmentSnapshot(
                reduceMotion: false,
                isLowPowerModeEnabled: true,
                isThermallyConstrained: false
            ).allowsParticles == false
        )
        #expect(
            TaskDeletionEnvironmentSnapshot(
                reduceMotion: false,
                isLowPowerModeEnabled: false,
                isThermallyConstrained: true
            ).allowsParticles == false
        )
    }

    @Test("粒子采样边界和任务种子保持确定")
    func renderingGeometryIsBoundedAndDeterministic() {
        let taskID = UUID(uuidString: "3E93295A-9E0F-49B8-9D9E-5798BBD79D33")!
        #expect(TaskDeletionAnimationTiming.standard.particleDuration == 1.80)
        #expect(TaskDeletionRenderingPolicy.maximumSampleOffset.width == 72)
        #expect(TaskDeletionRenderingPolicy.maximumSampleOffset.height == 24)
        #expect(TaskDeletionRenderingPolicy.seed(for: taskID) == TaskDeletionRenderingPolicy.seed(for: taskID))
    }

    @Test("持久化成功后才移除列表展示")
    func successfulPersistenceFinalizesPresentation() async {
        let session = TaskDeletionAnimationSession(timing: .init(
            particleDuration: 0,
            fallbackFadeDuration: 0,
            collapseDuration: 0
        ))
        var finalizationCount = 0

        session.requestDeletion(
            taskID: UUID(),
            environment: .init(
                reduceMotion: true,
                isLowPowerModeEnabled: false,
                isThermallyConstrained: false
            ),
            persist: { true },
            finalize: { finalizationCount += 1 }
        )
        await session.waitForCurrentOperation()

        #expect(finalizationCount == 1)
        #expect(session.phase == .idle)
    }

    @Test("持久化失败时保留列表展示")
    func failedPersistenceDoesNotFinalizePresentation() async {
        let session = TaskDeletionAnimationSession(timing: .init(
            particleDuration: 0,
            fallbackFadeDuration: 0,
            collapseDuration: 0
        ))
        var finalizationCount = 0

        session.requestDeletion(
            taskID: UUID(),
            environment: .init(
                reduceMotion: false,
                isLowPowerModeEnabled: false,
                isThermallyConstrained: false
            ),
            persist: { false },
            finalize: { finalizationCount += 1 }
        )
        await session.waitForCurrentOperation()

        #expect(finalizationCount == 0)
        #expect(session.phase == .idle)
    }
}
