import SwiftUI

enum AppearanceMode: String, CaseIterable, Sendable {
    case system
}

@Observable
final class AppearanceManager: @unchecked Sendable {
    private static let storageKey = "app.appearanceMode"

    var mode: AppearanceMode = .system

    var resolvedColorScheme: ColorScheme? {
        nil
    }

    init() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}
