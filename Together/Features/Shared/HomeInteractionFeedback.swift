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

    /// 破坏性删除确认触感（警告级 notification）。
    static func delete() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #endif
    }

    /// 错误路径触感（error notification），配合 alert 给用户多一层感知。
    static func error() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
        #endif
    }

    /// 警示性触感（medium impact），用于表单验证失败或 unbind 二次确认。
    static func warning() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.92)
        #endif
    }
}
