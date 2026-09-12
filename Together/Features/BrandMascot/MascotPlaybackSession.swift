import Foundation
import Observation
import RiveRuntime
import UIKit

/// A single character survives its native navigation-bar presentation surfaces.
@MainActor
@Observable
final class MascotPlaybackSession {
    let controller = MascotController()
    let runtime = MascotRuntime()
    private(set) var ownership = MascotPlaybackOwnership()
    private(set) var animationAllowed = false
    private(set) var isShowingUpdateNotice = false

    private var homeContext = MascotContext()
    @ObservationIgnored private var isDark = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let visual = MascotVisualTransfer()
    @ObservationIgnored private var isInteractivelyReturning = false
    @ObservationIgnored private var surfaceVisible = true
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var noticeID: UUID?

    init() {
        controller.onPresentationChange = { [weak self] in
            self?.synchronize()
        }
        visual.onDock = { [weak self] surface in
            self?.didDock(at: surface)
        }
        visual.onNoticeActiveChange = { [weak self] active in
            guard let self else { return }
            self.isShowingUpdateNotice = active
            if !active {
                self.noticeTask?.cancel()
                self.noticeTask = nil
                self.noticeID = nil
            }
        }
        visual.onNoticePresented = { [weak self] request in
            self?.scheduleNoticeDismissal(request)
        }
    }

    var isEditing: Bool { ownership.editorID != nil }
    var usesAnimatedArtwork: Bool { animationAllowed && runtime.rive != nil }

    func editor(id: UUID) -> MascotEditorHandle {
        MascotEditorHandle(session: self, id: id)
    }

    func updateHomeContext(_ context: MascotContext) {
        homeContext = context
        if !context.isVisible { cancelUpdateNotice() }
        if !isEditing || ownership.isReturning { applyContext() }
    }

    @discardableResult
    func beginEditing(id: UUID) -> Bool {
        cancelUpdateNotice()
        let startsNewSession = ownership.editorID == nil
        guard ownership.beginEditing(id: id) else { return false }
        guard startsNewSession else { return true }
        visual.prepare(from: .home, to: .editor(id))
        applyContext()
        return true
    }

    func beginReturn(id: UUID) {
        guard ownership.beginReturn(id: id) else { return }
        visual.prepare(from: .editor(id), to: .home)
        // The same artwork continues WritingExit while travelling back to Home.
        applyContext()
    }

    func finishEditing(id: UUID) {
        guard ownership.finishEditing(id: id) else { return }
        isInteractivelyReturning = false
        visual.arrive(at: .home)
        applyContext()
    }

    func setEnvironment(animationAllowed: Bool, isDark: Bool, surfaceVisible: Bool) {
        self.isDark = isDark
        self.surfaceVisible = surfaceVisible
        if !surfaceVisible { cancelUpdateNotice() }
        if self.animationAllowed != animationAllowed {
            self.animationAllowed = animationAllowed
            controller.setPlaybackAllowed(animationAllowed)
            if !animationAllowed {
                loadTask?.cancel()
                loadTask = nil
                runtime.suspend()
            }
        }
        synchronize()
    }

    func recordTextInput(from surface: MascotSurface) {
        guard ownership.acceptsInput(from: surface) else { return }
        controller.recordTextInput()
    }

    func stopTyping(from surface: MascotSurface) {
        guard ownership.acceptsInput(from: surface) else { return }
        controller.stopTyping()
    }

    func staticAssetName(for surface: MascotSurface) -> String {
        switch surface {
        case .editor: return "MascotHolding"
        case .home:
            let context = homeContext
            if context.isProcessing { return "MascotThinking" }
            return context.hasOverdueTasks ? "MascotConcerned" : "MascotIdle"
        }
    }

    func presentUpdateNotice(_ feedback: TaskUpdateFeedback) {
        guard !isEditing, homeContext.isVisible else { return }
        noticeTask?.cancel()
        noticeTask = nil
        noticeID = feedback.id
        let message = feedback.message()
        visual.showNotice(MascotNoticeRequest(
            id: feedback.id, message: message, announcement: "\(feedback.title)，\(message)"
        ))
    }

