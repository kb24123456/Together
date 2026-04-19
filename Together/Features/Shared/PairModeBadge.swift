import SwiftUI

/// 双人模式标识胶囊，显示在首页顶部当 `sessionStore.activeMode == .pair` 时。
struct PairModeBadge: View {
    var body: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Image(systemName: "person.2.fill")
                .font(AppTheme.typography.sized(11, weight: .semibold))
            Text("双人模式")
                .font(AppTheme.typography.sized(12, weight: .semibold))
        }
        .foregroundStyle(AppTheme.colors.pairAccent)
        .padding(.horizontal, AppTheme.spacing.sm)
        .padding(.vertical, AppTheme.spacing.xxs)
        .background(AppTheme.colors.pairAccentSoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("双人模式")
        .accessibilityHint("当前处于双人协作模式")
    }
}

#Preview {
    PairModeBadge()
        .padding()
        .background(AppTheme.colors.background)
}
