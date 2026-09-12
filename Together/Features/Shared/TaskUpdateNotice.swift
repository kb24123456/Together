import UIKit

/// The surface grows; its single, reparented mascot and text never stretch.
@MainActor
final class TaskUpdateNotice: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "together.task-update-notice"
        layer.masksToBounds = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isAccessibilityElement = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func configure(message: String, announcement: String, diameter: CGFloat, isDark: Bool) -> CGFloat {
        label.text = message
        accessibilityLabel = announcement
        // The toolbar height limits text growth; preserve the full result for VoiceOver.
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .medium),
            maximumPointSize: min(24, diameter * 0.6), compatibleWith: traitCollection
        )
        label.textColor = isDark ? UIColor(white: 0.106, alpha: 1) : .white
        let gradient = layer as! CAGradientLayer
        gradient.colors = isDark
            ? [UIColor(white: 240 / 255, alpha: 1).cgColor, UIColor(white: 213 / 255, alpha: 1).cgColor]
            : [UIColor(white: 16 / 255, alpha: 1).cgColor, UIColor(white: 3 / 255, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.cornerRadius = diameter / 2
        return ceil(label.intrinsicContentSize.width) + diameter + 28
    }

    func placeText(diameter: CGFloat, width: CGFloat) {
        label.frame = CGRect(x: diameter + 8, y: 0,
                             width: max(0, width - diameter - 28), height: diameter)
    }
}
