import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum HomeInteractionFeedback {
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

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

    static func swipeReveal() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.82)
        #endif
    }

    static func swipeCommitReady() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.92)
        #endif
    }

    static func menuTap() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        #endif
    }

    static func assigneeChange() {
        #if canImport(UIKit)
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
        #endif
    }
}
