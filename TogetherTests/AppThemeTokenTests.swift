import CoreFoundation
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
}
