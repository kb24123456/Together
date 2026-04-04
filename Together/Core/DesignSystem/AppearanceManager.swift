import SwiftUI

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
        }
    }

    var resolvedColorScheme: ColorScheme? {
        mode.colorScheme
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        self.mode = AppearanceMode(rawValue: stored) ?? .system
    }
}
