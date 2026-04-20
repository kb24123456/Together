import SwiftUI
import Testing
import UIKit
@testable import Together

@Suite
struct ProfileTokenContrastTests {

    // MARK: - hairline visibility

    @Test func hairlineLightContrastNonZero() {
        let delta = channelDelta(
            AppTheme.colors.hairline.uiColor(style: .light),
            AppTheme.colors.background.uiColor(style: .light)
        )
        #expect(delta > 0.02, "Hairline must differ from background by >2% in light mode")
    }

    @Test func hairlineDarkContrastNonZero() {
        let delta = channelDelta(
            AppTheme.colors.hairline.uiColor(style: .dark),
            AppTheme.colors.background.uiColor(style: .dark)
        )
        #expect(delta > 0.02, "Hairline must differ from background by >2% in dark mode")
    }

    // MARK: - selectionTint on surfaceElevated (for inline options + checkmark)

    @Test func selectionTintContrastLightModeAA() {
        let ratio = luminanceContrastRatio(
            AppTheme.colors.selectionTint.uiColor(style: .light),
            AppTheme.colors.surfaceElevated.uiColor(style: .light)
        )
        #expect(ratio >= 3.0, "Selection tint must meet WCAG AA for graphical objects (3:1) in light mode; got \(ratio)")
    }

    @Test func selectionTintContrastDarkModeAA() {
        let ratio = luminanceContrastRatio(
            AppTheme.colors.selectionTint.uiColor(style: .dark),
            AppTheme.colors.surfaceElevated.uiColor(style: .dark)
        )
        #expect(ratio >= 3.0, "Selection tint must meet WCAG AA for graphical objects (3:1) in dark mode; got \(ratio)")
    }

    // MARK: - Helpers

    private func channelDelta(_ a: UIColor, _ b: UIColor) -> CGFloat {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) + abs(ag - bg) + abs(ab - bb)
    }

    private func luminanceContrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let (bright, dark) = la > lb ? (la, lb) : (lb, la)
        return (bright + 0.05) / (dark + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Double {
            let vv = Double(v)
            return vv <= 0.03928 ? vv / 12.92 : pow((vv + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

private extension Color {
    /// Resolves this SwiftUI Color as a UIColor under a given interface style.
    /// Used by contrast tests to compare the light and dark flavors of
    /// dynamic tokens.
    func uiColor(style: UIUserInterfaceStyle) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return UIColor(self).resolvedColor(with: traits)
    }
}
