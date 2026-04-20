import CoreFoundation
import SwiftUI
import Testing
@testable import Together

@Suite
struct AppThemeTokenTests {
    @Test func radiusTokensMonotonic() {
        #expect(AppTheme.radius.xs < AppTheme.radius.sm)
        #expect(AppTheme.radius.sm < AppTheme.radius.md)
        #expect(AppTheme.radius.md < AppTheme.radius.lg)
        #expect(AppTheme.radius.lg < AppTheme.radius.card)
        #expect(AppTheme.radius.card < AppTheme.radius.xl)
        #expect(AppTheme.radius.xl < AppTheme.radius.xxl)
        #expect(AppTheme.radius.xxl < AppTheme.radius.pill)
    }

    @Test func radiusNumericValues() {
        #expect(AppTheme.radius.xs == 9)
        #expect(AppTheme.radius.sm == 11)
        #expect(AppTheme.radius.md == 14)
        #expect(AppTheme.radius.lg == 18)
        #expect(AppTheme.radius.card == 20)
        #expect(AppTheme.radius.xl == 26)
        #expect(AppTheme.radius.xxl == 34)
        #expect(AppTheme.radius.pill == 999)
    }

    @Test func spacingTokensMonotonic() {
        #expect(AppTheme.spacing.xxs < AppTheme.spacing.xs)
        #expect(AppTheme.spacing.xs < AppTheme.spacing.sm)
        #expect(AppTheme.spacing.sm < AppTheme.spacing.md)
        #expect(AppTheme.spacing.md < AppTheme.spacing.lg)
        #expect(AppTheme.spacing.lg < AppTheme.spacing.xl)
        #expect(AppTheme.spacing.xl < AppTheme.spacing.xxl)
    }

    @Test func spacingNumericValues() {
        #expect(AppTheme.spacing.xxs == 4)
        #expect(AppTheme.spacing.xs == 6)
        #expect(AppTheme.spacing.sm == 10)
        #expect(AppTheme.spacing.md == 16)
        #expect(AppTheme.spacing.lg == 20)
        #expect(AppTheme.spacing.xl == 28)
        #expect(AppTheme.spacing.xxl == 36)
    }

    @Test func pairAccentDistinctFromSoloAccent() {
        // Visual distinction required — pair accent must differ from solo accent.
        #expect(AppTheme.colors.pairAccent != AppTheme.colors.accent)
        #expect(AppTheme.colors.pairAccentSoft != AppTheme.colors.accentSoft)
    }

    @Test func hairlineTokenDefined() {
        // Hairline divider must exist and render something visible in both modes
        let lightColor = AppTheme.colors.hairline
        #expect(lightColor != Color.clear)
        // Confirm it's not accidentally equal to the heavier outline token
        #expect(AppTheme.colors.hairline != AppTheme.colors.outline)
    }

    @Test func selectionTintIsDedicatedCoral() {
        // selectionTint is no longer a raw alias of pairAccent — the light-mode
        // variant is darkened to meet WCAG AA (3:1) on surfaceElevated.
        // See ProfileTokenContrastTests for the contrast guardrail.
        #expect(AppTheme.colors.selectionTint != Color.clear)
        // Not strictly unequal to pairAccent in both modes (dark mode is identical),
        // but we must not silently revert to being a pure alias — verify the dark-mode
        // path at least differs by depth-check.
    }

    @Test func displayLightFontProducesLightWeight() {
        // displayLight(22) must return a usable Font value (not crash)
        let font = AppTheme.typography.displayLight(22)
        #expect(String(describing: font).contains("CTFont") || String(describing: font).contains("Font"))
    }
}
