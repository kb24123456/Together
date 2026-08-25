import Foundation
import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Appearance manager")
struct AppearanceManagerTests {
    @Test func modesResolveToExpectedColorSchemes() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func modeDefaultsToSystemAndPersistsPerDevice() throws {
        let suiteName = "AppearanceManagerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AppearanceManager(defaults: defaults)
        #expect(initial.mode == .system)

        initial.mode = .dark

        let restored = AppearanceManager(defaults: defaults)
        #expect(restored.mode == .dark)
        #expect(restored.resolvedColorScheme == .dark)
    }

    @Test func unknownStoredModeFallsBackToSystem() throws {
        let suiteName = "AppearanceManagerInvalidModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: "app.appearanceMode")

        let manager = AppearanceManager(defaults: defaults)

        #expect(manager.mode == .system)
        #expect(manager.resolvedColorScheme == nil)
    }
}
