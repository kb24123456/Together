import SwiftUI

enum AppTheme {
    enum colors {
        static let background = Color(red: 0.97, green: 0.96, blue: 0.94)
        static let surface = Color.white
        static let accent = Color(red: 0.24, green: 0.47, blue: 0.42)
        static let accentSoft = Color(red: 0.88, green: 0.94, blue: 0.90)
        static let secondaryAccent = Color(red: 0.86, green: 0.78, blue: 0.67)
        static let title = Color(red: 0.16, green: 0.18, blue: 0.19)
        static let body = Color(red: 0.34, green: 0.36, blue: 0.38)
        static let success = Color(red: 0.25, green: 0.61, blue: 0.44)
        static let warning = Color(red: 0.82, green: 0.56, blue: 0.26)
        static let danger = Color(red: 0.74, green: 0.35, blue: 0.32)
        static let outline = Color.black.opacity(0.08)
    }

    enum spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum radius {
        static let card: CGFloat = 20
        static let pill: CGFloat = 999
    }
}
