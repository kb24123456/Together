import Foundation
import Observation

@MainActor
@Observable
final class AmbientBackgroundSettings {
    static let storageKey = "together.ambientBackground.isEnabled"

    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.storageKey) as? Bool ?? true
    }
}
