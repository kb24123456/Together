import SwiftUI

enum WidgetTheme {
    static func todayBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.12, green: 0.11, blue: 0.10),
                    Color(red: 0.17, green: 0.14, blue: 0.17)
                ]
                : [
                    Color(red: 1.0, green: 0.98, blue: 0.95),
                    Color(red: 0.98, green: 0.96, blue: 1.0)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func anniversaryBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.13, green: 0.11, blue: 0.11),
                    Color(red: 0.15, green: 0.13, blue: 0.18)
                ]
                : [
                    Color(red: 1.0, green: 0.96, blue: 0.92),
                    Color(red: 1.0, green: 0.95, blue: 0.98)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.47, blue: 0.41)
            : Color(red: 0.92, green: 0.36, blue: 0.31)
    }

    static func accentText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.58, blue: 0.52)
            : Color(red: 0.78, green: 0.32, blue: 0.28)
    }

    static func accentFill(for colorScheme: ColorScheme, opacity: Double) -> Color {
        accent(for: colorScheme).opacity(opacity)
    }

    static func divider(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.10)
    }

    static func avatarStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.72) : .white.opacity(0.94)
    }

    static func avatarShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.08)
    }

    static func avatarSymbol(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.78)
            : Color(red: 0.18, green: 0.20, blue: 0.22).opacity(0.78)
    }

    static func avatarFallbackColors(tintIndex: Int, colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return tintIndex == 0
                ? [
                    Color(red: 0.58, green: 0.31, blue: 0.24),
                    Color(red: 0.32, green: 0.20, blue: 0.18)
                ]
                : [
                    Color(red: 0.26, green: 0.36, blue: 0.58),
                    Color(red: 0.20, green: 0.20, blue: 0.34)
                ]
        }

        return tintIndex == 0
            ? [
                Color(red: 0.98, green: 0.76, blue: 0.64),
                Color(red: 1.0, green: 0.89, blue: 0.84)
            ]
            : [
                Color(red: 0.77, green: 0.87, blue: 1.0),
                Color(red: 0.93, green: 0.91, blue: 1.0)
            ]
    }

    static func blurredAvatarFallback(index: Int, colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return index == 0
                ? Color(red: 0.55, green: 0.28, blue: 0.22)
                : Color(red: 0.24, green: 0.34, blue: 0.62)
        }

        return index == 0
            ? Color(red: 0.98, green: 0.70, blue: 0.56)
            : Color(red: 0.70, green: 0.82, blue: 1.0)
    }

    static func materialOverlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.34) : .white.opacity(0.54)
    }
}
