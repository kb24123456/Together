import SwiftUI

enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

@Observable
final class AppearanceManager: @unchecked Sendable {
    private static let storageKey = "app.appearanceMode"
    private let defaults: UserDefaults

    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.storageKey)
        }
    }

    var resolvedColorScheme: ColorScheme? {
        mode.colorScheme
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = defaults.string(forKey: Self.storageKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
