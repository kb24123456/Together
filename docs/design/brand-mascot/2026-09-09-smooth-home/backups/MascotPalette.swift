import RiveRuntime

/// The reviewed light/dark pair for every color exposed by TogetherSphereModel.
enum MascotPalette {
    static let colors: [(path: String, light: UInt32, dark: UInt32)] = [
        ("bodyLight", 0xFF101010, 0xFFF0F0F0),
        ("bodyShade", 0xFF030303, 0xFFD5D5D5),
        ("handLight", 0xFF141414, 0xFFF0F0F0),
        ("handShade", 0xFF060606, 0xFFBDBDBD),
        ("farHandLight", 0xFF080808, 0xFFE8E8E8),
        ("farHandShade", 0xFF080808, 0xFFB8B8B8),
        ("eyeColor", 0xFFFFFFFF, 0xFF1B1B1B),
        ("sweatColor", 0xFFFFFFFF, 0xFF686868),
        ("penBodyColor", 0xFFF2EEE6, 0xFF767676),
        ("penTipColor", 0xFF111111, 0xFFADADAD),
        ("inkColor", 0xFF777777, 0xFF929292),
        ("tearColor", 0xFF88CFF3, 0xFF347FA6),
    ]

    @MainActor
    static func apply(to instance: ViewModelInstance, isDark: Bool) {
        for color in colors {
            instance.setValue(
                of: ColorProperty(path: color.path),
                to: RiveRuntime.Color(isDark ? color.dark : color.light)
            )
        }
    }
}
