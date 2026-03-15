import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum HomeInteractionFeedback {
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)

    static func selection() {
        #if canImport(UIKit)
        softGenerator.prepare()
        softGenerator.impactOccurred(intensity: 0.88)
        #endif
    }

    static func soft() {
        #if canImport(UIKit)
        softGenerator.prepare()
        softGenerator.impactOccurred(intensity: 0.96)
        #endif
    }

    static func completion() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}
