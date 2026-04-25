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

        /// body 层级派生（Wave 5 design system 统一）— 替代散落在各页面的 `body.opacity(0.7x)` 硬编码。
        /// 用于 section 内副标 / 弱副信息。
        static let bodySecondary = Color(light: .init(red: 0.34, green: 0.36, blue: 0.38).opacity(0.74),
                                         dark: .init(red: 0.72, green: 0.72, blue: 0.74).opacity(0.74))

        static let timeText = Color(light: .init(red: 0.72, green: 0.72, blue: 0.73),
                                    dark: .init(red: 0.50, green: 0.50, blue: 0.52))

        // MARK: - Accent & Brand

        static let accent = Color(light: .init(red: 0.24, green: 0.47, blue: 0.42),
                                  dark: .init(red: 0.38, green: 0.68, blue: 0.60))

        static let accentSoft = Color(light: .init(red: 0.92, green: 0.96, blue: 0.94),
                                      dark: .init(red: 0.18, green: 0.26, blue: 0.24))

        // MARK: - Pair Mode Accent (双人模式专属色系)

        static let pairAccent = Color(light: .init(red: 0.87, green: 0.48, blue: 0.41),
                                      dark: .init(red: 0.93, green: 0.60, blue: 0.52))

        static let pairAccentSoft = Color(light: .init(red: 0.99, green: 0.93, blue: 0.91),
                                          dark: .init(red: 0.30, green: 0.20, blue: 0.18))

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

        static let glassTint = Color(light: .white.opacity(0.08),
                                     dark: .white.opacity(0.06))

        static let outline = Color(light: .black.opacity(0.08),
                                   dark: .white.opacity(0.10))

        /// Ultra-thin divider for editorial separation between identity card and groups.
        /// Weaker than `outline` and `separator`.
        static let hairline = Color(light: .init(red: 0.16, green: 0.18, blue: 0.19).opacity(0.10),
                                    dark: .white.opacity(0.08))

        /// Profile-module selection accent. Shares the warm coral hue with `pairAccent`
        /// but the light-mode variant is deepened to meet WCAG AA (3:1) on near-white
        /// `surfaceElevated` — the brand `pairAccent` itself sits at ~2.8:1 which is
        /// fine for large decorative uses (4pt dot, avatar backgrounds) but not for
        /// information-bearing UI like the selection checkmark. Dark-mode variant
        /// matches pairAccent dark (already compliant). Guarded by
        /// `ProfileTokenContrastTests`.
        ///
        /// Do NOT use outside Profile module.
        static let selectionTint = Color(
            light: .init(red: 0.78, green: 0.40, blue: 0.33),
            dark: .init(red: 0.93, green: 0.60, blue: 0.52)
        )

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
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36
    }

    enum radius {
        static let xs: CGFloat = 9
        static let sm: CGFloat = 11
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let card: CGFloat = 20
        static let xl: CGFloat = 26
        static let xxl: CGFloat = 34
        static let pill: CGFloat = 999
    }

    enum metrics {
        /// SF Symbol "checkmark" 视觉居中补偿：字形短臂偏左下、长臂延伸右上，需向左下微调
        static let checkmarkVisualOffset: CGSize = CGSize(width: -0.5, height: 0.5)
    }

    /// 标准动画曲线（Wave 5 design system 统一）。
    /// 在所有 view 用这些常量代替散落的 `.spring(response: 0.3x, dampingFraction: 0.8x)`，
    /// 确保 app 内动画节奏一致。
    enum motion {
        /// 快速反应：tap / select / row 触感反馈
        static let snappy = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.86)
        /// 平滑过渡：sheet present / 状态切换 / list row 进入
        static let smooth = SwiftUI.Animation.spring(response: 0.36, dampingFraction: 0.82)
        /// 弹性入场：CTA 按钮 / hero element / spring overshoot
        static let bouncy = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.78)
        /// 微调：opacity / color 状态切换
        static let micro = SwiftUI.Animation.easeInOut(duration: 0.22)
    }

    enum typography {
        static let body = textStyle(.body)

        // MARK: - Semantic display tokens (Wave 5 design system 统一)
        // 用语义化 token 替代散落的 `sized(N, weight:)`，确保层级统一。

        /// Page hero / paywall 主标题 — 30pt bold（如 "Together Pro"）
        static let display = sized(30, weight: .bold)
        /// 章节中央装饰 header — 15pt semibold（"你已解锁 X 个 Pro 功能"）
        static let sectionHeader = sized(15, weight: .semibold)
        /// 卡内 label — 12pt medium（plan 卡上方"月付"/"年付"）
        static let cardLabel = sized(12, weight: .medium)
        /// 卡内 caption — 11pt regular（plan 卡下方副标 / 极小字）
        static let cardCaption = sized(11, weight: .regular)
        /// 大价格数字 — 20-22pt bold（plan 卡价格 ¥18 / ¥98）
        static let priceLarge = sized(20, weight: .bold)
        static let priceXLarge = sized(22, weight: .bold)

        private static var hasLoggedRoundedFallback = false

        static func textStyle(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> Font {
            Font(uiFont(textStyle: style, weight: weight))
        }

        static func sized(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
            Font(uiFont(size: size, weight: weight))
        }

        /// Editorial large-display helper. Pins weight to `.light` so name card titles
        /// feel airy and restrained rather than bold. No font bundling — relies on
        /// system rounded Chinese fallback configured in `uiFont(size:weight:)`.
        static func displayLight(_ size: CGFloat) -> Font {
            Font(uiFont(size: size, weight: .light))
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
            self.scrollEdgeEffectStyle(nil, for: [.top, .bottom])
        } else {
            self
        }
    }
}
