import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTheme {
    enum colors {
        static let background = Color(red: 0.965, green: 0.961, blue: 0.949)
        static let backgroundSoft = Color(red: 0.982, green: 0.979, blue: 0.972)
        static let homeBackground = background
        static let homeBackgroundSoft = backgroundSoft
        static let projectLayerBackground = Color(red: 0.15, green: 0.16, blue: 0.18)
        static let projectLayerSurface = Color(red: 0.20, green: 0.22, blue: 0.25)
        static let projectLayerOutline = Color.white.opacity(0.10)
        static let projectLayerText = Color(red: 0.95, green: 0.96, blue: 0.98)
        static let projectLayerSecondaryText = Color(red: 0.74, green: 0.76, blue: 0.80)
        static let surface = Color.white
        static let surfaceElevated = Color(red: 0.979, green: 0.977, blue: 0.969)
        static let pillSurface = Color(red: 0.973, green: 0.972, blue: 0.966)
        static let pillOutline = Color.white.opacity(0.9)
        static let accent = Color(red: 0.24, green: 0.47, blue: 0.42)
        static let accentSoft = Color(red: 0.92, green: 0.96, blue: 0.94)
        static let profileAccent = Color(red: 0.29, green: 0.31, blue: 0.34)
        static let profileAccentSoft = Color(red: 0.16, green: 0.18, blue: 0.19).opacity(0.08)
        static let sky = Color(red: 0.42, green: 0.70, blue: 0.98)
        static let secondaryAccent = Color(red: 0.86, green: 0.78, blue: 0.67)
        static let coral = Color(red: 0.87, green: 0.48, blue: 0.41)
        static let sun = Color(red: 0.93, green: 0.74, blue: 0.18)
        static let violet = Color(red: 0.44, green: 0.28, blue: 0.91)
        static let avatarWarm = Color(red: 0.96, green: 0.88, blue: 0.84)
        static let avatarNeutral = Color(red: 0.92, green: 0.92, blue: 0.93)
        static let title = Color(red: 0.16, green: 0.18, blue: 0.19)
        static let body = Color(red: 0.34, green: 0.36, blue: 0.38)
        static let textTertiary = Color(red: 0.70, green: 0.70, blue: 0.70)
        static let timeText = Color(red: 0.72, green: 0.72, blue: 0.73)
        static let success = Color(red: 0.25, green: 0.61, blue: 0.44)
        static let warning = Color(red: 0.82, green: 0.56, blue: 0.26)
        static let danger = Color(red: 0.74, green: 0.35, blue: 0.32)
        static let outline = Color.black.opacity(0.08)
        static let outlineStrong = Color(red: 0.74, green: 0.74, blue: 0.74)
        static let separator = Color(red: 0.87, green: 0.86, blue: 0.84)
        static let shadow = Color(red: 0.10, green: 0.10, blue: 0.09).opacity(0.08)
    }

    enum spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36
    }

    enum radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum typography {
        static let body = textStyle(.body)
        private static var hasLoggedRoundedFallback = false

        static func textStyle(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> Font {
            Font(uiFont(textStyle: style, weight: weight))
        }

        static func sized(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
            Font(uiFont(size: size, weight: weight))
        }

        #if canImport(UIKit)
        static func sizedUIFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            uiFont(size: size, weight: weight)
        }
        #endif

        #if canImport(UIKit)
        private static func uiFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let metrics = UIFontMetrics(forTextStyle: textStyle)
            let basePointSize = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).pointSize
            return metrics.scaledFont(for: uiFont(size: basePointSize, weight: weight))
        }

        private static func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
            let roundedBase = UIFont.systemFont(ofSize: size, weight: weight)
            let roundedDescriptor = roundedBase.fontDescriptor.withDesign(.rounded) ?? roundedBase.fontDescriptor

            guard let chineseDescriptor = roundedChineseDescriptor(size: size, weight: weight) else {
                logRoundedFallbackIfNeeded()
                return UIFont(descriptor: roundedDescriptor, size: size)
            }

            let cascadedDescriptor = roundedDescriptor.addingAttributes([
                .cascadeList: [chineseDescriptor]
            ])
            return UIFont(descriptor: cascadedDescriptor, size: size)
        }

        private static func roundedChineseDescriptor(size: CGFloat, weight: UIFont.Weight) -> UIFontDescriptor? {
            preferredRoundedChineseNames(for: weight)
                .lazy
                .compactMap { UIFont(name: $0, size: size)?.fontDescriptor }
                .first
        }

        private static func preferredRoundedChineseNames(for weight: UIFont.Weight) -> [String] {
            switch weight {
            case ..<UIFont.Weight.regular:
                return ["Resource-Han-Rounded-CN-ExtraLight", "Resource-Han-Rounded-CN-Light", "Resource-Han-Rounded-CN-Regular"]
            case ..<UIFont.Weight.medium:
                return ["Resource-Han-Rounded-CN-Light", "Resource-Han-Rounded-CN-Regular", "Resource-Han-Rounded-CN-Normal"]
            case ..<UIFont.Weight.semibold:
                return ["Resource-Han-Rounded-CN-Regular", "Resource-Han-Rounded-CN-Normal", "Resource-Han-Rounded-CN-Medium"]
            case ..<UIFont.Weight.bold:
                return ["Resource-Han-Rounded-CN-Medium", "Resource-Han-Rounded-CN-Bold", "Resource-Han-Rounded-CN-Normal"]
            default:
                return ["Resource-Han-Rounded-CN-Bold", "Resource-Han-Rounded-CN-Heavy", "Resource-Han-Rounded-CN-Medium"]
            }
        }

        private static func logRoundedFallbackIfNeeded() {
            guard !hasLoggedRoundedFallback else { return }
            hasLoggedRoundedFallback = true
            #if DEBUG
            print("AppTheme.typography warning: Resource Han Rounded CN is unavailable on the current device/runtime. Falling back to the rounded system font.")
            #endif
        }
        #endif
    }
}
