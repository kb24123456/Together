import UIKit

/// A temporary native face in the existing artwork, not another Rive renderer.
@MainActor
final class MascotConfirmationView: UIView {
    enum Phase { case idle, ready, confirming, restoring, suppressed }
    private(set) var phase: Phase = .idle
    private let mainStroke = CAShapeLayer()
    private let secondaryStroke = CAShapeLayer()
    private var generation = UUID()
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        isHidden = true
        layer.cornerRadius = 20
        layer.masksToBounds = true
        for stroke in [mainStroke, secondaryStroke] {
            stroke.fillColor = nil
            stroke.lineWidth = 3.2
            stroke.lineCap = .round
            stroke.lineJoin = .round
            layer.addSublayer(stroke)
        }
        setPose(MascotConfirmationMotion.idle)
    }

    required init?(coder: NSCoder) { nil }

    func configure(isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gradient = layer as! CAGradientLayer
        gradient.colors = isDark
            ? [UIColor(white: 240 / 255, alpha: 1).cgColor, UIColor(white: 213 / 255, alpha: 1).cgColor]
            : [UIColor(white: 16 / 255, alpha: 1).cgColor, UIColor(white: 3 / 255, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        let color = isDark ? UIColor(white: 0.106, alpha: 1) : .white
        mainStroke.strokeColor = color.cgColor
        secondaryStroke.strokeColor = color.cgColor
        CATransaction.commit()
    }

    func prepare(animated: Bool) {
        reset()
        guard animated else { phase = .suppressed; return }
        phase = .ready
        isHidden = false
        alpha = 0
        // Normalize an incidental home expression while the capsule opens.
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.alpha = 1
        }
    }

    func confirm(animated: Bool) {
        guard animated else { suppress(); return }
        guard phase == .ready || phase == .restoring else { return }
        let initial = currentPose()
        phase = .confirming
        animate(duration: MascotConfirmationMotion.entranceDuration) {
            MascotConfirmationMotion.entering(at: $0 * MascotConfirmationMotion.entranceDuration, from: initial)
        }
    }

    func restore(animated: Bool, duration: TimeInterval) {
        guard !isHidden else { return }
        guard animated else { suppress(); return }
        let initial = currentPose()
        phase = .restoring
        animate(duration: duration) {
            MascotConfirmationMotion.restoring(
                at: $0 * MascotConfirmationMotion.restorationDuration, from: initial
            )
        }
    }

    func finish(animated: Bool) {
        guard animated, !isHidden else { reset(); return }
        let id = generation
        UIView.animate(withDuration: 0.10, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.generation == id else { return }
            self.reset()
        }
    }

    func suppress() {
        reset()
        phase = .suppressed
    }

    func reset() {
        generation = UUID()
        layer.removeAllAnimations()
        mainStroke.removeAllAnimations()
        secondaryStroke.removeAllAnimations()
        setPose(MascotConfirmationMotion.idle)
        alpha = 0
        isHidden = true
        phase = .idle
    }

    private func animate(duration: TimeInterval, pose: (Double) -> MascotConfirmationMotion.Pose) {
        let poses = (0...60).map { pose(Double($0) / 60) }
        guard let final = poses.last else { return }
        mainStroke.removeAllAnimations()
        secondaryStroke.removeAllAnimations()
        setPose(final)
        for (stroke, paths) in [(mainStroke, poses.map { path($0.main) }),
                                (secondaryStroke, poses.map { path($0.secondary) })] {
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = paths
            animation.duration = duration
            animation.calculationMode = .linear
            stroke.add(animation, forKey: "confirmation")
        }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = poses.map { NSNumber(value: Double($0.secondaryOpacity)) }
        opacity.duration = duration
        secondaryStroke.add(opacity, forKey: "confirmation-opacity")
    }

    private func currentPose() -> MascotConfirmationMotion.Pose {
        let main = mainStroke.presentation() ?? mainStroke
        let secondary = secondaryStroke.presentation() ?? secondaryStroke
        return .init(main: points(main.path, fallback: MascotConfirmationMotion.idle.main),
                     secondary: points(secondary.path, fallback: MascotConfirmationMotion.idle.secondary),
                     secondaryOpacity: CGFloat(secondary.opacity))
    }

    private func setPose(_ pose: MascotConfirmationMotion.Pose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mainStroke.path = path(pose.main)
        secondaryStroke.path = path(pose.secondary)
        secondaryStroke.opacity = Float(pose.secondaryOpacity)
        CATransaction.commit()
    }

    private func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    private func points(_ path: CGPath?, fallback: [CGPoint]) -> [CGPoint] {
        var points: [CGPoint] = []
        path?.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .moveToPoint || element.type == .addLineToPoint {
                points.append(element.points[0])
            }
        }
        return points.count == fallback.count ? points : fallback
    }
}
