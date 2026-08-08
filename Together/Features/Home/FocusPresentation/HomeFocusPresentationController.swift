import SwiftUI
import UIKit

@MainActor
final class HomeFocusPresentationController: UIViewController {
    let backgroundControl = UIControl(frame: .zero)
    let blurView = UIVisualEffectView(effect: nil)
    let dimView = UIView(frame: .zero)
    let surfaceShadowView = UIView(frame: .zero)
    let surfaceContainerView = UIView(frame: .zero)

    private let surfaceHost = UIHostingController(rootView: AnyView(EmptyView()))
    private weak var model: HomeFocusPresentationModel?

    override func loadView() {
        let root = UIView(frame: .zero)
        root.backgroundColor = .clear
        root.isUserInteractionEnabled = false
        root.accessibilityElementsHidden = true
        view = root

        backgroundControl.backgroundColor = .clear
        backgroundControl.addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)
        installFullScreen(backgroundControl, in: root)

        blurView.isUserInteractionEnabled = false
        installFullScreen(blurView, in: root)

        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        installFullScreen(dimView, in: root)

        surfaceShadowView.backgroundColor = .clear
        surfaceShadowView.layer.shadowColor = UIColor.black.cgColor
        surfaceShadowView.layer.shadowOpacity = HomeFocusMotionProfile.shadowOpacity
        surfaceShadowView.layer.shadowRadius = HomeFocusMotionProfile.shadowRadius
        surfaceShadowView.layer.shadowOffset = HomeFocusMotionProfile.shadowOffset
        root.addSubview(surfaceShadowView)

        surfaceContainerView.backgroundColor = UIColor.systemBackground
        surfaceContainerView.clipsToBounds = true
        surfaceContainerView.layer.cornerCurve = .continuous
        surfaceContainerView.layer.cornerRadius = HomeFocusMotionProfile.expandedCornerRadius
        surfaceShadowView.addSubview(surfaceContainerView)

        addChild(surfaceHost)
        surfaceHost.view.backgroundColor = .clear
        surfaceContainerView.addSubview(surfaceHost.view)
        surfaceHost.didMove(toParent: self)
    }

    func configure(model: HomeFocusPresentationModel, focusView: AnyView) {
        self.model = model
        surfaceHost.rootView = focusView
    }

    func activate() {
        view.isHidden = false
        view.isUserInteractionEnabled = true
        view.accessibilityElementsHidden = false
        backgroundControl.isEnabled = true
    }

    func deactivate() {
        surfaceShadowView.layer.removeAllAnimations()
        surfaceContainerView.layer.removeAllAnimations()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.isHidden = true
        backgroundControl.isEnabled = false
        blurView.effect = nil
        dimView.alpha = 0
        surfaceShadowView.layer.shadowOpacity = 0
    }

    func prepareSurface(sourceFrame: CGRect, targetSize: CGSize) {
        surfaceShadowView.frame = sourceFrame
        surfaceContainerView.frame = surfaceShadowView.bounds
        surfaceContainerView.layer.cornerRadius = HomeFocusMotionProfile.compactCornerRadius
        surfaceShadowView.layer.shadowOpacity = 0
        surfaceHost.view.frame = CGRect(origin: .zero, size: targetSize)
        surfaceHost.view.setNeedsLayout()
        surfaceHost.view.layoutIfNeeded()
        surfaceShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: surfaceShadowView.bounds,
            cornerRadius: HomeFocusMotionProfile.compactCornerRadius
        ).cgPath
    }

    func setSurfaceFrame(_ frame: CGRect, cornerRadius: CGFloat, showsShadow: Bool) {
        surfaceShadowView.bounds = CGRect(origin: .zero, size: frame.size)
        surfaceShadowView.center = CGPoint(x: frame.midX, y: frame.midY)
        surfaceContainerView.frame = surfaceShadowView.bounds
        surfaceContainerView.layer.cornerRadius = cornerRadius
        surfaceShadowView.layer.shadowOpacity = showsShadow ? HomeFocusMotionProfile.shadowOpacity : 0
        surfaceShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: surfaceShadowView.bounds,
            cornerRadius: cornerRadius
        ).cgPath
    }

    func presentationSurfaceFrame() -> CGRect? {
        guard let presentation = surfaceShadowView.layer.presentation() else { return nil }
        return presentation.frame
    }

    func capturePresentationState() -> SurfacePresentationState? {
        guard let shadowPresentation = surfaceShadowView.layer.presentation() else { return nil }
        let surfacePresentation = surfaceContainerView.layer.presentation()
        return SurfacePresentationState(
            frame: shadowPresentation.frame,
            cornerRadius: surfacePresentation?.cornerRadius ?? surfaceContainerView.layer.cornerRadius,
            shadowOpacity: shadowPresentation.shadowOpacity
        )
    }

    func applyPresentationState(_ state: SurfacePresentationState) {
        surfaceShadowView.layer.removeAllAnimations()
        surfaceContainerView.layer.removeAllAnimations()
        surfaceShadowView.frame = state.frame
        surfaceContainerView.frame = surfaceShadowView.bounds
        surfaceContainerView.layer.cornerRadius = state.cornerRadius
        surfaceShadowView.layer.shadowOpacity = state.shadowOpacity
        surfaceShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: surfaceShadowView.bounds,
            cornerRadius: state.cornerRadius
        ).cgPath
    }

    @objc private func backgroundTapped() {
        model?.handleBackgroundTap()
    }

    private func installFullScreen(_ child: UIView, in root: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            child.topAnchor.constraint(equalTo: root.topAnchor),
            child.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }
}

struct SurfacePresentationState {
    let frame: CGRect
    let cornerRadius: CGFloat
    let shadowOpacity: Float
}
