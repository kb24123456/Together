import Foundation
import Observation
import OSLog
import RiveRuntime

/// Owns one worker-backed Rive instance across the character's native surfaces.
@MainActor
@Observable
final class MascotRuntime {
    private(set) var rive: Rive?

    @ObservationIgnored private var loadGeneration: UUID?
    @ObservationIgnored private var didFail = false
    @ObservationIgnored private var appliedMode: Int?
    @ObservationIgnored private var appliedExpression: Int?
    @ObservationIgnored private var appliedIdleFace: Int?
    @ObservationIgnored private var appliedTyping: Bool?
    @ObservationIgnored private var appliedDark: Bool?
    @ObservationIgnored private var desiredDark = false
    @ObservationIgnored private var consumedFeedbackID: UUID?
    @ObservationIgnored private var issuedFeedbackUntil: TimeInterval?
    @ObservationIgnored private var hasPresentedHomeFace = false

    private static let modeProperty = NumberProperty(path: "mode")
    private static let expressionProperty = NumberProperty(path: "expression")
    private static let idleFaceProperty = NumberProperty(path: "idleFace")
    private static let typingProperty = BoolProperty(path: "isTyping")
    private static let celebrateProperty = BoolProperty(path: "celebrateRequested")
    private static let acknowledgeProperty = TriggerProperty(path: "acknowledge")
    private static let noticeResultProperty = TriggerProperty(path: "noticeResult")
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "BrandMascot")

    func load(controller: MascotController, isDark: Bool) async {
        guard rive == nil, !didFail else { return }
        let generation = UUID()
        loadGeneration = generation
        desiredDark = isDark
        appliedMode = nil
        appliedExpression = nil
        appliedIdleFace = nil
        appliedTyping = nil
        appliedDark = nil
        defer {
            if loadGeneration == generation { loadGeneration = nil }
        }

        do {
            // Bundle lookup and file reads are outside the main actor and view construction.
            let data = try await Task.detached(priority: .utility) {
                guard let url = Bundle.main.url(
                    forResource: "together_sphere_motion_study", withExtension: "riv"
                ) else {
                    throw MascotAssetError.missingResource
                }
                return try Data(contentsOf: url)
            }.value
            try checkLoad(generation)
            let worker = try await Worker()
            try checkLoad(generation)
            let file = try await RiveRuntime.File(source: .data(data), worker: worker)
            try checkLoad(generation)
            let artboard = try await file.createArtboard("TogetherSphere")
            try checkLoad(generation)
            let stateMachine = try await artboard.createStateMachine("Mascot")
            try checkLoad(generation)
            let instance = try await file.createViewModelInstance(
                .viewModelDefault(from: .name("TogetherSphereModel"))
            )
            try checkLoad(generation)
            let configuration = try await Rive(
                file: file, artboard: artboard, stateMachine: stateMachine,
                dataBind: .instance(instance), fit: .contain(alignment: .center)
            )
            try checkLoad(generation)

            applyInputs(controller: controller, to: instance)
            applyPalette(to: instance)
            // Resolve Entry and its initial face blend before drawing or accepting feedback.
            // Fixed worker advancement avoids publishing the initial empty-face frame.
            stateMachine.advance(by: 0)
            stateMachine.advance(by: 0.15)
            _ = try await instance.value(of: Self.modeProperty)
            try checkLoad(generation)
            applyInputs(controller: controller, to: instance)
            applyPalette(to: instance)
            consumedFeedbackID = controller.feedback?.id
            rive = configuration
        } catch is CancellationError {
            // A later appearance can retry a cancelled load.
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            didFail = true
            Self.logger.error("Local mascot could not load; using static artwork: \(error.localizedDescription, privacy: .public)")
        }
    }

    func synchronize(controller: MascotController, isDark: Bool) {
        desiredDark = isDark
        guard let instance = rive?.viewModelInstance else { return }
        applyInputs(controller: controller, to: instance)
        applyPalette(to: instance)
    }

    func consumeFeedback(_ feedback: MascotFeedback?, canPlay: Bool) {
        guard canPlay else {
            if let feedback { consumedFeedbackID = feedback.id }
            // Navigation preserves ordinary pose. Only a global suspension resets it.
            discardTransientFeedback(resetHomeFace: false)
            return
        }
        guard let feedback, consumedFeedbackID != feedback.id else { return }
        consumedFeedbackID = feedback.id
        guard let instance = rive?.viewModelInstance else { return }
        if feedback.kind != .noticeResult {
            instance.setValue(of: Self.idleFaceProperty, to: -1)
            appliedIdleFace = -1
            instance.setValue(of: Self.expressionProperty, to: 0)
            appliedExpression = 0
        }
        // Includes the longest one-shot plus its resolve/exit blend. This is a
        // discard boundary, not another timer or a delay before accepting input.
        issuedFeedbackUntil = ProcessInfo.processInfo.systemUptime + 2.2
        switch feedback.kind {
        case .acknowledge:
            instance.fire(trigger: Self.acknowledgeProperty)
        case .celebrate:
            instance.setValue(of: Self.celebrateProperty, to: true)
        case .noticeResult:
            instance.fire(trigger: Self.noticeResultProperty)
        }
    }

    func suspend() {
        loadGeneration = nil
        discardTransientFeedback(resetHomeFace: true)
    }

    private func discardTransientFeedback(resetHomeFace: Bool) {
        let hadFeedback = issuedFeedbackUntil.map {
            ProcessInfo.processInfo.systemUptime < $0
        } == true
        issuedFeedbackUntil = nil
        guard hadFeedback || (resetHomeFace && hasPresentedHomeFace),
              let rive, let instance = rive.viewModelInstance else { return }
        hasPresentedHomeFace = false
        appliedIdleFace = -1
        appliedExpression = 0
        instance.setValue(of: Self.idleFaceProperty, to: -1)
        instance.setValue(of: Self.expressionProperty, to: 0)
        instance.setValue(of: Self.celebrateProperty, to: false)
        // New Runtime has no trigger-clear/reset API. Consume a pending trigger, finish the
        // <= 1.6s one-shot, then cross FeedbackDone/Resolve and its 50ms blend without drawing.
        // Four worker commands only; no display loop, timer, or new runtime instance.
        rive.stateMachine.advance(by: 0)
        if hadFeedback {
            rive.stateMachine.advance(by: 2)
            rive.stateMachine.advance(by: 0.1)
            rive.stateMachine.advance(by: 0.1)
        } else {
            // Finish the home-face exit and restore Auto while hidden, including when
            // the neutral home eyes were visible. Fixed commands, without a drawing loop.
            rive.stateMachine.advance(by: 0.3)
            rive.stateMachine.advance(by: 0.3)
            rive.stateMachine.advance(by: 0.1)
        }
    }

    private func checkLoad(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard loadGeneration == generation else { throw CancellationError() }
    }

    private func applyInputs(controller: MascotController, to instance: ViewModelInstance) {
        // Home eyes share the continuous gaze rig. Release them before task-state or
        // feedback changes; the existing expression interface remains in Auto mode.
        let keepsHomeFace = controller.feedback == nil || controller.feedback?.kind == .noticeResult
        let idleFace = controller.mode == 0 && controller.isPlaying && keepsHomeFace
            ? controller.expression : -1
        if appliedIdleFace != idleFace {
            instance.setValue(of: Self.idleFaceProperty, to: Float(idleFace))
            appliedIdleFace = idleFace
            if idleFace >= 0 { hasPresentedHomeFace = true }
        }
        if appliedExpression != 0 {
            instance.setValue(of: Self.expressionProperty, to: 0)
            appliedExpression = 0
        }
        if appliedMode != controller.mode {
            instance.setValue(of: Self.modeProperty, to: Float(controller.mode))
            appliedMode = controller.mode
        }
        if appliedTyping != controller.isTyping {
            instance.setValue(of: Self.typingProperty, to: controller.isTyping)
            appliedTyping = controller.isTyping
        }
    }

    private func applyPalette(to instance: ViewModelInstance) {
        guard appliedDark != desiredDark else { return }
        MascotPalette.apply(to: instance, isDark: desiredDark)
        appliedDark = desiredDark
    }
}

private nonisolated enum MascotAssetError: Error {
    case missingResource
}
