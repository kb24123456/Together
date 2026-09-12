import UIKit
import RiveRuntime
#if DEBUG
import OSLog
#endif

/// The only rendered character. Toolbars contain layout anchors, never another copy.
@MainActor
final class MascotVisualTransfer {
    let artwork = MascotArtworkView()
    var onDock: ((MascotSurface) -> Void)?
    var onNoticeActiveChange: ((Bool) -> Void)?
    var onNoticePresented: ((MascotNoticeRequest) -> Void)?
    private let overlay = UIView()
    private let noticeView = TaskUpdateNotice(frame: .zero)
    private var noticeState = MascotNoticeState()
    private var noticeAnimator: UIViewPropertyAnimator?
    private var noticeAnimationID = UUID()
    private var noticeSourceFrame: CGRect?
    private var presentedNoticeID: UUID?
    private var notifiedNoticeID: UUID?
    private var noticeStartScheduled = false
    private var isDark = false
    private var state = MascotTransferState()
    private var anchors: [UUID: WeakAnchor] = [:]
    private var sequence = 0
    private var restFrames: [MascotSurface: CGRect] = [:]
    private var nativeTransitionID: UUID?
    private var nativeCoordinatorID: ObjectIdentifier?
    private var fallbackAnimator: UIViewPropertyAnimator?
    private var fallbackCompletion: (id: UUID, cancelled: Bool)?
    private var entrance: Entrance?
    private var lastDockedSurface: MascotSurface?
    private weak var editorController: UIViewController?
    private var motionAllowed = false
    private var visible = false
    private var playbackAllowed = false
    private static let defaultEntranceDuration: TimeInterval = 0.34

    private struct WeakAnchor {
        weak var view: MascotAnchorView?
        let sequence: Int
    }

    private struct Entrance {
        let id: UUID
        var duration: TimeInterval?
        var geometryReady = false
        var targetFrame: CGRect?
        var nativeFinished = false
        var animationFinished = false
        var startScheduled = false
        #if DEBUG
        var hasReportedDisabledLayout = false
        #endif
    }

    init() {
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        overlay.backgroundColor = .clear
        artwork.onWindowChanged = { [weak self] in self?.updatePlayback() }
    }

    deinit {
        // A root can be removed while its decorative layer is still in the window.
        let view = overlay
        DispatchQueue.main.async { view.removeFromSuperview() }
    }

    func update(rive: Rive?, animatedArtwork: Bool, staticAsset: String,
                playbackAllowed: Bool, motionAllowed: Bool, visible: Bool, isDark: Bool = false) {
        let themeChanged = self.isDark != isDark
        self.isDark = isDark
        self.playbackAllowed = playbackAllowed
        self.visible = visible
        artwork.riveView.rive = rive
        artwork.riveView.isHidden = !animatedArtwork
        artwork.imageView.isHidden = animatedArtwork
        artwork.imageView.image = UIImage(named: staticAsset)
        artwork.isHidden = !visible
        let stopsMotion = self.motionAllowed && !motionAllowed
        self.motionAllowed = motionAllowed
        if !visible { cancelNotice() }
        if noticeView.superview != nil {
            if stopsMotion {
                if noticeState.isDismissing { cancelNotice() }
                else { presentNoticeIfReady(force: true) }
            } else if themeChanged {
                presentNoticeIfReady(force: true)
            }
        }
        if stopsMotion {
            let completion = fallbackCompletion
            freezePresentation()
            if let completion {
                if entrance?.id == completion.id {
                    entrance?.animationFinished = true
                    completeEntranceIfReady()
                } else {
                    _ = state.complete(id: completion.id, cancelled: completion.cancelled)
                    dock(at: state.settledSurface)
                }
            }
        }
        updatePlayback()
        if state.transition == nil { dock(at: state.settledSurface) }
        startEntranceIfReady()
    }

    func register(_ anchor: MascotAnchorView) {
        sequence += 1
        anchors[anchor.registrationID] = WeakAnchor(view: anchor, sequence: sequence)
        anchorChanged(anchor)
    }

    func unregister(_ anchor: MascotAnchorView) {
        anchors.removeValue(forKey: anchor.registrationID)
        if anchor.surface == .home, self.anchor(for: .home) == nil { cancelNotice() }
        if artwork.superview === anchor, state.transition == nil {
            artwork.riveView.isPaused = true
            dock(at: state.settledSurface)
        }
    }

