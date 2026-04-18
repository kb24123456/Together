import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTheme {
    enum colors {
        // MARK: - Backgrounds & Surfaces

        static let background = Color(light: .init(red: 0.965, green: 0.961, blue: 0.949),
                                      dark: .init(red: 0.11, green: 0.11, blue: 0.12))

        static let backgroundSoft = Color(light: .init(red: 0.982, green: 0.979, blue: 0.972),
                                          dark: .init(red: 0.13, green: 0.13, blue: 0.14))

        static let homeBackground = background
        static let homeBackgroundSoft = backgroundSoft

        static let surface = Color(light: .white,
                                   dark: .init(red: 0.16, green: 0.16, blue: 0.17))

        static let surfaceElevated = Color(light: .init(red: 0.979, green: 0.977, blue: 0.969),
                                           dark: .init(red: 0.20, green: 0.20, blue: 0.22))

        static let pillSurface = Color(light: .init(red: 0.973, green: 0.972, blue: 0.966),
                                       dark: .init(red: 0.22, green: 0.22, blue: 0.24))

        static let pillOutline = Color(light: .white.opacity(0.9),
                                       dark: .white.opacity(0.10))

        // MARK: - Project Layer (always dark)

        static let projectLayerBackground = Color(red: 0.15, green: 0.16, blue: 0.18)
        static let projectLayerSurface = Color(red: 0.20, green: 0.22, blue: 0.25)
        static let projectLayerOutline = Color.white.opacity(0.10)
        static let projectLayerText = Color(red: 0.95, green: 0.96, blue: 0.98)
        static let projectLayerSecondaryText = Color(red: 0.74, green: 0.76, blue: 0.80)

        // MARK: - Text

        static let title = Color(light: .init(red: 0.16, green: 0.18, blue: 0.19),
                                 dark: .init(red: 0.95, green: 0.95, blue: 0.96))

        static let body = Color(light: .init(red: 0.34, green: 0.36, blue: 0.38),
                                dark: .init(red: 0.72, green: 0.72, blue: 0.74))

        static let textTertiary = Color(light: .init(red: 0.70, green: 0.70, blue: 0.70),
                                        dark: .init(red: 0.46, green: 0.46, blue: 0.48))

        static let timeText = Color(light: .init(red: 0.72, green: 0.72, blue: 0.73),
                                    dark: .init(red: 0.50, green: 0.50, blue: 0.52))

        // MARK: - Accent & Brand

        static let accent = Color(light: .init(red: 0.24, green: 0.47, blue: 0.42),
                                  dark: .init(red: 0.38, green: 0.68, blue: 0.60))

        static let accentSoft = Color(light: .init(red: 0.92, green: 0.96, blue: 0.94),
                                      dark: .init(red: 0.18, green: 0.26, blue: 0.24))

        static let profileAccent = Color(light: .init(red: 0.29, green: 0.31, blue: 0.34),
                                         dark: .init(red: 0.78, green: 0.78, blue: 0.80))

        static let profileAccentSoft = Color(light: .init(red: 0.16, green: 0.18, blue: 0.19).opacity(0.08),
                                             dark: .init(red: 0.90, green: 0.90, blue: 0.92).opacity(0.10))

        // MARK: - Semantic Colors

        static let sky = Color(red: 0.42, green: 0.70, blue: 0.98)
        static let secondaryAccent = Color(red: 0.86, green: 0.78, blue: 0.67)
        static let coral = Color(red: 0.87, green: 0.48, blue: 0.41)
        static let sun = Color(red: 0.93, green: 0.74, blue: 0.18)
        static let violet = Color(red: 0.44, green: 0.28, blue: 0.91)

        static let success = Color(red: 0.25, green: 0.61, blue: 0.44)
        static let warning = Color(red: 0.82, green: 0.56, blue: 0.26)
        static let danger = Color(red: 0.74, green: 0.35, blue: 0.32)

        // MARK: - Avatar

        static let avatarWarm = Color(light: .init(red: 0.96, green: 0.88, blue: 0.84),
                                      dark: .init(red: 0.38, green: 0.30, blue: 0.26))

        static let avatarNeutral = Color(light: .init(red: 0.92, green: 0.92, blue: 0.93),
                                         dark: .init(red: 0.30, green: 0.30, blue: 0.32))

        // MARK: - Borders & Shadows

        static let outline = Color(light: .black.opacity(0.08),
                                   dark: .white.opacity(0.10))

        static let outlineStrong = Color(light: .init(red: 0.74, green: 0.74, blue: 0.74),
                                         dark: .init(red: 0.36, green: 0.36, blue: 0.38))

        static let separator = Color(light: .init(red: 0.87, green: 0.86, blue: 0.84),
                                     dark: .init(red: 0.26, green: 0.26, blue: 0.28))

        static let shadow = Color(light: .init(red: 0.10, green: 0.10, blue: 0.09).opacity(0.08),
                                  dark: .black.opacity(0.30))

        // MARK: - Gradient Grid Background

        static let gradientBottom = Color(light: .init(red: 0.961, green: 0.938, blue: 0.922),
                                          dark: .init(red: 0.130, green: 0.118, blue: 0.112))

        static let gridLine = Color(light: .black.opacity(0.022),
                                    dark: .white.opacity(0.02))
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

    enum metrics {
        /// SF Symbol "checkmark" 视觉居中补偿：字形短臂偏左下、长臂延伸右上，需向左下微调
        static let checkmarkVisualOffset: CGSize = CGSize(width: -0.5, height: 0.5)
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

// MARK: - Adaptive Color Helper

extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Scroll Edge Protection

extension View {
    @ViewBuilder
    func applyScrollEdgeProtection() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }
}
