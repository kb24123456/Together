import Foundation
import Observation
import OSLog
import RiveRuntime

/// Owns one worker-backed Rive instance for the lifetime of a mascot surface.
@MainActor
@Observable
final class MascotRuntime {
    private(set) var rive: Rive?

    @ObservationIgnored private var loadGeneration: UUID?
    @ObservationIgnored private var didFail = false
    @ObservationIgnored private var appliedMode: Int?
    @ObservationIgnored private var appliedExpression: Int?
    @ObservationIgnored private var appliedTyping: Bool?
    @ObservationIgnored private var appliedDark: Bool?
    @ObservationIgnored private var desiredDark = false
    @ObservationIgnored private var consumedFeedbackID: UUID?
    @ObservationIgnored private var hasIssuedFeedback = false
    @ObservationIgnored private var hasPresentedIdleExpression = false

    private static let modeProperty = NumberProperty(path: "mode")
    private static let expressionProperty = NumberProperty(path: "expression")
    private static let typingProperty = BoolProperty(path: "isTyping")
    private static let celebrateProperty = BoolProperty(path: "celebrateRequested")
    private static let acknowledgeProperty = TriggerProperty(path: "acknowledge")
    private static let logger = Logger(subsystem: "com.pigdog.Together", category: "BrandMascot")

    func load(controller: MascotController, isDark: Bool) async {
        guard rive == nil, !didFail else { return }
        let generation = UUID()
        loadGeneration = generation
        desiredDark = isDark
        appliedMode = nil
        appliedExpression = nil
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
            // Run Entry/Resolve before accepting a one-shot request; Resolve clears celebration.
            stateMachine.advance(by: 0)
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
            discardTransientFeedback()
            return
        }
        guard let feedback, consumedFeedbackID != feedback.id else { return }
        consumedFeedbackID = feedback.id
        guard let instance = rive?.viewModelInstance else { return }
        instance.setValue(of: Self.expressionProperty, to: 0)
        appliedExpression = 0
        hasIssuedFeedback = true
        switch feedback.kind {
        case .acknowledge:
            instance.fire(trigger: Self.acknowledgeProperty)
        case .celebrate:
            instance.setValue(of: Self.celebrateProperty, to: true)
        }
    }

    func suspend() {
        loadGeneration = nil
        discardTransientFeedback()
    }

    private func discardTransientFeedback() {
        guard hasIssuedFeedback || hasPresentedIdleExpression,
              let rive, let instance = rive.viewModelInstance else { return }
        let hadFeedback = hasIssuedFeedback
        hasIssuedFeedback = false
        hasPresentedIdleExpression = false
        appliedExpression = 0
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
            // Finish Close -> Resolve -> Auto while hidden, so resuming cannot flash
            // the old idle face. Fixed worker commands, without a drawing loop.
            rive.stateMachine.advance(by: 0.12)
            rive.stateMachine.advance(by: 0.12)
            rive.stateMachine.advance(by: 0.12)
        }
    }

    private func checkLoad(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard loadGeneration == generation else { throw CancellationError() }
    }

    private func applyInputs(controller: MascotController, to instance: ViewModelInstance) {
        // Clear a spontaneous face before applying an editing or task-state change.
        if appliedExpression != controller.expression {
            instance.setValue(of: Self.expressionProperty, to: Float(controller.expression))
            appliedExpression = controller.expression
            if controller.expression != 0 { hasPresentedIdleExpression = true }
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
