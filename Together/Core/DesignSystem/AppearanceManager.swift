import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@Observable
final class AppearanceManager: @unchecked Sendable {
    private static let storageKey = "app.appearanceMode"

    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            applyUIKitOverride()
        }
    }

    var resolvedColorScheme: ColorScheme? {
        mode.colorScheme
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        self.mode = AppearanceMode(rawValue: stored) ?? .system
    }

    private func applyUIKitOverride() {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light:  style = .light
        case .dark:   style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                applyStyle(style, toViewControllerHierarchy: window.rootViewController)
            }
        }
    }

    // 递归地将样式应用到整个 VC 层级（含 presented VCs，覆盖 fullScreenCover 的 UIHostingController）
    private func applyStyle(_ style: UIUserInterfaceStyle, toViewControllerHierarchy vc: UIViewController?) {
        guard let vc else { return }
        vc.overrideUserInterfaceStyle = style
        for child in vc.children {
            applyStyle(style, toViewControllerHierarchy: child)
        }
        applyStyle(style, toViewControllerHierarchy: vc.presentedViewController)
    }
}
