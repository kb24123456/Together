import SwiftUI

/// 通用文字 capsule（badge / chip / status pill）。
/// 替代散落各页面的 Capsule + Text + tint 组合。
struct Badge: View {
    enum Size {
        case small  // 11pt 字 / sm 水平 padding（"共享" 标签）
        case regular  // 12pt 字 / md 水平 padding（status chip）
    }

    let text: String
    let tint: Color
    /// 默认 tint.opacity(0.12)，可显式覆盖（如选中态用实色）
    var background: Color? = nil
    var size: Size = .regular
    var weight: Font.Weight = .bold

    private var fontSize: CGFloat {
        switch size {
        case .small: 11
        case .regular: 12
        }
    }
    private var hPadding: CGFloat {
        switch size {
        case .small: AppTheme.spacing.sm
        case .regular: AppTheme.spacing.md
        }
    }

    var body: some View {
        Text(text)
            .font(AppTheme.typography.sized(fontSize, weight: weight))
            .foregroundStyle(tint)
            .padding(.horizontal, hPadding)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(background ?? tint.opacity(0.12))
            )
    }
}

/// 双人/单人模式指示器。
/// HomeView 3 处（spaceModeLine / projectModeIndicator / routinesModeHeaderMeta）原本重复定义。
/// 默认色：active = pairAccent，可覆盖为 coral（project / routines 用）。
struct ModeIndicator: View {
    let isPairMode: Bool
    var pairLabel: String = "双人模式"
    var soloLabel: String = "单人模式"
    var pairTint: Color = AppTheme.colors.pairAccent
    var pairBackground: Color = AppTheme.colors.pairAccentSoft
    var soloTint: Color = AppTheme.colors.body.opacity(0.68)
    var soloBackground: Color = AppTheme.colors.surfaceElevated

    var body: some View {
        Text(isPairMode ? pairLabel : soloLabel)
            .font(AppTheme.typography.sized(12, weight: .bold))
            .foregroundStyle(isPairMode ? pairTint : soloTint)
            .padding(.horizontal, AppTheme.spacing.sm)
            .padding(.vertical, AppTheme.spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(isPairMode ? pairBackground : soloBackground)
            )
    }
}

/// 双态切换按钮（capsule 风）。
/// CalendarView filter 按钮原本重复定义，可以泛用到任何 segmented-like 按钮组。
struct PillToggleButton: View {
    let title: String
    let isActive: Bool
    var activeTint: Color = AppTheme.colors.coral
    var inactiveTint: Color = AppTheme.colors.title
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(13, weight: .bold))
                .foregroundStyle(isActive ? Color.white : inactiveTint)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? activeTint : AppTheme.colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Badges") {
    VStack(spacing: AppTheme.spacing.md) {
        Badge(text: "共享", tint: AppTheme.colors.coral, size: .small)
        Badge(text: "已完成", tint: AppTheme.colors.success)
        Badge(text: "超期", tint: AppTheme.colors.danger, size: .regular)
        ModeIndicator(isPairMode: true)
        ModeIndicator(isPairMode: false)
        ModeIndicator(isPairMode: true,
                      pairTint: AppTheme.colors.coral,
                      pairBackground: AppTheme.colors.coral.opacity(0.12))
        HStack {
            PillToggleButton(title: "全部", isActive: true) {}
            PillToggleButton(title: "你负责", isActive: false) {}
            PillToggleButton(title: "TA 负责", isActive: false) {}
        }
    }
    .padding()
}
#endif