    func cancelUpdateNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        noticeID = nil
        visual.cancelNotice()
    }

    private func scheduleNoticeDismissal(_ request: MascotNoticeRequest) {
        guard noticeID == request.id else { return }
        noticeTask?.cancel()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: request.announcement)
        }
        let duration: TimeInterval = UIAccessibility.isVoiceOverRunning ? 5 : 2.6
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, self.noticeID == request.id else { return }
            self.visual.dismissNotice(id: request.id)
        }
    }

    func register(_ anchor: MascotAnchorView) {
        visual.register(anchor)
        synchronize()
    }

    func unregister(_ anchor: MascotAnchorView) { visual.unregister(anchor) }
    func anchorChanged(_ anchor: MascotAnchorView) { visual.anchorChanged(anchor) }

    func editorLayoutDidChange(id: UUID, observer: UIViewController) {
        guard ownership.editorID == id else { return }
        visual.editorLayoutChanged(observer: observer)
    }

    func coordinateEditorTransition(
        id: UUID, returning: Bool,
        coordinator: any UIViewControllerTransitionCoordinator,
        observer: UIViewController
    ) {
        guard ownership.editorID == id else { return }
        if returning && !ownership.isReturning {
            isInteractivelyReturning = true
            applyContext()
        }
        visual.coordinate(
            from: returning ? .editor(id) : .home,
            to: returning ? .home : .editor(id),
            coordinator: coordinator, observer: observer
        )
    }

    func editorDidAppear(id: UUID) {
        guard ownership.editorID == id, !ownership.isReturning else { return }
        isInteractivelyReturning = false
        visual.arrive(at: .editor(id))
        applyContext()
    }

    func editorDidDisappear(id: UUID) {
        guard ownership.editorID == id else { return }
        // A covering child sheet can also cause this callback. Only root onDismiss
        // finishes editing; native artwork attachment independently pauses rendering.
        synchronize()
    }

    private func applyContext() {
        if isEditing {
            controller.updateContext(
                isVisible: true,
                isEditing: !ownership.isReturning && !isInteractivelyReturning,
                isProcessing: (ownership.isReturning || isInteractivelyReturning) && homeContext.isProcessing,
                hasOverdueTasks: (ownership.isReturning || isInteractivelyReturning) && homeContext.hasOverdueTasks
            )
        } else {
            controller.updateContext(
                isVisible: homeContext.isVisible,
                isProcessing: homeContext.isProcessing,
                hasOverdueTasks: homeContext.hasOverdueTasks,
                isInteracting: homeContext.isInteracting
            )
        }
        synchronize()
    }

    private func didDock(at surface: MascotSurface) {
        guard case let .editor(id) = surface,
              ownership.arriveAtEditor(id: id) else { return }
    }

    private func synchronize() {
        runtime.synchronize(controller: controller, isDark: isDark)
        runtime.consumeFeedback(controller.feedback, canPlay: animationAllowed && controller.isPlaying)
        updateArtwork()

        guard animationAllowed, controller.isPlaying, runtime.rive == nil, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            await runtime.load(controller: controller, isDark: isDark)
            guard !Task.isCancelled else { return }
            loadTask = nil
            updateArtwork()
        }
    }

    private func updateArtwork() {
        visual.update(
            rive: runtime.rive,
            animatedArtwork: usesAnimatedArtwork,
            staticAsset: staticAssetName(for: ownership.surface),
            playbackAllowed: animationAllowed && controller.isPlaying,
            motionAllowed: animationAllowed,
            visible: surfaceVisible && (isEditing || homeContext.isVisible),
            isDark: isDark
        )
    }

}

/// A stale input/focus callback can only affect the editor that owns this handle.
@MainActor
struct MascotEditorHandle {
    let session: MascotPlaybackSession
    let id: UUID

    var surface: MascotSurface { .editor(id) }
    func recordTextInput() { session.recordTextInput(from: surface) }
    func stopTyping() { session.stopTyping(from: surface) }
    func beginReturn() { session.beginReturn(id: id) }
}
