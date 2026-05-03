#if DEBUG
import Foundation
import Testing
@testable import Together

@Suite("ProfileDebugVisibility")
struct ProfileDebugVisibilityTests {
    private let suiteName = "ProfileDebugVisibilityTests.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("default Debug run keeps profile developer section hidden")
    func defaultDebugRunHidesDeveloperSection() {
        defer { cleanup() }
        #expect(ProfileDebugVisibility.isEnabled(arguments: [], environment: [:], defaults: defaults) == false)
    }

    @Test("launch argument enables profile developer section")
    func launchArgumentEnablesDeveloperSection() {
        defer { cleanup() }
        #expect(
            ProfileDebugVisibility.isEnabled(
                arguments: ["Together", ProfileDebugVisibility.launchArgument],
                environment: [:],
                defaults: defaults
            ) == true
        )
    }

    @Test("environment variable enables profile developer section")
    func environmentEnablesDeveloperSection() {
        defer { cleanup() }
        #expect(
            ProfileDebugVisibility.isEnabled(
                arguments: [],
                environment: [ProfileDebugVisibility.environmentKey: "true"],
                defaults: defaults
            ) == true
        )
    }

    @Test("user defaults enables profile developer section")
    func defaultsEnableDeveloperSection() {
        defer { cleanup() }
        defaults.set(true, forKey: ProfileDebugVisibility.userDefaultsKey)
        #expect(ProfileDebugVisibility.isEnabled(arguments: [], environment: [:], defaults: defaults) == true)
    }
}
#endif