    func anchorChanged(_ anchor: MascotAnchorView) {
        guard anchor.window != nil, anchor.bounds.width > 0, anchor.bounds.height > 0 else { return }
        if noticeView.superview != nil, anchor.surface == .home,
           let original = noticeSourceFrame {
            let current = anchor.convert(anchor.bounds, to: overlay)
            // Rotation or a changed native toolbar cancels stale geometry immediately.
            if targetMovedBeyondPixel(from: original, to: current) { cancelNotice() }
        }
        // Resting window geometry is safe to cache; moving UIKit ancestors are not.
        if state.transition == nil, anchor.surface == state.settledSurface {
            restFrames[anchor.surface] = anchor.convert(anchor.bounds, to: anchor.window)
            dock(at: anchor.surface)
        } else if anchor.surface == state.transition?.destination {
            startEntranceIfReady()
        }
    }

    func editorLayoutChanged(observer: UIViewController) {
        guard observer.isViewLoaded, observer.view.window != nil else { return }
        editorController = presentedAncestor(of: observer)
        #if DEBUG
        if let entrance, !entrance.geometryReady {
            Logger(subsystem: "com.pigdog.Together", category: "Motion").notice(
                "[Motion] entrance geometry available id=\(entrance.id.uuidString, privacy: .public)"
            )
        }
        #endif
        entrance?.geometryReady = true
        if entrance?.duration == nil {
            entrance?.duration = observer.transitionCoordinator?.transitionDuration ?? Self.defaultEntranceDuration
        }
        startEntranceIfReady()
    }

    func prepare(from source: MascotSurface, to destination: MascotSurface) {
        cancelNotice()
        let previousID = state.transition?.id
        let transition = state.begin(from: source, to: destination)
        guard transition.id != previousID else { return }
        nativeTransitionID = nil
        nativeCoordinatorID = nil
        freezePresentation()
        lastDockedSurface = nil
        if source == .home, case .editor = destination {
            entrance = Entrance(id: transition.id)
            #if DEBUG
            Logger(subsystem: "com.pigdog.Together", category: "Motion").notice(
                "[Motion] entrance prepared id=\(transition.id.uuidString, privacy: .public) motion=\(self.motionAllowed) visible=\(self.visible) uiAnimations=\(UIView.areAnimationsEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)"
            )
            #endif
        } else {
            entrance = nil
        }
        liftIntoWindow()
    }

