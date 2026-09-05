import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Together

@MainActor
@Suite("Appearance manager")
struct AppearanceManagerTests {
    @Test func redTextRemainsReadableOnAppSurfaces() {
        let surfaces = [AppTheme.colors.background, AppTheme.colors.surface,
                        AppTheme.colors.surfaceElevated, AppTheme.colors.pillSurface]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for surface in surfaces {
                #expect(contrastRatio(AppTheme.colors.warmText, surface, style: style) >= 4.5)
            }
        }
    }

    @Test func filledSelectionKeepsReadableNumbersInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(contrastRatio(
                AppTheme.colors.onSelection, AppTheme.colors.selectionFill, style: style
            ) >= 4.5)
        }
    }

    private func contrastRatio(_ foreground: Color, _ background: Color, style: UIUserInterfaceStyle) -> Double {
        func luminance(_ color: Color) -> Double {
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            #expect(alpha == 1)
            let channels = [red, green, blue].map { component -> Double in
                let value = Double(component)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let values = [luminance(foreground), luminance(background)]
        return (values.max()! + 0.05) / (values.min()! + 0.05)
    }

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
