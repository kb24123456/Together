import UIKit

@MainActor
final class HomeFocusPresentationCoordinator: NSObject, HomeFocusPresentationDriving {
    private weak var backgroundView: UIView?
    private weak var presentationController: HomeFocusPresentationController?
    private weak var model: HomeFocusPresentationModel?
    private var animator: UIViewPropertyAnimator?
    private var expandedFrame: CGRect?
    private var isAtExpandedEndpoint = false

    init(
        backgroundView: UIView,
        presentationController: HomeFocusPresentationController,
        model: HomeFocusPresentationModel
    ) {
        self.backgroundView = backgroundView
        self.presentationController = presentationController
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameDidChange(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func present(
        subject: HomeFocusSubject,
        sourceFrame: CGRect,
        targetFrame: CGRect,
        token: HomeFocusSessionToken
    ) {
        guard let presentationController else { return }
        stopAtCurrentPresentation()
        expandedFrame = targetFrame
        isAtExpandedEndpoint = false
        presentationController.activate()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let effectiveSourceFrame = reduceMotion
            ? CGRect(
                x: targetFrame.minX,
                y: targetFrame.minY + 8,
                width: targetFrame.width,
                height: max(44, targetFrame.height - 16)
            )
            : sourceFrame
        presentationController.prepareSurface(sourceFrame: effectiveSourceFrame, targetSize: targetFrame.size)

        let duration = reduceMotion
            ? 0.16
            : (subject.isCreation ? HomeFocusMotionProfile.creationDuration : HomeFocusMotionProfile.duration)
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: HomeFocusMotionProfile.timing()
        )
        animator.addAnimations { [weak self] in
            guard let self, let presentationController = self.presentationController else { return }
            presentationController.setSurfaceFrame(
                targetFrame,
                cornerRadius: HomeFocusMotionProfile.expandedCornerRadius,
                showsShadow: true
            )
            self.applyFocusedBackground(reduceMotion: reduceMotion)
        }
        animator.addCompletion { [weak self] position in
            guard position == .end else { return }
            self?.animator = nil
            self?.isAtExpandedEndpoint = true
            self?.model?.finishPresentation(using: token)
        }
        self.animator = animator
        animator.startAnimation()
    }

    func dismiss(to targetFrame: CGRect, token: HomeFocusSessionToken) {
        animateToCompact(targetFrame: targetFrame, token: token, isLanding: false)
    }

    func land(to targetFrame: CGRect, token: HomeFocusSessionToken) {
        animateToCompact(targetFrame: targetFrame, token: token, isLanding: true)
    }

    func recover(token: HomeFocusSessionToken) {
        animator?.stopAnimation(true)
        animator = nil
        restoreBackgroundImmediately()
        expandedFrame = nil
        isAtExpandedEndpoint = false
        model?.finishRecovery(using: token)
        backgroundView?.setNeedsLayout()
        backgroundView?.layoutIfNeeded()
        presentationController?.deactivate()
    }

    private func animateToCompact(
        targetFrame: CGRect,
        token: HomeFocusSessionToken,
        isLanding: Bool
    ) {
        guard presentationController != nil else { return }
        stopAtCurrentPresentation()
        isAtExpandedEndpoint = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let animator = UIViewPropertyAnimator(
            duration: reduceMotion ? 0.16 : HomeFocusMotionProfile.duration,
            timingParameters: HomeFocusMotionProfile.timing()
        )
        animator.addAnimations { [weak self] in
            guard let self, let presentationController = self.presentationController else { return }
            presentationController.setSurfaceFrame(
                targetFrame,
                cornerRadius: HomeFocusMotionProfile.compactCornerRadius,
                showsShadow: false
            )
            self.applyRestoredBackground()
        }
        animator.addCompletion { [weak self] position in
            guard let self, position == .end else { return }
            self.animator = nil
            self.expandedFrame = nil
            if isLanding {
                self.model?.finishLanding(using: token)
            } else {
                self.model?.finishDismissal(using: token)
            }
            self.backgroundView?.setNeedsLayout()
            self.backgroundView?.layoutIfNeeded()
            self.presentationController?.deactivate()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func stopAtCurrentPresentation() {
        let surfaceState = presentationController?.capturePresentationState()
        let backgroundTransform = backgroundView?.layer.presentation()?.affineTransform()
        let dimOpacity = presentationController?.dimView.layer.presentation()?.opacity
        if let animator {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            self.animator = nil
        }
        if let surfaceState {
            presentationController?.applyPresentationState(surfaceState)
        }
        if let backgroundTransform {
            backgroundView?.transform = backgroundTransform
        }
        if let dimOpacity {
            presentationController?.dimView.alpha = CGFloat(dimOpacity)
        }
    }

    private func applyFocusedBackground(reduceMotion: Bool) {
        guard let backgroundView, let presentationController else { return }
        if reduceMotion == false {
            backgroundView.transform = CGAffineTransform(
                scaleX: HomeFocusMotionProfile.backgroundScale,
                y: HomeFocusMotionProfile.backgroundScale
            )
        }
        if UIAccessibility.isReduceTransparencyEnabled == false, reduceMotion == false {
            presentationController.blurView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        presentationController.dimView.alpha = dimAlpha
    }

    private func applyRestoredBackground() {
        backgroundView?.transform = .identity
        presentationController?.blurView.effect = nil
        presentationController?.dimView.alpha = 0
    }

    private func restoreBackgroundImmediately() {
        backgroundView?.layer.removeAllAnimations()
        backgroundView?.transform = .identity
        presentationController?.blurView.layer.removeAllAnimations()
        presentationController?.blurView.effect = nil
        presentationController?.dimView.layer.removeAllAnimations()
        presentationController?.dimView.alpha = 0
    }

    private var dimAlpha: CGFloat {
        guard let traits = presentationController?.traitCollection else { return 0.10 }
        if UIAccessibility.isReduceTransparencyEnabled { return traits.userInterfaceStyle == .dark ? 0.26 : 0.18 }
        return traits.userInterfaceStyle == .dark ? 0.16 : 0.10
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard isAtExpandedEndpoint,
              let expandedFrame,
              let presentationController,
              let screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let keyboardFrame = presentationController.view.convert(screenFrame, from: nil)
        let availableFrame = HomeFocusGeometryPolicy.availableFrame(
            in: presentationController.view.bounds,
            safeAreaInsets: presentationController.view.safeAreaInsets
        )
        let isHiding = notification.name == UIResponder.keyboardWillHideNotification
            || keyboardFrame.minY >= presentationController.view.bounds.maxY
        let correction = isHiding ? 0 : HomeFocusGeometryPolicy.keyboardVerticalCorrection(
            cardFrame: expandedFrame,
            keyboardFrame: keyboardFrame,
            availableFrame: availableFrame,
            clearance: 12
        )
        let adjustedFrame = expandedFrame.offsetBy(dx: 0, dy: correction)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRawValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState]) {
            presentationController.setSurfaceFrame(
                adjustedFrame,
                cornerRadius: HomeFocusMotionProfile.expandedCornerRadius,
                showsShadow: true
            )
        }
    }
}

private extension HomeFocusSubject {
    var isCreation: Bool {
        if case .creation = self { return true }
        return false
    }
}
