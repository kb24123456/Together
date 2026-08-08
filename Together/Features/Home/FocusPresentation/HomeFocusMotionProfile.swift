import UIKit

enum HomeFocusMotionProfile {
    static let duration: TimeInterval = 0.38
    static let creationDuration: TimeInterval = 0.30
    static let dampingRatio: CGFloat = 0.94
    static let backgroundScale: CGFloat = 0.985
    static let expandedCornerRadius: CGFloat = 28
    static let compactCornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.14
    static let shadowRadius: CGFloat = 24
    static let shadowOffset = CGSize(width: 0, height: 10)

    static func timing(initialVelocity: CGVector = .zero) -> UISpringTimingParameters {
        UISpringTimingParameters(dampingRatio: dampingRatio, initialVelocity: initialVelocity)
    }
}
