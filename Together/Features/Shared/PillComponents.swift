import SwiftUI

/// 通用文字 capsule（badge / chip / status pill）。
/// 替代散落各页面的 Capsule + Text + tint 组合。
struct Badge: View {
    enum Size {
        case small  // 11pt 字 / sm 水平 padding（紧凑标签）
        case regular  // 12pt 字 / md 水平 padding（status chip）
    }

    let text: String
    let tint: Color
    /// 默认 tint.opacity(0.12)，可显式覆盖（如选中态用实色）
    var background: Color? = nil
    var size: Size = .regular
    var weight: UIFont.Weight = .bold

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

struct ModeIndicator: View {
    var label: String = "今日视图"
    var tint: Color = AppTheme.colors.sky
    var background: Color = AppTheme.colors.sky.opacity(0.12)

    var body: some View {
        Text(label)
            .font(AppTheme.typography.sized(12, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.spacing.sm)
            .padding(.vertical, AppTheme.spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }
}

/// 双态切换按钮（capsule 风）。
/// 可用于任何 segmented-like 双态切换场景。
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
        Badge(text: "紧急", tint: AppTheme.colors.coral, size: .small)
        Badge(text: "已完成", tint: AppTheme.colors.coral)
        Badge(text: "超期", tint: AppTheme.colors.danger, size: .regular)
        ModeIndicator()
        HStack {
            PillToggleButton(title: "全部", isActive: true) {}
            PillToggleButton(title: "你负责", isActive: false) {}
            PillToggleButton(title: "TA 负责", isActive: false) {}
        }
    }
    .padding()
}
#endif