    func coordinate(from source: MascotSurface, to destination: MascotSurface,
                    coordinator: any UIViewControllerTransitionCoordinator,
                    observer: UIViewController) {
        let coordinatorID = ObjectIdentifier(coordinator)
        // A cancelled dismissal emits appearance callbacks on the same coordinator.
        guard nativeCoordinatorID != coordinatorID else { return }
        prepare(from: source, to: destination)
        guard let transition = state.transition else { return }
        editorController = presentedAncestor(of: observer)
        if entrance?.id == transition.id {
            coordinateEntrance(transition, coordinator: coordinator)
            return
        }
        guard liftIntoWindow() else { return }

        nativeCoordinatorID = coordinatorID
        nativeTransitionID = transition.id
        let startFrame = artwork.convert(artwork.bounds, to: overlay)
        let joined = coordinator.animateAlongsideTransition(in: overlay, animation: { [weak self] _ in
            guard let self, self.state.transition?.id == transition.id else { return }
            self.overlay.superview?.bringSubviewToFront(self.overlay)
            guard let target = self.targetFrame(for: destination, finalGeometry: true) else { return }
            if self.motionAllowed {
                self.placeInOverlay(target)
            } else {
                UIView.performWithoutAnimation { self.placeInOverlay(target) }
            }
        }, completion: { [weak self] context in
            let cancelled = context.isCancelled
            // A failed registration can also invoke completion. Inspect the accepted
            // registration after animateAlongsideTransition has returned its Bool.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.nativeTransitionID == transition.id else { return }
                self.nativeTransitionID = nil
                self.nativeCoordinatorID = nil
                self.finish(id: transition.id, cancelled: cancelled)
            }
        })
        if !joined {
            nativeTransitionID = nil
            nativeCoordinatorID = nil
            UIView.performWithoutAnimation { placeInOverlay(startFrame) }
            // The destination's didAppear supplies settled geometry without guessing
            // when UIKit has finished. It will start the short fallback if needed.
        }
    }

    /// The modal lifecycle confirms availability; it does not override an active clock.
    func arrive(at surface: MascotSurface) {
        if let transition = state.transition {
            if entrance?.id == transition.id {
                if surface == transition.destination {
                    entrance?.nativeFinished = true
                    if entrance?.duration == nil { entrance?.duration = Self.defaultEntranceDuration }
                    startEntranceIfReady()
                    completeEntranceIfReady()
                } else if surface == transition.source {
                    cancelEntrance(id: transition.id)
                }
                return
            }
            guard nativeTransitionID == nil, fallbackAnimator == nil else { return }
            if transition.destination == surface {
                finish(id: transition.id, cancelled: false)
            } else if transition.source == surface {
                finish(id: transition.id, cancelled: true)
            }
        } else {
            if state.settledSurface != surface {
                prepare(from: state.settledSurface, to: surface)
                arrive(at: surface)
            } else {
                dock(at: surface)
            }
        }
    }

    private func coordinateEntrance(
        _ transition: MascotVisualTransition,
        coordinator: any UIViewControllerTransitionCoordinator
    ) {
        let coordinatorID = ObjectIdentifier(coordinator)
        entrance?.duration = coordinator.transitionDuration
        nativeTransitionID = transition.id
        nativeCoordinatorID = coordinatorID
        // Observe the native outcome now. The entrance position has its own single
        // clock once the new toolbar has geometry; no late coordinator registration.
        _ = coordinator.animateAlongsideTransition(in: overlay, animation: nil) { [weak self] context in
            let cancelled = context.isCancelled
            DispatchQueue.main.async { [weak self] in
                guard let self, self.entrance?.id == transition.id,
                      self.nativeCoordinatorID == coordinatorID else { return }
                self.nativeTransitionID = nil
                self.nativeCoordinatorID = nil
                if cancelled {
                    self.cancelEntrance(id: transition.id)
                } else {
                    self.entrance?.nativeFinished = true
                    self.startEntranceIfReady()
                    self.completeEntranceIfReady()
                }
            }
        }
        startEntranceIfReady()
    }

    private func startEntranceIfReady() {
        guard let entrance, let duration = entrance.duration,
              !entrance.animationFinished, entrance.geometryReady || entrance.nativeFinished,
              let transition = state.transition, transition.id == entrance.id else { return }
        if entrance.nativeFinished, anchor(for: transition.destination) == nil {
            artwork.riveView.isPaused = true
            artwork.removeFromSuperview()
            overlay.removeFromSuperview()
            return
        }
        guard liftIntoWindow() else {
            // A launch directly into an editor may have no visible Home source.
            if entrance.nativeFinished, anchor(for: transition.destination) != nil {
                self.entrance?.animationFinished = true
                completeEntranceIfReady()
            }
            return
        }
        guard let target = targetFrame(
            for: transition.destination, finalGeometry: !entrance.nativeFinished
        ) else { return }
        if let animator = fallbackAnimator {
            guard animator.state == .active, let previous = entrance.targetFrame,
                  targetMovedBeyondPixel(from: previous, to: target) else { return }
            self.entrance?.targetFrame = target
            // Active additions use this animator's remaining time; they neither
            // restart the entrance nor append a correction after it has stopped.
            animator.addAnimations { [weak self] in self?.placeInOverlay(target) }
            return
        }
        // SwiftUI can lay out a newly presented toolbar with UIKit animations
        // disabled. An animator started there jumps to its end despite a duration.
        // Leave that transaction before starting, then read the latest geometry.
        if motionAllowed, visible, !UIView.areAnimationsEnabled {
            guard !entrance.startScheduled else { return }
            #if DEBUG
            if !entrance.hasReportedDisabledLayout {
                self.entrance?.hasReportedDisabledLayout = true
                Logger(subsystem: "com.pigdog.Together", category: "Motion").notice(
                    "[Motion] entrance deferred outside disabled layout id=\(transition.id.uuidString, privacy: .public)"
                )
            }
            #endif
            self.entrance?.startScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.entrance?.id == transition.id else { return }
                self.entrance?.startScheduled = false
                self.startEntranceIfReady()
            }
            return
        }
        overlay.superview?.bringSubviewToFront(overlay)
        self.entrance?.targetFrame = target
        #if DEBUG
        Logger(subsystem: "com.pigdog.Together", category: "Motion").notice(
            "[Motion] entrance start id=\(transition.id.uuidString, privacy: .public) duration=\(duration) motion=\(self.motionAllowed) visible=\(self.visible) uiAnimations=\(UIView.areAnimationsEnabled)"
        )
        #endif
        guard motionAllowed, visible, duration > 0 else {
            UIView.performWithoutAnimation { placeInOverlay(target) }
            self.entrance?.animationFinished = true
            completeEntranceIfReady()
            return
        }

        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) { [weak self] in
            self?.placeInOverlay(target)
        }
        fallbackAnimator = animator
        fallbackCompletion = (transition.id, false)
        animator.addCompletion { [weak self] _ in
            guard let self, self.entrance?.id == transition.id else { return }
            self.fallbackAnimator = nil
            self.fallbackCompletion = nil
            self.entrance?.animationFinished = true
            self.completeEntranceIfReady()
        }
        animator.startAnimation()
    }

    private func targetMovedBeyondPixel(from previous: CGRect, to target: CGRect) -> Bool {
        let tolerance = 1 / max(overlay.traitCollection.displayScale, 1)
        return abs(previous.midX - target.midX) > tolerance
            || abs(previous.midY - target.midY) > tolerance
            || abs(previous.width - target.width) > tolerance
            || abs(previous.height - target.height) > tolerance
    }

    private func completeEntranceIfReady() {
        guard let entrance, entrance.nativeFinished, entrance.animationFinished,
              let transition = state.transition, transition.id == entrance.id else { return }
        self.entrance = nil
        nativeTransitionID = nil
        nativeCoordinatorID = nil
        _ = state.complete(id: transition.id, cancelled: false)
        dock(at: transition.destination)
    }

    private func cancelEntrance(id: UUID) {
        guard entrance?.id == id, let transition = state.transition, transition.id == id else { return }
        freezePresentation()
        entrance = nil
        nativeTransitionID = nil
        nativeCoordinatorID = nil
        _ = state.complete(id: id, cancelled: true)
        dock(at: transition.source)
    }

    private func finish(id: UUID, cancelled: Bool) {
        guard let transition = state.transition, transition.id == id else { return }
        let destination = cancelled ? transition.source : transition.destination
        guard let target = targetFrame(for: destination, finalGeometry: false) else {
            _ = state.complete(id: id, cancelled: cancelled)
            dock(at: destination)
            return
        }

        // A returning or cancelled native transition can leave a small distance.
        // Continue from the actual presentation rather than snapping to the dock.
        let current = artwork.convert(artwork.bounds, to: overlay)
        let remaining = abs(current.midX - target.midX) + abs(current.midY - target.midY)
            + abs(current.width - target.width) + abs(current.height - target.height)
        if motionAllowed, visible, artwork.superview === overlay, remaining > 0.5 {
            freezePresentation()
            let animator = UIViewPropertyAnimator(duration: 0.34, dampingRatio: 1) { [weak self] in
                self?.placeInOverlay(target)
            }
            fallbackAnimator = animator
            fallbackCompletion = (id, cancelled)
            animator.addCompletion { [weak self] _ in
                guard let self, self.state.transition?.id == id else { return }
                self.fallbackAnimator = nil
                self.fallbackCompletion = nil
                _ = self.state.complete(id: id, cancelled: cancelled)
                self.dock(at: destination)
            }
            animator.startAnimation()
        } else {
            _ = state.complete(id: id, cancelled: cancelled)
            dock(at: destination)
        }
    }

    @discardableResult
    private func liftIntoWindow() -> Bool {
        if artwork.superview === overlay, overlay.window != nil { return true }
        let source = state.transition?.source ?? state.settledSurface
        let destination = state.transition?.destination ?? state.settledSurface
        guard let window = artwork.window ?? anchor(for: destination)?.window else { return false }
        let frame: CGRect
        if artwork.window === window, let parent = artwork.superview {
            frame = parent.convert(artwork.frame, to: window)
        } else if let saved = restFrames[source] {
            frame = saved
        } else {
            return false
        }
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        UIView.performWithoutAnimation {
            overlay.addSubview(artwork)
            placeInOverlay(frame)
        }
        updatePlayback()
        return true
    }

    private func dock(at surface: MascotSurface) {
        guard state.transition == nil else { return }
        guard noticeView.superview == nil else { return }
        guard let anchor = anchor(for: surface),
              anchor.bounds.width > 0, anchor.bounds.height > 0 else {
            artwork.riveView.isPaused = true
            artwork.removeFromSuperview()
            overlay.removeFromSuperview()
            return
        }
        let shouldNotify = lastDockedSurface != surface || artwork.superview !== anchor
        UIView.performWithoutAnimation {
            if artwork.superview !== anchor { anchor.addSubview(artwork) }
            artwork.center = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
            artwork.transform = CGAffineTransform(
                scaleX: anchor.bounds.width / MascotArtworkView.canvasSide,
                y: anchor.bounds.height / MascotArtworkView.canvasSide
            )
        }
        restFrames[surface] = anchor.convert(anchor.bounds, to: anchor.window)
        overlay.removeFromSuperview()
        updatePlayback()
        lastDockedSurface = surface
        if shouldNotify { onDock?(surface) }
        presentNoticeIfReady()
    }

    func showNotice(_ request: MascotNoticeRequest) {
        noticeState.replace(with: request)
        presentNoticeIfReady()
    }

    func dismissNotice(id: UUID) {
        guard noticeState.dismiss(id: id) else { return }
        guard noticeView.superview != nil, let source = noticeSourceFrame else {
            cancelNotice()
            return
        }
        animateNotice(to: MascotNoticeGeometry.body(in: source), showingText: false) { [weak self] in
            guard let self, self.noticeState.finish(id: id) else { return }
            self.removeNoticeSurface()
        }
    }

    func cancelNotice() {
        noticeState.cancel()
        stopNoticeAnimation()
        if noticeView.superview != nil { removeNoticeSurface() }
    }

    private func presentNoticeIfReady(force: Bool = false) {
        guard let request = noticeState.request, !noticeState.isDismissing,
              state.transition == nil, state.settledSurface == .home, visible,
              let anchor = anchor(for: .home), let window = anchor.window,
              force || presentedNoticeID != request.id else { return }
        // A toolbar update may run with UIKit animations disabled. Start once that
        // layout transaction has ended, keeping the latest request authoritative.
        if motionAllowed && !UIView.areAnimationsEnabled {
            guard !noticeStartScheduled else { return }
            noticeStartScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.noticeStartScheduled = false
                self.presentNoticeIfReady(force: force)
            }
            return
        }
        let isNewSurface = noticeView.superview == nil
        if isNewSurface {
            guard liftIntoWindow() else { return }
            let canvas = anchor.convert(anchor.bounds, to: overlay)
            let body = MascotNoticeGeometry.body(in: canvas)
            noticeSourceFrame = canvas
            UIView.performWithoutAnimation {
                noticeView.frame = body
                overlay.addSubview(noticeView)
                noticeView.addSubview(artwork)
                artwork.center = CGPoint(x: body.width / 2,
                                         y: body.height / 2 + canvas.height * 16 / 512)
                noticeView.bringSubviewToFront(noticeView.label)
                noticeView.label.alpha = 0
            }
            overlay.accessibilityElementsHidden = false
            onNoticeActiveChange?(true)
        }
        guard let source = noticeSourceFrame else { return }
        let body = MascotNoticeGeometry.body(in: source)
        let width = noticeView.configure(message: request.message, announcement: request.announcement,
                                         diameter: body.height, isDark: isDark)
        let target = MascotNoticeGeometry.expanded(
            from: body, in: overlay.bounds,
            safeInsets: max(28, max(window.safeAreaInsets.left, window.safeAreaInsets.right)),
            contentWidth: width
        )
        presentedNoticeID = request.id
        animateNotice(to: target, showingText: true) { [weak self] in
            guard let self, self.noticeState.request?.id == request.id,
                  !self.noticeState.isDismissing else { return }
            if self.notifiedNoticeID != request.id {
                self.notifiedNoticeID = request.id
                self.onNoticePresented?(request)
            }
        }
    }

    private func animateNotice(to frame: CGRect, showingText: Bool, completion: @escaping () -> Void) {
        stopNoticeAnimation()
        let id = noticeAnimationID
        if showingText {
            // Lay out once at the destination width; the expanding surface reveals
            // the text without resizing glyphs or moving text through the eyes.
            UIView.performWithoutAnimation {
                noticeView.placeText(diameter: frame.height, width: frame.width)
            }
        }
        let changes = { [self] in
            noticeView.frame = frame
            noticeView.label.alpha = showingText ? 1 : 0
        }
        guard motionAllowed, !UIAccessibility.isReduceMotionEnabled else {
            UIView.performWithoutAnimation(changes)
            completion()
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.32, curve: .easeInOut, animations: changes)
        noticeAnimator = animator
        animator.addCompletion { [weak self] _ in
            guard let self, self.noticeAnimationID == id else { return }
            self.noticeAnimator = nil
            completion()
        }
        animator.startAnimation()
    }

    private func stopNoticeAnimation() {
        noticeAnimationID = UUID()
        if let animator = noticeAnimator, animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
        }
        noticeAnimator = nil
    }

    private func removeNoticeSurface() {
        stopNoticeAnimation()
        // Restore the existing artwork before removing its temporary parent.
        overlay.addSubview(artwork)
        if let source = noticeSourceFrame { placeInOverlay(source) }
        noticeView.removeFromSuperview()
        noticeSourceFrame = nil
        presentedNoticeID = nil
        notifiedNoticeID = nil
        overlay.accessibilityElementsHidden = true
        onNoticeActiveChange?(false)
        dock(at: state.settledSurface)
    }

    private func targetFrame(for surface: MascotSurface, finalGeometry: Bool) -> CGRect? {
        guard let window = overlay.window else { return nil }
        if let anchor = anchor(for: surface), anchor.window === window, anchor.bounds.width > 0 {
            if finalGeometry, surface == .home,
               let root = window.rootViewController?.view, anchor.isDescendant(of: root),
               let mapped = MascotTransferGeometry.map(
                    anchor.convert(anchor.bounds, to: root), from: root.bounds, to: window.bounds
               ) {
                return window.convert(mapped, to: overlay)
            }
            if finalGeometry, case .editor = surface,
               let presentation = editorController?.presentationController,
               let presented = presentation.presentedView,
               anchor.isDescendant(of: presented),
               let container = presentation.containerView, container.window === window,
               let mapped = MascotTransferGeometry.map(
                    anchor.convert(anchor.bounds, to: presented),
                    from: presented.bounds,
                    to: presentation.frameOfPresentedViewInContainerView
               ) {
                return container.convert(mapped, to: overlay)
            }
            if !finalGeometry { return anchor.convert(anchor.bounds, to: overlay) }
        }
        if let saved = restFrames[surface] { return window.convert(saved, to: overlay) }
        return nil
    }

    private func placeInOverlay(_ frame: CGRect) {
        artwork.center = CGPoint(x: frame.midX, y: frame.midY)
        artwork.transform = CGAffineTransform(
            scaleX: frame.width / MascotArtworkView.canvasSide,
            y: frame.height / MascotArtworkView.canvasSide
        )
    }

    private func freezePresentation() {
        let layer = artwork.layer.presentation()
        let position = layer?.position ?? artwork.layer.position
        let transform = layer?.affineTransform() ?? artwork.transform
        fallbackAnimator?.stopAnimation(true)
        fallbackAnimator = nil
        fallbackCompletion = nil
        artwork.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            artwork.center = position
            artwork.transform = transform
        }
    }

    private func anchor(for surface: MascotSurface) -> MascotAnchorView? {
        anchors = anchors.filter { $0.value.view != nil }
        return anchors.values.filter {
            $0.view?.surface == surface && $0.view?.window != nil
        }.max(by: { $0.sequence < $1.sequence })?.view
    }

    private func presentedAncestor(of controller: UIViewController) -> UIViewController? {
        var candidate: UIViewController? = controller
        var presented: UIViewController?
        while let current = candidate {
            if current.presentingViewController != nil { presented = current }
            candidate = current.parent
        }
        return presented
    }

    private func updatePlayback() {
        artwork.riveView.isPaused = !(playbackAllowed && visible && artwork.window != nil)
    }
}

final class MascotArtworkView: UIView {
    static let canvasSide: CGFloat = 40 * 512 / 368
    let riveView = RiveUIView(rive: nil, isPaused: true)
    let imageView = UIImageView()
    var onWindowChanged: (() -> Void)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.canvasSide, height: Self.canvasSide))
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        riveView.frameRate = .fps(30)
        riveView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        for child in [riveView, imageView] {
            child.frame = bounds
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(child)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
    }
}
